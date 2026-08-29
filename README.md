# Shark

A macOS menu-bar quick terminal: a global hotkey drops a terminal panel down from
the top of the screen, and it disappears again the moment it loses focus. The
shells keep running while it is hidden.

Built on [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) with a plain
AppKit `NSPanel`; no Electron, no external terminal app.

## Behaviour

| | |
|:---|:---|
| Form | Menu-bar agent, no Dock icon |
| Show | Global hotkey (default `⌃\``) or the menu-bar item |
| While shown | Floats above other windows, including full-screen apps |
| Loses focus | Hides immediately, shells keep running |
| Session | Up to two side-by-side panes, each with its own shell |
| Screen | Drops down from the screen holding the mouse pointer |

Status: early but usable daily. Single developer, no releases cut yet.

## Requirements

macOS 13 or newer, and a Swift 5.9+ toolchain (Xcode or the Command Line Tools).
One dependency, resolved by SwiftPM. No Accessibility or other TCC permission is
needed — the global hotkey goes through Carbon, not an event tap.

## Build

```bash
./Scripts/build-app.sh          # -> dist/Shark.app (release)
./Scripts/build-app.sh debug    # same bundle, debug build
open dist/Shark.app
```

`swift build` alone produces a bare binary; the `.app` bundle is what makes it an
agent and what "Launch at Login" registers.

## Install

```bash
./Scripts/install.sh            # build, then replace /Applications/Shark.app
```

It quits the installed copy before overwriting it and relaunches when done, so
re-running is the normal way to upgrade. `SHARK_INSTALL_DIR=~/Applications` picks a
different destination. Enable **Launch at Login** from the menu *after* installing:
the login item records the bundle it was registered from, so a copy still living in
`dist/` would be the one that starts.

The bundle is signed with a local self-signed identity so macOS privacy grants
survive rebuilds; moving it to another Mac needs real signing and notarization.
Version strings live in the `Info.plist` heredoc inside `Scripts/build-app.sh`.

## Keys

| | |
|:---|:---|
| `⌃\`` | Show / hide |
| `⌘D` | Split left / right |
| `⌘W` | Close pane, or hide the panel when only one is left |
| `⌘]` | Focus the other pane |
| `⌘K` | Clear the screen and the scrollback |
| `⌘C` `⌘V` | Copy / paste |
| `⌘+` `⌘-` `⌘0` | Font size |

The first five are rebindable under **Shortcuts** in the menu; copy, paste and
font size stay on their system-conventional keys.

Dragging or double-clicking puts the selection straight on the pasteboard — turn
**Copy on Select** off if you would rather press `⌘C`.

## Settings

Everything lives in the menu-bar menu and persists in `UserDefaults`: shortcuts,
monospaced font, size, theme, opacity, panel height, window level, launch at
login, hide-on-deactivate, copy-on-select and follow-mouse-screen. Changes apply to running
panes without restarting the shells.

If the window is still covered by something, raise **Window Level**; start at
Standard and only go higher if you have to.

## Architecture

```
Sources/Shark/
  main.swift          NSApplication as an .accessory agent
  AppDelegate.swift   wires the three controllers together
  Panel/              the window and its show/hide state machine
  Session/            panes: one PTY + terminal view each, in an NSSplitView
  Hotkey/             Carbon global hotkey, key-combo formatting
  Settings/           UserDefaults store, shortcut definitions, themes
  UI/                 menu-bar menu, shortcut recorder
```

`PanelController` owns visibility; `WindowSession` owns the shells. They are kept
apart on purpose: hiding is a window operation and must never touch session state,
which is what lets the shells keep running.

Three flows carry almost everything:

- **Toggle** — Carbon hotkey fires `HotkeyController.onTrigger` →
  `PanelController.toggle()` → slide the panel in or out. Focus loss arrives as
  `windowDidResignKey` and routes to the same `hide(reason:)`.
- **Commands** — the agent has no menu bar, so `QuickTerminalPanel`
  `performKeyEquivalent` hands the event to `PanelController.handleKeyEquivalent`,
  which matches it against the configured `PaneCommand` combos and calls into
  `WindowSession`. Menu items call the same methods.
- **Settings** — writes go to `AppSettings`, which persists to `UserDefaults` and
  posts one of three notifications (appearance / geometry / hotkey). Observers
  re-apply to live panes; nothing restarts.

Deeper notes, invariants and the verification checklist are in `AGENTS.md`.

## Known limits

- System UI (login window, some security prompts, the screen saver) always wins.
- A few exclusive-fullscreen games cannot be covered. This is a macOS limit, not
  a level that can be raised further.
- Layout and shells survive hide/show, but not an app restart.

## Troubleshooting

The app has no console; it logs its show/hide transitions:

```bash
log stream --predicate 'subsystem == "com.o98k.shark"' --level info
```
