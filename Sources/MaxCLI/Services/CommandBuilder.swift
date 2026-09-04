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
        // The `-s` resume flag only applies to the TUI. A leading bare word
        // (e.g. `auth list`, `run`) selects a subcommand, where an unknown
        // `-s` would abort with a usage error.
        if session.agent == .opencode, !launchesSubcommand(arguments) {
            parts.append(contentsOf: resumeArguments)
        }
        return parts.joined(separator: " ")
    }

    private static func launchesSubcommand(_ arguments: String) -> Bool {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ").first else { return false }
        return !first.hasPrefix("-")
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

    /// The provider prefix of the session's `-m provider/model` argument,
    /// which also decides which stored account/credential applies.
    static func modelProvider(for session: WorkspaceSession) -> String? {
        let args = session.arguments
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\s)-m\s+([^/\s]+)"#) else { return nil }
        let range = NSRange(args.startIndex..., in: args)
        guard let match = regex.firstMatch(in: args, range: range),
              match.numberOfRanges >= 2,
              let providerRange = Range(match.range(at: 1), in: args)
        else { return nil }
        return String(args[providerRange])
    }

    /// Per-session environment. When the session has a provider account
    /// assigned, inject `OPENCODE_CONFIG_CONTENT` with that account's API key
    /// (from the Keychain); config `provider.options.apiKey` outranks
    /// auth.json inside that opencode process only.
    static func environment(for session: WorkspaceSession) -> [String]? {
        guard session.agent == .opencode else { return nil }
        let provider = session.accountProvider ?? modelProvider(for: session)
        guard let provider, let account = session.providerAccount,
              let key = ProviderAccountStore.key(provider: provider, account: account)
        else { return nil }

        let payload: [String: Any] = [
            "provider": [
                provider: [
                    "options": ["apiKey": key],
                ],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return nil }

        var env = ProcessInfo.processInfo.environment
        env["OPENCODE_CONFIG_CONTENT"] = json
        return env.map { "\($0.key)=\($0.value)" }
    }
}
