import Foundation
import Testing
@testable import StudSyncCore

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, String, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, type, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": type])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct ClientTests {
    private func client() -> StudIPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return StudIPClient(session: URLSession(configuration: config))
    }
    @Test func paginationAndCourseDecoding() async throws {
        FixtureProtocol.handler = { request in
            let url = request.url!
            if url.path == "/jsonapi.php/v1/semesters" {
                return (200, "application/json", #"{"data":[{"id":"aa","attributes":{"is-current":true}}]}"#)
            }
            if url.path.contains("/users/bb/courses") {
                if url.query?.contains("page=2") == true {
                    return (200, "application/json", #"{"data":[{"id":"dd","attributes":{"title":"Second"}}]}"#)
                }
                return (200, "application/json", #"{"data":[{"id":"cc","attributes":{"title":"First"}}],"links":{"next":"/jsonapi.php/v1/users/bb/courses?page=2"}}"#)
            }
            return (200, "application/json", #"{"data":{"id":"bb"}}"#)
        }
        let courses = try await client().courses()
        #expect(courses.map(\.title) == ["First", "Second"])
    }
    @Test func repeatedOrForeignPaginationIsRejected() async throws {
        for next in ["https://foreign.invalid/steal", "/jsonapi.php/v1/semesters"] {
            FixtureProtocol.handler = { request in
                if request.url!.path.contains("semesters") {
                    let body = try JSONSerialization.data(withJSONObject: ["data": [], "links": ["next": next]])
                    return (200, "application/json", String(decoding: body, as: UTF8.self))
                }
                return (200, "application/json", #"{"data":{"id":"bb"}}"#)
            }
            await #expect(throws: StudSyncError.self) { try await client().courses() }
        }
    }
    @Test func rejectedSessionIsNotTreatedAsSuccessfulLogin() async throws {
        FixtureProtocol.handler = { request in
            if request.url!.path.hasPrefix("/jsonapi") { return (401, "application/json", "{}") }
            return (200, "text/html", #"<form action="/dispatch.php/login"><input name="loginname"><input name="password"><input type="hidden" name="security_token" value="fixture"></form>"#)
        }
        await #expect(throws: StudSyncError.self) { try await client().signIn(username: "fixture", password: "not-real") }
    }
    @Test func htmlAttachmentsRequireAValidSessionRatherThanADifferentMimeType() async throws {
        let response = HTTPURLResponse(url: StudIPClient.origin.appendingPathComponent("jsonapi.php/v1/file-refs/aa/content"), statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        for valid in [true, false] {
            FixtureProtocol.handler = { _ in
                valid ? (200, "application/json", #"{"data":{"id":"bb"}}"#) : (401, "application/json", "{}")
            }
            if valid { try await client().validateDownload(response) }
            else { await #expect(throws: StudSyncError.self) { try await client().validateDownload(response) } }
        }
    }
    @Test func unavailableCourseDoesNotBlockOtherCourseFiles() async throws {
        for disabled in ["folders", "file-refs"] {
            FixtureProtocol.handler = { request in
                if request.url!.path == "/jsonapi.php/v1/courses/aa/\(disabled)" { return (403, "application/json", "{}") }
                if request.url!.path.hasSuffix("folders") { return (200, "application/json", #"{"data":[]}"#) }
                return (200, "application/json", #"{"data":[{"id":"ee","attributes":{"name":"notes.html","filesize":5,"chdate":"1","is-downloadable":true}}]}"#)
            }
            let client = client()
            #expect(try await client.files(course: Course(id: "aa", title: "Unavailable")).isEmpty)
            #expect(try await client.files(course: Course(id: "bb", title: "Available")).count == 1)
        }
    }
    @Test func duplicateCourseTitlesHaveSeparateDirectories() async throws {
        FixtureProtocol.handler = { request in
            if request.url!.path.hasSuffix("folders") { return (200, "application/json", #"{"data":[]}"#) }
            return (200, "application/json", #"{"data":[{"id":"ee","attributes":{"name":"notes.pdf","filesize":5,"chdate":"1","is-downloadable":true}}]}"#)
        }
        let client = client()
        let first = try await client.files(course: Course(id: "aa", title: "Seminar"))
        let second = try await client.files(course: Course(id: "bb", title: "Seminar"))
        #expect(first[0].components[0] != second[0].components[0])
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["STUDSYNC_LIVE_TEST"] == "1"))
func liveGoettingenReadOnlyCheck() async throws {
    struct Config: Decodable {
        struct User: Decodable { var login: String; var password: String }
        var user: User
    }
    let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/studip-sync/config.json")
    let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: file))
    let client = StudIPClient()
    try await client.signIn(username: config.user.login, password: config.user.password)
    let courses = try await client.courses()
    let course = try #require(courses.first)
    let files = try await client.files(course: course)
    let remote = try #require(files.first(where: { $0.size < 10_000_000 }))
    let temporary = try await client.download(id: remote.id)
    defer { try? FileManager.default.removeItem(at: temporary) }
    #expect(Int64(try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1) == remote.size)
}
