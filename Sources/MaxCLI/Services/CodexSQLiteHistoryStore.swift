import Foundation
import SQLite3

private let CODEX_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum CodexSQLiteHistoryError: LocalizedError {
    case databaseNotFound
    case cannotOpen(String)
    case queryFailed(String)
    case threadNotFound(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Codex history database not found"
        case let .cannotOpen(message):
            return "Could not open Codex history database: \(message)"
        case let .queryFailed(message):
            return "Codex history query failed: \(message)"
        case let .threadNotFound(threadID):
            return "Codex thread \(threadID) not found"
        }
    }
}

/// Read-only access to Codex 0.149+'s projected history database.
///
/// Recent Codex releases keep the live thread index in
/// `~/.codex/thread_history_1.sqlite` rather than the older JSONL rollout
/// directories. The database is opened read-only so the active Codex
/// process remains the only writer.
enum CodexSQLiteHistoryStore {
    /// Test seam: when non-nil, overrides the default database location.
    nonisolated(unsafe) static var databaseURLOverride: URL?

    static var databaseURL: URL? {
        if let override = databaseURLOverride {
            return FileManager.default.fileExists(atPath: override.path) ? override : nil
        }
        let url = HistoryPath.codexHome.appendingPathComponent("thread_history_1.sqlite")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func listSessions() throws -> [HistorySession] {
        try withConnection { db in
            let summaries = try threadSummaries(db: db)
            let directoryCounts = try directoryCounts(db: db)

            return try summaries.map { summary in
                let prompt = try firstUserPrompt(db: db, threadID: summary.threadID)
                return makeSession(
                    threadID: summary.threadID,
                    title: prompt ?? "Codex session",
                    directory: preferredDirectory(directoryCounts[summary.threadID]),
                    created: summary.created,
                    updated: summary.updated,
                    messageCount: summary.messageCount
                )
            }
        }
    }

    static func transcript(for threadID: String) throws -> HistoryTranscript {
        try withConnection { db in
            let items = try items(db: db, threadID: threadID)
            guard !items.isEmpty else {
                throw CodexSQLiteHistoryError.threadNotFound(threadID)
            }

            let messages = items.compactMap(parseMessage)
            let created = items.map(\.createdAt).min() ?? .distantPast
            let updated = items.map(\.createdAt).max() ?? created
            let session = makeSession(
                threadID: threadID,
                title: HistoryProviderSupport.title(for: messages, fallback: "Codex session"),
                directory: preferredDirectory(directoryCounts(for: items)),
                created: created,
                updated: updated,
                messageCount: messages.count
            )
            return HistoryProviderSupport.transcript(session: session, messages: messages)
        }
    }

    // MARK: - Session metadata

    private struct ThreadSummary {
        let threadID: String
        let created: Date
        let updated: Date
        let messageCount: Int
    }

    private struct CodexItem {
        let itemID: String
        let rolloutOrdinal: Int
        let createdAt: Date
        let itemType: String
        let object: [String: Any]
    }

    private static func threadSummaries(db: OpaquePointer) throws -> [ThreadSummary] {
        let sql = """
            SELECT thread_id, MIN(created_at_ms), MAX(created_at_ms),
                   SUM(CASE WHEN item_type IN ('userMessage', 'agentMessage') THEN 1 ELSE 0 END)
            FROM thread_items
            GROUP BY thread_id
            ORDER BY MAX(created_at_ms) DESC, thread_id ASC
            """
        var summaries: [ThreadSummary] = []
        try query(db, sql: sql, bindings: []) { columns in
            guard let threadID = columns[0], !threadID.isEmpty else { return }
            summaries.append(ThreadSummary(
                threadID: threadID,
                created: date(fromMilliseconds: columns[1]),
                updated: date(fromMilliseconds: columns[2]),
                messageCount: Int(columns[3] ?? "0") ?? 0
            ))
        }
        return summaries
    }

    private static func firstUserPrompt(db: OpaquePointer, threadID: String) throws -> String? {
        let sql = """
            SELECT item_json
            FROM thread_items
            WHERE thread_id = ? AND item_type = 'userMessage'
            ORDER BY rollout_ordinal ASC
            LIMIT 1
            """
        var prompt: String?
        try query(db, sql: sql, bindings: [threadID]) { columns in
            guard prompt == nil, let object = decodeJSON(columns[0]) else { return }
            let id = HistoryRecordID.codex(threadID)
            let parts = HistoryJSON.contentParts(object["content"], idPrefix: id)
            let message = HistoryMessage(
                id: id,
                role: "user",
                timeCreated: .distantPast,
                parts: parts
            )
            prompt = HistoryProviderSupport.firstPrompt(in: [message])
        }
        return prompt
    }

    private static func directoryCounts(db: OpaquePointer) throws -> [String: [String: Int]] {
        let sql = """
            SELECT thread_id, json_extract(item_json, '$.cwd')
            FROM thread_items
            WHERE item_type = 'commandExecution'
              AND json_extract(item_json, '$.cwd') IS NOT NULL
            """
        var counts: [String: [String: Int]] = [:]
        do {
            try query(db, sql: sql, bindings: []) { columns in
                guard let threadID = columns[0],
                      let directory = columns[1],
                      !directory.isEmpty
                else { return }
                counts[threadID, default: [:]][directory, default: 0] += 1
            }
        } catch {
            // JSON1 is available in the macOS SQLite shipped with supported
            // systems, but fall back to decoding the rows if it is disabled.
            let fallbackSQL = """
                SELECT thread_id, item_json
                FROM thread_items
                WHERE item_type = 'commandExecution'
                """
            try query(db, sql: fallbackSQL, bindings: []) { columns in
                guard let threadID = columns[0],
                      let object = decodeJSON(columns[1]),
                      let directory = HistoryJSON.string(object["cwd"]),
                      !directory.isEmpty
                else { return }
                counts[threadID, default: [:]][directory, default: 0] += 1
            }
        }
        return counts
    }

    private static func directoryCounts(for items: [CodexItem]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for item in items {
            guard item.itemType == "commandExecution",
                  let directory = HistoryJSON.string(item.object["cwd"]),
                  !directory.isEmpty
            else { continue }
            counts[directory, default: 0] += 1
        }
        return counts
    }

    private static func preferredDirectory(_ counts: [String: Int]?) -> String {
        preferredDirectory(counts ?? [:])
    }

    private static func preferredDirectory(_ counts: [String: Int]) -> String {
        counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .first?.key
            ?? HistoryPath.codexHome.path
    }

    private static func makeSession(
        threadID: String,
        title: String,
        directory: String,
        created: Date,
        updated: Date,
        messageCount: Int
    ) -> HistorySession {
        HistoryProviderSupport.session(
            id: HistoryRecordID.codex(threadID),
            sessionID: threadID,
            title: title,
            directory: directory,
            agent: .codex,
            model: nil,
            created: created,
            updated: updated,
            messages: [],
            messageCount: messageCount
        )
    }

    // MARK: - Transcript parsing

    private static func items(db: OpaquePointer, threadID: String) throws -> [CodexItem] {
        let sql = """
            SELECT item_id, rollout_ordinal, created_at_ms, item_type, item_json
            FROM thread_items
            WHERE thread_id = ?
            ORDER BY rollout_ordinal ASC, item_id ASC
            """
        var result: [CodexItem] = []
        try query(db, sql: sql, bindings: [threadID]) { columns in
            guard let itemID = columns[0],
                  let itemType = columns[3],
                  let object = decodeJSON(columns[4])
            else { return }
            result.append(CodexItem(
                itemID: itemID,
                rolloutOrdinal: Int(columns[1] ?? "0") ?? 0,
                createdAt: date(fromMilliseconds: columns[2]),
                itemType: itemType,
                object: object
            ))
        }
        return result
    }

    private static func parseMessage(_ item: CodexItem) -> HistoryMessage? {
        let id = item.itemID
        switch item.itemType {
        case "userMessage":
            let parts = HistoryJSON.contentParts(item.object["content"], idPrefix: id)
            guard !parts.isEmpty else { return nil }
            return HistoryMessage(id: id, role: "user", timeCreated: item.createdAt, parts: parts)

        case "agentMessage":
            guard let text = HistoryJSON.text(item.object["text"] ?? item.object["content"]),
                  !text.isEmpty
            else { return nil }
            return HistoryMessage(
                id: id,
                role: "assistant",
                timeCreated: item.createdAt,
                parts: [HistoryPart(id: id, kind: .text, text: text)]
            )

        case "reasoning":
            guard let text = HistoryJSON.text(
                item.object["summary"] ?? item.object["content"] ?? item.object["text"]
            ), !text.isEmpty else { return nil }
            return HistoryMessage(
                id: id,
                role: "assistant",
                timeCreated: item.createdAt,
                parts: [HistoryPart(id: id, kind: .reasoning, text: text)]
            )

        case "commandExecution":
            let command = HistoryJSON.string(item.object["command"])
            let output = HistoryJSON.string(item.object["aggregatedOutput"])
            let status = normalizedStatus(HistoryJSON.string(item.object["status"]))
            guard command != nil || output != nil || status != nil else { return nil }
            return HistoryMessage(
                id: id,
                role: "tool",
                timeCreated: item.createdAt,
                parts: [HistoryPart(
                    id: id,
                    kind: .tool,
                    toolName: "command",
                    toolStatus: status,
                    toolInput: command,
                    toolOutput: output
                )]
            )

        case "fileChange":
            let changes = item.object["changes"] as? [[String: Any]] ?? []
            let paths = changes.compactMap { HistoryJSON.string($0["path"]) }
            guard !paths.isEmpty else { return nil }
            return HistoryMessage(
                id: id,
                role: "tool",
                timeCreated: item.createdAt,
                parts: [HistoryPart(id: id, kind: .patch, patchFiles: paths)]
            )

        case "webSearch":
            let query = HistoryJSON.string(item.object["query"])
            return HistoryMessage(
                id: id,
                role: "tool",
                timeCreated: item.createdAt,
                parts: [HistoryPart(
                    id: id,
                    kind: .tool,
                    toolName: "web search",
                    toolStatus: "completed",
                    toolInput: query
                )]
            )

        default:
            return nil
        }
    }

    private static func normalizedStatus(_ status: String?) -> String? {
        guard let status else { return nil }
        switch status.lowercased() {
        case "inprogress", "in_progress", "running": return "running"
        case "completed", "success", "succeeded": return "completed"
        case "failed", "failure", "error": return "error"
        default: return status
        }
    }

    // MARK: - SQLite

    private static func decodeJSON(_ string: String?) -> [String: Any]? {
        guard let string,
              let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func date(fromMilliseconds value: String?) -> Date {
        Date(timeIntervalSince1970: (Double(value ?? "") ?? 0) / 1000)
    }

    private static func withConnection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let databaseURL else { throw CodexSQLiteHistoryError.databaseNotFound }
        var db: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let db { sqlite3_close(db) }
            throw CodexSQLiteHistoryError.cannotOpen(message)
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private static func query(
        _ db: OpaquePointer,
        sql: String,
        bindings: [String],
        row: ([String?]) throws -> Void
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw CodexSQLiteHistoryError.queryFailed(
                String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), binding, -1, CODEX_SQLITE_TRANSIENT)
        }

        let columnCount = Int(sqlite3_column_count(statement))
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw CodexSQLiteHistoryError.queryFailed(
                    String(cString: sqlite3_errmsg(db))
                )
            }
            var columns: [String?] = []
            columns.reserveCapacity(columnCount)
            for index in 0..<columnCount {
                if let value = sqlite3_column_text(statement, Int32(index)) {
                    columns.append(String(cString: value))
                } else {
                    columns.append(nil)
                }
            }
            try row(columns)
        }
    }
}
