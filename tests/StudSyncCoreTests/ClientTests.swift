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
    #expect(!courses.isEmpty)
    if let course = courses.first {
        let files = try await client.files(course: course)
        if let file = files.first, file.size < 10_000_000 {
            let temporary = try await client.download(id: file.id)
            defer { try? FileManager.default.removeItem(at: temporary) }
            #expect(Int64(try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1) == file.size)
        }
    }
}
