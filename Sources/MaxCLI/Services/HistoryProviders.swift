import Foundation

private enum HistoryProviderSupport {
    static func dates(for url: URL) -> (created: Date, updated: Date) {
        let fileDates = HistoryFiles.dates(for: url)
        let created = fileDates.created ?? Date(timeIntervalSince1970: 0)
        let updated = fileDates.updated ?? created
        return (created, updated)
    }

    static func date(_ record: HistoryJSONLRecord, fallback: Date) -> Date {
        HistoryJSON.firstDate(in: record.object, keys: ["timestamp", "time", "createdAt", "updatedAt"])
            ?? fallback
    }

    static func firstPrompt(in messages: [HistoryMessage]) -> String? {
        for message in messages where message.role == "user" {
            let text = message.parts
                .filter { $0.kind == .text }
                .compactMap(\.text)
                .joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return HistoryJSON.shortened(text)
            }
        }
        return nil
    }

    static func title(for messages: [HistoryMessage], fallback: String) -> String {
        firstPrompt(in: messages) ?? fallback
    }

    static func textPart(_ text: String, id: String) -> HistoryPart? {
        guard !text.isEmpty else { return nil }
        return HistoryPart(id: id, kind: .text, text: text)
    }

    static func session(
        id: String,
        sessionID: String? = nil,
        title: String,
        directory: String,
        agent: AgentKind,
        model: String?,
        parentID: String? = nil,
        created: Date,
        updated: Date,
        messages: [HistoryMessage]
    ) -> HistorySession {
        HistorySession(
            id: id,
            sessionID: sessionID,
            title: title,
            directory: directory,
            agent: agent.rawValue,
            model: model,
            parentID: parentID,
            timeCreated: created,
            timeUpdated: updated,
            messageCount: messages.count,
            source: agent
        )
    }

    static func transcript(
        session: HistorySession,
        messages: [HistoryMessage]
    ) -> HistoryTranscript {
        HistoryTranscript(session: session, messages: messages)
    }
}

enum CodexHistoryProvider {
    static func listSessions() -> [HistorySession] {
        files().compactMap { parse(at: $0)?.session }
    }

    static func transcript(at url: URL) -> HistoryTranscript? {
        parse(at: url)
    }

    private static func files() -> [URL] {
        let root = HistoryPath.codexHome
        let sessions = HistoryFiles.files(in: root.appendingPathComponent("sessions")) {
            $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-")
        }
        let archived = HistoryFiles.files(in: root.appendingPathComponent("archived_sessions")) {
            $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-")
        }
        return Array(Set(sessions + archived)).sorted { $0.path < $1.path }
    }

    private static func parse(at url: URL) -> HistoryTranscript? {
        let records = HistoryFiles.jsonLines(at: url)
        guard !records.isEmpty else { return nil }

        let fileDates = HistoryProviderSupport.dates(for: url)
        var sessionID = url.deletingPathExtension().lastPathComponent
        var directory = ""
        var model: String?
        var created = fileDates.created
        var updated = fileDates.updated
        var messages: [HistoryMessage] = []
        var fallbackMessages: [HistoryMessage] = []

        for record in records {
            let date = HistoryProviderSupport.date(record, fallback: updated)
            updated = max(updated, date)
            let type = HistoryJSON.string(record.object["type"])?.lowercased()

            if type == "session_meta", let payload = HistoryJSON.object(record.object["payload"]) {
                sessionID = HistoryJSON.string(payload["id"] ?? payload["session_id"])
                    ?? sessionID
                directory = HistoryJSON.string(payload["cwd"] ?? payload["working_directory"])
                    ?? directory
                model = HistoryJSON.string(payload["model"] ?? payload["model_provider"])
                    ?? model
                if let metadataDate = HistoryJSON.firstDate(
                    in: payload,
                    keys: ["timestamp", "created_at", "createdAt"]
                ) {
                    created = metadataDate
                    updated = max(updated, metadataDate)
                }
                continue
            }

            if type == "response_item", let payload = HistoryJSON.object(record.object["payload"]) {
                if let message = parseResponseItem(payload, record: record, date: date, url: url) {
                    messages.append(message)
                }
                continue
            }

            // Older rollouts also expose a compact event stream. Use it only
            // when response_item records are unavailable, to avoid duplicates.
            if type == "event_msg", let payload = HistoryJSON.object(record.object["payload"]) {
                let eventType = HistoryJSON.string(payload["type"])
                let role: String
                let value: Any?
                switch eventType {
                case "user_message":
                    role = "user"
                    value = payload["message"]
                case "agent_message":
                    role = "assistant"
                    value = payload["message"]
                default:
                    continue
                }
                if let text = HistoryJSON.text(value),
                   let part = HistoryProviderSupport.textPart(
                    text,
                    id: "\(HistoryRecordID.file(source: .codex, path: url.path))#\(record.lineNumber)"
                   ) {
                    fallbackMessages.append(HistoryMessage(
                        id: "\(url.path)#\(record.lineNumber)",
                        role: role,
                        timeCreated: date,
                        parts: [part]
                    ))
                }
            }
        }

        if messages.isEmpty {
            messages = fallbackMessages
        }
        let session = HistoryProviderSupport.session(
            id: HistoryRecordID.file(source: .codex, path: url.path),
            sessionID: sessionID,
            title: HistoryProviderSupport.title(for: messages, fallback: "Codex session"),
            directory: directory.isEmpty ? HistoryPath.codexHome.path : directory,
            agent: .codex,
            model: model,
            created: created,
            updated: updated,
            messages: messages
        )
        return HistoryProviderSupport.transcript(session: session, messages: messages)
    }

