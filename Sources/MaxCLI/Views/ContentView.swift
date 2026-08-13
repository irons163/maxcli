import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var closeCandidate: WorkspaceSession?

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
        }
        .alert(
            "Close running session?",
            isPresented: Binding(
                get: { closeCandidate != nil },
                set: { if !$0 { closeCandidate = nil } }
            ),
            presenting: closeCandidate
        ) { session in
            Button("Cancel", role: .cancel) { closeCandidate = nil }
            Button("Stop and Close", role: .destructive) {
                model.close(session.id)
                closeCandidate = nil
            }
        } message: { session in
            Text("\(session.title) is still running. Its process will be terminated.")
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
        } else if model.layoutMode == .grid {
            gridWorkspace
        } else if let session = model.selectedSession {
            TerminalPane(session: session, compact: false) {
                requestClose(session)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        } else {
            ContentUnavailableView("Select a session", systemImage: "terminal")
        }
    }

    private var gridWorkspace: some View {
        GeometryReader { proxy in
            let count = proxy.size.width > 1120 ? 3 : (proxy.size.width > 700 ? 2 : 1)
            let columns = Array(repeating: GridItem(.flexible(minimum: 330), spacing: 12), count: count)
            ScrollView([.vertical, .horizontal]) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(model.visibleSessions) { session in
                        TerminalPane(session: session, compact: true) {
                            requestClose(session)
                        }
                        .frame(minWidth: 330, minHeight: 270, idealHeight: 330)
                    }
                }
                .padding(12)
                .frame(minWidth: proxy.size.width, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if let session = model.selectedSession {
                HStack(spacing: 7) {
                    Image(systemName: session.agent.symbolName)
                        .foregroundStyle(Color(nsColor: session.agent.color))
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
            .help("opencode History (⌘⇧H)")

            Button {
                model.isShowingQuickSwitcher = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Quick switcher (⌘K)")

            Picker("Layout", selection: $model.layoutMode) {
                ForEach(LayoutMode.allCases) { mode in
                    Image(systemName: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 86)
            .help("Focus or grid layout")

            Button {
                model.isShowingNewSession = true
            } label: {
                Image(systemName: "plus")
            }
            .help("New session (⌘N)")
        }
    }
}
