import AppKit
import Foundation

enum AgentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case gemini
    case cursor
    case copilot
    case opencode
    case aider
    case goose
    case amp
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
        case .aider: "Aider"
        case .goose: "Goose"
        case .amp: "Amp"
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
        case .aider: "aider"
        case .goose: "goose"
        case .amp: "amp"
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
        case .aider: "wand.and.stars"
        case .goose: "bird"
        case .amp: "bolt.fill"
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
        case .aider: .systemPink
        case .goose: .systemYellow
        case .amp: .systemRed
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
        case .aider: "pipx install aider-chat"
        case .goose: "brew install block-goose-cli"
        case .amp: "Install Amp CLI"
        case .shell, .custom: ""
        }
    }
}