    private static func parseResponseItem(
        _ payload: [String: Any],
        record: HistoryJSONLRecord,
        date: Date,
        url: URL
    ) -> HistoryMessage? {
        let type = HistoryJSON.string(payload["type"])?.lowercased() ?? ""
        let id = "\(url.path)#\(record.lineNumber)"
        switch type {
        case "message":
            let rawRole = HistoryJSON.string(payload["role"]) ?? "assistant"
            let role = rawRole == "developer" ? "system" : rawRole
            let parts = HistoryJSON.contentParts(payload["content"], idPrefix: id)
            guard !parts.isEmpty else { return nil }
            return HistoryMessage(id: id, role: role, timeCreated: date, parts: parts)
        case "reasoning":
            guard let text = HistoryJSON.text(payload["summary"] ?? payload["content"] ?? payload["text"]),
                  !text.isEmpty
            else { return nil }
            return HistoryMessage(
                id: id,
                role: "assistant",
                timeCreated: date,
                parts: [HistoryPart(id: id, kind: .reasoning, text: text)]
            )
        case "function_call", "custom_tool_call", "computer_call", "web_search_call":
            return HistoryMessage(
                id: id,
                role: "assistant",
                timeCreated: date,
                parts: [HistoryPart(
                    id: id,
                    kind: .tool,
                    toolName: HistoryJSON.string(payload["name"] ?? payload["tool"]) ?? type,
                    toolStatus: "running",
                    toolInput: HistoryJSON.stringify(payload["arguments"] ?? payload["input"] ?? payload["action"])
                )]
            )
        case "function_call_output", "custom_tool_call_output":
            return HistoryMessage(
                id: id,
                role: "tool",
                timeCreated: date,
                parts: [HistoryPart(
                    id: id,
                    kind: .tool,
                    toolName: HistoryJSON.string(payload["name"] ?? payload["tool"]),
                    toolStatus: "completed",
                    toolOutput: HistoryJSON.stringify(payload["output"] ?? payload["result"] ?? payload["content"])
                )]
            )
        default:
            return nil
        }
    }
}

enum ClaudeHistoryProvider {
    static func listSessions() -> [HistorySession] {
        files().compactMap { parse(at: $0)?.session }
    }

    static func transcript(at url: URL) -> HistoryTranscript? {
        parse(at: url)
    }

    private static func files() -> [URL] {
        let root = HistoryPath.claudeHome.appendingPathComponent("projects")
        return HistoryFiles.files(in: root) { url in
            url.pathExtension == "jsonl"
                && !url.pathComponents.contains("subagents")
                && url.lastPathComponent != "history.jsonl"
        }
    }

