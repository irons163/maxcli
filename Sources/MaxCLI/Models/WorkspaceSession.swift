import AppKit
import Foundation

enum SessionActivity: String, Codable, Sendable {
    case launching
    case running
    case attention
    case stopped
    case failed

    var labelKey: String {
        switch self {
        case .launching: "activity.launching"
        case .running: "activity.running"
        case .attention: "activity.attention"
        case .stopped: "activity.stopped"
        case .failed: "activity.failed"
        }
    }
}

struct WorkspaceSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var agent: AgentKind
    var workingDirectory: String
    var arguments: String
    var customCommand: String
    /// Native conversation/session ID used by the agent CLI to resume history.
    var boundSessionID: String?
    /// Kept for decoding older MaxCLI session files.
    var opencodeSessionID: String?
    var iconName: String?
    var iconColorName: String?
    var isPinned: Bool
    var manualOrder: Int?
    var groupName: String?
    var createdAt: Date
    var lastActivatedAt: Date
    var lastActivityAt: Date?
    var activity: SessionActivity
    var isTransient: Bool

    init(
        id: UUID = UUID(),
        title: String,
        agent: AgentKind,
        workingDirectory: String,
        arguments: String = "",
        customCommand: String = "",
        boundSessionID: String? = nil,
        opencodeSessionID: String? = nil,
        iconName: String? = nil,
        iconColorName: String? = nil,
        isPinned: Bool = false,
        manualOrder: Int? = nil,
        groupName: String? = nil,
        createdAt: Date = .now,
        lastActivatedAt: Date = .now,
        lastActivityAt: Date? = nil,
        activity: SessionActivity = .launching,
        isTransient: Bool = false
    ) {
        self.id = id
        self.title = title
        self.agent = agent
        self.workingDirectory = workingDirectory
        self.arguments = arguments
        self.customCommand = customCommand
        self.boundSessionID = boundSessionID ?? opencodeSessionID
        self.opencodeSessionID = opencodeSessionID ?? (agent == .opencode ? boundSessionID : nil)
        self.iconName = iconName
        self.iconColorName = iconColorName
        self.isPinned = isPinned
        self.manualOrder = manualOrder
        self.groupName = groupName
        self.createdAt = createdAt
        self.lastActivatedAt = lastActivatedAt
        self.lastActivityAt = lastActivityAt
        self.activity = activity
        self.isTransient = isTransient
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, agent, workingDirectory, arguments, customCommand
        case boundSessionID, opencodeSessionID, iconName, iconColorName, isPinned, manualOrder
        case groupName, createdAt, lastActivatedAt, lastActivityAt, activity, isTransient
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        agent = try c.decode(AgentKind.self, forKey: .agent)
        workingDirectory = try c.decode(String.self, forKey: .workingDirectory)
        arguments = try c.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        customCommand = try c.decodeIfPresent(String.self, forKey: .customCommand) ?? ""
        let legacyOpenCodeID = try c.decodeIfPresent(String.self, forKey: .opencodeSessionID)
        boundSessionID = try c.decodeIfPresent(String.self, forKey: .boundSessionID) ?? legacyOpenCodeID
        opencodeSessionID = legacyOpenCodeID ?? (agent == .opencode ? boundSessionID : nil)
        iconName = try c.decodeIfPresent(String.self, forKey: .iconName)
        iconColorName = try c.decodeIfPresent(String.self, forKey: .iconColorName)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        manualOrder = try c.decodeIfPresent(Int.self, forKey: .manualOrder)
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        lastActivatedAt = try c.decodeIfPresent(Date.self, forKey: .lastActivatedAt) ?? .now
        lastActivityAt = try c.decodeIfPresent(Date.self, forKey: .lastActivityAt)
        activity = try c.decodeIfPresent(SessionActivity.self, forKey: .activity) ?? .stopped
        isTransient = try c.decodeIfPresent(Bool.self, forKey: .isTransient) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(agent, forKey: .agent)
        try c.encode(workingDirectory, forKey: .workingDirectory)
        try c.encode(arguments, forKey: .arguments)
        try c.encode(customCommand, forKey: .customCommand)
        try c.encodeIfPresent(boundSessionID, forKey: .boundSessionID)
        try c.encodeIfPresent(opencodeSessionID, forKey: .opencodeSessionID)
        try c.encodeIfPresent(iconName, forKey: .iconName)
        try c.encodeIfPresent(iconColorName, forKey: .iconColorName)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encodeIfPresent(manualOrder, forKey: .manualOrder)
        try c.encodeIfPresent(groupName, forKey: .groupName)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(lastActivatedAt, forKey: .lastActivatedAt)
        try c.encodeIfPresent(lastActivityAt, forKey: .lastActivityAt)
        try c.encode(activity, forKey: .activity)
        try c.encode(isTransient, forKey: .isTransient)
    }

    var directoryName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    var symbolName: String {
        iconName ?? agent.symbolName
    }

    var iconColor: NSColor {
        guard let iconColorName else { return agent.color }
        return Self.iconColorChoices.first { $0.name == iconColorName }?.color ?? agent.color
    }

    static var iconColorChoices: [(name: String, color: NSColor)] {
        [
            ("red", .systemRed),
            ("orange", .systemOrange),
            ("yellow", .systemYellow),
            ("green", .systemGreen),
            ("blue", .systemBlue),
            ("purple", .systemPurple),
            ("pink", .systemPink),
            ("teal", .systemTeal),
            ("indigo", .systemIndigo),
            ("gray", .systemGray),
        ]
    }

    var launchCommand: String {
        let base = agent == .custom ? customCommand : agent.executable
        return arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? base
            : "\(base) \(arguments)"
    }

    var searchableText: String {
        "\(title) \(agent.displayName) \(workingDirectory) \(launchCommand)".lowercased()
    }
}
