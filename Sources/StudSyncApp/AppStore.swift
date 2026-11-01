import AppKit
import Foundation
import Observation
import ServiceManagement
import StudSyncCore

@MainActor @Observable
final class AppStore {
    static let shared = AppStore()
    var preferences = Preferences()
    var courses: [Course] = []
    var username = ""
    var password = ""
    var message: String?
    var status = "Ready"
    var isBusy = false
    var paused = false
    var signedIn = false
    var completed = 0
    var total = 0
    var bytes: Int64 = 0
    var showWebLogin = false
    var changes: [Change] { preferences.changes }
    let client: StudIPClient
    var nextSync: Date?
    private var engine: SyncEngine?
    private var storageError: String?
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var reconnectPending = false
    private var retrySyncWhenOnline = false
    private var networkAvailable: Bool?
    private var networkRecoveryPending = false
    private let support: URL
    private let writeCredentials: (Credentials) throws -> Void
    private var settingsURL: URL { support.appendingPathComponent("settings.json") }

    init(support: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StudSync"),
         client: StudIPClient = StudIPClient(),
         readCredentials: () throws -> Credentials? = CredentialVault.read,
         writeCredentials: @escaping (Credentials) throws -> Void = CredentialVault.save) {
        self.support = support; self.client = client
        self.writeCredentials = writeCredentials
        do { engine = try SyncEngine(manifest: support.appendingPathComponent("manifest.json")) }
        catch { storageError = error.localizedDescription; message = storageError }
        do {
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                preferences = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: settingsURL))
            }
            if let saved = try readCredentials() { username = saved.username; password = saved.password }
        } catch { message = error.localizedDescription }
    }

    func start() {
        guard !username.isEmpty, !password.isEmpty else { return }
        connect()
    }
    func connect() {
        guard !isBusy else { return }
        guard engine != nil else { message = storageError; return }
        let credentials = Credentials(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        reconnectPending = false
        isBusy = true; message = nil; status = "Signing in…"
        task = Task {
            var syncOnSuccess = false
            defer { isBusy = false; schedule(); if syncOnSuccess { sync() }; resumeAfterNetworkChange() }
            do {
                try await client.signIn(username: credentials.username, password: credentials.password)
                try writeCredentials(credentials)
                courses = try await client.courses()
                signedIn = true; status = "Ready"
                if preferences.selectedCourses.isEmpty && !preferences.setupComplete {
                    preferences.selectedCourses = Set(courses.map(\.id))
                }
                password = ""
                syncOnSuccess = preferences.setupComplete
            } catch {
                signedIn = false
                reconnectPending = canRetryConnection(error)
                status = reconnectPending ? "Waiting for connection" : "Sign-in required"
                message = error.localizedDescription
            }
        }
    }
    func finishSetup() {
        guard !isBusy, signedIn, !preferences.destination.isEmpty, !preferences.selectedCourses.isEmpty else { return }
        let wasComplete = preferences.setupComplete
        preferences.setupComplete = true
        guard save() else {
            preferences.setupComplete = wasComplete
            status = "Settings need attention"
            return
        }
        schedule(); sync()
    }
    @discardableResult func save() -> Bool {
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try JSONEncoder().encode(preferences).write(to: settingsURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Choose sync folder"
        if panel.runModal() == .OK, let url = panel.url {
            preferences.destination = url.path; save()
        }
    }
    func reveal(_ path: String? = nil) {
        let path = path ?? preferences.destination
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    var canSync: Bool {
        signedIn && !paused && preferences.setupComplete && !preferences.destination.isEmpty && !preferences.selectedCourses.isEmpty
    }
    func refreshCourses() {
        guard !isBusy, signedIn else { return }
        retrySyncWhenOnline = false
        isBusy = true; message = nil; status = "Loading courses…"
        task = Task {
            defer { isBusy = false; schedule(); resumeAfterNetworkChange() }
            do { courses = try await client.courses(); status = "Ready" }
            catch { reportSyncFailure(error) }
        }
    }
    private func reportSyncFailure(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { status = "Cancelled"; return }
        if case StudSyncError.authentication = error {
            signedIn = false; reconnectPending = false; status = "Sign-in required"
        } else { status = "Sync needs attention" }
        retrySyncWhenOnline = canRetryConnection(error)
        message = error.localizedDescription
    }
    private func canRetryConnection(_ error: Error) -> Bool {
        if let error = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
        }
        if case StudSyncError.http(let code) = error { return (500..<600).contains(code) }
        return false
    }
    func networkChanged(available: Bool) {
        let wasOffline = networkAvailable == false
        networkAvailable = available
        if wasOffline && available { networkRecoveryPending = true }
        resumeAfterNetworkChange()
    }
    private func resumeAfterNetworkChange() {
        guard networkRecoveryPending, !isBusy else { return }
        networkRecoveryPending = false
        guard networkAvailable == true, !paused, preferences.setupComplete,
              preferences.intervalMinutes > 0, !preferences.destination.isEmpty,
              !preferences.selectedCourses.isEmpty else { return }
        if signedIn && retrySyncWhenOnline { sync() }
        else if reconnectPending { connect() }
    }
    func sync() {
        guard !isBusy, canSync, let engine else { return }
        retrySyncWhenOnline = false
        isBusy = true; message = nil; completed = 0; total = 0; bytes = 0; status = "Checking courses…"
        let selectedIDs = preferences.selectedCourses
        let root = URL(fileURLWithPath: preferences.destination, isDirectory: true)
        task = Task {
            defer { isBusy = false; schedule(); resumeAfterNetworkChange() }
            do {
                courses = try await client.courses()
                let selected = courses.filter { selectedIDs.contains($0.id) }
                guard !selected.isEmpty else {
                    status = "Choose courses"
                    message = "No selected courses are currently available. Check your course selection in Settings."
                    return
                }
                for course in selected {
                    try Task.checkCancellation()
                    status = course.title
                    let files = try await client.files(course: course)
                    total += files.count
                    for file in files {
                        try Task.checkCancellation()
                        if let change = try await engine.synchronize(file, courseID: course.id, root: root, fetch: { [client] in
                            try await client.download(id: file.id)
                        }) {
                            preferences.changes.insert(change, at: 0)
                            preferences.changes = Array(preferences.changes.prefix(200))
                            bytes += file.size
                            save()
                        }
                        completed += 1
                    }
                }
                preferences.lastSync = Date(); status = "Up to date"; save()
            } catch { reportSyncFailure(error) }
        }
    }
    func cancel() { task?.cancel() }
    func schedule() {
        timer?.cancel()
        nextSync = nil
        guard !paused, signedIn || reconnectPending, preferences.setupComplete,
              !preferences.destination.isEmpty, !preferences.selectedCourses.isEmpty, preferences.intervalMinutes > 0 else { return }
        let delay = Double(preferences.intervalMinutes * 60)
        nextSync = Date().addingTimeInterval(delay)
        timer = Task {
            do { try await Task.sleep(for: .seconds(delay)); runScheduledSync() } catch { }
        }
    }
    func runScheduledSync() {
        if signedIn { sync() } else if reconnectPending { connect() }
    }
    func setPaused(_ value: Bool) { paused = value; schedule() }
    func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { message = error.localizedDescription }
    }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    func importCLI() {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/studip-sync/config.json")
        struct OldConfig: Decodable {
            struct User: Decodable { var login: String; var password: String? }
            var user: User
            var files_destination: String?
        }
        do {
            let old = try JSONDecoder().decode(OldConfig.self, from: Data(contentsOf: path))
            username = old.user.login; password = old.user.password ?? ""
            if let destination = old.files_destination {
                preferences.destination = (destination as NSString).expandingTildeInPath
            }
            message = "Imported locally. Sign in to verify and save in Keychain. The old configuration was not changed."
        } catch { message = "The CLI configuration could not be imported. Enter your details instead." }
    }
    func adoptWebSession(_ cookies: [HTTPCookie]) {
        guard !isBusy else { return }
        guard engine != nil else { message = storageError; return }
        isBusy = true
        task = Task {
            defer { isBusy = false }
            do {
                try await client.adopt(cookies: cookies)
                courses = try await client.courses()
                signedIn = true; showWebLogin = false; status = "Ready"; message = nil
                reconnectPending = false
                if !preferences.setupComplete { preferences.selectedCourses = Set(courses.map(\.id)) }
                schedule()
            } catch { message = "Finish signing into Stud.IP, then click Continue." }
        }
    }
}
