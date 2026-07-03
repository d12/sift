import AppKit
import SwiftUI

// MARK: – Delegate protocol

@MainActor
protocol SearchWindowControllerDelegate: AnyObject {
    func searchWindowDidClose()
}

// MARK: – Controller

@MainActor
final class SearchWindowController: NSWindowController, NSWindowDelegate {

    weak var delegate: SearchWindowControllerDelegate?

    convenience init() {
        let panel = SearchPanel()
        self.init(window: panel)
        panel.delegate = self

        let searchView = SearchView { [weak self] in self?.close() }
        let host = NSHostingController(rootView: searchView)
        // Let the hosting controller resize the panel as SwiftUI content changes
        // (e.g. when results appear). Width is fixed by frame(width:680) in SearchView;
        // height grows and shrinks automatically.
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host

        positionOnScreen()
    }

    private func positionOnScreen() {
        guard let screen = NSScreen.main, let window else { return }
        let x = screen.visibleFrame.midX - window.frame.width / 2
        let y = screen.visibleFrame.midY + 80          // slightly above center
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    override func showWindow(_ sender: Any?) {
        positionOnScreen()
        window?.makeKeyAndOrderFront(sender)
        // Give the run-loop one cycle to actually make the window key, then hand
        // focus to the SwiftUI content so @FocusState picks it up reliably.
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.window?.contentView)
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Close when the user clicks away from the search panel.
        close()
    }

    private var isClosing = false

    override func close() {
        // Guard against re-entrant calls: closing a key window causes it to resign
        // key status, which fires windowDidResignKey → close() again before the
        // first close() has finished. Without this guard, searchWindowDidClose()
        // would be called twice.
        guard !isClosing else { return }
        isClosing = true
        super.close()
        delegate?.searchWindowDidClose()
    }
}

// MARK: – Custom NSPanel

private final class SearchPanel: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 64),
            // .hudWindow is intentionally omitted: HUD panels behave like
            // non-activating palettes and swallow keyboard events.
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        contentMinSize = NSSize(width: 680, height: 64)
        // .transient implies .moveToActiveSpace which conflicts with .canJoinAllSpaces.
        // Use .stationary instead to keep the panel on all spaces without moving it.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
