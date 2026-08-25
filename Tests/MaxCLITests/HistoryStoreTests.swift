import XCTest
@testable import MaxCLI

final class HistoryStoreTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("maxcli-history-providers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        HistoryStore.homeDirectoryOverride = home
        OpenCodeHistoryStore.databaseURLOverride = home.appendingPathComponent("missing-opencode.db")
        CodexSQLiteHistoryStore.databaseURLOverride = home.appendingPathComponent("missing-codex.db")
    }

    override func tearDownWithError() throws {
        HistoryStore.homeDirectoryOverride = nil
        OpenCodeHistoryStore.databaseURLOverride = nil
        CodexSQLiteHistoryStore.databaseURLOverride = nil
        if let home {
            try? FileManager.default.removeItem(at: home)
        }
        try super.tearDownWithError()
    }

    func testListSessionsAggregatesSupportedLocalProviders() throws {
        try write(
            ".codex/sessions/2026/08/25/rollout-test.jsonl",
            """
            {"timestamp":"2026-08-25T01:00:00Z","type":"session_meta","payload":{"id":"codex-id","cwd":"/tmp/codex","model_provider":"openai"}}
            {"timestamp":"2026-08-25T01:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Fix Codex"}]}}
            {"timestamp":"2026-08-25T01:00:02Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done"}]}}
            """
        )
        try write(
            ".claude/projects/-tmp-claude/session.jsonl",
            """
            {"type":"user","sessionId":"claude-id","cwd":"/tmp/claude","timestamp":"2026-08-25T02:00:00Z","message":{"role":"user","content":[{"type":"text","text":"Review Claude"}]}}
            {"type":"assistant","sessionId":"claude-id","cwd":"/tmp/claude","timestamp":"2026-08-25T02:00:01Z","message":{"role":"assistant","model":"claude-test","content":[{"type":"text","text":"Reviewed"}]}}
            """
        )
        try write(
            ".gemini/tmp/project-hash/chats/session-test.jsonl",
            """
            {"sessionId":"gemini-id","projectHash":"project-hash","startTime":"2026-08-25T03:00:00Z","lastUpdated":"2026-08-25T03:00:02Z"}
            {"type":"user","content":"Fix Gemini","timestamp":"2026-08-25T03:00:01Z"}
            {"type":"gemini","content":"Done","timestamp":"2026-08-25T03:00:02Z"}
            """
        )
        try write(
            ".cursor/projects/Users-tmp-cursor/agent-transcripts/cursor-id/cursor-id.jsonl",
            """
            {"role":"user","message":{"content":"Fix Cursor"}}
            {"role":"assistant","message":{"content":[{"type":"text","text":"Done"}]}}
            """
        )
        try write(
            ".copilot/session-state/copilot-id/events.jsonl",
            """
            {"type":"session.start","timestamp":"2026-08-25T05:00:00Z","data":{"sessionId":"copilot-id","startTime":"2026-08-25T05:00:00Z","context":{"cwd":"/tmp/copilot"}}}
            {"type":"user.message","timestamp":"2026-08-25T05:00:01Z","data":{"content":"Fix Copilot"}}
            {"type":"assistant.message","timestamp":"2026-08-25T05:00:02Z","data":{"content":"Done"}}
            """
        )
        try write(
            ".grok/sessions/%2Ftmp%2Fgrok/grok-id/summary.json",
            """
            {"info":{"session_id":"grok-id","cwd":"/tmp/grok"},"generated_title":"Fix Grok","created_at":"2026-08-25T06:00:00Z","updated_at":"2026-08-25T06:00:02Z","current_model_id":"grok-test"}
            """
        )
        try write(
            ".grok/sessions/%2Ftmp%2Fgrok/grok-id/updates.jsonl",
            """
            {"timestamp":"2026-08-25T06:00:01Z","method":"session/update","params":{"update":{"sessionUpdate":"user_message_chunk","content":{"text":"Fix Grok"}}}}
            {"timestamp":"2026-08-25T06:00:02Z","method":"session/update","params":{"update":{"sessionUpdate":"agent_message_chunk","content":{"text":"Done"}}}}
            """
        )

        let sessions = HistoryStore.listSessions()

        XCTAssertEqual(Set(sessions.map(\.source)), [.codex, .claude, .gemini, .cursor, .copilot, .grok])
        XCTAssertEqual(sessions.count, 6)
        XCTAssertTrue(sessions.contains { $0.title == "Fix Codex" && $0.directory == "/tmp/codex" })
        XCTAssertTrue(sessions.contains { $0.title == "Review Claude" && $0.model == "claude-test" })
        XCTAssertTrue(sessions.contains { $0.title == "Fix Grok" && $0.directory == "/tmp/grok" })
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: sessions.map { ($0.source, $0.sessionID) }),
            [
                .codex: "codex-id",
                .claude: "claude-id",
                .gemini: "gemini-id",
                .cursor: "cursor-id",
                .copilot: "copilot-id",
                .grok: "grok-id",
            ]
        )
    }

    func testTranscriptUsesNamespacedFileIDAndParsesParts() throws {
        let path = ".claude/projects/-tmp-claude/session.jsonl"
        try write(
            path,
            """
            {"type":"user","sessionId":"claude-id","cwd":"/tmp/claude","timestamp":"2026-08-25T02:00:00Z","message":{"role":"user","content":[{"type":"text","text":"Review Claude"}]}}
            {"type":"assistant","sessionId":"claude-id","cwd":"/tmp/claude","timestamp":"2026-08-25T02:00:01Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"Check the diff"},{"type":"tool_use","name":"bash","input":{"command":"git diff"}},{"type":"text","text":"Reviewed"}]}}
            """
        )

        let session = try XCTUnwrap(HistoryStore.listSessions().first)
        let transcript = try HistoryStore.transcript(for: session.id)

        XCTAssertEqual(transcript.session.id, session.id)
        XCTAssertEqual(transcript.messages.count, 2)
        XCTAssertEqual(transcript.messages[1].parts.map(\.kind), [.reasoning, .tool, .text])
        XCTAssertEqual(transcript.messages[1].parts[1].toolName, "bash")
    }

    private func write(_ relativePath: String, _ contents: String) throws {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.data(using: .utf8)!.write(to: url)
    }
}
