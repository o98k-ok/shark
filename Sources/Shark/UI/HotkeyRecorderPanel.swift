import AppKit
import Carbon.HIToolbox

/// Small floating window that records one shortcut, global or pane-local.
final class HotkeyRecorderPanel: NSObject, NSWindowDelegate {

    private var window: NSPanel?
    private var onClose: (() -> Void)?

    var isPresented: Bool { window != nil }

    func present(target: ShortcutTarget, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let recorder = HotkeyRecorderView(
            frame: NSRect(x: 0, y: 0, width: 360, height: 160),
            current: AppSettings.shared.combo(for: target)
        )
        recorder.autoresizingMask = [.width, .height]
        recorder.onCapture = { [weak self, weak recorder] combo in
            if let taken = AppSettings.shared.assign(combo, to: target) {
                recorder?.reportConflict(with: taken.title)
            } else {
                self?.window?.performClose(nil)
            }
        }
        recorder.onCancel = { [weak self] in self?.window?.performClose(nil) }

        let panel = NSPanel(
            contentRect: recorder.frame,
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = target.title
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView?.addSubview(recorder)

        window = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(recorder)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose?()
        onClose = nil
    }
}

final class HotkeyRecorderView: NSView {

    var onCapture: ((HotkeyCombo) -> Void)?
    var onCancel: (() -> Void)?

    private let current: HotkeyCombo
    private let preview = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "Esc cancels · at least one modifier required")

    override var acceptsFirstResponder: Bool { true }

    init(frame frameRect: NSRect, current: HotkeyCombo) {
        self.current = current
        super.init(frame: frameRect)

        let title = NSTextField(labelWithString: "Press the new shortcut")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.alignment = .center

        preview.font = .monospacedSystemFont(ofSize: 28, weight: .regular)
        preview.alignment = .center
        preview.stringValue = KeyCodeFormatter.describe(current)

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        let stack = NSStackView(views: [title, preview, hint])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func reportConflict(with owner: String) {
        hint.stringValue = "Already used by “\(owner)”"
        hint.textColor = .systemRed
        preview.stringValue = KeyCodeFormatter.describe(current)
        NSSound.beep()
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            onCancel?()
            return
        }

        let modifiers = KeyCodeFormatter.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        onCapture?(HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers))
    }

    override func flagsChanged(with event: NSEvent) {
        let symbols = KeyCodeFormatter.modifierSymbols(
            KeyCodeFormatter.carbonModifiers(from: event.modifierFlags)
        )
        preview.stringValue = symbols.isEmpty ? KeyCodeFormatter.describe(current) : symbols
    }
}
