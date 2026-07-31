import AppKit
import Darwin
import SwiftTerm

/// One shell: a PTY plus the view that renders it.
final class TerminalPane: NSObject, LocalProcessTerminalViewDelegate {

    let id = UUID()
    let terminalView = SharkTerminalView(frame: .zero)
    let containerView = PaneContainerView()

    private(set) var isRunning = false

    var onExit: ((TerminalPane) -> Void)?

    override init() {
        super.init()
        terminalView.processDelegate = self
        terminalView.onSelectionEnd = { [weak self] in
            guard AppSettings.shared.copyOnSelect else { return }
            self?.copySelection()
        }
        containerView.embed(terminalView)
    }

    /// Working directory of the shell, read straight from the kernel so it works
    /// without any shell-integration hooks.
    var currentDirectory: String? {
        guard isRunning else { return nil }
        return ProcessDirectory.current(of: terminalView.process.shellPid)
    }

    func start(inDirectory directory: String?) {
        guard !isRunning else { return }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        environment.append("TERM_PROGRAM=Shark")

        isRunning = true
        terminalView.startProcess(
            executable: shell,
            args: [],
            environment: environment,
            // Leading dash makes it a login shell, so the user's profile is sourced.
            execName: "-\(shellName)",
            currentDirectory: directory
        )
    }

    func terminate() {
        guard isRunning else { return }
        isRunning = false
        terminalView.terminate()
    }

    func apply(theme: TerminalTheme, font: NSFont, opacity: CGFloat) {
        let background = theme.background.withAlphaComponent(opacity)

        terminalView.installColors(theme.swiftTermPalette)
        terminalView.nativeForegroundColor = theme.foreground
        terminalView.nativeBackgroundColor = background
        terminalView.caretColor = theme.cursor
        terminalView.selectedTextBackgroundColor = theme.selectionBackground
        // SwiftTerm only pushes the background into its layer during setup, so a later
        // theme or opacity change has to be mirrored here.
        terminalView.layer?.backgroundColor = background.cgColor

        // Setting the font resizes the grid and syncs the PTY winsize.
        if terminalView.font != font { terminalView.font = font }

        containerView.focusColor = theme.cursor
        terminalView.needsDisplay = true
    }

    /// SwiftTerm's `copy` clears the pasteboard before writing, so an empty selection
    /// would wipe the clipboard rather than leave it alone.
    func copySelection() {
        guard terminalView.selectionActive else { return }
        terminalView.copy(self)
    }
    func paste() { terminalView.paste(self) }

    /// Erases the visible grid and the scrollback locally, then sends Ctrl-L so the
    /// shell repaints its prompt with whatever was already typed still on the line.
    func clear() {
        terminalView.feed(text: "\u{1b}[H\u{1b}[2J\u{1b}[3J")
        guard isRunning else { return }
        terminalView.process.send(data: [0x0C][...])
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        isRunning = false
        onExit?(self)
    }
}

/// SwiftTerm reports the end of a drag only through `mouseUp`, so that is where
/// copy-on-select has to hook in.
final class SharkTerminalView: LocalProcessTerminalView {
    var onSelectionEnd: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onSelectionEnd?()
    }
}

enum ProcessDirectory {
    static func current(of pid: pid_t) -> String? {
        guard pid > 0 else { return nil }

        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }

        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw -> String in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return path.isEmpty ? nil : path
    }
}
