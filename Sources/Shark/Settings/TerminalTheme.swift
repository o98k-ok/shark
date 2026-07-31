import AppKit
import SwiftTerm

struct TerminalTheme: Equatable {
    let id: String
    let name: String
    let background: NSColor
    let foreground: NSColor
    let cursor: NSColor
    let selectionBackground: NSColor
    let selectionForeground: NSColor
    /// 16 ANSI colors: 0-7 normal, 8-15 bright.
    let ansi: [NSColor]

    var swiftTermPalette: [SwiftTerm.Color] {
        ansi.map { $0.asTerminalColor }
    }
}

extension NSColor {
    /// SwiftTerm stores channels as 16-bit values in the sRGB space.
    var asTerminalColor: SwiftTerm.Color {
        let c = usingColorSpace(.sRGB) ?? self
        return SwiftTerm.Color(
            red: UInt16(c.redComponent * 65535),
            green: UInt16(c.greenComponent * 65535),
            blue: UInt16(c.blueComponent * 65535)
        )
    }

    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum ThemeCatalog {
    static let all: [TerminalTheme] = [dark, light, nord, catppuccinMocha]
    static let fallback = dark

    static func theme(id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? fallback
    }

    static let dark = TerminalTheme(
        id: "dark",
        name: "Shark Dark",
        background: NSColor(hex: "0B0B0F"),
        foreground: NSColor(hex: "E4E4EF"),
        cursor: NSColor(hex: "6BE5C8"),
        selectionBackground: NSColor(hex: "2A3550"),
        selectionForeground: NSColor(hex: "E4E4EF"),
        ansi: [
            "1A1A22", "F2777A", "6BE5C8", "FFCC66",
            "6699CC", "CC99CC", "66CCCC", "C7C7D1",
            "4A4A57", "FF9A9D", "8BFFE0", "FFE08A",
            "8FBEF0", "E0B3E0", "8FE5E5", "F2F2F7",
        ].map { NSColor(hex: $0) }
    )

    static let light = TerminalTheme(
        id: "light",
        name: "Shark Light",
        background: NSColor(hex: "FBFBFD"),
        foreground: NSColor(hex: "26262C"),
        cursor: NSColor(hex: "1F8A70"),
        selectionBackground: NSColor(hex: "CFE0F5"),
        selectionForeground: NSColor(hex: "16161A"),
        ansi: [
            "26262C", "C0392B", "1F8A70", "B7791F",
            "2C6FBB", "8E44AD", "2C9AA0", "D8D8E0",
            "5A5A66", "E05B4C", "31A98C", "D69E2E",
            "4189D6", "A968C4", "3FB6BC", "FFFFFF",
        ].map { NSColor(hex: $0) }
    )

    static let nord = TerminalTheme(
        id: "nord",
        name: "Nord",
        background: NSColor(hex: "2E3440"),
        foreground: NSColor(hex: "D8DEE9"),
        cursor: NSColor(hex: "88C0D0"),
        selectionBackground: NSColor(hex: "434C5E"),
        selectionForeground: NSColor(hex: "ECEFF4"),
        ansi: [
            "3B4252", "BF616A", "A3BE8C", "EBCB8B",
            "81A1C1", "B48EAD", "88C0D0", "E5E9F0",
            "4C566A", "BF616A", "A3BE8C", "EBCB8B",
            "81A1C1", "B48EAD", "8FBCBB", "ECEFF4",
        ].map { NSColor(hex: $0) }
    )

    static let catppuccinMocha = TerminalTheme(
        id: "catppuccin-mocha",
        name: "Catppuccin Mocha",
        background: NSColor(hex: "1E1E2E"),
        foreground: NSColor(hex: "CDD6F4"),
        cursor: NSColor(hex: "F5E0DC"),
        selectionBackground: NSColor(hex: "45475A"),
        selectionForeground: NSColor(hex: "CDD6F4"),
        ansi: [
            "45475A", "F38BA8", "A6E3A1", "F9E2AF",
            "89B4FA", "F5C2E7", "94E2D5", "BAC2DE",
            "585B70", "F38BA8", "A6E3A1", "F9E2AF",
            "89B4FA", "F5C2E7", "94E2D5", "A6ADC8",
        ].map { NSColor(hex: $0) }
    )
}
