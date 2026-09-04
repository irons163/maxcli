import SwiftUI

/// Compact editor for an existing session's appearance: title, icon, color.
struct EditSessionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let sessionID: UUID

    @State private var title = ""
    @State private var iconName: String?
    @State private var iconColorName: String?
    @State private var arguments = ""
    @State private var customCommand = ""
    @State private var loaded = false

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 8)]
    private static let iconChoices = [
        "sparkles", "brain.head.profile", "diamond", "cursorarrow.rays",
        "chevron.left.forwardslash.chevron.right", "terminal", "sparkle",
        "apple.terminal", "slider.horizontal.3", "wand.and.stars",
        "bolt.fill", "star.fill", "flame.fill", "leaf.fill",
        "gearshape.2.fill", "hammer.fill", "camera.fill", "gamecontroller.fill",
    ]

    private var session: WorkspaceSession? {
        model.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.tr("edit.title"))
                        .font(.title2.weight(.semibold))
                    Text(session?.title ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(model.tr("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            TextField(model.tr("field.sessionName"), text: $title)

            if let agent = session?.agent {
                if agent == .custom {
                    TextField(model.tr("field.command"), text: $customCommand, prompt: Text(model.tr("field.commandExample")))
                        .font(.system(.body, design: .monospaced))
                } else if agent != .shell {
                    TextField(model.tr("field.arguments"), text: $arguments)
                        .font(.system(.body, design: .monospaced))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(model.tr("sheet.icon")).font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    iconButton(nil, symbol: session?.agent.symbolName ?? "terminal", tint: session?.agent.color, help: model.tr("help.agentDefault"))
                    ForEach(Self.iconChoices, id: \.self) { symbol in
                        iconButton(symbol, symbol: symbol, tint: nil, help: symbol)
                    }
                }
                HStack(spacing: 8) {
                    colorButton(nil, color: session?.agent.color ?? .gray, help: model.tr("help.agentDefault"))
                    ForEach(WorkspaceSession.iconColorChoices, id: \.name) { choice in
                        colorButton(choice.name, color: choice.color, help: choice.name)
                    }
                }
            }

            HStack {
                Spacer()
                Button(model.tr("common.save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(session == nil)
            }
        }
        .padding(22)
        .frame(width: 590)
        .onAppear {
            guard !loaded, let session else { return }
            title = session.title
            iconName = session.iconName
            iconColorName = session.iconColorName
            arguments = session.arguments
            customCommand = session.customCommand
            loaded = true
        }
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

    private func save() {
        model.updateSessionAppearance(
            sessionID,
            title: title,
            iconName: iconName,
            iconColorName: iconColorName
        )
        if let agent = session?.agent, agent != .shell {
            model.updateSessionLaunch(
                sessionID,
                arguments: arguments,
                customCommand: customCommand
            )
        }
        dismiss()
    }
}
