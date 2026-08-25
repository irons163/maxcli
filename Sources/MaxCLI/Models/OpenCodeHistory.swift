import Foundation

struct HistorySession: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let directory: String
    let agent: String?
    let model: String?
    let parentID: String?
    let timeCreated: Date
    let timeUpdated: Date
    let messageCount: Int
    let source: AgentKind

    init(
        id: String,
        title: String,
        directory: String,
        agent: String?,
        model: String?,
        parentID: String?,
        timeCreated: Date,
        timeUpdated: Date,
        messageCount: Int,
        source: AgentKind = .opencode
    ) {
        self.id = id
        self.title = title
        self.directory = directory
        self.agent = agent
        self.model = model
        self.parentID = parentID
        self.timeCreated = timeCreated
        self.timeUpdated = timeUpdated
        self.messageCount = messageCount
        self.source = source
    }

    var isSubagent: Bool { parentID != nil }
}

/// Compatibility aliases for the OpenCode-specific sidebar integration.
/// New history sources use the provider-neutral types above.
typealias OpenCodeHistorySession = HistorySession

/// The provider/model selection stored as JSON in opencode's `session.model`
/// column, e.g. `{"id":"claude-sonnet-4-5","providerID":"anthropic"}`.
struct OpenCodeModelInfo: Hashable, Sendable {
    let providerID: String?
    let modelID: String?
    let variant: String?

    static func parse(_ json: String?) -> OpenCodeModelInfo? {
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return OpenCodeModelInfo(
            providerID: object["providerID"] as? String,
            modelID: object["id"] as? String,
            variant: object["variant"] as? String
        )
    }
}

struct HistoryPart: Identifiable, Sendable {
    let id: String
    let kind: HistoryPartKind
    let text: String?
    let toolName: String?
    let toolStatus: String?
    let toolInput: String?
    let toolOutput: String?
    let filename: String?
    let fileURL: String?
    let patchFiles: [String]
    let synthetic: Bool
    let ignored: Bool

    init(
        id: String,
        kind: HistoryPartKind,
        text: String? = nil,
        toolName: String? = nil,
        toolStatus: String? = nil,
        toolInput: String? = nil,
        toolOutput: String? = nil,
        filename: String? = nil,
        fileURL: String? = nil,
        patchFiles: [String] = [],
        synthetic: Bool = false,
        ignored: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.toolName = toolName
        self.toolStatus = toolStatus
        self.toolInput = toolInput
        self.toolOutput = toolOutput
        self.filename = filename
        self.fileURL = fileURL
        self.patchFiles = patchFiles
        self.synthetic = synthetic
        self.ignored = ignored
    }

    var isDisplayable: Bool {
        !synthetic && !ignored
    }
}

typealias OpenCodePart = HistoryPart

enum HistoryPartKind: String, Sendable, Equatable {
    case text
    case reasoning
    case tool
    case file
    case patch
    case stepStart = "step-start"
    case stepFinish = "step-finish"
    case compaction
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "text": self = .text
        case "reasoning": self = .reasoning
        case "tool": self = .tool
        case "file": self = .file
        case "patch": self = .patch
        case "step-start": self = .stepStart
        case "step-finish": self = .stepFinish
        case "compaction": self = .compaction
        default: self = .unknown
        }
    }
}

typealias OpenCodePartKind = HistoryPartKind

struct HistoryMessage: Identifiable, Sendable {
    let id: String
    let role: String
    let timeCreated: Date
    let parts: [HistoryPart]
}

typealias OpenCodeMessage = HistoryMessage

struct HistoryTranscript: Sendable {
    let session: HistorySession
    let messages: [HistoryMessage]
}

typealias OpenCodeTranscript = HistoryTranscript
