import SwiftUI

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
}

@main
struct SiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(AppSettings.shared)
        }

        MenuBarExtra {
            MenuBarContent(appDelegate: appDelegate)
        } label: {
            Image(systemName: "sparkle.magnifyingglass")
        }
    }
}

// MARK: – Menu content

private struct MenuBarContent: View {
    let appDelegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Show Sift") { appDelegate.toggle() }
        Divider()
        Button("Reindex All") { Task { await IndexManager.shared.reindexAll() } }
        Divider()
        Button("Settings…") { showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Sift") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
        // Bridge: lets AppKit code (AppDelegate alert) trigger openSettings
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
                showSettings()
            }
    }

    private func showSettings() {
        // Flag all existing non-panel windows to move to the current Space
        // when ordered front, so Settings always appears where the user is.
        for window in NSApp.windows where !(window is NSPanel) {
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
        openSettings()
        // Raise and then remove the transient flag so the window stays where
        // it landed from this point on.
        DispatchQueue.main.async {
            for window in NSApp.windows where !(window is NSPanel) {
                window.makeKeyAndOrderFront(nil)
                window.collectionBehavior.remove(.moveToActiveSpace)
            }
        }
    }
}
