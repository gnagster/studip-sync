import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = AppStore.shared
        store.start()
        if !store.preferences.setupComplete { AppWindows.show(store) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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
