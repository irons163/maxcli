import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    let onRequestClose: (WorkspaceSession) -> Void
    @State private var draggingSessionID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            overview
            searchAndFilter
            sessionList
            footer
        }
        .background(.ultraThinMaterial)
        .navigationSplitViewColumnWidth(min: 240, ideal: 278, max: 340)
    }

    private var overview: some View {
        HStack(spacing: 8) {
            metric(value: model.runningCount, label: model.tr("metric.running"), color: .green)
            metric(value: model.attentionCount, label: model.tr("metric.attention"), color: .orange)
            metric(value: model.sessions.count, label: model.tr("metric.total"), color: .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func metric(value: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    private var searchAndFilter: some View {
        HStack(spacing: 6) {
            TextField(model.tr("search.placeholder"), text: $model.searchText)
                .textFieldStyle(.roundedBorder)

            Menu {
                Button(model.tr("filter.allAgents")) { model.agentFilter = nil }
                Divider()
                ForEach(AgentKind.allCases.filter { $0 != .custom }) { agent in
                    Button {
                        model.agentFilter = agent
                    } label: {
                        Label(agent.displayName, systemImage: agent.symbolName)
                    }
                }
            } label: {
                Image(systemName: model.agentFilter?.symbolName ?? "line.3.horizontal.decrease.circle")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .help("Filter by agent")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(Array(model.visibleSessions.enumerated()), id: \.element.id) { index, session in
                    SessionRow(
                        session: session,
                        isSelected: model.selectedSessionID == session.id,
                        shortcutIndex: index < 9 ? index + 1 : nil
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { model.select(session.id) }
                    .onDrag {
                        draggingSessionID = session.id
                        return NSItemProvider(object: session.id.uuidString as NSString)
                    } preview: {
                        SessionDragPreview(session: session)
                    }
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: SessionReorderDelegate(
                            target: session.id,
                            draggedID: $draggingSessionID,
                            model: model
                        )
                    )
                    .contextMenu {
                        Button(session.isPinned ? model.tr("context.unpin") : model.tr("context.pin")) {
                            model.togglePin(session.id)
                        }
                        Button(model.tr("context.duplicate")) {
                            model.select(session.id)
                            model.duplicateSelected()
                        }
                        if model.runtime(for: session.id)?.isRunning == true {
                            Button(model.tr("context.stop")) { model.stop(session.id) }
                        } else {
                            Button(model.tr("context.start")) { model.start(session.id) }
                        }
                        Button(model.tr("context.restart")) { model.restart(session.id) }
                        if session.agent.supportsHistoryBinding {
                            let availableSessions = model.recentSessionsByDirectory[session.workingDirectory, default: []]
                                .filter { $0.source == session.agent && !$0.isSubagent }
                            Menu(model.trf("context.bindSession", session.agent.displayName)) {
                                if availableSessions.isEmpty {
                                    Text(model.trf("context.noHistorySessions", session.agent.displayName))
                                }
                                ForEach(availableSessions) { entry in
                                    Button {
                                        model.bindSession(session.id, to: entry)
                                    } label: {
                                        Label(
                                            entry.title,
                                            systemImage: session.boundSessionID == entry.sessionID
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )
                                    }
                                }
                                if session.boundSessionID != nil {
                                    Divider()
                                    Button(model.tr("context.unbind")) {
                                        model.bindSession(session.id, to: nil)
                                    }
                                }
                                if model.runtime(for: session.id)?.isRunning == true {
                                    Divider()
                                    Text(model.tr("context.bindNeedsRestart"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Divider()
                        Button(model.tr("context.copyLaunchCommand")) { model.copyLaunchCommand(session.id) }
                        Button(model.tr("context.revealInFinder")) { model.revealInFinder(session.id) }
                        Divider()
                        Button(model.tr("context.close"), role: .destructive) { onRequestClose(session) }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .overlay {
            if model.visibleSessions.isEmpty, !model.sessions.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.isShowingNewSession = true
            } label: {
                Label(model.tr("sidebar.newSession"), systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Spacer()

            Menu {
                Button(model.tr("sidebar.startAllStopped")) { model.restartStopped() }
                    .disabled(model.sessions.allSatisfy { model.runtime(for: $0.id)?.isRunning == true })
                Button(model.tr("sidebar.stopAll"), role: .destructive) { model.stopAll() }
                    .disabled(model.runningCount == 0)
                Divider()
                Menu {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            model.language = language
                        } label: {
                            Label(
                                languageLabel(language),
                                systemImage: model.language == language ? "checkmark" : ""
                            )
                        }
                    }
                } label: {
                    Label(model.tr("menu.language"), systemImage: "globe")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help(model.tr("sidebar.sessionActions"))
        }
        .padding(12)
        .background(.bar)
    }

    private func languageLabel(_ language: AppLanguage) -> String {
        language == .system ? model.tr("language.system") : language.displayName
    }
}

/// Reorders sessions live while the drag hovers over a row or grid cell, so
/// neighbours animate apart instead of snapping only when the mouse is released.
struct SessionReorderDelegate: DropDelegate {
    let target: UUID
    @Binding var draggedID: UUID?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedID, dragged != target else { return }
        let sessions = model.visibleSessions
        guard let from = sessions.firstIndex(where: { $0.id == dragged }),
              let to = sessions.firstIndex(where: { $0.id == target })
        else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            model.moveSession(dragged, relativeTo: target, after: from < to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

struct SessionDragPreview: View {
    let session: WorkspaceSession

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.symbolName)
                .foregroundStyle(Color(nsColor: session.iconColor))
                .frame(width: 22, height: 22)
                .background(
                    Color(nsColor: session.iconColor).opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 5)
                )
            Text(session.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

private struct SessionRow: View {
    let session: WorkspaceSession
    let isSelected: Bool
    let shortcutIndex: Int?
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: session.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(nsColor: session.iconColor))
                    .frame(width: 30, height: 30)
                    .background(Color(nsColor: session.iconColor).opacity(0.13), in: RoundedRectangle(cornerRadius: 7))

                StatusDot(
                    activity: session.activity,
                    isWorking: model.workingSessionIDs.contains(session.id)
                )
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    if session.boundSessionID != nil {
                        Image(systemName: "link")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .help(model.trf("context.boundToSession", session.agent.displayName))
                    }
                }
                if let preview = model.firstPrompts[session.id] {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(agentDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(modelDetailHelp)
            }

            Spacer(minLength: 4)

            if let shortcutIndex {
                Text("⌘\(shortcutIndex)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.17) : Color.clear)
        }
        .overlay {
            if session.activity == .attention || session.activity == .failed {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(session.activity == .failed ? Color.red.opacity(0.55) : Color.orange.opacity(0.5))
            }
        }
    }

    private var agentDetailLine: String {
        var parts = [session.agent.displayName]
        if let providerID = model.modelInfoBySessionID[session.id]?.providerID {
            parts.append(providerID)
        }
        parts.append(session.directoryName)
        return parts.joined(separator: " · ")
    }

    private var modelDetailHelp: String {
        guard let info = model.modelInfoBySessionID[session.id] else {
            return session.agent.displayName
        }
        var lines: [String] = []
        if let providerID = info.providerID {
            lines.append("\(model.tr("sidebar.provider")): \(providerID)")
        }
        if let modelID = info.modelID {
            lines.append("\(model.tr("sidebar.model")): \(modelID)")
        }
        if let variant = info.variant {
            lines.append("\(model.tr("sidebar.variant")): \(variant)")
        }
        return lines.joined(separator: "\n")
    }
}
