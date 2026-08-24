import Foundation

struct OpenCodeHistorySession: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let directory: String
    let agent: String?
    let model: String?
    let parentID: String?
    let timeCreated: Date
    let timeUpdated: Date
    let messageCount: Int

    var isSubagent: Bool { parentID != nil }
}

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

struct OpenCodePart: Identifiable, Sendable {
    let id: String
    let kind: OpenCodePartKind
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
        kind: OpenCodePartKind,
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

enum OpenCodePartKind: String, Sendable {
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

struct OpenCodeMessage: Identifiable, Sendable {
    let id: String
    let role: String
    let timeCreated: Date
    let parts: [OpenCodePart]
}

struct OpenCodeTranscript: Sendable {
    let session: OpenCodeHistorySession
    let messages: [OpenCodeMessage]
}
