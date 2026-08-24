import XCTest
import SQLite3
@testable import MaxCLI

final class OpenCodeHistoryStoreTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        OpenCodeHistoryStore.databaseURLOverride = nil
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("maxcli-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        OpenCodeHistoryStore.databaseURLOverride = nil
        if let workspace {
            try? FileManager.default.removeItem(at: workspace)
        }
        try super.tearDownWithError()
    }

    // MARK: - SQLite fixture

    private final class FixtureDB {
        private let handle: OpaquePointer?

        init(url: URL) throws {
            var db: OpaquePointer?
            guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
                throw NSError(domain: "OpenCodeHistoryStoreTests", code: 1)
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
                    domain: "OpenCodeHistoryStoreTests",
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
                    domain: "OpenCodeHistoryStoreTests",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))]
                )
            }
            defer { sqlite3_finalize(statement) }
            for (index, value) in bindings.enumerated() {
                if let value {
                    sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(statement, Int32(index + 1))
                }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NSError(
                    domain: "OpenCodeHistoryStoreTests",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))]
                )
            }
        }
    }

    /// Millisecond timestamps used across the fixture.
    private let early = "1000"
    private let mid = "2000"
    private let late = "3000"

    @discardableResult
    private func makeFixture(at url: URL) throws -> FixtureDB {
        let db = try FixtureDB(url: url)
        try db.exec("""
        CREATE TABLE session (
            id TEXT PRIMARY KEY, title TEXT, directory TEXT, agent TEXT, model TEXT,
            parent_id TEXT, time_created INTEGER, time_updated INTEGER
        );
        CREATE TABLE message (
            id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT
        );
        CREATE TABLE part (
            id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, data TEXT
        );
        """)

        try db.insert(
            "INSERT INTO session VALUES (?,?,?,?,?,?,?,?)",
            bindings: ["sess_a", "Root A", "/tmp/proj", "opencode", "model/x", nil, early, late]
        )
        try db.insert(
            "INSERT INTO session VALUES (?,?,?,?,?,?,?,?)",
            bindings: ["sess_b", "Older Root", "/tmp/proj", "opencode", "model/x", nil, early, mid]
        )
        try db.insert(
            "INSERT INTO session VALUES (?,?,?,?,?,?,?,?)",
            bindings: ["sess_sub", "Subtask", "/tmp/proj", "opencode", "model/y", "sess_a", mid, "9000"]
        )
        try db.insert(
            "INSERT INTO session VALUES (?,?,?,?,?,?,?,?)",
            bindings: ["sess_c", nil, "/tmp/other", "opencode", nil, nil, early, early]
        )

        // sess_a: assistant opener, then the user prompt under test, then a reply.
        try db.insert(
            "INSERT INTO message VALUES (?,?,?,?)",
            bindings: ["m1", "sess_a", early, #"{"role":"assistant","time":{"created":1000}}"#]
        )
        try db.insert(
            "INSERT INTO message VALUES (?,?,?,?)",
            bindings: ["m2", "sess_a", mid, #"{"role":"user","time":{"created":2000}}"#]
        )
        try db.insert(
            "INSERT INTO message VALUES (?,?,?,?)",
            bindings: ["m3", "sess_a", late, #"{"role":"assistant","time":{"created":3000}}"#]
        )
        // sess_d: user message whose only part is a tool call (no text answer).
        try db.insert(
            "INSERT INTO message VALUES (?,?,?,?)",
            bindings: ["m4", "sess_d", early, #"{"role":"user","time":{"created":1000}}"#]
        )
        try db.insert(
            "INSERT INTO session VALUES (?,?,?,?,?,?,?,?)",
            bindings: ["sess_d", "No Text", "/tmp/other", "opencode", nil, nil, early, mid]
        )
        try db.insert(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            bindings: ["p_tool_only", "m4", "sess_d", early, #"{"type":"tool","tool":"bash"}"#]
        )

        // Parts attached to m2: synthetic and ignored entries must be skipped.
        try db.insert(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            bindings: [
                "p_syn", "m2", "sess_a", early,
                #"{"type":"text","text":"synthetic greeting","synthetic":true}"#,
            ]
        )
        try db.insert(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            bindings: [
                "p_ign", "m2", "sess_a", early,
                #"{"type":"text","text":"ignored context","ignored":true}"#,
            ]
        )
        try db.insert(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            bindings: [
                "p_text", "m2", "sess_a", mid,
                #"{"type":"text","text":"hello   world  from\nfixture"}"#,
            ]
        )

        // Parts attached to m3 exercising every parser branch.
        try db.insert(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            bindings: [
                "p_tool", "m3", "sess_a", early,
                #"{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"ls"},"output":"file.txt"}}"#,
            ]
        )
        try db.insert(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            bindings: [
                "p_file", "m3", "sess_a", mid,
                #"{"type":"file","filename":"App.swift","url":"/tmp/App.swift"}"#,
            ]
        )
        try db.insert(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            bindings: [
                "p_patch", "m3", "sess_a", late,
                #"{"type":"patch","files":["x.swift","y.swift"]}"#,
            ]
        )
        try db.insert(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            bindings: ["p_weird", "m3", "sess_a", late, #"{"type":"mystery"}"#]
        )
        try db.insert(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            bindings: ["p_broken", "m3", "sess_a", late, nil]
        )
        return db
    }

    private func installFixture() throws {
        let url = workspace.appendingPathComponent("opencode.db")
        try makeFixture(at: url)
        OpenCodeHistoryStore.databaseURLOverride = url
    }

    // MARK: - listSessions

    func testListSessionsOrdersByUpdateAndCountsMessages() throws {
        try installFixture()

        let sessions = try OpenCodeHistoryStore.listSessions()

        XCTAssertEqual(sessions.map(\.id), ["sess_sub", "sess_a", "sess_b", "sess_d", "sess_c"])
        XCTAssertEqual(sessions.first?.messageCount, 0)
        XCTAssertEqual(sessions.first?.parentID, "sess_a")
        XCTAssertTrue(sessions.first!.isSubagent)

        let rootA = try XCTUnwrap(sessions.first { $0.id == "sess_a" })
        XCTAssertEqual(rootA.title, "Root A")
        XCTAssertEqual(rootA.directory, "/tmp/proj")
        XCTAssertEqual(rootA.agent, "opencode")
        XCTAssertEqual(rootA.model, "model/x")
        XCTAssertNil(rootA.parentID)
        XCTAssertFalse(rootA.isSubagent)
        XCTAssertEqual(rootA.messageCount, 3)
        XCTAssertEqual(rootA.timeCreated, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(rootA.timeUpdated, Date(timeIntervalSince1970: 3))

        let untitled = try XCTUnwrap(sessions.first { $0.id == "sess_c" })
        XCTAssertEqual(untitled.title, "Untitled", "NULL title falls back to Untitled")
    }

    // MARK: - transcript

    func testTranscriptAssemblesMessagesWithParsedParts() throws {
        try installFixture()

        let transcript = try OpenCodeHistoryStore.transcript(for: "sess_a")

        XCTAssertEqual(transcript.session.id, "sess_a")
        XCTAssertEqual(transcript.messages.map(\.id), ["m1", "m2", "m3"])
        XCTAssertTrue(transcript.messages[0].parts.isEmpty)

        let userParts = transcript.messages[1].parts
        XCTAssertEqual(userParts.count, 3)
        let textPart = try XCTUnwrap(userParts.first { $0.id == "p_text" })
        XCTAssertEqual(textPart.kind, .text)
        XCTAssertEqual(textPart.text, "hello   world  from\nfixture")
        XCTAssertTrue(textPart.isDisplayable)
        XCTAssertTrue(userParts.contains { $0.id == "p_syn" && !$0.isDisplayable })
        XCTAssertTrue(userParts.contains { $0.id == "p_ign" && !$0.isDisplayable })

        let replyParts = transcript.messages[2].parts
        let tool = try XCTUnwrap(replyParts.first { $0.id == "p_tool" })
        XCTAssertEqual(tool.kind, .tool)
        XCTAssertEqual(tool.toolName, "bash")
        XCTAssertEqual(tool.toolStatus, "completed")
        XCTAssertEqual(tool.toolInput, "{\n  \"command\" : \"ls\"\n}")
        XCTAssertEqual(tool.toolOutput, "file.txt")

        let file = try XCTUnwrap(replyParts.first { $0.id == "p_file" })
        XCTAssertEqual(file.kind, .file)
        XCTAssertEqual(file.filename, "App.swift")
        XCTAssertEqual(file.fileURL, "/tmp/App.swift")

        let patch = try XCTUnwrap(replyParts.first { $0.id == "p_patch" })
        XCTAssertEqual(patch.kind, .patch)
        XCTAssertEqual(patch.patchFiles, ["x.swift", "y.swift"])

        let weird = try XCTUnwrap(replyParts.first { $0.id == "p_weird" })
        XCTAssertEqual(weird.kind, .unknown)

        let broken = try XCTUnwrap(replyParts.first { $0.id == "p_broken" })
        XCTAssertEqual(broken.kind, .unknown)
        XCTAssertNil(broken.text)
    }

    func testTranscriptForUnknownSessionThrowsQueryFailed() throws {
        try installFixture()

        XCTAssertThrowsError(try OpenCodeHistoryStore.transcript(for: "missing")) { error in
            guard case OpenCodeHistoryError.queryFailed = error else {
                return XCTFail("expected queryFailed, got \(error)")
            }
        }
    }

    // MARK: - firstUserPrompt

    func testFirstUserPromptNormalizesWhitespaceAndSkipsSyntheticParts() throws {
        try installFixture()

        let prompt = try XCTUnwrap(OpenCodeHistoryStore.firstUserPrompt(sessionID: "sess_a"))
        XCTAssertEqual(prompt, "hello world from fixture")
    }

    func testFirstUserPromptReturnsNilWithoutTextAnswer() throws {
        try installFixture()

        XCTAssertNil(try OpenCodeHistoryStore.firstUserPrompt(sessionID: "sess_d"))
        XCTAssertNil(try OpenCodeHistoryStore.firstUserPrompt(sessionID: "sess_c"))
    }

    func testFirstUserPromptByDirectoryUsesLatestRootSession() throws {
        try installFixture()

        let prompt = try XCTUnwrap(OpenCodeHistoryStore.firstUserPrompt(directory: "/tmp/proj"))
        XCTAssertEqual(prompt, "hello world from fixture")

        XCTAssertNil(try OpenCodeHistoryStore.firstUserPrompt(directory: "/tmp/nothing"))
    }

    // MARK: - latestSessionID

    func testLatestSessionIDIgnoresSubagentsAndOtherDirectories() throws {
        try installFixture()

        XCTAssertEqual(try OpenCodeHistoryStore.latestSessionID(directory: "/tmp/proj"), "sess_a")
        XCTAssertEqual(try OpenCodeHistoryStore.latestSessionID(directory: "/tmp/other"), "sess_d")
        XCTAssertNil(try OpenCodeHistoryStore.latestSessionID(directory: "/tmp/none"))
    }

    // MARK: - Error paths

    func testMissingDatabaseThrowsDatabaseNotFound() {
        OpenCodeHistoryStore.databaseURLOverride =
            workspace.appendingPathComponent("does-not-exist.db")
        XCTAssertNil(OpenCodeHistoryStore.databaseURL)

        XCTAssertThrowsError(try OpenCodeHistoryStore.listSessions()) { error in
            guard case OpenCodeHistoryError.databaseNotFound = error else {
                return XCTFail("expected databaseNotFound, got \(error)")
            }
        }
    }

    func testDirectoryAsDatabaseThrowsCannotOpen() throws {
        OpenCodeHistoryStore.databaseURLOverride = workspace
        XCTAssertNotNil(OpenCodeHistoryStore.databaseURL)

        XCTAssertThrowsError(try OpenCodeHistoryStore.listSessions()) { error in
            guard case OpenCodeHistoryError.cannotOpen = error else {
                return XCTFail("expected cannotOpen, got \(error)")
            }
        }
    }

    func testGarbageFileThrowsQueryFailed() throws {
        let url = workspace.appendingPathComponent("garbage.db")
        try Data("this is definitely not sqlite".utf8).write(to: url)
        OpenCodeHistoryStore.databaseURLOverride = url

        XCTAssertThrowsError(try OpenCodeHistoryStore.listSessions()) { error in
            guard case OpenCodeHistoryError.queryFailed = error else {
                return XCTFail("expected queryFailed, got \(error)")
            }
        }
    }

    func testErrorMessagesAreHumanReadable() {
        XCTAssertEqual(
            OpenCodeHistoryError.databaseNotFound.errorDescription,
            "opencode database not found"
        )
        XCTAssertEqual(
            OpenCodeHistoryError.cannotOpen("locked").errorDescription,
            "Could not open database: locked"
        )
        XCTAssertEqual(
            OpenCodeHistoryError.queryFailed("syntax").errorDescription,
            "Query failed: syntax"
        )
    }

    // MARK: - Live database (environment dependent)

    func testLiveDatabaseStillReadableWhenPresent() throws {
        guard OpenCodeHistoryStore.databaseURL != nil else {
            throw XCTSkip("no ~/.local/share/opencode/opencode.db on this machine")
        }

        let sessions = try OpenCodeHistoryStore.listSessions()
        for session in sessions {
            XCTAssertFalse(session.id.isEmpty)
            XCTAssertTrue(session.messageCount >= 0)
        }
    }
}
