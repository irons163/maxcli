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
    @State private var pinSession = false
    @State private var titleWasEdited = false

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 8)]

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
            isPinned: pinSession
        )
        model.addSession(session)
        dismiss()
    }
}
