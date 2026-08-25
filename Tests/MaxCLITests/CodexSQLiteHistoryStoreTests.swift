import XCTest
import SQLite3
@testable import MaxCLI

final class CodexSQLiteHistoryStoreTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("maxcli-codex-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        HistoryStore.homeDirectoryOverride = workspace
        OpenCodeHistoryStore.databaseURLOverride = workspace.appendingPathComponent("missing-opencode.db")
    }

    override func tearDownWithError() throws {
        CodexSQLiteHistoryStore.databaseURLOverride = nil
        OpenCodeHistoryStore.databaseURLOverride = nil
        HistoryStore.homeDirectoryOverride = nil
        if let workspace {
            try? FileManager.default.removeItem(at: workspace)
        }
        try super.tearDownWithError()
    }

    func testReadsProjectedThreadAndResolvesWorkingDirectory() throws {
        let database = workspace.appendingPathComponent("thread_history_1.sqlite")
        try makeFixture(at: database)
        CodexSQLiteHistoryStore.databaseURLOverride = database

        let sessions = HistoryStore.listSessions()
        let session = try XCTUnwrap(sessions.first(where: { $0.sessionID == "thread-1" }))
        XCTAssertEqual(session.id, "codex:thread:thread-1")
        XCTAssertEqual(session.source, .codex)
        XCTAssertEqual(session.title, "Fix Codex binding")
        XCTAssertEqual(session.directory, "/tmp/codex")
        XCTAssertEqual(session.messageCount, 2)

        let transcript = try HistoryStore.transcript(for: session.id)
        XCTAssertEqual(transcript.session.id, session.id)
        XCTAssertEqual(transcript.messages.map(\.role), ["user", "tool", "tool", "tool", "assistant"])
        XCTAssertEqual(transcript.messages[1].parts.first?.toolInput, "pwd")
        XCTAssertEqual(transcript.messages[1].parts.first?.toolStatus, "completed")
    }

    private final class FixtureDB {
        private let handle: OpaquePointer?

        init(url: URL) throws {
            var db: OpaquePointer?
            guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
                throw NSError(domain: "CodexSQLiteHistoryStoreTests", code: 1)
            }
            handle = db
        }

        deinit {
            sqlite3_close(handle)
        }

        func exec(_ sql: String) throws {
            var error: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
                let message = error.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(error)
                throw NSError(
                    domain: "CodexSQLiteHistoryStoreTests",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
        }

        func insert(_ sql: String, bindings: [String?]) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement
            else {
                throw NSError(
                    domain: "CodexSQLiteHistoryStoreTests",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))]
                )
            }
            defer { sqlite3_finalize(statement) }

            for (index, value) in bindings.enumerated() {
                if let value {
                    sqlite3_bind_text(
                        statement,
                        Int32(index + 1),
                        value,
                        -1,
                        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                    )
                } else {
                    sqlite3_bind_null(statement, Int32(index + 1))
                }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NSError(
                    domain: "CodexSQLiteHistoryStoreTests",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))]
                )
            }
        }
    }

    private func makeFixture(at url: URL) throws {
        let db = try FixtureDB(url: url)
        try db.exec("""
            CREATE TABLE thread_items (
                thread_id TEXT NOT NULL,
                turn_id TEXT NOT NULL,
                item_id TEXT NOT NULL,
                rollout_ordinal INTEGER NOT NULL,
                created_at_ms INTEGER NOT NULL,
                item_json TEXT NOT NULL,
                item_type TEXT NOT NULL DEFAULT '',
                updated_at_ordinal INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (thread_id, turn_id, item_id)
            );
            """)

        let insertSQL = "INSERT INTO thread_items VALUES (?,?,?,?,?,?,?,?)"
        try db.insert(insertSQL, bindings: [
            "thread-1", "turn-1", "u1", "1", "1000",
            #"{"type":"userMessage","id":"u1","content":[{"type":"text","text":"Fix Codex binding"}]}"#,
            "userMessage", "1",
        ])
        try db.insert(insertSQL, bindings: [
            "thread-1", "turn-1", "c1", "2", "2000",
            #"{"type":"commandExecution","id":"c1","cwd":"/tmp/codex","command":"pwd","status":"completed","aggregatedOutput":"/tmp/codex"}"#,
            "commandExecution", "2",
        ])
        try db.insert(insertSQL, bindings: [
            "thread-1", "turn-1", "c2", "3", "2500",
            #"{"type":"commandExecution","id":"c2","cwd":"/tmp/codex","command":"ls","status":"completed"}"#,
            "commandExecution", "3",
        ])
        try db.insert(insertSQL, bindings: [
            "thread-1", "turn-1", "c3", "4", "3000",
            #"{"type":"commandExecution","id":"c3","cwd":"/tmp/other","command":"pwd","status":"completed"}"#,
            "commandExecution", "4",
        ])
        try db.insert(insertSQL, bindings: [
            "thread-1", "turn-1", "a1", "5", "4000",
            #"{"type":"agentMessage","id":"a1","text":"Found it","phase":"final"}"#,
            "agentMessage", "5",
        ])
    }
}
