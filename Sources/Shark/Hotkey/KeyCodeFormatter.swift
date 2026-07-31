import AppKit
import Carbon.HIToolbox

enum KeyCodeFormatter {
    static func describe(_ combo: HotkeyCombo) -> String {
        guard combo.keyCode != 0 || combo.modifiers != 0 else { return "None" }
        return modifierSymbols(combo.modifiers) + keyName(combo.keyCode)
    }

    static func modifierSymbols(_ carbonModifiers: UInt32) -> String {
        var out = ""
        if carbonModifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out
    }

    static func modifierFlags(from carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var out: UInt32 = 0
        if flags.contains(.control) { out |= UInt32(controlKey) }
        if flags.contains(.option) { out |= UInt32(optionKey) }
        if flags.contains(.shift) { out |= UInt32(shiftKey) }
        if flags.contains(.command) { out |= UInt32(cmdKey) }
        return out
    }

    private static let namedKeys: [Int: String] = [
        kVK_ANSI_Grave: "`",
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Escape: "⎋",
        kVK_Delete: "⌫",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_Minus: "-",
        kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/",
    ]

    static func keyName(_ keyCode: UInt32) -> String {
        if let named = namedKeys[Int(keyCode)] { return named }
        if let translated = translateToString(keyCode) { return translated.uppercased() }
        return "Key\(keyCode)"
    }

    /// Maps a virtual key to its character using the active keyboard layout.
    private static func translateToString(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return OSStatus(-1) }
            return UCKeyTranslate(
                base.assumingMemoryBound(to: UCKeyboardLayout.self),
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
