import XCTest
@testable import MaxCLI

final class ModelsTests: XCTestCase {
    // MARK: - AgentKind

    func testAgentKindDisplayNamesAreUnique() {
        let names = AgentKind.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, AgentKind.allCases.count)
        XCTAssertEqual(AgentKind(rawValue: "opencode")?.displayName, "OpenCode")
    }

    func testAgentKindExecutables() {
        XCTAssertEqual(AgentKind.codex.executable, "codex")
        XCTAssertEqual(AgentKind.claude.executable, "claude")
        XCTAssertEqual(AgentKind.opencode.executable, "opencode")
        XCTAssertEqual(AgentKind.custom.executable, "")

        let expectedShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        XCTAssertEqual(AgentKind.shell.executable, expectedShell)
    }

    func testAgentKindSymbolsAndColorsAreConfigured() {
        for agent in AgentKind.allCases {
            XCTAssertFalse(agent.symbolName.isEmpty, "\(agent) missing symbol")
            XCTAssertNotNil(agent.color, "\(agent) missing color")
        }
    }

    func testAgentKindInstallHints() {
        XCTAssertTrue(AgentKind.codex.installHint.contains("codex"))
        XCTAssertTrue(AgentKind.opencode.installHint.contains("opencode"))
        XCTAssertEqual(AgentKind.shell.installHint, "")
        XCTAssertEqual(AgentKind.custom.installHint, "")
    }

    func testAgentKindCodableRoundTrip() throws {
        for agent in AgentKind.allCases {
            let data = try JSONEncoder().encode(agent)
            XCTAssertEqual(try JSONDecoder().decode(AgentKind.self, from: data), agent)
        }
    }

    // MARK: - LayoutMode

    func testLayoutModeMetadata() {
        XCTAssertEqual(LayoutMode.focus.titleKey, "menu.layout.focus")
        XCTAssertEqual(LayoutMode.grid.titleKey, "menu.layout.grid")
        XCTAssertEqual(LayoutMode.active.titleKey, "menu.layout.active")

        XCTAssertFalse(LayoutMode.focus.symbolName.isEmpty)
        XCTAssertFalse(LayoutMode.grid.symbolName.isEmpty)
        XCTAssertFalse(LayoutMode.active.symbolName.isEmpty)
        XCTAssertEqual(LayoutMode.active.symbolName, "bell.fill")
    }

    func testLayoutModeNextCyclesThroughAllModes() {
        XCTAssertEqual(LayoutMode.focus.next, .grid)
        XCTAssertEqual(LayoutMode.grid.next, .active)
        XCTAssertEqual(LayoutMode.active.next, .focus)
    }

    // MARK: - AppLanguage

    func testAppLanguageCodeIsNilOnlyForSystem() {
        XCTAssertNil(AppLanguage.system.code)
        for language in AppLanguage.allCases where language != .system {
            XCTAssertEqual(language.code, language.rawValue)
        }
        XCTAssertEqual(AppLanguage.zhHant.rawValue, "zh-Hant")
        XCTAssertEqual(AppLanguage.zhHans.rawValue, "zh-Hans")
    }

    func testAppLanguageDisplayNames() {
        XCTAssertEqual(AppLanguage.system.displayName, "system")
        XCTAssertEqual(AppLanguage.en.displayName, "English")
        XCTAssertEqual(AppLanguage.zhHant.displayName, "繁體中文")
        XCTAssertEqual(AppLanguage.ja.displayName, "日本語")
    }

    func testAppLanguageBundleResolvesLocalizationForKnownLanguages() {
        for language in AppLanguage.allCases.dropFirst() {
            let bundle = language.bundle
            XCTAssertTrue(
                bundle.bundlePath.hasSuffix(".lproj"),
                "\(language.rawValue) should resolve to a localized bundle, got \(bundle.bundlePath)"
            )
        }
        XCTAssertEqual(AppLanguage.system.bundle.bundlePath, Bundle.module.bundlePath)
    }

    func testAppLanguageCodableRoundTripUsesRawValues() throws {
        let data = try JSONEncoder().encode(AppLanguage.zhHant)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"zh-Hant\"")
        XCTAssertEqual(try JSONDecoder().decode(AppLanguage.self, from: data), .zhHant)
    }

    // MARK: - SessionActivity

    func testSessionActivityLabelKeys() {
        XCTAssertEqual(SessionActivity.launching.labelKey, "activity.launching")
        XCTAssertEqual(SessionActivity.running.labelKey, "activity.running")
        XCTAssertEqual(SessionActivity.attention.labelKey, "activity.attention")
        XCTAssertEqual(SessionActivity.stopped.labelKey, "activity.stopped")
        XCTAssertEqual(SessionActivity.failed.labelKey, "activity.failed")
    }

    // MARK: - WorkspaceSession

    private func makeSession(
        title: String = "Web",
        agent: AgentKind = .codex,
        workingDirectory: String = "/tmp/My Project",
        arguments: String = "--full-auto",
        customCommand: String = "",
        iconName: String? = nil,
        iconColorName: String? = nil,
        isPinned: Bool = false
    ) -> WorkspaceSession {
        WorkspaceSession(
            title: title,
            agent: agent,
            workingDirectory: workingDirectory,
            arguments: arguments,
            customCommand: customCommand,
            iconName: iconName,
            iconColorName: iconColorName,
            isPinned: isPinned
        )
    }

    func testDirectoryNameExtractsLastPathComponent() {
        XCTAssertEqual(makeSession().directoryName, "My Project")
        XCTAssertEqual(
            makeSession(workingDirectory: "/").directoryName,
            "/",
            "URL.lastPathComponent keeps the root slash"
        )
    }

    func testSymbolNamePrefersCustomIcon() {
        XCTAssertEqual(makeSession().symbolName, AgentKind.codex.symbolName)
        XCTAssertEqual(
            makeSession(iconName: "star").symbolName,
            "star"
        )
    }

    func testIconColorFallsBackToAgentColorForUnknownOrMissingName() {
        XCTAssertEqual(makeSession().iconColor, AgentKind.codex.color)
        XCTAssertEqual(
            makeSession(iconColorName: "not-a-color").iconColor,
            AgentKind.codex.color
        )
        let session = makeSession(iconColorName: "teal")
        let teal = WorkspaceSession.iconColorChoices.first { $0.name == "teal" }
        XCTAssertEqual(session.iconColor, teal?.color)
    }

    func testIconColorChoicesCoverTenNamedColors() {
        let names = WorkspaceSession.iconColorChoices.map(\.name)
        XCTAssertEqual(names.count, 10)
        XCTAssertEqual(Set(names).count, 10)
    }

    func testLaunchCommandComposesBaseWithArguments() {
        XCTAssertEqual(makeSession().launchCommand, "codex --full-auto")
        XCTAssertEqual(
            makeSession(arguments: "   ").launchCommand,
            "codex"
        )
        XCTAssertEqual(
            makeSession(agent: .custom, arguments: "-v", customCommand: "/bin/echo hi").launchCommand,
            "/bin/echo hi -v"
        )
        XCTAssertEqual(
            makeSession(agent: .custom).launchCommand,
            " --full-auto",
            "custom agents with no command keep the arguments verbatim (leading space included)"
        )
        XCTAssertEqual(
            makeSession(agent: .custom, arguments: "   ").launchCommand,
            "",
            "whitespace-only arguments are dropped"
        )
    }

    func testSearchableTextIsLowercasedAndContainsFields() {
        let text = makeSession(title: "API Gateway", agent: .claude).searchableText
        XCTAssertTrue(text.contains("api gateway"))
        XCTAssertTrue(text.contains("claude code"))
        XCTAssertTrue(text.contains("/tmp/my project"))
        XCTAssertEqual(text, text.lowercased())
    }

    func testDecodeAppliesDefaultsForMissingOptionalFields() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "title": "Legacy",
            "agent": "gemini",
            "workingDirectory": "/tmp/legacy",
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let session = try JSONDecoder().decode(WorkspaceSession.self, from: data)

        XCTAssertEqual(session.arguments, "")
        XCTAssertEqual(session.customCommand, "")
        XCTAssertNil(session.opencodeSessionID)
        XCTAssertNil(session.iconName)
        XCTAssertNil(session.iconColorName)
        XCTAssertNil(session.manualOrder)
        XCTAssertNil(session.lastActivityAt)
        XCTAssertFalse(session.isPinned)
        XCTAssertFalse(session.isTransient)
        XCTAssertEqual(session.activity, .stopped)
    }

    func testEncodeDecodeRoundTripPreservesAllFields() throws {
        var session = makeSession(iconName: "star", iconColorName: "teal", isPinned: true)
        session.opencodeSessionID = "sess_1"
        session.manualOrder = 3
        session.lastActivityAt = Date(timeIntervalSince1970: 100)
        session.activity = .attention
        session.isTransient = true

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(WorkspaceSession.self, from: data)

        XCTAssertEqual(decoded, session)
    }

    // MARK: - OpenCodePart / OpenCodePartKind

    func testOpenCodePartIsDisplayableUnlessSyntheticOrIgnored() {
        XCTAssertTrue(OpenCodePart(id: "p1", kind: .text, text: "hi").isDisplayable)
        XCTAssertFalse(
            OpenCodePart(id: "p2", kind: .text, text: "", synthetic: true).isDisplayable
        )
        XCTAssertFalse(
            OpenCodePart(id: "p3", kind: .text, text: "", ignored: true).isDisplayable
        )
    }

    func testOpenCodePartKindParsing() {
        XCTAssertEqual(OpenCodePartKind(rawValue: "text"), .text)
        XCTAssertEqual(OpenCodePartKind(rawValue: "reasoning"), .reasoning)
        XCTAssertEqual(OpenCodePartKind(rawValue: "tool"), .tool)
        XCTAssertEqual(OpenCodePartKind(rawValue: "file"), .file)
        XCTAssertEqual(OpenCodePartKind(rawValue: "patch"), .patch)
        XCTAssertEqual(OpenCodePartKind(rawValue: "step-start"), .stepStart)
        XCTAssertEqual(OpenCodePartKind(rawValue: "step-finish"), .stepFinish)
        XCTAssertEqual(OpenCodePartKind(rawValue: "compaction"), .compaction)
        XCTAssertEqual(OpenCodePartKind(rawValue: "mystery"), .unknown)
        XCTAssertEqual(OpenCodePartKind(rawValue: ""), .unknown)
        XCTAssertEqual(OpenCodePartKind.stepStart.rawValue, "step-start")
    }

    // MARK: - OpenCodeHistorySession

    func testHistorySessionSubagentDetection() {
        let root = OpenCodeHistorySession(
            id: "a", title: "t", directory: "/d", agent: nil, model: nil,
            parentID: nil, timeCreated: .now, timeUpdated: .now, messageCount: 0
        )
        let sub = OpenCodeHistorySession(
            id: "b", title: "t", directory: "/d", agent: nil, model: nil,
            parentID: "a", timeCreated: .now, timeUpdated: .now, messageCount: 0
        )
        XCTAssertFalse(root.isSubagent)
        XCTAssertTrue(sub.isSubagent)
    }
}
