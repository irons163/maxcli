import XCTest
@testable import MaxCLI

final class ExecutableLocatorTests: XCTestCase {
    private func makeTempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("maxcli-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeBin(in home: URL, named name: String = "tools") throws -> URL {
        let bin = home.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        return bin
    }

    private func installExecutable(named name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func testCustomAgentNeverResolvesToAPath() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let locator = ExecutableLocator(environment: [:], homeDirectory: home.path, additionalSearchPaths: [])
        XCTAssertNil(locator.path(for: .custom))
    }

    func testShellAgentResolvesLoginShellFromRealEnvironment() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        // SHELL is read from the real process environment, so the locator can
        // only return it when it is actually executable.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let locator = ExecutableLocator(
            environment: [:],
            homeDirectory: home.path,
            additionalSearchPaths: []
        )

        if FileManager.default.isExecutableFile(atPath: shell) {
            XCTAssertEqual(locator.path(for: .shell), shell)
        } else {
            XCTAssertNil(locator.path(for: .shell))
        }
    }

    func testFindsAgentInAdditionalSearchPaths() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bin = try makeBin(in: home)
        try installExecutable(named: "codex", in: bin)

        let locator = ExecutableLocator(
            environment: [:],
            homeDirectory: home.path,
            additionalSearchPaths: [bin.path]
        )

        XCTAssertEqual(locator.path(for: .codex), bin.appendingPathComponent("codex").path)
    }

    func testFindsAgentViaPATHEnvironment() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bin = try makeBin(in: home, named: "pathbin")
        try installExecutable(named: "claude", in: bin)

        let locator = ExecutableLocator(
            environment: ["PATH": "\(bin.path):/usr/bin"],
            homeDirectory: home.path,
            additionalSearchPaths: []
        )

        XCTAssertEqual(locator.path(for: .claude), bin.appendingPathComponent("claude").path)
    }

    func testPATHEntriesAreDeduplicatedWithoutBreakingLookup() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bin = try makeBin(in: home, named: "dup")
        try installExecutable(named: "gemini", in: bin)

        let locator = ExecutableLocator(
            environment: ["PATH": "\(bin.path):\(bin.path)"],
            homeDirectory: home.path,
            additionalSearchPaths: []
        )

        for _ in 0..<20 {
            XCTAssertEqual(locator.path(for: .gemini), bin.appendingPathComponent("gemini").path)
        }
    }

    func testMissingAgentReturnsNilWithIsolatedEnvironment() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let locator = ExecutableLocator(
            environment: [:],
            homeDirectory: home.path,
            additionalSearchPaths: []
        )
        XCTAssertNil(locator.path(for: .grok))
        XCTAssertNil(locator.path(for: .cursor))
    }

    func testInstalledAgentsAlwaysIncludeCustom() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let isolated = ExecutableLocator(
            environment: [:],
            homeDirectory: home.path,
            additionalSearchPaths: []
        )
        XCTAssertEqual(isolated.installedAgents, [.shell, .custom], "only shell (login shell) and the always-present custom survive an empty environment")
    }
}
