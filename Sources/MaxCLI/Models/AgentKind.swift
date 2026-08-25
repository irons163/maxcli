import AppKit
import Foundation

enum AgentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case gemini
    case cursor
    case copilot
    case opencode
    case grok
    case shell
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .gemini: "Gemini CLI"
        case .cursor: "Cursor Agent"
        case .copilot: "GitHub Copilot"
        case .opencode: "OpenCode"
        case .grok: "Grok"
        case .shell: "Shell"
        case .custom: "Custom"
        }
    }

    var executable: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        case .gemini: "gemini"
        case .cursor: "agent"
        case .copilot: "copilot"
        case .opencode: "opencode"
        case .grok: "grok"
        case .shell: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        case .custom: ""
        }
    }

    var symbolName: String {
        switch self {
        case .codex: "sparkles"
        case .claude: "brain.head.profile"
        case .gemini: "diamond"
        case .cursor: "cursorarrow.rays"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .opencode: "terminal"
        case .grok: "sparkle"
        case .shell: "apple.terminal"
        case .custom: "slider.horizontal.3"
        }
    }

    var color: NSColor {
        switch self {
        case .codex: .systemGreen
        case .claude: .systemOrange
        case .gemini: .systemBlue
        case .cursor: .systemPurple
        case .copilot: .systemIndigo
        case .opencode: .systemTeal
        case .grok: .systemPink
        case .shell: .secondaryLabelColor
        case .custom: .systemGray
        }
    }

    var installHint: String {
        switch self {
        case .codex: "npm install -g @openai/codex"
        case .claude: "npm install -g @anthropic-ai/claude-code"
        case .gemini: "npm install -g @google/gemini-cli"
        case .cursor: "Install Cursor CLI"
        case .copilot: "Install GitHub Copilot CLI"
        case .opencode: "brew install anomalyco/tap/opencode"
        case .grok: "npm install -g @grok-ai/grok-cli"
        case .shell, .custom: ""
        }
    }

    var supportsHistoryBinding: Bool {
        switch self {
        case .codex, .claude, .gemini, .cursor, .copilot, .opencode, .grok:
            true
        case .shell, .custom:
            false
        }
    }
}