    private static func parse(at url: URL) -> HistoryTranscript? {
        let records = HistoryFiles.jsonLines(at: url)
        guard !records.isEmpty else { return nil }
        let fileDates = HistoryProviderSupport.dates(for: url)
        var sessionID = url.deletingPathExtension().lastPathComponent
        var directory = ""
        var model: String?
        var created = fileDates.created
        var updated = fileDates.updated
        var messages: [HistoryMessage] = []

        for record in records {
            guard (record.object["isSidechain"] as? Bool) != true else { continue }
            let type = HistoryJSON.string(record.object["type"])?.lowercased()
            guard type == "user" || type == "assistant" || type == "system" else { continue }
            let date = HistoryProviderSupport.date(record, fallback: updated)
            created = min(created, date)
            updated = max(updated, date)
            sessionID = HistoryJSON.string(record.object["sessionId"]) ?? sessionID
            directory = HistoryJSON.string(record.object["cwd"] ?? record.object["directory"]) ?? directory

            let message = HistoryJSON.object(record.object["message"])
            let role = HistoryJSON.string(message?["role"]) ?? (type == "system" ? "system" : type)
            model = HistoryJSON.string(message?["model"]) ?? model
            let content = message?["content"] ?? record.object["content"]
            let parts = HistoryJSON.contentParts(
                content,
                idPrefix: "\(url.path)#\(record.lineNumber)"
            )
            guard !parts.isEmpty else { continue }
            messages.append(HistoryMessage(
                id: "\(url.path)#\(record.lineNumber)",
                role: role ?? "user",
                timeCreated: date,
                parts: parts
            ))
        }

        let fallbackDirectory = url.deletingLastPathComponent().lastPathComponent
        let session = HistoryProviderSupport.session(
            id: HistoryRecordID.file(source: .claude, path: url.path),
            sessionID: sessionID,
            title: HistoryProviderSupport.title(for: messages, fallback: "Claude Code session"),
            directory: directory.isEmpty ? fallbackDirectory : directory,
            agent: .claude,
            model: model,
            created: created,
            updated: updated,
            messages: messages
        )
        return HistoryProviderSupport.transcript(session: session, messages: messages)
    }
}

enum GeminiHistoryProvider {
    static func listSessions() -> [HistorySession] {
        files().compactMap { parse(at: $0)?.session }
    }

    static func transcript(at url: URL) -> HistoryTranscript? {
        parse(at: url)
    }

    private static func files() -> [URL] {
        let root = HistoryPath.geminiHome.appendingPathComponent("tmp")
        return HistoryFiles.files(in: root) { url in
            let name = url.lastPathComponent
            return (url.pathExtension == "jsonl" || url.pathExtension == "json")
                && name.hasPrefix("session-")
        }
    }

    private static func parse(at url: URL) -> HistoryTranscript? {
        let records = records(at: url)
        guard !records.isEmpty else { return nil }
        let fileDates = HistoryProviderSupport.dates(for: url)
        let metadata = records.first?.object ?? [:]
        var sessionID = HistoryJSON.string(metadata["sessionId"] ?? metadata["session_id"])
            ?? url.deletingPathExtension().lastPathComponent
        var directory = HistoryJSON.string(
            metadata["cwd"] ?? metadata["projectRoot"] ?? metadata["workingDirectory"] ?? metadata["directory"]
        )
        var model = HistoryJSON.string(metadata["model"] ?? metadata["modelName"])
        var created = HistoryJSON.firstDate(in: metadata, keys: ["startTime", "createdAt", "timestamp"])
            ?? fileDates.created
        var updated = HistoryJSON.firstDate(in: metadata, keys: ["lastUpdated", "updatedAt", "timestamp"])
            ?? fileDates.updated
        var messages: [HistoryMessage] = []

        for record in records.dropFirst() {
            let type = HistoryJSON.string(record.object["type"])?.lowercased()
            guard type == "user" || type == "gemini" else { continue }
            let date = HistoryProviderSupport.date(record, fallback: updated)
            created = min(created, date)
            updated = max(updated, date)
            let role = type == "gemini" ? "assistant" : "user"
            let parts = HistoryJSON.contentParts(
                record.object["content"] ?? record.object["parts"],
                idPrefix: "\(url.path)#\(record.lineNumber)"
            )
            guard !parts.isEmpty else { continue }
            messages.append(HistoryMessage(
                id: "\(url.path)#\(record.lineNumber)",
                role: role,
                timeCreated: date,
                parts: parts
            ))
            model = HistoryJSON.string(record.object["model"]) ?? model
        }

        if directory == nil {
            let projectHash = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            directory = "Gemini project \(projectHash)"
        }
        sessionID = sessionID.isEmpty ? url.deletingPathExtension().lastPathComponent : sessionID
        let session = HistoryProviderSupport.session(
            id: HistoryRecordID.file(source: .gemini, path: url.path),
            sessionID: sessionID,
            title: HistoryProviderSupport.title(for: messages, fallback: "Gemini CLI session"),
            directory: directory ?? HistoryPath.geminiHome.path,
            agent: .gemini,
            model: model,
            created: created,
            updated: updated,
            messages: messages
        )
        return HistoryProviderSupport.transcript(session: session, messages: messages)
    }

