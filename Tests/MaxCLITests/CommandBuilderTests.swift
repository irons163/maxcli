import XCTest
@testable import MaxCLI

final class CommandBuilderTests: XCTestCase {
    func testEscapesSingleQuotesInDirectory() {
        XCTAssertEqual(
            CommandBuilder.shellEscape("/tmp/it's here"),
            "'/tmp/it'\\''s here'"
        )
    }

    func testBuildsAgentCommandInsideDirectory() {
        let session = WorkspaceSession(
            title: "API",
            agent: .codex,
            workingDirectory: "/tmp/My Project",
            arguments: "--full-auto"
        )

        XCTAssertEqual(
            CommandBuilder.loginShellArguments(
                for: session,
                executableLocator: .isolated
            ),
            ["-l", "-c", "cd '/tmp/My Project'; exec codex --full-auto"]
        )
    }

    func testResolvesInstalledAgentExecutableToAbsolutePath() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory
            .appendingPathComponent("maxcli-home-\(UUID().uuidString)")
        let bin = home.appendingPathComponent(".opencode/bin")
        try fileManager.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appendingPathComponent("opencode")
        fileManager.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8))
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        defer { try? fileManager.removeItem(at: home) }

        let session = WorkspaceSession(
            title: "OC",
            agent: .opencode,
            workingDirectory: "/tmp",
            arguments: "--verbose"
        )

        XCTAssertEqual(
            CommandBuilder.loginShellArguments(
                for: session,
                executableLocator: ExecutableLocator(
                    environment: [:],
                    homeDirectory: home.path
                )
            ),
            ["-l", "-c", "cd '/tmp'; exec '\(executable.path)' --verbose"]
        )
    }

    func testPastedPathsWrapsEachPathInBracketedPaste() {
        XCTAssertEqual(
            CommandBuilder.pastedPaths(["/tmp/a.png", "/tmp/it's here/b.jpg", ""]),
            "\u{1B}[200~/tmp/a.png\u{1B}[201~ \u{1B}[200~/tmp/it's here/b.jpg\u{1B}[201~"
        )
        XCTAssertEqual(CommandBuilder.pastedPaths([]), "")
    }

    func testResumesBoundOpenCodeSession() throws {
        let session = WorkspaceSession(
            title: "OC",
            agent: .opencode,
            workingDirectory: "/tmp",
            arguments: "--verbose",
            opencodeSessionID: "sess_abc123"
        )

        XCTAssertEqual(
            CommandBuilder.loginShellArguments(
                for: session,
                executableLocator: .isolated
            ),
            ["-l", "-c", "cd '/tmp'; exec opencode --verbose -s 'sess_abc123'"]
        )
    }

    func testEmptyCommandFallsBackToInteractiveShell() {
        let session = WorkspaceSession(
            title: "Empty",
            agent: .custom,
            workingDirectory: "/tmp",
            customCommand: ""
        )

        XCTAssertEqual(
            CommandBuilder.loginShellArguments(for: session, executableLocator: .isolated),
            ["-l", "-c", "cd '/tmp'; printf '\\033[31mMaxCLI: command is empty\\033[0m\\n'; exec \"$SHELL\" -l"]
        )
    }

    func testCustomAgentPassesCommandThroughUnresolved() {
        let session = WorkspaceSession(
            title: "Script",
            agent: .custom,
            workingDirectory: "/tmp/my dir",
            customCommand: "/bin/echo hi"
        )

        XCTAssertEqual(
            CommandBuilder.loginShellArguments(for: session, executableLocator: .isolated),
            ["-l", "-c", "cd '/tmp/my dir'; exec /bin/echo hi"]
        )
    }

    func testUnboundOpenCodeSessionOmitsResumeFlag() {
        let session = WorkspaceSession(
            title: "OC",
            agent: .opencode,
            workingDirectory: "/tmp"
        )

        let arguments = CommandBuilder.loginShellArguments(
            for: session,
            executableLocator: .isolated
        )

        XCTAssertFalse(arguments.last!.contains("-s"))
    }

    func testResumedOpenCodeEscapesQuotesInSessionID() throws {
        let session = WorkspaceSession(
            title: "OC",
            agent: .opencode,
            workingDirectory: "/tmp",
            opencodeSessionID: "sess_it's"
        )

        XCTAssertEqual(
            CommandBuilder.loginShellArguments(for: session, executableLocator: .isolated),
            ["-l", "-c", "cd '/tmp'; exec opencode -s 'sess_it'\\''s'"]
        )
    }

    func testRestoredSessionsAreStopped() throws {
        let suite = "MaxCLITests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SessionPersistence(defaults: defaults)
        persistence.save([
            WorkspaceSession(
                title: "Web",
                agent: .claude,
                workingDirectory: "/tmp",
                activity: .running
            )
        ])

        XCTAssertEqual(persistence.load().sessions.first?.activity, .stopped)
    }
}

private extension ExecutableLocator {
    static var isolated: ExecutableLocator {
        ExecutableLocator(
            environment: [:],
            homeDirectory: "/nonexistent-maxcli-home",
            additionalSearchPaths: []
        )
    }
}
