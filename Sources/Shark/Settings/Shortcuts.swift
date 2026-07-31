import Carbon.HIToolbox

/// Pane commands that the user can rebind. Copy, paste and font size stay fixed
/// on their system-conventional keys.
enum PaneCommand: String, CaseIterable {
    case split
    case closePane
    case focusOther
    case clear

    var title: String {
        switch self {
        case .split: return "Split Left / Right"
        case .closePane: return "Close Pane"
        case .focusOther: return "Focus Other Pane"
        case .clear: return "Clear Terminal"
        }
    }

    var defaultCombo: HotkeyCombo {
        switch self {
        case .split:
            return HotkeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey))
        case .closePane:
            return HotkeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey))
        case .focusOther:
            return HotkeyCombo(keyCode: UInt32(kVK_ANSI_RightBracket), modifiers: UInt32(cmdKey))
        case .clear:
            return HotkeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey))
        }
    }
}

/// Everything that owns a shortcut, so the global hotkey and the pane commands
/// share one store, one recorder and one conflict check.
enum ShortcutTarget: Equatable {
    case globalToggle
    case pane(PaneCommand)

    static let all: [ShortcutTarget] = [.globalToggle] + PaneCommand.allCases.map(ShortcutTarget.pane)

    var id: String {
        switch self {
        case .globalToggle: return "toggle"
        case .pane(let command): return command.rawValue
        }
    }

    var title: String {
        switch self {
        case .globalToggle: return "Toggle Quick Terminal"
        case .pane(let command): return command.title
        }
    }

    var defaultCombo: HotkeyCombo {
        switch self {
        case .globalToggle:
            return HotkeyCombo(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(controlKey))
        case .pane(let command):
            return command.defaultCombo
        }
    }
}
