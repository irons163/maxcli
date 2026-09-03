import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var closeCandidate: WorkspaceSession?
    @State private var draggingSessionID: UUID?
    @State private var scrollPositionID: UUID?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView { session in
                requestClose(session)
            }
        } detail: {
            workspace
                .toolbar { toolbar }
        }
        .navigationTitle("MaxCLI")
        .sheet(isPresented: $model.isShowingNewSession) {
            NewSessionSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.isShowingQuickSwitcher) {
            QuickSwitcherView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.isShowingHistory) {
            HistoryView()
                .frame(minWidth: 1100, minHeight: 700)
        }
        .alert(
            model.tr("close.title"),
            isPresented: Binding(
                get: { closeCandidate != nil },
                set: { if !$0 { closeCandidate = nil } }
            ),
            presenting: closeCandidate
        ) { session in
            Button(model.tr("common.cancel"), role: .cancel) { closeCandidate = nil }
            Button(model.tr("close.confirm"), role: .destructive) {
                model.close(session.id)
                closeCandidate = nil
            }
        } message: { session in
            Text(verbatim: model.trf("close.message", session.title))
        }
        .alert(
            model.tr("bind.restartTitle"),
            isPresented: Binding(
                get: { model.pendingBindRestart != nil },
                set: { if !$0 { model.cancelBindRestart() } }
            )
        ) {
            Button(model.tr("common.cancel"), role: .cancel) { model.cancelBindRestart() }
            Button(model.tr("context.restart")) { model.confirmBindRestart() }
        } message: {
            Text(model.tr("bind.restartMessage"))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.stopAll()
        }
    }

    private func requestClose(_ session: WorkspaceSession) {
        if model.runtime(for: session.id)?.isRunning == true {
            closeCandidate = session
        } else {
            model.close(session.id)
        }
    }

    @ViewBuilder
    private var workspace: some View {
        if model.sessions.isEmpty {
            EmptyWorkspaceView()
        } else if model.layoutMode == .active {
            activeWorkspace
        } else if model.layoutMode == .grid {
            gridWorkspace
        } else if let session = model.selectedSession {
            TerminalPane(session: session, compact: false) {
                requestClose(session)
            }
            .id(session.id)
            .ignoresSafeArea(.container, edges: .bottom)
        } else {
            ContentUnavailableView(model.tr("workspace.selectSession"), systemImage: "terminal")
        }
    }

    @ViewBuilder
    private var activeWorkspace: some View {
        if model.activeSessions.isEmpty {
            ContentUnavailableView(model.tr("workspace.noActive"), systemImage: "bolt.slash")
        } else {
            gridWorkspace(sessions: model.activeSessions)
        }
    }

    private var gridWorkspace: some View {
        gridWorkspace(sessions: model.visibleSessions)
    }

    private func gridWorkspace(sessions: [WorkspaceSession]) -> some View {
        let manualGrouped = Dictionary(grouping: sessions.filter { $0.groupName != nil }) { $0.groupName! }
        let manualSections: [(title: String, icon: String, sessions: [WorkspaceSession])] = manualGrouped.keys.sorted().map { name in
            let list = (manualGrouped[name] ?? []).sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                let lo = lhs.manualOrder ?? Int.max
                let ro = rhs.manualOrder ?? Int.max
                if lo != ro { return lo < ro }
                return lhs.createdAt < rhs.createdAt
            }
            return (title: name, icon: "person.3.fill", sessions: list)
        }
        let ungrouped = sessions.filter { $0.groupName == nil }
        let autoSections: [(title: String, icon: String, sessions: [WorkspaceSession])] = {
            if ungrouped.isEmpty { return [] }
            if !model.groupByFolder {
                return [(title: "", icon: "", sessions: ungrouped)]
            }
            var order: [String] = []
            var groups: [String: [WorkspaceSession]] = [:]
            for s in ungrouped {
                let key = s.workingDirectory
                if groups[key] == nil {
                    order.append(key)
                    groups[key] = []
                }
                groups[key]?.append(s)
            }
            return order.map { dir in
                let name = URL(fileURLWithPath: dir).lastPathComponent
                return (title: name.isEmpty ? dir : name, icon: "folder.fill", sessions: groups[dir] ?? [])
            }
        }()
        let allSections = manualSections + autoSections

        return GeometryReader { proxy in
            let count = model.gridColumns != 0 ? model.gridColumns : (proxy.size.width > 1120 ? 3 : (proxy.size.width > 700 ? 2 : 1))
            // Non-lazy layout: a lazy grid positions un-materialized cells by
            // estimate, which produced phantom blank gaps between sections
            // (especially after scrollPosition jumps). Session counts are
            // small, so eager layout costs nothing and positions are exact.
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(allSections, id: \.title) { section in
                        if !section.title.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(section.icon == "person.3.fill" ? .blue : .secondary)
                                Text(section.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text("\(section.sessions.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.secondary.opacity(0.15), in: Capsule())
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                        ForEach(Array(stride(from: 0, to: section.sessions.count, by: count)), id: \.self) { rowStart in
                            let row = section.sessions[rowStart..<min(rowStart + count, section.sessions.count)]
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(row, id: \.id) { session in
                                    gridCell(for: session)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
            .scrollPosition(id: $scrollPositionID, anchor: .center)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                // Jump (no animation) to the selected session when entering
                // grid/active mode.
                if let id = model.selectedSessionID, sessions.contains(where: { $0.id == id }) {
                    scrollPositionID = id
                }
            }
            .onChange(of: model.selectedSessionID) { _, newID in
                guard let id = newID, sessions.contains(where: { $0.id == id }) else { return }
                guard model.layoutMode == .grid || model.layoutMode == .active else { return }
                // No animation: animating the scroll materializes cells
                // mid-flight, which makes sections and cells appear to fly.
                scrollPositionID = id
            }
        }
    }

    private func gridCell(for session: WorkspaceSession) -> some View {
        TerminalPane(
            session: session,
            compact: true,
            onRequestClose: { requestClose(session) },
            headerDragID: session.id,
            onHeaderDragStart: { draggingSessionID = session.id },
            onDoubleClick: {
                guard model.layoutMode == .grid else { return }
                model.select(session.id)
                model.layoutMode = .focus
            }
        )
        .id(session.id)
        // Fixed height keeps LazyVGrid's position estimates exact, so
        // scrollPosition(id:) lands precisely even for distant cells.
        .frame(minWidth: 330, minHeight: 300, maxHeight: 300)
        .onDrop(
            of: SessionDragPayload.dropTypes,
            delegate: SessionReorderDelegate(
                target: session.id,
                draggedID: $draggingSessionID,
                model: model
            )
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if let session = model.selectedSession {
                HStack(spacing: 7) {
                    Image(systemName: session.symbolName)
                        .foregroundStyle(Color(nsColor: session.iconColor))
                    Text(session.title)
                        .fontWeight(.semibold)
                    Text("—")
                        .foregroundStyle(.tertiary)
                    Text(session.directoryName)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
        }

        ToolbarItemGroup {
            Button {
                model.isShowingHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help(model.tr("help.history"))

            Button {
                model.isShowingQuickSwitcher = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help(model.tr("help.quickSwitcher"))

            Picker("Layout", selection: $model.layoutMode) {
                ForEach(LayoutMode.allCases) { mode in
                    Image(systemName: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 122)
            .help(model.tr("help.layout"))

            if model.layoutMode == .grid || model.layoutMode == .active {
                Menu {
                    Button("自動") { model.gridColumns = 0 }
                    Divider()
                    ForEach(1...4, id: \.self) { n in
                        Button("\(n) 欄  \(n == model.gridColumns ? "✓" : "")") { model.gridColumns = n }
                    }
                } label: {
                    Image(systemName: model.gridColumns == 0 ? "rectangle.grid.2x2" : "\(model.gridColumns).circle")
                }
                .help(model.gridColumns == 0 ? "自動欄數（依寬度）" : "固定 \(model.gridColumns) 欄")
            }

            Button {
                model.isShowingNewSession = true
            } label: {
                Image(systemName: "plus")
            }
            .help(model.tr("help.newSession"))
        }
    }
}
