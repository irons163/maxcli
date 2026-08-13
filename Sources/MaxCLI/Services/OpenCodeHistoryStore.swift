import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum OpenCodeHistoryError: LocalizedError {
    case databaseNotFound
    case cannotOpen(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "opencode database not found"
        case let .cannotOpen(message):
            return "Could not open database: \(message)"
        case let .queryFailed(message):
            return "Query failed: \(message)"
        }
    }
}

/// Read-only access to opencode's SQLite storage at
/// `~/.local/share/opencode/opencode.db`. Queries run on a fresh read-only
/// connection per call, so the live database (including WAL) is never touched.
enum OpenCodeHistoryStore {
    static var databaseURL: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func listSessions() throws -> [OpenCodeHistorySession] {
        try withConnection { db in
            let sql = """
                SELECT s.id, s.title, s.directory, s.agent, s.model, s.parent_id,
                       s.time_created, s.time_updated, COUNT(m.id)
                FROM session s
                LEFT JOIN message m ON m.session_id = s.id
                GROUP BY s.id
                ORDER BY s.time_updated DESC
                """
            var rows: [OpenCodeHistorySession] = []
            try query(db, sql: sql, bindings: []) { columns in
                rows.append(OpenCodeHistorySession(
                    id: columns[0] ?? "",
                    title: columns[1] ?? "Untitled",
                    directory: columns[2] ?? "",
                    agent: columns[3],
                    model: columns[4],
                    parentID: columns[5],
                    timeCreated: date(fromMilliseconds: columns[6]),
                    timeUpdated: date(fromMilliseconds: columns[7]),
                    messageCount: Int(columns[8] ?? "0") ?? 0
                ))
            }
            return rows
        }
    }

    static func transcript(for sessionID: String) throws -> OpenCodeTranscript {
        try withConnection { db in
            let sessionSQL = """
                SELECT s.id, s.title, s.directory, s.agent, s.model, s.parent_id,
                       s.time_created, s.time_updated, COUNT(m.id)
                FROM session s
                LEFT JOIN message m ON m.session_id = s.id
                WHERE s.id = ?
                GROUP BY s.id
                """
            var session: OpenCodeHistorySession?
            try query(db, sql: sessionSQL, bindings: [sessionID]) { columns in
                session = OpenCodeHistorySession(
                    id: columns[0] ?? "",
                    title: columns[1] ?? "Untitled",
                    directory: columns[2] ?? "",
                    agent: columns[3],
                    model: columns[4],
                    parentID: columns[5],
                    timeCreated: date(fromMilliseconds: columns[6]),
                    timeUpdated: date(fromMilliseconds: columns[7]),
                    messageCount: Int(columns[8] ?? "0") ?? 0
                )
            }
            guard let session else {
                throw OpenCodeHistoryError.queryFailed("session \(sessionID) not found")
            }

            let messageSQL = """
                SELECT id, time_created, data
                FROM message
                WHERE session_id = ?
                ORDER BY time_created ASC, id ASC
                """
            var messages: [OpenCodeMessage] = []
            try query(db, sql: messageSQL, bindings: [sessionID]) { columns in
                let data = decodeJSON(columns[2])
                let role = data["role"] as? String ?? "unknown"
                let time = data["time"] as? [String: Any]
                messages.append(OpenCodeMessage(
                    id: columns[0] ?? "",
                    role: role,
                    timeCreated: date(fromMilliseconds: (time?["created"] as? NSNumber)?.stringValue),
                    parts: []
                ))
            }

            let partSQL = """
                SELECT message_id, id, data
                FROM part
                WHERE session_id = ?
                ORDER BY message_id ASC, time_created ASC, id ASC
                """
            var partsByMessage: [String: [OpenCodePart]] = [:]
            try query(db, sql: partSQL, bindings: [sessionID]) { columns in
                let messageID = columns[0] ?? ""
                partsByMessage[messageID, default: []].append(parsePart(id: columns[1] ?? "", data: columns[2]))
            }

            let messagesWithParts = messages.map { message in
                OpenCodeMessage(
                    id: message.id,
                    role: message.role,
                    timeCreated: message.timeCreated,
                    parts: partsByMessage[message.id] ?? []
                )
            }

            return OpenCodeTranscript(session: session, messages: messagesWithParts)
        }
    }

