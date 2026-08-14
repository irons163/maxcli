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
    var opencodeSessionID: String?
    var iconName: String?
    var iconColorName: String?
    var isPinned: Bool
    var createdAt: Date
    var lastActivatedAt: Date
    var lastActivityAt: Date?
    var activity: SessionActivity

    init(
        id: UUID = UUID(),
        title: String,
        agent: AgentKind,
        workingDirectory: String,
        arguments: String = "",
        customCommand: String = "",
        opencodeSessionID: String? = nil,
        iconName: String? = nil,
        iconColorName: String? = nil,
        isPinned: Bool = false,
        createdAt: Date = .now,
        lastActivatedAt: Date = .now,
        lastActivityAt: Date? = nil,
        activity: SessionActivity = .launching
    ) {
        self.id = id
        self.title = title
        self.agent = agent
        self.workingDirectory = workingDirectory
        self.arguments = arguments
        self.customCommand = customCommand
        self.opencodeSessionID = opencodeSessionID
        self.iconName = iconName
        self.iconColorName = iconColorName
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.lastActivatedAt = lastActivatedAt
        self.lastActivityAt = lastActivityAt
        self.activity = activity
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
