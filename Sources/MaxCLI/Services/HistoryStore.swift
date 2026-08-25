import Foundation

enum HistoryStoreError: LocalizedError {
    case sessionNotFound
    case unreadableSession

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "History session not found"
        case .unreadableSession:
            return "History session could not be read"
        }
    }
}

/// Read-only aggregation of the local history formats used by the supported
/// agent CLIs. A provider is allowed to be absent or unreadable; the other
/// providers still contribute their sessions.
enum HistoryStore {
    /// Test seam. In production this is the user's home directory.
    nonisolated(unsafe) static var homeDirectoryOverride: URL?

    static func listSessions() -> [HistorySession] {
        var sessions: [HistorySession] = []
        for provider in HistoryProviderKind.allCases {
            sessions.append(contentsOf: provider.listSessions())
        }
        return sessions.sorted {
            if $0.timeUpdated != $1.timeUpdated {
                return $0.timeUpdated > $1.timeUpdated
            }
            return $0.id < $1.id
        }
    }

    static func transcript(for sessionID: String) throws -> HistoryTranscript {
        if let rawID = HistoryRecordID.openCodeSessionID(from: sessionID) {
            let transcript = try OpenCodeHistoryStore.transcript(for: rawID)
            return HistoryTranscript(
                session: transcript.session.with(source: .opencode, id: sessionID),
                messages: transcript.messages
            )
        }

        guard let provider = HistoryProviderKind.provider(for: sessionID),
              let path = HistoryRecordID.filePath(from: sessionID, source: provider.agent)
        else {
            throw HistoryStoreError.sessionNotFound
        }
        guard let transcript = provider.transcript(at: URL(fileURLWithPath: path)) else {
            throw HistoryStoreError.unreadableSession
        }
        return transcript
    }

    static var storageDescription: String {
        let paths = HistoryProviderKind.allCases.map { $0.storagePath }
        return paths.map(prettyPath).joined(separator: " · ")
    }

    private static func prettyPath(_ path: String) -> String {
        let home = HistoryPath.home.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

enum HistoryProviderKind: CaseIterable {
    case codex
    case claude
    case gemini
    case cursor
    case copilot
    case grok
    case opencode

    var agent: AgentKind {
        switch self {
        case .codex: .codex
        case .claude: .claude
        case .gemini: .gemini
        case .cursor: .cursor
        case .copilot: .copilot
        case .grok: .grok
        case .opencode: .opencode
        }
    }

    var storagePath: String {
        switch self {
        case .codex: HistoryPath.codexHome.appendingPathComponent("sessions").path
        case .claude: HistoryPath.claudeHome.appendingPathComponent("projects").path
        case .gemini: HistoryPath.geminiHome.appendingPathComponent("tmp").path
        case .cursor: HistoryPath.cursorHome.appendingPathComponent("projects").path
        case .copilot: HistoryPath.copilotHome.appendingPathComponent("session-state").path
        case .grok: HistoryPath.grokHome.appendingPathComponent("sessions").path
        case .opencode:
            OpenCodeHistoryStore.databaseURL?.path
                ?? HistoryPath.home.appendingPathComponent(".local/share/opencode/opencode.db").path
        }
    }

    func listSessions() -> [HistorySession] {
        switch self {
        case .codex: CodexHistoryProvider.listSessions()
        case .claude: ClaudeHistoryProvider.listSessions()
        case .gemini: GeminiHistoryProvider.listSessions()
        case .cursor: CursorHistoryProvider.listSessions()
        case .copilot: CopilotHistoryProvider.listSessions()
        case .grok: GrokHistoryProvider.listSessions()
        case .opencode:
            (try? OpenCodeHistoryStore.listSessions())?.map {
                $0.with(source: .opencode, id: HistoryRecordID.openCode($0.id))
            } ?? []
        }
    }

    func transcript(at url: URL) -> HistoryTranscript? {
        switch self {
        case .codex: CodexHistoryProvider.transcript(at: url)
        case .claude: ClaudeHistoryProvider.transcript(at: url)
        case .gemini: GeminiHistoryProvider.transcript(at: url)
        case .cursor: CursorHistoryProvider.transcript(at: url)
        case .copilot: CopilotHistoryProvider.transcript(at: url)
        case .grok: GrokHistoryProvider.transcript(at: url)
        case .opencode: nil
        }
    }

    static func provider(for sessionID: String) -> HistoryProviderKind? {
        allCases.first { sessionID.hasPrefix(HistoryRecordID.filePrefix(for: $0.agent)) }
    }
}

enum HistoryPath {
    static var home: URL {
        HistoryStore.homeDirectoryOverride
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static var codexHome: URL {
        environmentURL("CODEX_HOME") ?? home.appendingPathComponent(".codex")
    }

    static var claudeHome: URL {
        home.appendingPathComponent(".claude")
    }

    static var geminiHome: URL {
        environmentURL("GEMINI_HOME") ?? home.appendingPathComponent(".gemini")
    }

    static var cursorHome: URL {
        home.appendingPathComponent(".cursor")
    }

    static var copilotHome: URL {
        environmentURL("COPILOT_HOME") ?? home.appendingPathComponent(".copilot")
    }

    static var grokHome: URL {
        environmentURL("GROK_HOME") ?? home.appendingPathComponent(".grok")
    }

    private static func environmentURL(_ key: String) -> URL? {
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: value)
    }
}

enum HistoryRecordID {
    private static let fileMarker = "file:"
    private static let openCodeMarker = "opencode:"

    static func filePrefix(for agent: AgentKind) -> String {
        "\(agent.rawValue):\(fileMarker)"
    }

    static func file(source: AgentKind, path: String) -> String {
        let encoded = Data(path.utf8).base64EncodedString()
        return "\(filePrefix(for: source))\(encoded)"
    }

    static func filePath(from id: String, source: AgentKind) -> String? {
        let prefix = filePrefix(for: source)
        guard id.hasPrefix(prefix) else { return nil }
        let encoded = String(id.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: encoded),
              let path = String(data: data, encoding: .utf8)
        else { return nil }
        return path
    }

    static func openCode(_ sessionID: String) -> String {
        "\(openCodeMarker)\(sessionID)"
    }

    static func openCodeSessionID(from id: String) -> String? {
        guard id.hasPrefix(openCodeMarker) else { return nil }
        return String(id.dropFirst(openCodeMarker.count))
    }
}

struct HistoryJSONLRecord {
    let lineNumber: Int
    let object: [String: Any]
}

enum HistoryFiles {
    static func jsonLines(at url: URL) -> [HistoryJSONLRecord] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return contents
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { index, line in
                guard let object = HistoryJSON.object(from: String(line)) else { return nil }
                return HistoryJSONLRecord(lineNumber: index + 1, object: object)
            }
    }

    static func files(in root: URL, where predicate: (URL) -> Bool) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
              )
        else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            guard predicate(url),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            result.append(url)
        }
        return result
    }

    static func dates(for url: URL) -> (created: Date?, updated: Date?) {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return (values?.creationDate, values?.contentModificationDate)
    }

    static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?): max(left, right)
        case let (date?, nil), let (nil, date?): date
        case (nil, nil): nil
        }
    }
}

