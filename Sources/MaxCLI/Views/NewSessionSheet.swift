import AppKit
import SwiftUI

struct NewSessionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var agent: AgentKind = .codex
    @State private var title = ""
    @State private var workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var arguments = ""
    @State private var customCommand = ""
    @State private var iconName: String?
    @State private var iconColorName: String?
    @State private var pinSession = false
    @State private var titleWasEdited = false

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 8)]
    private static let iconChoices = [
        "sparkles", "brain.head.profile", "diamond", "cursorarrow.rays",
        "chevron.left.forwardslash.chevron.right", "terminal", "sparkle",
        "apple.terminal", "slider.horizontal.3", "wand.and.stars",
        "bolt.fill", "star.fill", "flame.fill", "leaf.fill",
        "gearshape.2.fill", "hammer.fill", "camera.fill", "gamecontroller.fill",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("New Session")
                        .font(.title2.weight(.semibold))
                    Text("Launch an independent AI CLI in its own workspace.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Agent").font(.headline)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(AgentKind.allCases) { item in
                        agentButton(item)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    iconButton(nil, symbol: agent.symbolName, tint: agent.color, help: "Agent default")
                    ForEach(Self.iconChoices, id: \.self) { symbol in
                        iconButton(symbol, symbol: symbol, tint: nil, help: symbol)
                    }
                }
                HStack(spacing: 8) {
                    colorButton(nil, color: agent.color, help: "Agent default")
                    ForEach(WorkspaceSession.iconColorChoices, id: \.name) { choice in
                        colorButton(choice.name, color: choice.color, help: choice.name)
                    }
                }
            }

            Form {
                TextField("Session name", text: $title)
                    .onChange(of: title) { titleWasEdited = true }

                HStack {
                    TextField("Working directory", text: $workingDirectory)
                        .font(.system(.body, design: .monospaced))
                    Button("Choose…") { chooseDirectory() }
                }

                if agent == .custom {
                    TextField("Command", text: $customCommand, prompt: Text("e.g. my-agent --interactive"))
                        .font(.system(.body, design: .monospaced))
                } else if agent != .shell {
                    TextField("Arguments (optional)", text: $arguments)
                        .font(.system(.body, design: .monospaced))
                }

                Toggle("Pin in sidebar", isOn: $pinSession)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if !model.installedAgents.contains(agent), agent != .custom {
                Label("\(agent.displayName) was not found in the app PATH. MaxCLI will still try your login shell.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("⌘1…⌘9 switches sessions instantly")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Create Session") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(22)
        .frame(width: 590)
        .onAppear { updateSuggestedTitle() }
        .onChange(of: agent) { updateSuggestedTitle() }
    }

    private func agentButton(_ item: AgentKind) -> some View {
        let isSelected = agent == item
        let isInstalled = model.installedAgents.contains(item) || item == .custom
        return Button {
            titleWasEdited = false
            agent = item
        } label: {
            HStack(spacing: 7) {
                Image(systemName: item.symbolName)
                    .foregroundStyle(Color(nsColor: item.color))
                Text(item.displayName)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(isInstalled ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isSelected ? Color.accentColor.opacity(0.17) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor.opacity(0.8) : .clear))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ value: String?, symbol: String, tint: NSColor?, help: String) -> some View {
        let isSelected = iconName == value
        return Button {
            iconName = value
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint.map { Color(nsColor: $0) } ?? Color.accentColor)
                .frame(width: 44, height: 36)
                .background(isSelected ? Color.accentColor.opacity(0.17) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor.opacity(0.8) : .clear))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func colorButton(_ value: String?, color: NSColor, help: String) -> some View {
        let isSelected = iconColorName == value
        return Button {
            iconColorName = value
        } label: {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: isSelected ? 2 : 0))
                .frame(width: 30, height: 28)
                .background(isSelected ? Color(nsColor: color).opacity(0.25) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && FileManager.default.fileExists(atPath: workingDirectory)
            && (agent != .custom || !customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func updateSuggestedTitle() {
        guard !titleWasEdited else { return }
        let directory = URL(fileURLWithPath: workingDirectory).lastPathComponent
        title = directory.isEmpty ? agent.displayName : "\(directory) · \(agent.displayName)"
        titleWasEdited = false
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
            titleWasEdited = false
            updateSuggestedTitle()
        }
    }

    private func create() {
        let session = WorkspaceSession(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            agent: agent,
            workingDirectory: workingDirectory,
            arguments: arguments,
            customCommand: customCommand,
            iconName: iconName,
            iconColorName: iconColorName,
            isPinned: pinSession
        )
        model.addSession(session)
        dismiss()
    }
}
