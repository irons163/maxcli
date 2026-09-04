import AppKit
import Foundation
import SwiftTerm

enum TerminalRuntimeEvent {
    case started
    case output(Int)
    case userInput
    case focus(Bool)
    case bell
    case title(String)
    case directory(String)
    case terminated(Int32?)
}

final class ManagedTerminalView: LocalProcessTerminalView {
    var eventHandler: ((TerminalRuntimeEvent) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        eventHandler?(.output(slice.count))
        super.dataReceived(slice: slice)
    }

    override func bell(source: Terminal) {
        // SwiftTerm's default delegate plays NSSound.beep(). Route the event
        // through AppModel so background attention is deduplicated there.
        eventHandler?(.bell)
    }

    override func send(source: Terminal, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        if data == [0x1b, 0x5b, 0x49] || data == [0x9b, 0x49] {
            eventHandler?(.focus(true))
        } else if data == [0x1b, 0x5b, 0x4f] || data == [0x9b, 0x4f] {
            eventHandler?(.focus(false))
        } else {
            eventHandler?(.userInput)
        }
    }
}

@MainActor
final class TerminalRuntime: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
    let sessionID: UUID
    let terminalView: ManagedTerminalView
    private let eventHandler: (UUID, TerminalRuntimeEvent) -> Void

    var isRunning: Bool { terminalView.process.running }

    init(
        sessionID: UUID,
        eventHandler: @escaping (UUID, TerminalRuntimeEvent) -> Void
    ) {
        self.sessionID = sessionID
        self.eventHandler = eventHandler
        self.terminalView = ManagedTerminalView(frame: .zero)
        super.init()

        terminalView.processDelegate = self
        terminalView.eventHandler = { [weak self] event in
            guard let self else { return }
            self.eventHandler(self.sessionID, event)
        }
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.nativeForegroundColor = NSColor(
            calibratedRed: 0.88,
            green: 0.90,
            blue: 0.93,
            alpha: 1
        )
        terminalView.nativeBackgroundColor = NSColor(
            calibratedRed: 0.055,
            green: 0.063,
            blue: 0.078,
            alpha: 1
        )
        terminalView.caretColor = .systemMint
        terminalView.selectedTextBackgroundColor = NSColor.systemBlue.withAlphaComponent(0.48)
        terminalView.optionAsMetaKey = true
        terminalView.linkReporting = .implicit
        terminalView.wantsLayer = true
        terminalView.layer?.backgroundColor = terminalView.nativeBackgroundColor.cgColor
        terminalView.getTerminal().setCursorStyle(.steadyBlock)
        // Default is 320 MB per terminal; with 6+ sessions and frequent image
        // drops this can push the app past several GB. Keep it comfortable for
        // normal TUI use while staying well below the 8 GB the user hit.
        terminalView.getTerminal().options.kittyImageCacheLimitBytes = 32 * 1024 * 1024
    }

    func start(session: WorkspaceSession) {
        guard !terminalView.process.running else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.startProcess(
            executable: shell,
            args: CommandBuilder.loginShellArguments(for: session),
            environment: CommandBuilder.environment(for: session),
            execName: "-\(URL(fileURLWithPath: shell).lastPathComponent)",
            currentDirectory: session.workingDirectory
        )
        eventHandler(sessionID, .started)
    }

    func stop() {
        guard terminalView.process.running else { return }
        terminalView.terminate()
    }

    func send(text: String) {
        guard terminalView.process.running, !text.isEmpty else { return }
        terminalView.send(txt: text)
        focus()
    }

    func focus() {
        guard let window = terminalView.window, window.firstResponder !== terminalView else { return }
        window.makeFirstResponder(terminalView)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        eventHandler(sessionID, .title(title))
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        let path = URL(string: directory)?.path ?? directory
        eventHandler(sessionID, .directory(path))
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        eventHandler(sessionID, .terminated(exitCode))
    }
}