enum HistoryJSON {
    static func object(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return nil }
        return dictionary
    }

    static func object(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    static func string(_ object: [String: Any], _ key: String) -> String? {
        string(object[key])
    }

    static func object(_ object: [String: Any], _ key: String) -> [String: Any]? {
        self.object(object[key])
    }

    static func date(_ value: Any?) -> Date? {
        if let value = value as? NSNumber {
            return dateFromNumber(value.doubleValue)
        }
        guard let value = value as? String else { return nil }
        if let numeric = Double(value) {
            return dateFromNumber(numeric)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    static func firstDate(in object: [String: Any], keys: [String]) -> Date? {
        for key in keys where object[key] != nil {
            if let date = date(object[key]) { return date }
        }
        return nil
    }

    static func text(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let values = value as? [Any] {
            let texts = values.compactMap(text).filter { !$0.isEmpty }
            return texts.isEmpty ? nil : texts.joined(separator: "\n")
        }
        guard let object = value as? [String: Any] else { return nil }
        for key in ["text", "thinking", "content", "message", "output", "result"] {
            if let result = text(object[key]), !result.isEmpty { return result }
        }
        return nil
    }

    static func contentParts(_ value: Any?, idPrefix: String) -> [HistoryPart] {
        if let value = value as? String {
            return value.isEmpty ? [] : [HistoryPart(id: idPrefix, kind: .text, text: value)]
        }
        if let values = value as? [Any] {
            return values.enumerated().flatMap { index, item in
                contentParts(item, idPrefix: "(idPrefix)-(index)")
            }
        }
        guard let object = value as? [String: Any] else { return [] }
        let type = string(object["type"])?.lowercased()
        switch type {
        case "text", "input_text", "output_text":
            guard let text = text(object["text"]), !text.isEmpty else { return [] }
            return [HistoryPart(id: idPrefix, kind: .text, text: text)]
        case "thinking", "reasoning", "summary":
            guard let text = text(object["thinking"] ?? object["summary"] ?? object["text"]),
                  !text.isEmpty
            else { return [] }
            return [HistoryPart(id: idPrefix, kind: .reasoning, text: text)]
        case "tool_use", "server_tool_use", "function_call", "custom_tool_call", "computer_call":
            return [HistoryPart(
                id: idPrefix,
                kind: .tool,
                toolName: string(object["name"] ?? object["tool"]) ?? type,
                toolInput: stringify(object["input"] ?? object["arguments"] ?? object["action"])
            )]
        case "tool_result", "function_call_output", "custom_tool_call_output":
            let isError = (object["is_error"] as? Bool) == true || (object["isError"] as? Bool) == true
            return [HistoryPart(
                id: idPrefix,
                kind: .tool,
                toolName: string(object["name"] ?? object["tool"]),
                toolStatus: isError ? "error" : "completed",
                toolOutput: stringify(object["content"] ?? object["output"] ?? object["result"])
            )]
        case "file", "image":
            return [HistoryPart(
                id: idPrefix,
                kind: .file,
                filename: string(object["filename"] ?? object["name"] ?? object["file"]),
                fileURL: string(object["url"] ?? object["source"])
            )]
        default:
            if let nested = object["content"] {
                return contentParts(nested, idPrefix: idPrefix)
            }
            if let text = text(object), !text.isEmpty {
                return [HistoryPart(id: idPrefix, kind: .text, text: text)]
            }
            return []
        }
    }

    static func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let value = value as? String { return value }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        else { return String(describing: value) }
        return String(data: data, encoding: .utf8)
    }

    static func shortened(_ text: String, limit: Int = 240) -> String {
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit - 1)) + "…"
    }

    private static func dateFromNumber(_ value: Double) -> Date {
        let seconds = abs(value) > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}

private extension HistorySession {
    func with(source: AgentKind, id: String? = nil) -> HistorySession {
        HistorySession(
            id: id ?? self.id,
            sessionID: sessionID,
            title: title,
            directory: directory,
            agent: agent,
            model: model,
            parentID: parentID,
            timeCreated: timeCreated,
            timeUpdated: timeUpdated,
            messageCount: messageCount,
            source: source
        )
    }
}
