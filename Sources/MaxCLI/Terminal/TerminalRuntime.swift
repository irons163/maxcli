import AppKit
import Foundation
import SwiftTerm

enum TerminalRuntimeEvent {
    case started
    case output
    case bell
    case title(String)
    case directory(String)
    case terminated(Int32?)
}

final class ManagedTerminalView: LocalProcessTerminalView {
    var eventHandler: ((TerminalRuntimeEvent) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        eventHandler?(.output)
        if slice.contains(7) {
            eventHandler?(.bell)
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
    }

    func start(session: WorkspaceSession) {
        guard !terminalView.process.running else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.startProcess(
            executable: shell,
            args: CommandBuilder.loginShellArguments(for: session),
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
        terminalView.window?.makeFirstResponder(terminalView)
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
