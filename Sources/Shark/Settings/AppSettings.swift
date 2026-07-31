import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let sharkAppearanceChanged = Notification.Name("shark.appearanceChanged")
    static let sharkGeometryChanged = Notification.Name("shark.geometryChanged")
    static let sharkHotkeyChanged = Notification.Name("shark.hotkeyChanged")
}

/// How hard the panel fights to stay above other windows.
enum PanelLevel: String, CaseIterable {
    case standard
    case high
    case aggressive

    var windowLevel: NSWindow.Level {
        switch self {
        case .standard: return .floating
        case .high: return .statusBar
        case .aggressive: return NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)))
        }
    }

    var title: String {
        switch self {
        case .standard: return "Standard (floating)"
        case .high: return "High (above status bar)"
        case .aggressive: return "Aggressive (above full-screen apps)"
        }
    }
}

struct HotkeyCombo: Equatable {
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey / optionKey / controlKey / shiftKey).
    var modifiers: UInt32
}

final class AppSettings {
    static let shared = AppSettings()

    static let defaultFontSize: CGFloat = 14
    static let fontSizeRange: ClosedRange<CGFloat> = 9...30

    private let defaults = UserDefaults.standard

    private enum Key {
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let themeID = "themeID"
        static let opacity = "windowOpacity"
        static let heightRatio = "panelHeightRatio"
        static let splitRatio = "splitRatio"
        static let hideOnDeactivate = "hideOnDeactivate"
        static let copyOnSelect = "copyOnSelect"
        static let followMouseScreen = "followMouseScreen"
        static let panelLevel = "panelLevel"

        static func shortcutCode(_ id: String) -> String { "shortcut.\(id).keyCode" }
        static func shortcutModifiers(_ id: String) -> String { "shortcut.\(id).modifiers" }
    }

    private init() {
        var shortcutDefaults: [String: Any] = [:]
        for target in ShortcutTarget.all {
            shortcutDefaults[Key.shortcutCode(target.id)] = Int(target.defaultCombo.keyCode)
            shortcutDefaults[Key.shortcutModifiers(target.id)] = Int(target.defaultCombo.modifiers)
        }
        defaults.register(defaults: shortcutDefaults)

        defaults.register(defaults: [
            Key.fontName: "SF Mono",
            Key.fontSize: Double(Self.defaultFontSize),
            Key.themeID: ThemeCatalog.dark.id,
            Key.opacity: 0.9,
            Key.heightRatio: 0.40,
            Key.splitRatio: 0.5,
            Key.hideOnDeactivate: true,
            Key.copyOnSelect: true,
            Key.followMouseScreen: true,
            Key.panelLevel: PanelLevel.high.rawValue,
        ])
    }

    // MARK: - Appearance

    /// Family name, as listed by `NSFontManager`.
    var fontName: String {
        get { defaults.string(forKey: Key.fontName) ?? "SF Mono" }
        set { defaults.set(newValue, forKey: Key.fontName); postAppearance() }
    }

    var fontSize: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.fontSize)) }
        set {
            defaults.set(Double(newValue.clamped(to: Self.fontSizeRange)), forKey: Key.fontSize)
            postAppearance()
        }
    }

    /// Resolved font, falling back through a chain of monospaced faces.
    var font: NSFont {
        let manager = NSFontManager.shared
        return manager.font(withFamily: fontName, traits: [], weight: 5, size: fontSize)
            ?? NSFont(name: fontName, size: fontSize)
            ?? NSFont(name: "Menlo", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var themeID: String {
        get { defaults.string(forKey: Key.themeID) ?? ThemeCatalog.dark.id }
        set { defaults.set(newValue, forKey: Key.themeID); postAppearance() }
    }

    var theme: TerminalTheme { ThemeCatalog.theme(id: themeID) }

    var opacity: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.opacity)) }
        set {
            defaults.set(Double(newValue.clamped(to: 0.3...1.0)), forKey: Key.opacity)
            postAppearance()
        }
    }

    // MARK: - Geometry

    var heightRatio: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.heightRatio)) }
        set {
            defaults.set(Double(newValue.clamped(to: 0.2...0.9)), forKey: Key.heightRatio)
            NotificationCenter.default.post(name: .sharkGeometryChanged, object: nil)
        }
    }

    /// Width fraction taken by the left pane when split.
    var splitRatio: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.splitRatio)) }
        set { defaults.set(Double(newValue.clamped(to: 0.2...0.8)), forKey: Key.splitRatio) }
    }

    var followMouseScreen: Bool {
        get { defaults.bool(forKey: Key.followMouseScreen) }
        set { defaults.set(newValue, forKey: Key.followMouseScreen) }
    }

    // MARK: - Behavior

    var hideOnDeactivate: Bool {
        get { defaults.bool(forKey: Key.hideOnDeactivate) }
        set { defaults.set(newValue, forKey: Key.hideOnDeactivate) }
    }

    /// Mouse selection lands on the pasteboard without pressing ⌘C.
    var copyOnSelect: Bool {
        get { defaults.bool(forKey: Key.copyOnSelect) }
        set { defaults.set(newValue, forKey: Key.copyOnSelect) }
    }

    var panelLevel: PanelLevel {
        get { PanelLevel(rawValue: defaults.string(forKey: Key.panelLevel) ?? "") ?? .high }
        set {
            defaults.set(newValue.rawValue, forKey: Key.panelLevel)
            NotificationCenter.default.post(name: .sharkGeometryChanged, object: nil)
        }
    }

    // MARK: - Shortcuts

    var hotkey: HotkeyCombo { combo(for: .globalToggle) }

    func combo(for target: ShortcutTarget) -> HotkeyCombo {
        HotkeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Key.shortcutCode(target.id))),
            modifiers: UInt32(defaults.integer(forKey: Key.shortcutModifiers(target.id)))
        )
    }

    /// Assigns the combo, or refuses and returns the target already using it.
    @discardableResult
    func assign(_ combo: HotkeyCombo, to target: ShortcutTarget) -> ShortcutTarget? {
        if let taken = ShortcutTarget.all.first(where: { $0 != target && self.combo(for: $0) == combo }) {
            return taken
        }
        store(combo, for: target)
        return nil
    }

    func resetShortcuts() {
        for target in ShortcutTarget.all {
            store(target.defaultCombo, for: target)
        }
    }

    private func store(_ combo: HotkeyCombo, for target: ShortcutTarget) {
        defaults.set(Int(combo.keyCode), forKey: Key.shortcutCode(target.id))
        defaults.set(Int(combo.modifiers), forKey: Key.shortcutModifiers(target.id))
        if target == .globalToggle {
            NotificationCenter.default.post(name: .sharkHotkeyChanged, object: nil)
        }
    }

    private func postAppearance() {
        NotificationCenter.default.post(name: .sharkAppearanceChanged, object: nil)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
