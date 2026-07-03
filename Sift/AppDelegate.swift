import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The global shortcut to show/hide Sift. Default: ⌥Space (same convention as Raycast/Alfred).
    /// ⌘Space is Spotlight, ⌘⌥Space is Finder search — both are taken by macOS.
    static let toggleSift = Self("toggleSift", default: .init(.space, modifiers: [.option]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var searchWindowController: SearchWindowController?
    /// The app that was frontmost before Sift appeared, so we can restore focus.
    private var previousApp: NSRunningApplication?

    // MARK: – Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        // If another instance is already running (common during Xcode dev),
        // activate it and exit silently before completing our own startup.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != NSRunningApplication.current }
            if let existing = others.first {
                existing.activate(options: .activateIgnoringOtherApps)
                NSApp.terminate(nil)
                return
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // hide from Dock

        setupHotkey()

        Task { await IndexManager.shared.initialize() }

        // Listen for excessive re-indexing notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExcessiveReindexing(_:)),
            name: .excessiveReindexingDetected,
            object: nil
        )
    }

    // MARK: – Global hotkey

    private func setupHotkey() {
        KeyboardShortcuts.onKeyUp(for: .toggleSift) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
    }

    // MARK: – Show / hide

    func toggle() {
        if searchWindowController?.window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        // Activate first so the window is already key when makeKeyAndOrderFront runs.
        NSApp.activate(ignoringOtherApps: true)

        if searchWindowController == nil {
            searchWindowController = SearchWindowController()
            searchWindowController?.delegate = self
        }
        searchWindowController?.showWindow(nil)
    }

    private func hide() {
        // Capture and clear previousApp *before* closing the window.
        // closing triggers searchWindowDidClose() synchronously, which also nils
        // previousApp — so we must grab it first.
        let appToRestore = previousApp
        previousApp = nil
        searchWindowController?.close()
        searchWindowController = nil
        appToRestore?.activate(options: .activateIgnoringOtherApps)
    }

    // MARK: – Excessive re-indexing alert

    @objc private func handleExcessiveReindexing(_ note: Notification) {
        let path = note.userInfo?["path"] as? String ?? "Unknown"
        let alert = NSAlert()
        alert.messageText = "Excessive Re-indexing Detected"
        alert.informativeText = """
            The path "\(path)" is generating a very high number of file-system events and has been \
            paused to protect system performance. You can review or remove this rule in Settings.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Dismiss")
        if alert.runModal() == .alertFirstButtonReturn {
            // Routed through MenuBarContent which holds the openSettings environment action
            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
        }
    }
}

// MARK: – SearchWindowControllerDelegate

extension AppDelegate: SearchWindowControllerDelegate {
    func searchWindowDidClose() {
        searchWindowController = nil
        // Do NOT restore previousApp here. When the panel closes because the user
        // clicked away, macOS has already moved focus to the clicked app naturally.
        // Calling previousApp?.activate() would undo that and — worse — cause Sift
        // to voluntarily surrender activation, after which NSApp.activate() from the
        // next hotkey press is throttled by macOS 14+ and the window never appears.
        // Focus is only restored explicitly from hide() when the user toggles off.
        previousApp = nil
    }
}