    static func firstUserPrompt(directory: String) throws -> String? {
        try withConnection { db in
            let sessionSQL = """
                SELECT id FROM session
                WHERE directory = ? AND parent_id IS NULL
                ORDER BY time_updated DESC
                LIMIT 1
                """
            var sessionID: String?
            try query(db, sql: sessionSQL, bindings: [directory]) { columns in
                sessionID = columns[0]
            }
            guard let sessionID else { return nil }

            var messageID: String?
            let messageSQL = """
                SELECT id, data FROM message
                WHERE session_id = ?
                ORDER BY time_created ASC, id ASC
                """
            try query(db, sql: messageSQL, bindings: [sessionID]) { columns in
                guard messageID == nil,
                      decodeJSON(columns[1])["role"] as? String == "user"
                else { return }
                messageID = columns[0]
            }
            guard let messageID else { return nil }

            var text: String?
            let partSQL = """
                SELECT data FROM part
                WHERE message_id = ?
                ORDER BY time_created ASC, id ASC
                """
            try query(db, sql: partSQL, bindings: [messageID]) { columns in
                guard text == nil else { return }
                let data = decodeJSON(columns[0])
                guard data["type"] as? String == "text",
                      let value = data["text"] as? String,
                      !(data["synthetic"] as? Bool ?? false),
                      !(data["ignored"] as? Bool ?? false)
                else { return }
                text = value
            }
            return text.map {
                $0.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
        }
    }

    // MARK: - Parsing

    private static func parsePart(id: String, data: String?) -> OpenCodePart {
        guard let data else { return .init(id: id, kind: .unknown) }
        let dict = decodeJSON(data)
        let kind = OpenCodePartKind(rawValue: dict["type"] as? String ?? "")
        let toolState = dict["state"] as? [String: Any]
        let toolInput = toolState?["input"]
        return OpenCodePart(
            id: id,
            kind: kind,
            text: dict["text"] as? String,
            toolName: dict["tool"] as? String,
            toolStatus: toolState?["status"] as? String,
            toolInput: toolInput.map { stringifyJSON($0) },
            toolOutput: toolState?["output"] as? String,
            filename: dict["filename"] as? String,
            fileURL: dict["url"] as? String,
            patchFiles: dict["files"] as? [String] ?? [],
            synthetic: dict["synthetic"] as? Bool ?? false,
            ignored: dict["ignored"] as? Bool ?? false
        )
    }

    private static func decodeJSON(_ string: String?) -> [String: Any] {
        guard let string, let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private static func stringifyJSON(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else { return String(describing: value) }
        return string
    }

    private static func date(fromMilliseconds value: String?) -> Date {
        Date(timeIntervalSince1970: (Double(value ?? "") ?? 0) / 1000)
    }

    // MARK: - SQLite

    private static func withConnection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let databaseURL else { throw OpenCodeHistoryError.databaseNotFound }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw OpenCodeHistoryError.cannotOpen(sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown error")
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
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw OpenCodeHistoryError.queryFailed(sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown error")
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), binding, -1, SQLITE_TRANSIENT)
        }

        var columnCount = -1
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw OpenCodeHistoryError.queryFailed(sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown error")
            }
            if columnCount == -1 {
                columnCount = Int(sqlite3_column_count(statement))
            }
            var columns: [String?] = []
            columns.reserveCapacity(columnCount)
            for i in 0..<columnCount {
                if let text = sqlite3_column_text(statement, Int32(i)) {
                    columns.append(String(cString: text))
                } else {
                    columns.append(nil)
                }
            }
            try row(columns)
        }
    }
}
