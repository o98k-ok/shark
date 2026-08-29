import AppKit

enum HideReason {
    case hotkey
    case menuCommand
    case appDeactivated
    case windowResignedKey

    var isFocusLoss: Bool {
        self == .appDeactivated || self == .windowResignedKey
    }
}

/// Owns the show/hide state machine for the quick terminal panel.
final class PanelController: NSObject, NSWindowDelegate {

    let panel: QuickTerminalPanel
    let session: WindowSession

    private(set) var isVisible = false
    private var isAnimating = false

    /// Focus loss right after `show()` is spurious; ignore it briefly.
    private var ignoreResignUntil: Date = .distantPast
    private let resignGracePeriod: TimeInterval = 0.25
    private let animationDuration: TimeInterval = 0.12

    /// Raised while the status-bar menu or a settings popover is open, so
    /// interacting with them does not dismiss the terminal.
    var suppressAutoHide = false

    override init() {
        panel = QuickTerminalPanel()
        session = WindowSession()
        super.init()

        panel.delegate = self
        panel.contentView = session.rootView
        panel.onKeyEquivalent = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
        panel.onFirstResponderChange = { [weak self] responder in
            self?.session.syncFocus(with: responder)
        }
        session.onEmpty = { [weak self] in self?.hide(reason: .menuCommand) }
        session.onFocusRequest = { [weak self] view in
            _ = self?.panel.makeFirstResponder(view)
        }

        observeNotifications()
        applyAppearance()
    }

    // MARK: - Public commands

    func toggle() {
        isVisible ? hide(reason: .hotkey) : show()
    }

    func show() {
        guard !isAnimating, !isVisible else {
            focusTerminal()
            return
        }

        ignoreResignUntil = Date().addingTimeInterval(resignGracePeriod)

        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        let screen = ScreenLocator.targetScreen()
        let endFrame = ScreenLocator.visibleFrame(on: screen)
        panel.applyLevel(AppSettings.shared.panelLevel)

        // Land on the target screen first so Space assignment sees a real
        // intersection. Ordering front from an off-screen frame is how the
        // panel used to miss native full-screen Spaces.
        panel.alphaValue = 0
        panel.setFrame(endFrame, display: false)

        // The shell must not start before the terminal view knows its size, or the
        // first prompt is written into a zero-sized grid and never reappears.
        panel.contentView?.layoutSubtreeIfNeeded()
        session.ensureStarted()

        // Never `NSApp.activate` here. An accessory app that activates while a
        // full-screen Space is frontmost is moved to the Space behind it.
        panel.orderFrontRegardless()
        PanelLog.logger.notice("""
            fronted: activeSpace=\(self.panel.isOnActiveSpace, privacy: .public) \
            front=\(front, privacy: .public)
            """)

        isVisible = true
        isAnimating = true

        panel.setFrame(ScreenLocator.hiddenFrame(on: screen), display: false)
        panel.alphaValue = 1

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.isAnimating = false
            self.panel.makeKey()
            self.focusTerminal()
            PanelLog.logger.notice("""
                shown: key=\(self.panel.isKeyWindow, privacy: .public) \
                active=\(NSApp.isActive, privacy: .public) \
                visible=\(self.panel.isVisible, privacy: .public) \
                activeSpace=\(self.panel.isOnActiveSpace, privacy: .public) \
                front=\(front, privacy: .public) \
                target=\(Int(screen.frame.minX), privacy: .public) \
                landed=\(Int(self.panel.screen?.frame.minX ?? -9999), privacy: .public)
                """)
        }
    }

    func hide(reason: HideReason) {
        guard isVisible, !isAnimating else { return }
        if reason.isFocusLoss {
            guard AppSettings.shared.hideOnDeactivate else { return }
            guard !suppressAutoHide, Date() >= ignoreResignUntil else { return }
        }

        PanelLog.logger.notice("""
            hide: reason=\(String(describing: reason), privacy: .public) \
            key=\(self.panel.isKeyWindow, privacy: .public) \
            active=\(NSApp.isActive, privacy: .public)
            """)
        isVisible = false
        isAnimating = true

        let screen = panel.screen ?? ScreenLocator.targetScreen()
        let endFrame = ScreenLocator.hiddenFrame(on: screen)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            // Hidden, never closed: the shells keep running.
            self.panel.orderOut(nil)
            self.isAnimating = false
        }
    }

    /// The status menu and the hotkey recorder steal key status; when they close,
    /// focus goes straight back to the terminal instead of being read as "user
    /// switched away", which would dismiss the panel mid-setting-change.
    func resumeAfterAuxiliaryUI() {
        suppressAutoHide = false
        guard isVisible else { return }
        ignoreResignUntil = Date().addingTimeInterval(resignGracePeriod)
        panel.makeKey()
        focusTerminal()
    }

    private func focusTerminal() {
        guard let view = session.focusedTerminalView else { return }
        _ = panel.makeFirstResponder(view)
    }

    // MARK: - Keyboard commands

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if let command = PaneCommand.allCases.first(where: { matches(event, flags, AppSettings.shared.combo(for: .pane($0))) }) {
            perform(command)
            return true
        }

        guard flags.subtracting(.shift) == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            session.copySelection()
        case "v":
            session.paste()
        case "+", "=":
            AppSettings.shared.fontSize += 1
        case "-":
            AppSettings.shared.fontSize -= 1
        case "0":
            AppSettings.shared.fontSize = AppSettings.defaultFontSize
        default:
            return false
        }
        return true
    }

    private func matches(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ combo: HotkeyCombo) -> Bool {
        UInt32(event.keyCode) == combo.keyCode
            && flags == KeyCodeFormatter.modifierFlags(from: combo.modifiers)
    }

    private func perform(_ command: PaneCommand) {
        switch command {
        case .split:
            session.splitLeftRight()
        case .closePane:
            session.isSplit ? session.closeFocusedPane() : hide(reason: .menuCommand)
        case .focusOther:
            session.focusOtherPane()
        case .clear:
            session.clearFocusedPane()
        }
    }

    // MARK: - Appearance & geometry

    private func applyAppearance() {
        let settings = AppSettings.shared
        panel.alphaValue = 1
        session.applyAppearance(theme: settings.theme, font: settings.font, opacity: settings.opacity)
    }

    private func applyGeometry() {
        panel.applyLevel(AppSettings.shared.panelLevel)
        guard isVisible else { return }
        let screen = panel.screen ?? ScreenLocator.targetScreen()
        panel.setFrame(ScreenLocator.visibleFrame(on: screen), display: true)
    }

    private func observeNotifications() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: .sharkAppearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.applyAppearance() }

        center.addObserver(
            forName: .sharkGeometryChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.applyGeometry() }

        center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.hide(reason: .appDeactivated) }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking another pane or dragging the divider stays inside the panel,
        // so only a genuine loss of key status reaches here.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.panel.isKeyWindow else { return }
            self.hide(reason: .windowResignedKey)
        }
    }
}
