import Foundation
import CryptoKit

public actor SyncEngine {
    private struct Record: Codable {
        var revision: String
        var baselineHash: String?
        var incomingPath: String?
    }
    private let manifest: URL
    private var records: [String: Record]

    public init(manifest: URL) throws {
        self.manifest = manifest
        records = FileManager.default.fileExists(atPath: manifest.path)
            ? try JSONDecoder().decode([String: Record].self, from: Data(contentsOf: manifest)) : [:]
    }

    public static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { hash.update(data: block) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func synchronize(_ file: RemoteFile, courseID: String, root: URL,
                            fetch: @Sendable () async throws -> URL) async throws -> Change? {
        try Task.checkCancellation()
        let target = try SafePath.destination(root: root, components: file.components)
        let key = root.standardizedFileURL.resolvingSymlinksInPath().path + "/" + courseID + "/" + file.id
        let old = records[key]
        let manager = FileManager.default
        if old?.revision == file.revision, manager.fileExists(atPath: target.path) {
            if let path = old?.incomingPath {
                let incoming = URL(fileURLWithPath: path)
                if manager.fileExists(atPath: incoming.path) { return nil }
            } else { return nil }
        }
        let downloaded = try await fetch()
        defer { try? manager.removeItem(at: downloaded) }
        try Task.checkCancellation()
        let size = try downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard Int64(size ?? -1) == file.size else { throw StudSyncError.sizeMismatch }
        let remoteHash = try Self.hash(downloaded)
        _ = try SafePath.destination(root: root, components: file.components)
        let existingHash = manager.fileExists(atPath: target.path) ? try Self.hash(target) : nil
        if existingHash == remoteHash {
            records[key] = Record(revision: file.revision, baselineHash: remoteHash, incomingPath: nil)
            try save()
            return nil
        }
        let conflict = existingHash != nil && (old?.baselineHash == nil || old?.baselineHash != existingHash)
        var destination = target
        if conflict {
            let stem = target.deletingPathExtension().lastPathComponent
            let ext = target.pathExtension.isEmpty ? "" : "." + target.pathExtension
            destination = target.deletingLastPathComponent().appendingPathComponent("\(stem) (StudIP \(UUID().uuidString.prefix(8)))\(ext)")
        }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Validate again after creating directories; remote names may traverse existing symlinks.
        _ = try SafePath.destination(root: root, components: file.components)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".studsync-\(UUID().uuidString).part")
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: downloaded, to: staging)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else { try manager.moveItem(at: staging, to: destination) }
        records[key] = Record(revision: file.revision,
                              baselineHash: conflict ? old?.baselineHash : remoteHash,
                              incomingPath: conflict ? destination.path : nil)
        try save()
        return Change(name: destination.lastPathComponent, path: destination.path, conflict: conflict)
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: manifest, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
    }
}
