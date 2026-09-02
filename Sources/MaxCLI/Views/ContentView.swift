import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var closeCandidate: WorkspaceSession?
    @State private var draggingSessionID: UUID?

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

        if allSections.isEmpty {
            return AnyView(
                GeometryReader { proxy in
                    ScrollViewReader { scrollProxy in
                        let count = model.gridColumns != 0 ? model.gridColumns : (proxy.size.width > 1120 ? 3 : (proxy.size.width > 700 ? 2 : 1))
                        let columns = Array(repeating: GridItem(.flexible(minimum: 330), spacing: 12), count: count)
                        ScrollView([.vertical, .horizontal]) {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(sessions, id: \.id) { session in
                                    gridCell(for: session)
                                }
                            }
                            .padding(12)
                            .frame(minWidth: proxy.size.width, alignment: .topLeading)
                        }
                        .background(Color(nsColor: .windowBackgroundColor))
                        .onChange(of: model.selectedSessionID) { _, newID in
                            guard let id = newID, sessions.contains(where: { $0.id == id }) else { return }
                            guard model.layoutMode == .grid || model.layoutMode == .active else { return }
                            withAnimation { scrollProxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            )
        }

        return AnyView(
            GeometryReader { proxy in
                ScrollViewReader { scrollProxy in
                    let count = model.gridColumns != 0 ? model.gridColumns : (proxy.size.width > 1120 ? 3 : (proxy.size.width > 700 ? 2 : 1))
                    let columns = Array(repeating: GridItem(.flexible(minimum: 330), spacing: 12), count: count)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                            ForEach(allSections, id: \.title) { section in
                                Section {
                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                        ForEach(section.sessions, id: \.id) { session in
                                            gridCell(for: session)
                                        }
                                    }
                                } header: {
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
                                }
                            }
                        }
                        .padding(12)
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                    .onChange(of: model.selectedSessionID) { _, newID in
                        guard let id = newID, sessions.contains(where: { $0.id == id }) else { return }
                        guard model.layoutMode == .grid || model.layoutMode == .active else { return }
                        withAnimation { scrollProxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        )
    }

    private func gridCell(for session: WorkspaceSession) -> some View {
        TerminalPane(
            session: session,
            compact: true,
            onRequestClose: { requestClose(session) },
            headerDragID: session.id.uuidString,
            onHeaderDragStart: { draggingSessionID = session.id },
            onDoubleClick: {
                guard model.layoutMode == .grid else { return }
                model.select(session.id)
                model.layoutMode = .focus
            }
        )
        .id(session.id)
        .frame(minWidth: 330, minHeight: 270, idealHeight: 330)
        .onDrop(
            of: [UTType.plainText],
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
