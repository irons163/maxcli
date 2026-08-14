import Foundation

enum CommandBuilder {
    static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func pastedPaths(_ paths: [String]) -> String {
        paths
            .filter { !$0.isEmpty }
            .map { "\u{1B}[200~\($0)\u{1B}[201~" }
            .joined(separator: " ")
    }

    static func loginShellArguments(
        for session: WorkspaceSession,
        executableLocator: ExecutableLocator = ExecutableLocator()
    ) -> [String] {
        let command = launchCommand(for: session, executableLocator: executableLocator)
        let fallback = "printf '\\033[31mMaxCLI: command is empty\\033[0m\\n'; exec \"$SHELL\" -l"
        let executableCommand = command.isEmpty ? fallback : "exec \(command)"
        return ["-l", "-c", "cd \(shellEscape(session.workingDirectory)); \(executableCommand)"]
    }

    private static func launchCommand(
        for session: WorkspaceSession,
        executableLocator: ExecutableLocator
    ) -> String {
        let command = session.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let resumeFlag = resumeFlag(for: session)
        guard !command.isEmpty, session.agent != .custom,
              let executablePath = executableLocator.path(for: session.agent)
        else { return command.isEmpty ? command : "\(command)\(resumeFlag)" }

        let escapedExecutable = shellEscape(executablePath)
        let arguments = session.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        return arguments.isEmpty
            ? "\(escapedExecutable)\(resumeFlag)"
            : "\(escapedExecutable)\(resumeFlag) \(arguments)"
    }

    private static func resumeFlag(for session: WorkspaceSession) -> String {
        guard session.agent == .opencode, let sessionID = session.opencodeSessionID else { return "" }
        return " -s \(shellEscape(sessionID))"
    }
}
