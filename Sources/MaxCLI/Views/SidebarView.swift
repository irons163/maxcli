import SwiftUI
import UniformTypeIdentifiers

/// Frame of each session row, in the sidebar scroll view's coordinate space.
struct SidebarRowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Visible bounds of the sidebar scroll view, in its own coordinate space.
struct SidebarViewportKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    let onRequestClose: (WorkspaceSession) -> Void
    @State private var draggingSessionID: UUID?
    @State private var collapsedGroups: Set<String> = []
    @State private var collapsedManualGroups: Set<String> = []
    @State private var isShowingNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var newGroupTargetID: UUID?
    @State private var isShowingRenameAlert = false
    @State private var renamingGroup: String?
    @State private var renameText = ""
    /// Set while a selection was initiated from the sidebar itself, where the
    /// tapped row is visible by definition and scrolling to it would be jumpy.
    @State private var suppressSidebarScroll = false
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var viewportSize: CGSize = .zero
    @State private var availableModels: [String] = []
    @State private var isShowingAddAccountAlert = false
    @State private var addAccountProvider: String?
    @State private var addAccountName = ""
    @State private var addAccountKey = ""
    @State private var editingSessionID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            overview
            searchAndFilter
            sessionList
            footer
        }
        .background(.ultraThinMaterial)
        .navigationSplitViewColumnWidth(min: 240, ideal: 278, max: 340)
        .sheet(item: Binding(
            get: { editingSessionID.flatMap { id in model.sessions.first { $0.id == id } } },
            set: { newValue in editingSessionID = newValue?.id }
        )) { session in
            EditSessionSheet(sessionID: session.id)
                .environmentObject(model)
        }
        .task {
            availableModels = await OpenCodeModels.load()
        }
        .alert(
            model.tr("bind.restartTitle"),
            isPresented: Binding(
                get: { model.pendingModelChange != nil },
                set: { if !$0 { model.cancelModelChange() } }
            )
        ) {
            Button(model.tr("common.cancel"), role: .cancel) { model.cancelModelChange() }
            Button(model.tr("context.restart")) { model.confirmModelChangeRestart() }
        } message: {
            Text(model.tr("bind.restartMessage"))
        }
        .alert(
            model.tr("bind.restartTitle"),
            isPresented: Binding(
                get: { model.pendingAccountChange != nil },
                set: { if !$0 { model.cancelAccountChange() } }
            )
        ) {
            Button(model.tr("common.cancel"), role: .cancel) { model.cancelAccountChange() }
            Button(model.tr("context.restart")) { model.confirmAccountChangeRestart() }
        } message: {
            Text(model.tr("bind.restartMessage"))
        }
        .alert(
            model.tr("bind.restartTitle"),
            isPresented: Binding(
                get: { model.pendingArgumentsChange != nil },
                set: { if !$0 { model.cancelArgumentsChange() } }
            )
        ) {
            Button(model.tr("common.cancel"), role: .cancel) { model.cancelArgumentsChange() }
            Button(model.tr("context.restart")) { model.confirmArgumentsChangeRestart() }
        } message: {
            Text(model.tr("bind.restartMessage"))
        }
        .alert(model.tr("context.addAccount"), isPresented: $isShowingAddAccountAlert) {
            TextField(model.tr("field.accountName"), text: $addAccountName)
            SecureField(model.tr("field.accountKey"), text: $addAccountKey)
            Button(model.tr("common.save")) {
                guard let provider = addAccountProvider else { return }
                let saved = model.saveProviderAccount(provider: provider, account: addAccountName, key: addAccountKey)
                if saved, let target = model.selectedSessionID,
                   let session = model.sessions.first(where: { $0.id == target }),
                   session.agent == .opencode,
                   CommandBuilder.modelProvider(for: session) == provider
                   || model.modelInfoBySessionID[target]?.providerID == provider,
                   session.providerAccount == nil {
                    // Offer the new key by pre-selecting it for the tapped session.
                    model.changeSessionAccount(
                        session.id,
                        provider: provider,
                        account: addAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                addAccountName = ""
                addAccountKey = ""
            }
            Button(model.tr("common.cancel"), role: .cancel) {
                addAccountName = ""
                addAccountKey = ""
            }
        } message: {
            Text(model.trf("field.accountKeyHint", addAccountProvider ?? ""))
        }
        .alert("新增群組", isPresented: $isShowingNewGroupAlert) {
            TextField("群組名稱", text: $newGroupName)
            Button("建立") {
                let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                if let target = newGroupTargetID {
                    model.moveSessionToGroup(target, groupName: name)
                }
                newGroupName = ""
                newGroupTargetID = nil
            }
            Button("取消", role: .cancel) {
                newGroupName = ""
                newGroupTargetID = nil
            }
        } message: {
            Text("輸入新群組名稱")
        }
        .alert("重新命名群組", isPresented: $isShowingRenameAlert) {
            TextField("群組名稱", text: $renameText)
            Button("確定") {
                guard let old = renamingGroup else { return }
                let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !newName.isEmpty, newName != old else { return }
                model.renameGroup(from: old, to: newName)
                renamingGroup = nil
                renameText = ""
            }
            Button("取消", role: .cancel) {
                renamingGroup = nil
                renameText = ""
            }
        } message: {
            Text("輸入新的群組名稱")
        }
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

    private var manualGroups: [(name: String, sessions: [WorkspaceSession])] {
        model.manualGroups
    }

    private var autoGroups: [(directory: String, sessions: [WorkspaceSession])] {
        model.autoGroups
    }

    private var sessionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Eager layout so scrollTo can reach any row; sidebar rows
                // are lightweight text views.
                VStack(spacing: 10) {
                    ForEach(manualGroups, id: \.name) { group in
                        let isCollapsed = collapsedManualGroups.contains(group.name)
                        Section {
                            if !isCollapsed {
                                ForEach(group.sessions, id: \.id) { session in
                                    sessionRow(for: session)
                                }
                            }
                        } header: {
                            manualGroupHeader(name: group.name, count: group.sessions.count, isCollapsed: isCollapsed)
                        }
                    }

                    if model.groupByFolder {
                        ForEach(autoGroups, id: \.directory) { group in
                            let isCollapsed = collapsedGroups.contains(group.directory)
                            Section {
                                if !isCollapsed {
                                    ForEach(group.sessions, id: \.id) { session in
                                        sessionRow(for: session)
                                    }
                                }
                            } header: {
                                autoGroupHeader(directory: group.directory, count: group.sessions.count, isCollapsed: isCollapsed)
                            }
                        }
                    } else {
                        ForEach(model.visibleSessions.filter { $0.groupName == nil }, id: \.id) { session in
                            sessionRow(for: session)
                        }
                    }

                    if manualGroups.isEmpty && autoGroups.isEmpty {
                        ForEach(model.visibleSessions, id: \.id) { session in
                            sessionRow(for: session)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .coordinateSpace(name: "sidebarScroll")
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SidebarViewportKey.self,
                        value: geo.frame(in: .named("sidebarScroll"))
                    )
                }
            )
            .onPreferenceChange(SidebarViewportKey.self) { viewport in
                viewportSize = viewport.size
            }
            .onPreferenceChange(SidebarRowFramesKey.self) { frames in
                rowFrames = frames
            }
            .onChange(of: model.selectedSessionID) { _, newID in
                guard let newID else { return }
                if suppressSidebarScroll {
                    suppressSidebarScroll = false
                    return
                }
                // Scroll only when the row is (partially) obscured; keep the
                // user's scroll position when it is already fully visible.
                let needsScroll: Bool
                if let frame = rowFrames[newID], viewportSize != .zero {
                    let viewport = CGRect(origin: .zero, size: viewportSize)
                    needsScroll = !viewport.contains(frame)
                } else {
                    needsScroll = true
                }
                guard needsScroll else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
        .overlay {
            if model.visibleSessions.isEmpty, !model.sessions.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
    }

    private func manualGroupHeader(name: String, count: Int, isCollapsed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Image(systemName: "person.3.fill")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.blue.opacity(0.15), in: Capsule())
            Spacer()

            Button {
                quickAddSession(manualGroup: name)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(model.tr("sidebar.newSession"))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsedManualGroups.contains(name) {
                    collapsedManualGroups.remove(name)
                } else {
                    collapsedManualGroups.insert(name)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .contextMenu {
            Button("重新命名") {
                renamingGroup = name
                renameText = name
                isShowingRenameAlert = true
            }
            Button("刪除群組", role: .destructive) {
                model.deleteGroup(name)
            }
            Divider()
            Button(isCollapsed ? "展開" : "收合") {
                withAnimation {
                    if isCollapsed {
                        collapsedManualGroups.remove(name)
                    } else {
                        collapsedManualGroups.insert(name)
                    }
                }
            }
        }
        .onDrop(of: SessionDragPayload.dropTypes, isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            SessionDragPayload.sessionID(from: provider) { id in
                guard let id else { return }
                model.moveSessionToGroup(id, groupName: name)
            }
            return true
        }
    }

    private func autoGroupHeader(directory: String, count: Int, isCollapsed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(URL(fileURLWithPath: directory).lastPathComponent)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.secondary.opacity(0.15), in: Capsule())
            Spacer()

            Button {
                quickAddSession(directory: directory)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(model.tr("sidebar.newSession"))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsedGroups.contains(directory) {
                    collapsedGroups.remove(directory)
                } else {
                    collapsedGroups.insert(directory)
                }
            }
        }
        .help(directory)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .onDrop(of: SessionDragPayload.dropTypes, isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            SessionDragPayload.sessionID(from: provider) { id in
                guard let id else { return }
                model.moveSessionToGroup(id, groupName: nil)
            }
            return true
        }
    }

    private func sessionRow(for session: WorkspaceSession) -> some View {
        let displayIndex = model.displayOrderedSessions.firstIndex(where: { $0.id == session.id })
        return SessionRow(
            session: session,
            isSelected: model.selectedSessionID == session.id,
            shortcutIndex: (displayIndex ?? 0) < 9 ? (displayIndex ?? 0) + 1 : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            suppressSidebarScroll = true
            model.select(session.id)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SidebarRowFramesKey.self,
                    value: [session.id: geo.frame(in: .named("sidebarScroll"))]
                )
            }
        )
        .onDrag {
            draggingSessionID = session.id
            return SessionDragPayload.provider(for: session.id)
        } preview: {
            SessionDragPreview(session: session)
        }
        .onDrop(
            of: SessionDragPayload.dropTypes,
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
            Menu("移至群組") {
                Button("未分組") {
                    model.moveSessionToGroup(session.id, groupName: nil)
                }
                if !model.allGroupNames.isEmpty {
                    Divider()
                    ForEach(model.allGroupNames, id: \.self) { name in
                        Button {
                            model.moveSessionToGroup(session.id, groupName: name)
                        } label: {
                            Label(name, systemImage: session.groupName == name ? "checkmark" : "person.3")
                        }
                    }
                }
                Divider()
                Button("新增群組…") {
                    newGroupTargetID = session.id
                    newGroupName = ""
                    isShowingNewGroupAlert = true
                }
            }
            Button(model.tr("context.edit")) {
                editingSessionID = session.id
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
            if session.agent == .opencode {
                modelSwitchMenu(for: session)
                accountSwitchMenu(for: session)
            }
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

    /// Switch model (and thereby provider/account) for an OpenCode session.
    /// Models are grouped by the provider prefix; picking one updates the
    /// session's `-m` argument and restarts if it is running.
    private func modelSwitchMenu(for session: WorkspaceSession) -> some View {
        let groupedModels = Dictionary(grouping: availableModels) { model in
            model.split(separator: "/").first.map(String.init) ?? model
        }
        let sortedProviders = groupedModels.keys.sorted()
        let activeModel = model.modelInfoBySessionID[session.id].flatMap { info in
            [info.providerID, info.modelID].compactMap { $0 }.joined(separator: "/")
        }
        return Menu {
            if sortedProviders.isEmpty {
                Text(model.tr("field.modelsLoading"))
            }
            ForEach(sortedProviders, id: \.self) { provider in
                Menu(provider) {
                    ForEach(groupedModels[provider] ?? [], id: \.self) { item in
                        Button {
                            model.changeSessionModel(session.id, model: item)
                        } label: {
                            Label(item, systemImage: item == activeModel ? "checkmark" : "circle")
                        }
                    }
                }
            }
            Divider()
            Button(model.tr("context.modelDefault")) {
                model.changeSessionModel(session.id, model: "")
            }
        } label: {
            Label(model.tr("context.switchModel"), systemImage: "arrow.triangle.branch")
        }
    }

    /// Switch the named Keychain account (same provider, different API key)
    /// the session runs under. Requires the session to carry `-m provider/…`
    /// so the target provider is known.
    private func accountSwitchMenu(for session: WorkspaceSession) -> some View {
        let provider = CommandBuilder.modelProvider(for: session)
            ?? model.modelInfoBySessionID[session.id]?.providerID
        let accounts = provider.map { model.providerAccountNames(for: $0) } ?? []
        return Menu {
            if provider == nil {
                Text(model.tr("context.accountNeedsModel"))
            } else if accounts.isEmpty {
                Text(model.tr("context.noAccounts"))
            }
            if let provider {
                ForEach(accounts, id: \.self) { account in
                    let isCurrent = session.providerAccount == account && session.accountProvider == provider
                    Button {
                        model.changeSessionAccount(session.id, provider: provider, account: account)
                    } label: {
                        Label(account, systemImage: isCurrent ? "checkmark" : "person")
                    }
                }
                Divider()
                Button(model.tr("context.accountDefault")) {
                    model.changeSessionAccount(session.id, provider: provider, account: nil)
                }
                Divider()
                Button(model.tr("context.addAccount")) {
                    addAccountProvider = provider
                    addAccountName = ""
                    addAccountKey = ""
                    isShowingAddAccountAlert = true
                }
                if !accounts.isEmpty {
                    Menu(model.tr("context.deleteAccount")) {
                        ForEach(accounts, id: \.self) { account in
                            Button(account, role: .destructive) {
                                model.deleteProviderAccount(provider: provider, account: account)
                                if session.providerAccount == account, session.accountProvider == provider {
                                    model.changeSessionAccount(session.id, provider: provider, account: nil)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Label(model.tr("context.switchAccount"), systemImage: "person.crop.circle.badge.exclamationmark")
        }
    }

    /// One-tap session creation from a group header: reuses the group's most
    /// recent session as the template (agent + directory).
    private func quickAddSession(directory: String) {
        let template = model.sortedSessions.last { $0.workingDirectory == directory && $0.groupName == nil }
        model.quickAddSession(directory: directory, agent: template?.agent ?? .opencode)
    }

    private func quickAddSession(manualGroup name: String) {
        let sessions = manualGroups.first { $0.name == name }?.sessions ?? []
        let template = sessions.last
        let directory = template?.workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        model.quickAddSession(directory: directory, agent: template?.agent ?? .opencode, groupName: name)
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
                Toggle(isOn: $model.groupByFolder) {
                    Label("依資料夾分組", systemImage: "folder")
                }
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
        guard let draggedSession = model.sessions.first(where: { $0.id == dragged }),
              let targetSession = model.sessions.first(where: { $0.id == target }) else { return }
        if draggedSession.groupName != nil || targetSession.groupName != nil {
            guard draggedSession.groupName == targetSession.groupName else { return }
        } else if model.groupByFolder {
            guard draggedSession.workingDirectory == targetSession.workingDirectory else { return }
        }
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
