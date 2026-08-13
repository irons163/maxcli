import Foundation

enum SessionActivity: String, Codable, Sendable {
    case launching
    case running
    case attention
    case stopped
    case failed

    var label: String {
        switch self {
        case .launching: "Launching"
        case .running: "Running"
        case .attention: "Needs attention"
        case .stopped: "Stopped"
        case .failed: "Failed"
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
    var iconName: String?
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
        iconName: String? = nil,
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
        self.iconName = iconName
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