    private static func records(at url: URL) -> [HistoryJSONLRecord] {
        let records = HistoryFiles.jsonLines(at: url)
        if !records.isEmpty { return records }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var result = [HistoryJSONLRecord(lineNumber: 1, object: object)]
        for (index, message) in HistoryJSON.array(object["messages"]).enumerated() {
            if let message = message as? [String: Any] {
                result.append(HistoryJSONLRecord(lineNumber: index + 2, object: message))
            }
        }
        return result
    }
}

enum CursorHistoryProvider {
    static func listSessions() -> [HistorySession] {
        files().compactMap { parse(at: $0)?.session }
    }

    static func transcript(at url: URL) -> HistoryTranscript? {
        parse(at: url)
    }

    private static func files() -> [URL] {
        let root = HistoryPath.cursorHome.appendingPathComponent("projects")
        return HistoryFiles.files(in: root) { url in
            url.pathExtension == "jsonl" && url.pathComponents.contains("agent-transcripts")
        }
    }

    private static func parse(at url: URL) -> HistoryTranscript? {
        let records = HistoryFiles.jsonLines(at: url)
        guard !records.isEmpty else { return nil }
        let fileDates = HistoryProviderSupport.dates(for: url)
        var created = fileDates.created
        var updated = fileDates.updated
        var model: String?
        var messages: [HistoryMessage] = []
        for record in records {
            let date = HistoryProviderSupport.date(record, fallback: updated)
            created = min(created, date)
            updated = max(updated, date)
            let role = HistoryJSON.string(record.object["role"]) ?? "assistant"
            let message = HistoryJSON.object(record.object["message"])
            let content = message?["content"] ?? record.object["content"]
            let parts = HistoryJSON.contentParts(
                content,
                idPrefix: "\(url.path)#\(record.lineNumber)"
            )
            guard !parts.isEmpty else { continue }
            model = HistoryJSON.string(message?["model"] ?? record.object["model"]) ?? model
            messages.append(HistoryMessage(
                id: "\(url.path)#\(record.lineNumber)",
                role: role == "user" || role == "tool" ? role : "assistant",
                timeCreated: date,
                parts: parts
            ))
        }

        let encodedProject = projectComponent(for: url)
        let directory = decodeProjectDirectory(encodedProject)
        let sessionID = sessionComponent(for: url) ?? url.deletingPathExtension().lastPathComponent
        let parentID = url.pathComponents.contains("subagents") ? url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent : nil
        let session = HistoryProviderSupport.session(
            id: HistoryRecordID.file(source: .cursor, path: url.path),
            sessionID: sessionID,
            title: HistoryProviderSupport.title(for: messages, fallback: "Cursor Agent session"),
            directory: directory,
            agent: .cursor,
            model: model,
            parentID: parentID,
            created: created,
            updated: updated,
            messages: messages
        )
        _ = sessionID // The file path remains the stable source of truth.
        return HistoryProviderSupport.transcript(session: session, messages: messages)
    }

    private static func projectComponent(for url: URL) -> String {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "projects"), index + 1 < components.count else {
            return "Cursor project"
        }
        return components[index + 1]
    }

    private static func sessionComponent(for url: URL) -> String? {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "agent-transcripts"), index + 1 < components.count else {
            return nil
        }
        return components[index + 1]
    }

    private static func decodeProjectDirectory(_ encoded: String) -> String {
        let guess = "/" + encoded.replacingOccurrences(of: "-", with: "/")
        if FileManager.default.fileExists(atPath: guess) { return guess }
        return HistoryPath.cursorHome.appendingPathComponent("projects/(encoded)").path
    }
}

enum CopilotHistoryProvider {
    static func listSessions() -> [HistorySession] {
        files().compactMap { parse(at: $0)?.session }
    }

    static func transcript(at url: URL) -> HistoryTranscript? {
        parse(at: url)
    }

    private static func files() -> [URL] {
        let root = HistoryPath.copilotHome.appendingPathComponent("session-state")
        return HistoryFiles.files(in: root) { $0.lastPathComponent == "events.jsonl" }
    }

