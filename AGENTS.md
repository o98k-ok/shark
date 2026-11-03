# AGENTS.md

Working notes for agents and new contributors. Read `README.md` first for what the
app is and how it behaves; this file is about how to change it safely.

## Commands

```bash
swift build                      # compile check, debug — the fast feedback loop
./Scripts/build-app.sh           # release .app -> dist/Shark.app
./Scripts/build-app.sh debug     # same bundle from a debug build
open dist/Shark.app              # run it (menu-bar icon, no Dock tile)
pkill -f dist/Shark.app          # stop the running copy before rebuilding
./Scripts/install.sh             # build + replace /Applications/Shark.app, then relaunch
log stream --predicate 'subsystem == "com.o98k.shark"' --level info
defaults read com.o98k.shark     # inspect persisted settings
```

There is no test target, no linter and no CI. `swift build` is the only automated
check that exists — treat it as mandatory, not sufficient.

## Verifying a change

1. `swift build` must be clean. Warnings count as failures worth fixing.
2. Rebuild the bundle and relaunch; the bare SwiftPM binary is not a valid target
   for manual testing (see *Boundaries*).
3. Smoke-test the paths the change touches, watching `log stream`:
   - hotkey shows and hides the panel, and it takes keyboard focus immediately;
   - clicking away hides it, and the shell state is still there on the next show;
   - split, close pane, focus other pane — via both the menu and the shortcuts;
   - open the menu and a shortcut recorder: neither may dismiss the panel.
4. Settings changes must apply to running panes without restarting the shells.

**Do not drive the UI with `osascript`/screenshot automation while the user is
testing by hand.** The panel hides on focus loss, so two testers fight each other
and both get false failures. Ask the user to test, or test alone.

## Invariants

These are load-bearing; breaking them produces bugs that look unrelated.

- **Size before start.** `PanelController.show()` calls `layoutSubtreeIfNeeded()`
  before `session.ensureStarted()`. A shell started into a zero-sized grid writes
  its first prompt nowhere and never repaints.
- **Hide, never close.** The panel is ordered out, not closed, so PTYs and layout
  survive. Nothing outside `WindowSession.terminateAll()` may kill shells.
- **Auxiliary UI suspends auto-hide.** Anything that takes key status away from
  the panel (status menu, shortcut recorder) must set
  `panelController.suppressAutoHide` and call `resumeAfterAuxiliaryUI()` when it
  closes. Otherwise the panel reads it as "user switched away" and vanishes
  mid-interaction.
- **One place for window-level policy.** Level, collection behaviour and style
  mask live in `QuickTerminalPanel`. Do not set them from controllers.
- **One source of truth for shortcuts.** `ShortcutTarget` in
  `Sources/Shark/Settings/Shortcuts.swift` enumerates every rebindable command;
  `AppSettings.combo(for:)` reads it, `assign(_:to:)` rejects conflicts. Adding a
  command means adding a case, not a new key path or a hardcoded key check.
- **Two panes maximum.** `WindowSession.maxPanes`. Split/close logic assumes it.
- **No Accessibility permission.** The global hotkey uses Carbon
  `RegisterEventHotKey`, deliberately, so the app needs no TCC prompt. Do not
  replace it with a `CGEvent` tap.
- **Never activate on show.** `NSApp.activate` from an accessory app while a
  full-screen Space is frontmost parks the panel on the Space behind it. The
  panel is a `.nonactivatingPanel`; `orderFrontRegardless()` then `makeKey()`
  is enough for typing. Do not put `canJoinAllSpaces` back: it does not include
  full-screen Spaces and it suppresses `moveToActiveSpace`.

## Boundaries

- The `.app` bundle is not cosmetic: `LSUIElement` (no Dock tile) and
  `SMAppService` login items both require it. `LaunchAtLogin.set` throws when run
  from the bare binary, and the menu surfaces that error rather than swallowing it.
- Signing uses a local self-signed identity (`Shark Self-Signed`) in
  `~/Library/Keychains/shark-signing.keychain-db`, created once by
  `Scripts/ensure-signing-identity.sh`. Ad-hoc (`codesign --sign -`) pins TCC
  to the binary cdhash, so Files and Folders grants die on every rebuild. This
  is still not a distributable, notarized build.
- Version strings live in the `Info.plist` heredoc inside `Scripts/build-app.sh`.
- App icon is `Assets/icon/AppIcon.icns`, built from `Assets/icon/spec.json`.
  Menu bar glyph is `Assets/icon/MenuBar.pdf` (template). `build-app.sh` copies both;
  do not hand-draw SVG into the bundle.
- `Scripts/install.sh` refuses to write an unwritable destination instead of
  escalating; never add `sudo` to it. `SHARK_INSTALL_DIR` overrides the target,
  which is also how to exercise it without touching `/Applications`.
- Two copies can run at once (`dist/` and `/Applications/`) and they fight over the
  same hotkey — only one registers it. Kill the stray copy before debugging
  "the hotkey stopped working".
- Settings persist in `UserDefaults` under `com.o98k.shark`. Renaming a key
  silently resets that setting for existing users; keep `AppSettings.Key` and the
  registered defaults in step.
- `dist/` and `.build/` are generated and git-ignored. Never commit them.

## Amp orbs

`.agents/setup` installs Swift 6.2.3 through Swiftly and resolves the exact
`Package.resolved` dependencies in Linux. Amp snapshots the toolchain and SwiftPM
caches; warm setup reuses them. `.agents/resume` does not install anything.
The toolchain is available in new login shells, including Amp tool processes.

Linux has no AppKit, Carbon or macOS SDK, so dependency resolution is not a build
check. Use a Mac satellite for `swift build`, bundle creation and UI verification.
The Linux snapshot does not cache the Mac satellite's toolchain or build outputs.

## Style

Match what is there: small types with one job, doc comments that explain *why* a
non-obvious line exists, no comments restating the code. Prefer deleting a special
case over adding a flag.
