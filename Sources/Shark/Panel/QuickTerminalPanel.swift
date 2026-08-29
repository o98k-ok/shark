import AppKit

/// The drop-down window. All window-level policy lives here so the
/// top-most behaviour is expressed in exactly one place.
final class QuickTerminalPanel: NSPanel {

    // A borderless panel refuses key status by default, but the terminal needs typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Returns true when the event was consumed as a Shark command.
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var onFirstResponderChange: ((NSResponder?) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            // `.nonactivatingPanel` is what lets a menu-bar agent overlay a
            // full-screen Space. Activating the app instead makes macOS park
            // the panel on the Space behind it. `canBecomeKey` + `makeKey()`
            // still give the terminal typing focus.
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isMovableByWindowBackground = false

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        animationBehavior = .none
        // `canJoinAllSpaces` does not include full-screen Spaces and it
        // suppresses `moveToActiveSpace`. Order-front then joins the Space
        // the user is actually looking at, including native full-screen.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        applyLevel(AppSettings.shared.panelLevel)
    }

    func applyLevel(_ level: PanelLevel) {
        self.level = level.windowLevel
    }

    // The app is an agent without a visible menu bar, so command shortcuts are
    // resolved here rather than through NSMenu key equivalents.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted { onFirstResponderChange?(responder) }
        return accepted
    }
}