    private static func parse(at url: URL) -> HistoryTranscript? {
        let records = HistoryFiles.jsonLines(at: url)
        guard !records.isEmpty else { return nil }
        let fileDates = HistoryProviderSupport.dates(for: url)
        var sessionID = url.deletingLastPathComponent().lastPathComponent
        var directory = ""
        var model: String?
        var created = fileDates.created
        var updated = fileDates.updated
        var messages: [HistoryMessage] = []

        for record in records {
            let date = HistoryProviderSupport.date(record, fallback: updated)
            created = min(created, date)
            updated = max(updated, date)
            let type = HistoryJSON.string(record.object["type"])?.lowercased() ?? ""
            let data = HistoryJSON.object(record.object["data"]) ?? [:]

            if type == "session.start" {
                sessionID = HistoryJSON.string(data["sessionId"] ?? data["session_id"]) ?? sessionID
                let context = HistoryJSON.object(data["context"])
                directory = HistoryJSON.string(context?["cwd"] ?? data["cwd"] ?? data["workingDirectory"]) ?? directory
                model = HistoryJSON.string(data["model"] ?? context?["model"]) ?? model
                created = HistoryJSON.firstDate(in: data, keys: ["startTime", "createdAt"]) ?? created
                continue
            }

            let role: String
            let content: Any?
            switch type {
            case "user.message":
                role = "user"
                content = data["content"] ?? data["message"]
            case "assistant.message":
                role = "assistant"
                content = data["content"] ?? data["message"]
                model = HistoryJSON.string(data["model"]) ?? model
            case "system.message":
                role = "system"
                content = data["content"] ?? data["message"]
            case "tool.execution_start":
                let part = HistoryPart(
                    id: "\(url.path)#\(record.lineNumber)",
                    kind: .tool,
                    toolName: HistoryJSON.string(data["toolName"] ?? data["name"] ?? data["command"]),
                    toolStatus: "running",
                    toolInput: HistoryJSON.stringify(data["input"] ?? data["arguments"])
                )
                messages.append(HistoryMessage(
                    id: "\(url.path)#\(record.lineNumber)",
                    role: "assistant",
                    timeCreated: date,
                    parts: [part]
                ))
                continue
            case "tool.execution_complete":
                let part = HistoryPart(
                    id: "\(url.path)#\(record.lineNumber)",
                    kind: .tool,
                    toolName: HistoryJSON.string(data["toolName"] ?? data["name"]),
                    toolStatus: (data["success"] as? Bool) == false ? "error" : "completed",
                    toolOutput: HistoryJSON.stringify(data["output"] ?? data["result"] ?? data["content"])
                )
                messages.append(HistoryMessage(
                    id: "\(url.path)#\(record.lineNumber)",
                    role: "tool",
                    timeCreated: date,
                    parts: [part]
                ))
                continue
            default:
                continue
            }

            let parts = HistoryJSON.contentParts(
                content,
                idPrefix: "\(url.path)#\(record.lineNumber)"
            )
            guard !parts.isEmpty else { continue }
            messages.append(HistoryMessage(
                id: "\(url.path)#\(record.lineNumber)",
                role: role,
                timeCreated: date,
                parts: parts
            ))
        }

        let session = HistoryProviderSupport.session(
            id: HistoryRecordID.file(source: .copilot, path: url.path),
            sessionID: sessionID,
            title: HistoryProviderSupport.title(for: messages, fallback: "GitHub Copilot session"),
            directory: directory.isEmpty ? HistoryPath.copilotHome.path : directory,
            agent: .copilot,
            model: model,
            created: created,
            updated: updated,
            messages: messages
        )
        return HistoryProviderSupport.transcript(session: session, messages: messages)
    }
}

enum GrokHistoryProvider {
    static func listSessions() -> [HistorySession] {
        files().compactMap { parse(at: $0)?.session }
    }

    static func transcript(at url: URL) -> HistoryTranscript? {
        parse(at: url)
    }

    private static func files() -> [URL] {
        let root = HistoryPath.grokHome.appendingPathComponent("sessions")
        return HistoryFiles.files(in: root) { $0.lastPathComponent == "updates.jsonl" }
    }

