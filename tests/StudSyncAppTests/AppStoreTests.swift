import Foundation
import Testing
import StudSyncCore
@testable import StudSyncApp

private final class ConnectionFixture: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (@Sendable () throws -> Int)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let status = try Self.response!()
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized) @MainActor
struct AppStoreTests {
    private func store() -> AppStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConnectionFixture.self]
        let store = AppStore(support: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                             client: StudIPClient(session: URLSession(configuration: config)), loadStoredState: false)
        store.username = "fixture"; store.password = "not-real"
        store.preferences.setupComplete = true
        return store
    }
    private func waitForConnection(_ store: AppStore) async throws {
        let deadline = Date().addingTimeInterval(3)
        while store.isBusy && Date() < deadline { await Task.yield() }
        try #require(!store.isBusy)
    }
    @Test func offlineStartupSchedulesReconnectAndRejectedCredentialsStopIt() async throws {
        ConnectionFixture.response = { throw URLError(.notConnectedToInternet) }
        let store = store()
        defer { store.setPaused(true) }
        store.start()
        try await waitForConnection(store)
        #expect(!store.signedIn)
        #expect(store.status == "Waiting for connection")
        #expect(store.nextSync != nil)

        // Fire the actual timer callback without waiting an hour; 401 proves a new request ran.
        ConnectionFixture.response = { 401 }
        store.runScheduledSync()
        try await waitForConnection(store)
        #expect(store.status == "Sign-in required")
        #expect(store.nextSync == nil)
    }
    @Test func manualAndPausedModesDoNotRetryOfflineStartup() async throws {
        ConnectionFixture.response = { throw URLError(.notConnectedToInternet) }
        for paused in [true, false] {
            let store = store()
            store.preferences.intervalMinutes = paused ? 60 : 0
            store.setPaused(paused)
            store.start()
            try await waitForConnection(store)
            #expect(store.nextSync == nil)
        }
    }
}
