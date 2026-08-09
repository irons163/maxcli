import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    let onRequestClose: (WorkspaceSession) -> Void

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
            metric(value: model.runningCount, label: "Running", color: .green)
            metric(value: model.attentionCount, label: "Attention", color: .orange)
            metric(value: model.sessions.count, label: "Total", color: .secondary)
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
            TextField("Search sessions", text: $model.searchText)
                .textFieldStyle(.roundedBorder)

            Menu {
                Button("All agents") { model.agentFilter = nil }
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
                    .contextMenu {
                        Button(session.isPinned ? "Unpin" : "Pin") {
                            model.togglePin(session.id)
                        }
                        Button("Duplicate") {
                            model.select(session.id)
                            model.duplicateSelected()
                        }
                        if model.runtime(for: session.id)?.isRunning == true {
                            Button("Stop") { model.stop(session.id) }
                        } else {
                            Button("Start") { model.start(session.id) }
                        }
                        Button("Restart") { model.restart(session.id) }
                        Divider()
                        Button("Copy Launch Command") { model.copyLaunchCommand(session.id) }
                        Button("Reveal in Finder") { model.revealInFinder(session.id) }
                        Divider()
                        Button("Close", role: .destructive) { onRequestClose(session) }
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
                Label("New Session", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Spacer()

            Menu {
                Button("Start All Stopped") { model.restartStopped() }
                    .disabled(model.sessions.allSatisfy { model.runtime(for: $0.id)?.isRunning == true })
                Button("Stop All", role: .destructive) { model.stopAll() }
                    .disabled(model.runningCount == 0)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Session actions")
        }
        .padding(12)
        .background(.bar)
    }
}

private struct SessionRow: View {
    let session: WorkspaceSession
    let isSelected: Bool
    let shortcutIndex: Int?

    var body: some View {
        HStack(spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: session.agent.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(nsColor: session.agent.color))
                    .frame(width: 30, height: 30)
                    .background(Color(nsColor: session.agent.color).opacity(0.13), in: RoundedRectangle(cornerRadius: 7))

                StatusDot(activity: session.activity)
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
                }
                Text("\(session.agent.displayName) · \(session.directoryName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
}
