import Foundation
import Testing
@testable import StudSyncCore

private struct Scratch {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func download(_ text: String) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: url)
        return url
    }
}

@Test func normalizedPathsCannotEscape() throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    for name in ["", ".", "..", "．．", "\u{0000}"] {
        #expect(throws: StudSyncError.self) { try SafePath.destination(root: scratch.root, components: [name]) }
    }
    #expect(try SafePath.component("Über / notes") == "Über -- notes")
    let outside = try Scratch(); defer { outside.remove() }
    try FileManager.default.createSymbolicLink(at: scratch.root.appendingPathComponent("escape"), withDestinationURL: outside.root)
    #expect(throws: StudSyncError.self) { try SafePath.destination(root: scratch.root, components: ["escape", "file"]) }
}

@Test func untouchedFilesReplaceWithoutBackupsAndSkipUnchanged() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let root = scratch.root.appendingPathComponent("sync")
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    var remote = RemoteFile(id: "aa", components: ["Course", "lecture.txt"], size: 4, revision: "1")
    let first = try await engine.synchronize(remote, courseID: "bb", root: root) { try scratch.download("old!") }
    #expect(first?.conflict == false)
    remote.revision = "2"
    _ = try await engine.synchronize(remote, courseID: "bb", root: root) { try scratch.download("new!") }
    #expect(try String(contentsOf: root.appendingPathComponent("Course/lecture.txt"), encoding: .utf8) == "new!")
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Course").path) == ["lecture.txt"])
    let restored = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    let skipped = try await restored.synchronize(remote, courseID: "bb", root: root) { throw URLError(.badURL) }
    #expect(skipped == nil)
}

@Test func editedFilesAndUnknownExistingFilesArePreserved() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let root = scratch.root.appendingPathComponent("sync")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("notes.txt")
    try Data("mine".utf8).write(to: target)
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    let remote = RemoteFile(id: "aa", components: ["notes.txt"], size: 6, revision: "1")
    let change = try await engine.synchronize(remote, courseID: "bb", root: root) { try scratch.download("remote") }
    #expect(change?.conflict == true)
    #expect(try String(contentsOf: target, encoding: .utf8) == "mine")
    #expect(try String(contentsOf: URL(fileURLWithPath: #require(change).path), encoding: .utf8) == "remote")
    let skipped = try await engine.synchronize(remote, courseID: "bb", root: root) { throw URLError(.badURL) }
    #expect(skipped == nil)
}

@Test func identicalExistingFileIsAdoptedAndLaterEditsSurvive() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let target = scratch.root.appendingPathComponent("notes.txt")
    try Data("same".utf8).write(to: target)
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    var file = RemoteFile(id: "aa", components: ["notes.txt"], size: 4, revision: "1")
    let adopted = try await engine.synchronize(file, courseID: "bb", root: scratch.root) { try scratch.download("same") }
    #expect(adopted == nil)
    try Data("user edit".utf8).write(to: target)
    file.revision = "2"
    let changed = try await engine.synchronize(file, courseID: "bb", root: scratch.root) { try scratch.download("next") }
    #expect(changed?.conflict == true)
    #expect(try String(contentsOf: target, encoding: .utf8) == "user edit")
}

@Test func incompleteAndCancelledDownloadsDoNotChangeExistingFiles() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let target = scratch.root.appendingPathComponent("notes.txt")
    try Data("mine".utf8).write(to: target)
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    let file = RemoteFile(id: "aa", components: ["notes.txt"], size: 99, revision: "1")
    await #expect(throws: StudSyncError.self) {
        try await engine.synchronize(file, courseID: "bb", root: scratch.root) { try scratch.download("short") }
    }
    await #expect(throws: CancellationError.self) {
        try await engine.synchronize(file, courseID: "bb", root: scratch.root) { throw CancellationError() }
    }
    #expect(try String(contentsOf: target, encoding: .utf8) == "mine")
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path) == ["notes.txt"])
}

@Test func loginUsesCredentialFormAndRejectsForeignAction() throws {
    let html = """
    <form action="/settings"><input name="security_token" value="wrong"></form>
    <form action="/dispatch.php/login"><input name="loginname"><input name="password">
    <input type="hidden" name="security_token" value="correct"><input type="hidden" name="login_ticket" value="ticket"></form>
    """
    let (url, fields) = try StudIPClient.loginFields(html: html, username: "student", password: "test €&+")
    #expect(url.host == StudIPClient.origin.host)
    #expect(fields["security_token"] == "correct")
    #expect(fields["Login"] == "1")
    #expect(String(decoding: StudIPClient.formBody(fields), as: UTF8.self).contains("%26%2B"))
    #expect(throws: StudSyncError.self) {
        try StudIPClient.loginFields(html: html.replacingOccurrences(of: "/dispatch.php/login", with: "https://foreign.invalid/login"), username: "student", password: "test")
    }
}
