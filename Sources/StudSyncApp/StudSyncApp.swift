import SwiftUI
import AppKit
import Network

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let connectivity = NWPathMonitor()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = AppStore.shared
        connectivity.pathUpdateHandler = { path in
            let available = path.status == .satisfied
            Task { @MainActor in store.networkChanged(available: available) }
        }
        connectivity.start(queue: DispatchQueue(label: "com.gnagster.StudSync.connectivity"))
        store.start()
        if !store.preferences.setupComplete { AppWindows.show(store) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { connectivity.cancel() }
}

@MainActor
enum AppWindows {
    private static var window: NSWindow?
    static func show(_ store: AppStore) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "StudSync"
            window.minSize = NSSize(width: 540, height: 550)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SetupView(store: store))
            window.center(); window.setFrameAutosaveName("StudSyncSettings")
            Self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct StudSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore.shared
    var body: some Scene {
        MenuBarExtra {
            StatusPanel(store: store)
        } label: {
            Image(systemName: store.isBusy ? "arrow.triangle.2.circlepath" : (store.message == nil ? "folder.badge.arrow.down" : "exclamationmark.circle"))
                .accessibilityLabel("StudSync")
        }
        .menuBarExtraStyle(.window)
    }
}
