import Foundation
import Testing
import StudSyncCore
@testable import StudSyncApp

private final class ConnectionFixture: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (@Sendable (URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.response!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class RequestCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.withLock { value += 1; return value } }
}

@Suite(.serialized) @MainActor
struct AppStoreTests {
    private func store(support: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                       writeCredentials: @escaping (Credentials) throws -> Void = { _ in }) -> AppStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConnectionFixture.self]
        let store = AppStore(support: support,
                             client: StudIPClient(session: URLSession(configuration: config)),
                             readCredentials: { nil }, writeCredentials: writeCredentials)
        store.username = "fixture"; store.password = "not-real"
        store.preferences.setupComplete = true
        store.preferences.destination = support.appendingPathComponent("sync").path
        store.preferences.selectedCourses = ["cc"]
        return store
    }
    private func serveCourses(_ courses: [Course]) throws {
        let data = try JSONSerialization.data(withJSONObject: ["data": courses.map { ["id": $0.id, "attributes": ["title": $0.title]] }])
        let body = String(decoding: data, as: UTF8.self)
        ConnectionFixture.response = { request in
            let path = request.url!.path
            if path.isEmpty || path == "/" || path == "/dispatch.php/login" {
                return (200, #"<form action="/dispatch.php/login"><input name="loginname"><input name="password"></form>"#)
            }
            if path.hasSuffix("users/me") { return (200, #"{"data":{"id":"bb"}}"#) }
            if path.hasSuffix("/courses") { return (200, body) }
            return (200, #"{"data":[]}"#)
        }
    }
    private func waitForConnection(_ store: AppStore) async throws {
        let deadline = Date().addingTimeInterval(3)
        while store.isBusy && Date() < deadline { await Task.yield() }
        try #require(!store.isBusy)
    }
    @Test func offlineStartupSchedulesReconnectAndRejectedCredentialsStopIt() async throws {
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        let store = store()
        defer { store.setPaused(true) }
        store.start()
        try await waitForConnection(store)
        #expect(!store.signedIn)
        #expect(store.status == "Waiting for connection")
        #expect(store.nextSync != nil)

        // Fire the actual timer callback without waiting an hour; 401 proves a new request ran.
        ConnectionFixture.response = { _ in (401, "") }
        store.runScheduledSync()
        try await waitForConnection(store)
        #expect(store.status == "Sign-in required")
        #expect(store.nextSync == nil)
    }
    @Test func manualAndPausedModesDoNotRetryOfflineStartup() async throws {
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        for paused in [true, false] {
            let store = store()
            store.preferences.intervalMinutes = paused ? 60 : 0
            store.setPaused(paused)
            store.start()
            try await waitForConnection(store)
            #expect(store.nextSync == nil)
        }
    }
    @Test func successfulWebLoginReplacesPendingPasswordReconnectWithSync() async throws {
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = store(support: support)
        defer { store.setPaused(true); try? FileManager.default.removeItem(at: support) }
        store.start()
        try await waitForConnection(store)
        #expect(store.nextSync != nil)

        ConnectionFixture.response = { request in
            let path = request.url!.path
            #expect(path.hasPrefix("/jsonapi.php/v1/"))
            if path.hasSuffix("/courses") { return (200, #"{"data":[{"id":"cc","attributes":{"title":"Course"}}]}"#) }
            return (200, path.hasSuffix("users/me") ? #"{"data":{"id":"bb"}}"# : #"{"data":[]}"#)
        }
        store.adoptWebSession([])
        try await waitForConnection(store)
        #expect(store.signedIn)
        store.runScheduledSync()
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.preferences.lastSync != nil)
        #expect(store.status == "Up to date")
    }
    @Test func firstRunPersistsSetupAndKeepsCredentialsOutOfSettings() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var saved: Credentials?
        let store = store(support: support, writeCredentials: { saved = $0 })
        defer { store.setPaused(true); try? FileManager.default.removeItem(at: support) }
        store.preferences = Preferences()
        try serveCourses([Course(id: "cc", title: "First"), Course(id: "dd", title: "Second")])
        store.connect()
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.preferences.selectedCourses == ["cc", "dd"])
        #expect(store.password.isEmpty)
        #expect(saved?.username == "fixture")
        #expect(saved?.password == "not-real")

        let destination = support.appendingPathComponent("sync")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        store.preferences.destination = destination.path
        store.preferences.selectedCourses = ["cc"]
        store.preferences.intervalMinutes = 0
        store.finishSetup()
        try await waitForConnection(store)
        #expect(store.preferences.lastSync != nil)
        #expect(store.status == "Up to date")

        let restored = AppStore(support: support, readCredentials: { saved }, writeCredentials: { _ in })
        #expect(restored.preferences.setupComplete)
        #expect(restored.preferences.destination == destination.path)
        #expect(restored.preferences.selectedCourses == ["cc"])
        #expect(restored.preferences.intervalMinutes == 0)
        #expect(restored.username == "fixture")
        let settings = support.appendingPathComponent("settings.json")
        #expect(!(try String(contentsOf: settings, encoding: .utf8)).contains("not-real"))
        let permissions = try FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }
    @Test func setupPersistenceFailureDoesNotStartSyncOrCompleteSetup() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocked".utf8).write(to: support)
        defer { try? FileManager.default.removeItem(at: support) }
        ConnectionFixture.response = { _ in Issue.record("Setup must not start network requests after saving fails"); throw URLError(.badURL) }
        let store = store(support: support)
        store.signedIn = true
        store.preferences.setupComplete = false
        store.finishSetup()
        #expect(!store.preferences.setupComplete)
        #expect(!store.isBusy)
        #expect(store.preferences.lastSync == nil)
        #expect(store.message != nil)
        #expect(store.status == "Settings need attention")
    }
    @Test func courseRefreshPreservesSelectionAndSyncUsesTheCurrentList() async throws {
        let store = store()
        defer { store.setPaused(true) }
        store.signedIn = true
        store.courses = [Course(id: "cc", title: "Old title")]
        try serveCourses([Course(id: "cc", title: "New title"), Course(id: "dd", title: "New course")])
        store.refreshCourses()
        try await waitForConnection(store)
        #expect(Set(store.courses.map(\.id)) == ["cc", "dd"])
        #expect(store.courses.first(where: { $0.id == "cc" })?.title == "New title")
        #expect(store.preferences.selectedCourses == ["cc"])
        #expect(store.preferences.lastSync == nil)

        try serveCourses([Course(id: "dd", title: "New course")])
        store.sync()
        try await waitForConnection(store)
        #expect(store.courses.map(\.id) == ["dd"])
        #expect(store.preferences.selectedCourses == ["cc"])
        #expect(store.preferences.lastSync == nil)
        #expect(store.status == "Choose courses")
    }
    @Test func refreshFailurePreservesCoursesAndRejectedSessionStopsScheduling() async throws {
        let store = store()
        defer { store.setPaused(true) }
        store.signedIn = true
        store.courses = [Course(id: "cc", title: "Saved course")]
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        store.refreshCourses()
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.courses.map(\.id) == ["cc"])
        #expect(store.nextSync != nil)
        ConnectionFixture.response = { _ in (401, "") }
        store.refreshCourses()
        try await waitForConnection(store)
        #expect(!store.signedIn)
        #expect(store.nextSync == nil)
        #expect(store.status == "Sign-in required")
        #expect(store.preferences.selectedCourses == ["cc"])
    }
    @Test func networkRecoveryReconnectsAndSyncsWithoutWaitingForTheTimer() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = store(support: support)
        defer { store.setPaused(true); try? FileManager.default.removeItem(at: support) }
        store.networkChanged(available: false)
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        store.start()
        try await waitForConnection(store)
        try serveCourses([Course(id: "cc", title: "Course")])
        store.networkChanged(available: true)
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.preferences.lastSync != nil)

        store.networkChanged(available: false)
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        store.sync()
        try await waitForConnection(store)
        let previous = store.preferences.lastSync
        try serveCourses([Course(id: "cc", title: "Course")])
        store.networkChanged(available: true)
        try await waitForConnection(store)
        #expect(store.preferences.lastSync! > previous!)
        ConnectionFixture.response = { _ in Issue.record("Repeated online events must not start another sync"); throw URLError(.badURL) }
        store.networkChanged(available: true)
        #expect(!store.isBusy)
    }
    @Test func networkRecoveryDuringAnActiveRequestIsNotLost() async throws {
        let store = store()
        defer { store.setPaused(true) }
        store.signedIn = true
        store.networkChanged(available: false)
        let requests = RequestCount()
        ConnectionFixture.response = { _ in
            if requests.increment() == 1 { throw URLError(.notConnectedToInternet) }
            return (401, "")
        }
        store.refreshCourses()
        // Main-actor isolation keeps the response task pending until we yield below.
        store.networkChanged(available: true)
        try await waitForConnection(store)
        #expect(store.status == "Sign-in required")
        #expect(!store.signedIn)
        #expect(!store.isBusy) // The queued transition was consumed once, without a retry loop.
    }
    @Test func networkRecoveryRespectsManualPauseAndRejectedCredentials() async throws {
        for mode in ["manual", "paused", "rejected"] {
            let store = store()
            defer { store.setPaused(true) }
            store.networkChanged(available: false)
            ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
            store.start()
            try await waitForConnection(store)
            if mode == "manual" { store.preferences.intervalMinutes = 0 }
            if mode == "paused" { store.setPaused(true) }
            if mode == "rejected" {
                ConnectionFixture.response = { _ in (401, "") }
                store.runScheduledSync()
                try await waitForConnection(store)
            }
            ConnectionFixture.response = { _ in Issue.record("Network recovery must respect user choices and rejected login"); throw URLError(.badURL) }
            store.networkChanged(available: true)
            #expect(!store.isBusy)
            #expect(!store.signedIn)
        }
    }
}
