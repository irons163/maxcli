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
        let command = command(for: session, executableLocator: executableLocator)
        let fallback = "printf '\\033[31mMaxCLI: command is empty\\033[0m\\n'; exec \"$SHELL\" -l"
        let executableCommand = command.isEmpty ? fallback : "exec \(command)"
        return ["-l", "-c", "cd \(shellEscape(session.workingDirectory)); \(executableCommand)"]
    }

    static func command(
        for session: WorkspaceSession,
        executableLocator: ExecutableLocator = ExecutableLocator()
    ) -> String {
        let command = session.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return "" }
        guard session.agent != .custom else { return command }

        let resolvedExecutable = executableLocator.path(for: session.agent)
        let executable = resolvedExecutable ?? session.agent.executable
        guard !executable.isEmpty else { return command }
        let executableToken = resolvedExecutable.map(shellEscape) ?? executable
        let arguments = session.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let resumeArguments = resumeArguments(for: session)
        var parts = [executableToken]

        // OpenCode accepts its session flag after normal arguments. The other
        // CLIs expose resume as a subcommand or a leading option.
        if session.agent != .opencode {
            parts.append(contentsOf: resumeArguments)
        }
        if !arguments.isEmpty {
            parts.append(arguments)
        }
        if session.agent == .opencode {
            parts.append(contentsOf: resumeArguments)
        }
        return parts.joined(separator: " ")
    }

    private static func resumeArguments(for session: WorkspaceSession) -> [String] {
        guard let sessionID = session.boundSessionID else { return [] }
        let escapedID = shellEscape(sessionID)
        switch session.agent {
        case .codex:
            return ["resume", escapedID]
        case .claude, .gemini, .grok:
            return ["--resume", escapedID]
        case .cursor, .copilot:
            return ["--resume=\(escapedID)"]
        case .opencode:
            return ["-s", escapedID]
        case .shell, .custom:
            return []
        }
    }
}