    private static func parse(at url: URL) -> HistoryTranscript? {
        let records = HistoryFiles.jsonLines(at: url)
        guard !records.isEmpty else { return nil }
        let summary = summaryObject(for: url)
        let info = HistoryJSON.object(summary["info"])
        let fileDates = HistoryProviderSupport.dates(for: url)

        let directory = HistoryJSON.string(
            info?["cwd"] ?? summary["cwd"] ?? summary["working_directory"] ?? summary["workingDirectory"]
        ) ?? fallbackDirectory(for: url)
        let sessionID = HistoryJSON.string(
            info?["id"] ?? info?["session_id"] ?? summary["session_id"] ?? summary["sessionId"] ?? summary["id"]
        ) ?? url.deletingLastPathComponent().lastPathComponent
        let model = HistoryJSON.string(
            summary["current_model_id"] ?? summary["model"] ?? summary["model_id"]
        )
        let title = HistoryJSON.string(
            summary["generated_title"] ?? summary["session_summary"] ?? summary["title"] ?? summary["summary"]
        )
        var created = HistoryJSON.firstDate(
            in: summary,
            keys: ["created_at", "createdAt", "start_time", "startTime"]
        ) ?? fileDates.created
        var updated = HistoryJSON.firstDate(
            in: summary,
            keys: ["updated_at", "updatedAt", "last_updated", "lastUpdated"]
        ) ?? fileDates.updated
        let parentID = HistoryJSON.string(
            summary["parent_session_id"] ?? summary["parentSessionId"]
        )
        var messages: [HistoryMessage] = []

        for record in records {
            let date = HistoryProviderSupport.date(record, fallback: updated)
            created = min(created, date)
            updated = max(updated, date)
            let kind = eventKind(record.object).lowercased()
            let role: String
            if kind.contains("user") {
                role = "user"
            } else if kind.contains("assistant") || kind.contains("agent") {
                role = "assistant"
            } else if kind.contains("tool") {
                role = "tool"
            } else {
                continue
            }

            guard let value = firstValue(
                for: ["text", "content", "message", "output", "result"],
                in: record.object
            ) else { continue }
            let id = "\(url.path)#\(record.lineNumber)"
            var parts = HistoryJSON.contentParts(value, idPrefix: id)
            if role == "tool", parts.allSatisfy({ $0.kind == .text }) {
                parts = [HistoryPart(
                    id: id,
                    kind: .tool,
                    toolName: "tool",
                    toolStatus: "completed",
                    toolOutput: HistoryJSON.text(value)
                )]
            }
            guard !parts.isEmpty else { continue }
            messages.append(HistoryMessage(
                id: id,
                role: role,
                timeCreated: date,
                parts: parts
            ))
        }

        let session = HistoryProviderSupport.session(
            id: HistoryRecordID.file(source: .grok, path: url.path),
            sessionID: sessionID,
            title: title ?? HistoryProviderSupport.title(for: messages, fallback: "Grok session"),
            directory: directory,
            agent: .grok,
            model: model,
            parentID: parentID,
            created: created,
            updated: updated,
            messages: messages
        )
        return HistoryProviderSupport.transcript(session: session, messages: messages)
    }

    private static func summaryObject(for updatesURL: URL) -> [String: Any] {
        let summaryURL = updatesURL.deletingLastPathComponent().appendingPathComponent("summary.json")
        guard let data = try? Data(contentsOf: summaryURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private static func fallbackDirectory(for url: URL) -> String {
        let components = url.pathComponents
        guard let sessionsIndex = components.firstIndex(of: "sessions"),
              sessionsIndex + 1 < components.count
        else { return HistoryPath.grokHome.path }
        let encoded = components[sessionsIndex + 1]
        return encoded.removingPercentEncoding ?? encoded
    }

    private static func eventKind(_ value: Any, depth: Int = 0) -> String {
        guard depth < 5 else { return "" }
        guard let object = value as? [String: Any] else { return "" }
        var values: [String] = []
        for key in ["type", "method", "event", "kind", "sessionUpdate", "role"] {
            if let value = HistoryJSON.string(object[key]) {
                values.append(value)
            }
        }
        for value in object.values {
            values.append(eventKind(value, depth: depth + 1))
        }
        return values.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func firstValue(for keys: [String], in value: Any, depth: Int = 0) -> Any? {
        guard depth < 6 else { return nil }
        guard let object = value as? [String: Any] else { return nil }
        for key in keys {
            if let candidate = object[key] {
                return candidate
            }
        }
        for child in object.values {
            if let candidate = firstValue(for: keys, in: child, depth: depth + 1) {
                return candidate
            }
        }
        return nil
    }
}
