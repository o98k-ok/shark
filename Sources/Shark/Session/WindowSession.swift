import AppKit

/// The single window's content: one or two side-by-side shells.
/// Hiding the panel never touches this state, so layout and processes survive.
final class WindowSession: NSObject, NSSplitViewDelegate {

    static let maxPanes = 2

    let rootView = NSView()
    private let splitView = SharkSplitView()

    private(set) var panes: [TerminalPane] = []
    private(set) var focused: TerminalPane?

    /// Adding or removing a pane makes `NSSplitView` report intermediate widths;
    /// only a real divider drag should be persisted as the user's ratio.
    private var isAdjustingPanes = false

    /// Fired when the last shell is gone; the panel hides and a fresh pane is
    /// created on the next show.
    var onEmpty: (() -> Void)?
    /// Asks the window to route the keyboard to this view.
    var onFocusRequest: ((NSView) -> Void)?

    var isSplit: Bool { panes.count > 1 }
    var canSplit: Bool { panes.count < Self.maxPanes }
    var focusedTerminalView: NSView? { focused?.terminalView }

    override init() {
        super.init()

        rootView.wantsLayer = true
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: rootView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
        ])
    }

    // MARK: - Lifecycle

    func ensureStarted() {
        guard panes.isEmpty else { return }
        let pane = makePane()
        install(pane)
        pane.start(inDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
        setFocus(pane)
    }

    func terminateAll() {
        panes.forEach { $0.terminate() }
        panes.removeAll()
        focused = nil
    }

    // MARK: - Commands

    func splitLeftRight() {
        guard canSplit, let origin = focused else { return }

        let directory = origin.currentDirectory
        let pane = makePane()
        withoutPersistingRatio {
            install(pane)
            applyStoredRatio()
        }
        pane.start(inDirectory: directory)
        setFocus(pane)
    }

    func closeFocusedPane() {
        guard let pane = focused else { return }
        remove(pane)
    }

    func focusOtherPane() {
        guard isSplit, let current = focused else { return }
        guard let other = panes.first(where: { $0 !== current }) else { return }
        setFocus(other)
    }

    func copySelection() { focused?.copySelection() }
    func paste() { focused?.paste() }
    func clearFocusedPane() { focused?.clear() }

    var hasPanes: Bool { !panes.isEmpty }

    /// Keeps `focused` in step with the window's real first responder, so clicking
    /// a pane and the menu commands cannot disagree.
    func syncFocus(with responder: NSResponder?) {
        guard let view = responder as? NSView else { return }
        guard let pane = panes.first(where: { view.isDescendant(of: $0.containerView) }) else { return }
        guard pane !== focused else { return }
        focused = pane
        refreshFocusIndicators()
    }

    // MARK: - Appearance

    func applyAppearance(theme: TerminalTheme, font: NSFont, opacity: CGFloat) {
        rootView.layer?.backgroundColor = theme.background.withAlphaComponent(opacity).cgColor
        splitView.themeDividerColor = theme.selectionBackground
        panes.forEach { $0.apply(theme: theme, font: font, opacity: opacity) }
    }

    // MARK: - Internals

    private func makePane() -> TerminalPane {
        let pane = TerminalPane()
        let settings = AppSettings.shared
        pane.apply(theme: settings.theme, font: settings.font, opacity: settings.opacity)
        pane.onExit = { [weak self] pane in
            DispatchQueue.main.async { self?.remove(pane) }
        }
        return pane
    }

    private func withoutPersistingRatio(_ body: () -> Void) {
        isAdjustingPanes = true
        body()
        isAdjustingPanes = false
    }

    /// Adds the pane and lays it out; the caller starts the shell afterwards so the
    /// PTY is sized correctly from its very first byte.
    private func install(_ pane: TerminalPane) {
        panes.append(pane)
        splitView.addArrangedSubview(pane.containerView)
        splitView.layoutSubtreeIfNeeded()
    }

    private func remove(_ pane: TerminalPane) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }

        pane.terminate()
        panes.remove(at: index)
        withoutPersistingRatio {
            splitView.removeArrangedSubview(pane.containerView)
            pane.containerView.removeFromSuperview()
            splitView.layoutSubtreeIfNeeded()
        }

        if let survivor = panes.first {
            setFocus(survivor)
        } else {
            focused = nil
            onEmpty?()
        }
        refreshFocusIndicators()
    }

    private func setFocus(_ pane: TerminalPane) {
        focused = pane
        refreshFocusIndicators()
        onFocusRequest?(pane.terminalView)
    }

    private func refreshFocusIndicators() {
        let showsIndicator = isSplit
        for pane in panes {
            pane.containerView.showsFocusIndicator = showsIndicator
            pane.containerView.isFocused = (pane === focused)
        }
    }

    private func applyStoredRatio() {
        guard isSplit, splitView.bounds.width > 1 else { return }
        let position = (splitView.bounds.width * AppSettings.shared.splitRatio).rounded()
        splitView.setPosition(position, ofDividerAt: 0)
    }

    // MARK: - NSSplitViewDelegate

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinateOfSubviewAt dividerIndex: Int
    ) -> CGFloat {
        splitView.bounds.width * 0.2
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinateOfSubviewAt dividerIndex: Int
    ) -> CGFloat {
        splitView.bounds.width * 0.8
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isAdjustingPanes, isSplit, splitView.bounds.width > 1 else { return }
        let leftWidth = splitView.arrangedSubviews[0].frame.width
        AppSettings.shared.splitRatio = leftWidth / splitView.bounds.width
    }
}

final class SharkSplitView: NSSplitView {
    var themeDividerColor: NSColor = .black { didSet { needsDisplay = true } }

    override var dividerColor: NSColor { themeDividerColor }
    override var dividerThickness: CGFloat { 1 }
}
