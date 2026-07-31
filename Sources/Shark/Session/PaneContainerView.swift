import AppKit

/// Wraps one terminal view and marks it when it holds keyboard focus.
/// The inset is constant so toggling the indicator never reflows the grid.
final class PaneContainerView: NSView {

    private let borderWidth: CGFloat = 1

    var isFocused = false { didSet { needsDisplay = true } }
    var showsFocusIndicator = false { didSet { needsDisplay = true } }
    var focusColor: NSColor = .systemTeal { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    func embed(_ view: NSView) {
        view.autoresizingMask = [.width, .height]
        view.frame = bounds.insetBy(dx: borderWidth, dy: borderWidth)
        addSubview(view)
    }

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds.insetBy(dx: borderWidth, dy: borderWidth)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard showsFocusIndicator, isFocused else { return }
        focusColor.withAlphaComponent(0.75).setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
        path.lineWidth = borderWidth
        path.stroke()
    }
}
