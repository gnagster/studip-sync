import Foundation

public enum StudSyncError: LocalizedError, Sendable {
    case authentication, invalidResponse, unsafePath, sizeMismatch, http(Int)
    public var errorDescription: String? {
        switch self {
        case .authentication: return "Please sign in again. The university did not accept this session."
        case .invalidResponse: return "Stud.IP returned an unexpected response. Please try again later."
        case .unsafePath: return "A remote file has an unsafe or unavailable destination."
        case .sizeMismatch: return "A download was incomplete. Your existing file was not changed."
        case .http(let code): return "Stud.IP request failed (HTTP \(code))."
        }
    }
}

public struct Course: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public struct RemoteFile: Identifiable, Sendable {
    public var id: String
    public var components: [String]
    public var size: Int64
    public var revision: String
    public init(id: String, components: [String], size: Int64, revision: String) {
        self.id = id; self.components = components; self.size = size; self.revision = revision
    }
}

public struct Change: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var name: String
    public var path: String
    public var conflict: Bool
    public init(name: String, path: String, conflict: Bool) {
        self.name = name; self.path = path; self.conflict = conflict
    }
}

public struct Preferences: Codable, Sendable {
    public var destination = ""
    public var selectedCourses: Set<String> = []
    public var intervalMinutes = 60
    public var setupComplete = false
    public var lastSync: Date?
    public var changes: [Change] = []
    public init() {}
}

public enum SafePath {
    public static func remoteComponent(_ name: String, id: String, isFile: Bool) throws -> String {
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw StudSyncError.unsafePath
        }
        // Reserve brackets for identity markers so remote names cannot impersonate them.
        let name = try component(name).replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "[", with: "%5B").replacingOccurrences(of: "]", with: "%5D")
        return try suffixedComponent(name, suffix: " [\(isFile ? "file" : "folder")-\(id)]", isFile: isFile)
    }

    static func suffixedComponent(_ name: String, suffix: String, isFile: Bool) throws -> String {
        let name = try component(name)
        let ext = isFile ? (name as NSString).pathExtension : ""
        let ending = ext.isEmpty ? "" : "." + ext
        let stem = ending.isEmpty ? name : String(name.dropLast(ending.count))
        var budget = 255 - suffix.utf8.count - ending.utf8.count
        guard budget > 0 else { throw StudSyncError.unsafePath }
        var prefix = ""
        for character in stem {
            let count = String(character).utf8.count
            if count > budget { break }
            prefix.append(character); budget -= count
        }
        return prefix + suffix + ending
    }

    public static func component(_ name: String) throws -> String {
        let value = name.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "/", with: "--")
            .replacingOccurrences(of: "\\", with: "--")
        guard !value.isEmpty, value != ".", value != "..",
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw StudSyncError.unsafePath }
        return value
    }

    public static func destination(root: URL, components: [String]) throws -> URL {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var result = root
        for name in components {
            result.appendPathComponent(try component(name))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: result.path)) != nil {
                throw StudSyncError.unsafePath
            }
        }
        let resolved = result.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") else { throw StudSyncError.unsafePath }
        return result
    }
}
