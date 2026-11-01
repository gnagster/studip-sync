import SwiftUI
import AppKit
import WebKit
import StudSyncCore

func L(_ key: String) -> String {
    let bundled = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("StudSync_StudSyncApp.bundle")) }
    return NSLocalizedString(key, bundle: bundled ?? .module, comment: "")
}

struct StatusPanel: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.arrow.down").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("StudSync").font(.headline)
                    Text(L(store.paused ? "Paused" : store.status)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if store.isBusy { ProgressView().controlSize(.small) }
            }
            if store.isBusy && store.total > 0 {
                ProgressView(value: Double(store.completed), total: Double(store.total))
                Text("\(store.completed) / \(store.total)").font(.caption).monospacedDigit()
            }
            HStack {
                stat("Last sync", value: store.preferences.lastSync.map { $0.formatted(date: .omitted, time: .shortened) } ?? L("Not yet"))
                Spacer()
                stat("Next sync", value: store.nextSync.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                Spacer()
                stat("Courses", value: String(store.preferences.selectedCourses.count))
            }
            if store.bytes > 0 { Text(ByteCountFormatter.string(fromByteCount: store.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
            if let message = store.message {
                Text(L(message)).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(L(store.isBusy ? "Cancel" : "Sync now")) {
                    if store.isBusy { store.cancel() } else { store.sync() }
                }.buttonStyle(.borderedProminent).disabled(!store.signedIn || !store.preferences.setupComplete || store.paused)
                Button(L(store.paused ? "Resume" : "Pause")) { store.setPaused(!store.paused) }.disabled(store.isBusy)
                Spacer()
                Button { store.reveal() } label: { Image(systemName: "folder") }.help(L("Open in Finder")).disabled(store.preferences.destination.isEmpty)
            }
            Divider()
            Text(L("Recent changes")).font(.subheadline.bold())
            if store.changes.isEmpty {
                ContentUnavailableView(L("No changes yet"), systemImage: "checkmark.circle", description: Text(L("Downloaded files will appear here.")))
                    .frame(height: 110)
            } else {
                ForEach(store.changes.prefix(5)) { change in
                    Button { store.reveal(change.path) } label: {
                        HStack(alignment: .top) {
                            Image(systemName: change.conflict ? "exclamationmark.triangle" : "doc.badge.arrow.up")
                                .foregroundStyle(change.conflict ? .orange : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.name).lineLimit(1)
                                Text(change.conflict ? L("Local edits preserved") : change.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).help(L("Reveal in Finder"))
                }
            }
            Divider()
            HStack {
                Button(L(store.preferences.setupComplete ? "Settings…" : "Set up StudSync…")) { AppWindows.show(store) }
                Spacer()
                Button(L("Quit")) { NSApp.terminate(nil) }
            }.font(.caption)
        }.padding(18).frame(width: 380)
    }
    private func stat(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(key)).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold()).monospacedDigit()
        }
    }
}

struct SetupView: View {
    @Bindable var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Image(systemName: "folder.badge.arrow.down").font(.system(size: 42)).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.preferences.setupComplete ? L("Your courses, in Finder.") : L("Welcome to StudSync")).font(.largeTitle.bold())
                        Text(L("Universität Göttingen · Stud.IP")).foregroundStyle(.secondary)
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        heading("1", "Connect your university", done: store.signedIn)
                        TextField(L("Username (without email suffix)"), text: $store.username).textContentType(.username)
                        SecureField(L("Password"), text: $store.password).textContentType(.password)
                        HStack {
                            Button(L("Sign in")) { store.connect() }
                                .buttonStyle(.borderedProminent).disabled(store.username.isEmpty || store.password.isEmpty || store.isBusy)
                            Button(L("University web login…")) { store.showWebLogin = true }.disabled(store.isBusy)
                            if store.isBusy { ProgressView().controlSize(.small) }
                            if store.signedIn { Label(L("Connected"), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        }
                        Text(L("Credentials stay in your Mac’s Keychain. StudSync reuses your session and attempts one re-login when it expires."))
                            .font(.caption).foregroundStyle(.secondary)
                        if !store.preferences.setupComplete {
                            Button(L("Import existing CLI setup…")) { store.importCLI() }.font(.caption).disabled(store.isBusy)
                        }
                    }.padding(10)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        heading("2", "Choose your Finder folder", done: !store.preferences.destination.isEmpty)
                        HStack {
                            Text(store.preferences.destination.isEmpty ? L("No folder selected") : store.preferences.destination)
                                .foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                            Spacer()
                            Button(L("Choose…")) { store.chooseDestination() }.disabled(store.isBusy)
                        }
                        Text(L("Untouched files update automatically. Local edits are kept; incoming versions appear beside them. Server deletions never delete your files."))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        heading("3", "Choose courses", done: !store.preferences.selectedCourses.isEmpty)
                        if store.courses.isEmpty {
                            Text(L("Sign in to load your current courses.")).foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Button(L("Select all")) { store.preferences.selectedCourses = Set(store.courses.map(\.id)); store.save() }
                                Button(L("Select none")) { store.preferences.selectedCourses = []; store.save() }
                            }.font(.caption).disabled(store.isBusy)
                            ForEach(store.courses) { course in
                                Toggle(course.title, isOn: Binding(get: { store.preferences.selectedCourses.contains(course.id) }, set: { value in
                                    if value { store.preferences.selectedCourses.insert(course.id) } else { store.preferences.selectedCourses.remove(course.id) }
                                    store.save()
                                })).disabled(store.isBusy)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                HStack {
                    Picker(L("Sync"), selection: $store.preferences.intervalMinutes) {
                        Text(L("Manually")).tag(0)
                        Text(L("Every 15 minutes")).tag(15)
                        Text(L("Hourly")).tag(60)
                        Text(L("Every 4 hours")).tag(240)
                    }.frame(maxWidth: 260)
                    Spacer()
                    Toggle(L("Start at Login"), isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                }.disabled(store.isBusy)
                if let message = store.message {
                    Label(L(message), systemImage: "info.circle").font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text(L("StudSync stays in your menu bar when this window closes.")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L(store.preferences.setupComplete ? "Sync now" : "Start syncing")) { store.finishSetup() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.signedIn || store.preferences.destination.isEmpty || store.preferences.selectedCourses.isEmpty || store.isBusy)
                }
            }.padding(26)
        }
        .onChange(of: store.preferences.intervalMinutes) { store.save(); store.schedule() }
        .sheet(isPresented: $store.showWebLogin) { WebLogin(store: store) }
    }
    private func heading(_ number: String, _ title: String, done: Bool) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(L(title)).font(.headline)
        }
    }
}

struct WebLogin: View {
    @Bindable var store: AppStore
    @State private var webView = WKWebView()
    var body: some View {
        VStack(spacing: 0) {
            WebContent(webView: webView)
            HStack {
                Text(L("Finish the official university sign-in, then continue.")).font(.caption)
                Spacer()
                Button(L("Cancel")) { store.showWebLogin = false }
                Button(L("Continue")) {
                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        Task { @MainActor in store.adoptWebSession(cookies) }
                    }
                }.buttonStyle(.borderedProminent).disabled(store.isBusy)
            }.padding()
        }.frame(width: 760, height: 660)
        .onAppear { webView.load(URLRequest(url: StudIPClient.origin.appendingPathComponent("dispatch.php/my_courses"))) }
    }
}
struct WebContent: NSViewRepresentable {
    var webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) { }
}
