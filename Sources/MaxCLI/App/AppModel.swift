import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    struct PendingBindRestart {
        let sessionID: UUID
        let target: String?
    }

    private(set) var sessions: [WorkspaceSession]
    @Published var selectedSessionID: UUID?
    @Published var layoutMode: LayoutMode = .focus
    @Published var searchText = ""
    @Published var agentFilter: AgentKind?
    @Published var isShowingNewSession = false
    @Published var isShowingQuickSwitcher = false
    @Published var isShowingHistory = false
    @Published var sidebarVisible = true
    @Published var language: AppLanguage
    @Published var groupByFolder = true
    @Published var gridColumns = 0
    @Published private(set) var workingSessionIDs: Set<UUID> = []
    @Published private(set) var firstPrompts: [UUID: String] = [:]
    @Published private(set) var modelInfoBySessionID: [UUID: OpenCodeModelInfo] = [:]
    @Published private(set) var recentSessionsByDirectory: [String: [HistorySession]] = [:]
    @Published var pendingBindRestart: PendingBindRestart?

    private(set) var runtimes: [UUID: TerminalRuntime] = [:]
    let installedAgents: Set<AgentKind>
    private let persistence: SessionPersistence
    private var canPersistSafely: Bool
    private var cancellables = Set<AnyCancellable>()
    private var manuallyStopping = Set<UUID>()
    private var runtimeGenerations: [UUID: UUID] = [:]
    private var pendingOutputBytes: [UUID: Int] = [:]
    private var pendingActivityAt: [UUID: Date] = [:]
    private var lastFocusAt: [UUID: Date] = [:]
    private var outputHistory: [UUID: [Int]] = [:]
    private var idleTicks: [UUID: Int] = [:]
    /// Sessions that were working and then went silent — eligible for the
    /// finished/waiting notification. Fresh idle sessions never qualify.
    private var pendingIdleNotify: Set<UUID> = []
    private var idleNotifyArmed: Set<UUID> = []
    private var lastUserInputAt: [UUID: Date] = [:]
    private var launchDates: [UUID: Date] = [:]
    private static let workingByteThreshold = 400
    private static let idleByteThreshold = 100
    private static let idleTickLimit = 4
    /// Ticks (~0.6s each) of continued silence after the agent went idle
    /// before treating it as "task finished" and notifying the user. Longer
    /// than the working→idle threshold so quiet builds don't false-alarm.
    private static let idleNotifyTickLimit = 10
    private static let userInteractionGrace: TimeInterval = 1.5
    private static let focusGrace: TimeInterval = 2.0
    private static let languageKey = "maxcli.language.v1"
    private static let groupByFolderKey = "maxcli.groupByFolder.v1"
    private static let gridColumnsKey = "maxcli.gridColumns.v1"

    func tr(_ key: String, _ comment: String = "") -> String {
        NSLocalizedString(key, bundle: language.bundle, comment: comment)
    }

    func trf(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, bundle: language.bundle, comment: ""), arguments: arguments)
    }

    init(
        persistence: SessionPersistence = SessionPersistence(),
        executableLocator: ExecutableLocator = ExecutableLocator()
    ) {
        let loaded = persistence.load()
        self.persistence = persistence
        self.canPersistSafely = !loaded.decodeFailed
        self.installedAgents = executableLocator.installedAgents
        self.sessions = loaded.sessions
        self.selectedSessionID = loaded.sessions.first?.id
        let storedLanguage = UserDefaults.standard.string(forKey: Self.languageKey)
            .flatMap(AppLanguage.init(rawValue:))
        self.language = storedLanguage ?? .system
        $language
            .sink { language in UserDefaults.standard.setValue(language.rawValue, forKey: Self.languageKey) }
            .store(in: &cancellables)
        if UserDefaults.standard.object(forKey: Self.groupByFolderKey) != nil {
            self.groupByFolder = UserDefaults.standard.bool(forKey: Self.groupByFolderKey)
        }
        $groupByFolder
            .sink { value in UserDefaults.standard.set(value, forKey: Self.groupByFolderKey) }
            .store(in: &cancellables)
        self.gridColumns = UserDefaults.standard.integer(forKey: Self.gridColumnsKey)
        if self.gridColumns < 0 || self.gridColumns > 6 { self.gridColumns = 0 }
        $gridColumns
            .sink { value in UserDefaults.standard.set(value, forKey: Self.gridColumnsKey) }
            .store(in: &cancellables)
        updateDockBadge()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.6))
                self?.sampleOutputActivity()
            }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshFirstPrompts()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    var selectedSession: WorkspaceSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var visibleSessions: [WorkspaceSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sortedSessions.filter { session in
            let matchesAgent = agentFilter == nil || session.agent == agentFilter
            let matchesSearch = query.isEmpty
                || session.searchableText.contains(query)
                || (firstPrompts[session.id]?.lowercased().contains(query) ?? false)
            return matchesAgent && matchesSearch
        }
    }

    var sortedSessions: [WorkspaceSession] {
        sessions.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            // Activity timestamps change as terminal output arrives. Keep the
            // workspace order stable so active panes do not swap positions.
            let lhsOrder = lhs.manualOrder ?? Int.max
            let rhsOrder = rhs.manualOrder ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var manualGroups: [(name: String, sessions: [WorkspaceSession])] {
        let visible = visibleSessions
        let grouped = Dictionary(grouping: visible.filter { $0.groupName != nil }) { $0.groupName! }
        return grouped.keys.sorted().map { name in
            let sessions = (grouped[name] ?? []).sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                let lo = lhs.manualOrder ?? Int.max
                let ro = rhs.manualOrder ?? Int.max
                if lo != ro { return lo < ro }
                return lhs.createdAt < rhs.createdAt
            }
            return (name: name, sessions: sessions)
        }
    }

    var autoGroups: [(directory: String, sessions: [WorkspaceSession])] {
        let ungrouped = visibleSessions.filter { $0.groupName == nil }
        if ungrouped.isEmpty { return [] }
        var order: [String] = []
        var groups: [String: [WorkspaceSession]] = [:]
        for session in ungrouped {
            let key = session.workingDirectory
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(session)
        }
        return order.map { dir in (directory: dir, sessions: groups[dir] ?? []) }
    }

    var displayOrderedSessions: [WorkspaceSession] {
        let manual = manualGroups.flatMap(\.sessions)
        if groupByFolder {
            return manual + autoGroups.flatMap(\.sessions)
        } else {
            return manual + visibleSessions.filter { $0.groupName == nil }
        }
    }

    func moveSession(_ id: UUID, before targetID: UUID) {
        moveSession(id, relativeTo: targetID, after: false)
    }

    func moveSession(_ id: UUID, relativeTo targetID: UUID, after: Bool) {
        guard id != targetID else { return }
        var ordered = sessions
            .filter { !$0.isPinned }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.manualOrder ?? Int.max
                let rhsOrder = rhs.manualOrder ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.createdAt < rhs.createdAt
            }
        guard let from = ordered.firstIndex(where: { $0.id == id }),
              let to = ordered.firstIndex(where: { $0.id == targetID })
        else { return }
        let dragged = ordered.remove(at: from)
        let insertIndex: Int
        if from < to {
            insertIndex = after ? to : to - 1
        } else {
            insertIndex = after ? to + 1 : to
        }
        ordered.insert(dragged, at: insertIndex)
        for (index, session) in ordered.enumerated() {
            updateSession(session.id) { $0.manualOrder = index }
        }
        persist()
    }

    var activeSessions: [WorkspaceSession] {
        sortedSessions.filter { session in
            switch session.activity {
            case .launching, .running, .attention: true
            case .stopped, .failed: false
            }
        }
    }

    var runningCount: Int {
        sessions.filter { runtimes[$0.id]?.isRunning == true }.count
    }

    var attentionCount: Int {
        sessions.filter { $0.activity == .attention || $0.activity == .failed }.count
    }

    private func updateDockBadge() {
        let count = attentionCount
        NSApp?.dockTile.badgeLabel = count > 0 ? "\(count)" : ""
    }

    /// The agent stopped producing output while the user is elsewhere:
    /// flag the session as needing attention (finished turn, waiting for
    /// input). Only fires for currently-running sessions that are not
    /// selected and not already flagged.
    private func notifyAgentIdle(_ id: UUID) {
        guard selectedSessionID != id,
              let session = session(id),
              !session.isTransient,
              session.activity == .running,
              runtimes[id]?.isRunning == true
        else { return }
        updateSession(id) { $0.lastActivityAt = .now }
        updateSession(id) { $0.activity = .attention }
        NSSound(named: "Glass")?.play()
        persist()
    }

    func runtime(for sessionID: UUID) -> TerminalRuntime? {
        runtimes[sessionID]
    }

    func runOpenCodeAuth(_ argument: String) {
        let session = WorkspaceSession(
            title: "opencode \(argument)",
            agent: .opencode,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            arguments: argument,
            isTransient: true
        )
        addSession(session)
    }

    func addSession(_ session: WorkspaceSession) {
        canPersistSafely = true
        var newSession = session
        newSession.activity = .launching
        sessions.append(newSession)
        notifySessionsChanged()
        select(newSession.id)
        start(newSession.id)
        persist()
    }

    /// One-tap session creation from a group header: reuses the group's
    /// directory (and its most recent agent) without opening the sheet.
    func quickAddSession(directory: String, agent: AgentKind, groupName: String? = nil) {
        let name = URL(fileURLWithPath: directory).lastPathComponent
        let session = WorkspaceSession(
            title: "\(name) · \(agent.displayName)",
            agent: agent,
            workingDirectory: directory,
            groupName: groupName
        )
        addSession(session)
    }

    func start(_ id: UUID) {
        guard let current = session(id) else { return }
        if runtimes[id]?.isRunning == true {
            select(id)
            return
        }

        launchDates[id] = .now
        autoBindOpenCodeSessionIfNeeded(id)
        guard let latestSession = session(id) else { return }
        runtimes[id] = nil
        updateSession(id) { $0.activity = .launching }
        let generation = UUID()
        runtimeGenerations[id] = generation
        let runtime = TerminalRuntime(sessionID: id) { [weak self] sessionID, event in
            guard self?.runtimeGenerations[sessionID] == generation else { return }
            self?.handle(event, for: sessionID)
        }
        runtimes[id] = runtime
        runtime.start(session: latestSession)
        persist()
    }

    func stop(_ id: UUID) {
        guard let runtime = runtimes[id] else {
            updateSession(id) { $0.activity = .stopped }
            return
        }
        manuallyStopping.insert(id)
        runtime.stop()
        if !runtime.isRunning {
            updateSession(id) { $0.activity = .stopped }
            manuallyStopping.remove(id)
        }
        persist()
    }

    func restart(_ id: UUID) {
        if let runtime = runtimes[id], runtime.isRunning {
            manuallyStopping.insert(id)
            runtime.stop()
        }
        runtimes[id] = nil
        manuallyStopping.remove(id)
        start(id)
    }

    func close(_ id: UUID) {
        if let runtime = runtimes[id], runtime.isRunning {
            manuallyStopping.insert(id)
            runtime.stop()
        }
        runtimes[id] = nil
        runtimeGenerations[id] = nil
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id {
            selectedSessionID = sortedSessions.first?.id
        }
        notifySessionsChanged()
        persist()
    }

    func select(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        selectedSessionID = id
        updateSession(id) { session in
            session.lastActivatedAt = .now
            if session.activity == .attention {
                session.activity = self.runtimes[id]?.isRunning == true ? .running : .stopped
            }
        }
        persist()
    }

    func selectSession(at index: Int) {
        let sessions = displayOrderedSessions.isEmpty ? sortedSessions : displayOrderedSessions
        guard sessions.indices.contains(index) else { return }
        select(sessions[index].id)
    }

    func selectNext(offset: Int) {
        let sessions = sortedSessions
        guard !sessions.isEmpty else { return }
        let current = sessions.firstIndex { $0.id == selectedSessionID } ?? 0
        let next = (current + offset + sessions.count) % sessions.count
        select(sessions[next].id)
    }

    func duplicateSelected() {
        guard var copy = selectedSession else { return }
        copy = WorkspaceSession(
            title: uniqueTitle(from: copy.title),
            agent: copy.agent,
            workingDirectory: copy.workingDirectory,
            arguments: copy.arguments,
            customCommand: copy.customCommand,
            iconName: copy.iconName,
            iconColorName: copy.iconColorName,
            isPinned: copy.isPinned,
            groupName: copy.groupName
        )
        addSession(copy)
    }

    var allGroupNames: [String] {
        Array(Set(sessions.compactMap(\.groupName))).sorted()
    }

    func moveSessionToGroup(_ id: UUID, groupName: String?) {
        let normalized = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = (normalized?.isEmpty == true) ? nil : normalized
        updateSession(id) { $0.groupName = final }
        persist()
    }

    func createGroup(named name: String, for sessionID: UUID? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let sessionID { moveSessionToGroup(sessionID, groupName: trimmed) }
    }

    func renameGroup(from oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        for session in sessions where session.groupName == oldName {
            updateSession(session.id) { $0.groupName = trimmed }
        }
        persist()
    }

    func deleteGroup(_ name: String) {
        for session in sessions where session.groupName == name {
            updateSession(session.id) { $0.groupName = nil }
        }
        persist()
    }

    func togglePin(_ id: UUID) {
        updateSession(id) { $0.isPinned.toggle() }
        persist()
    }

    func updateSessionAppearance(
        _ id: UUID,
        title: String,
        iconName: String?,
        iconColorName: String?
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSession(id) { session in
            if !trimmed.isEmpty { session.title = trimmed }
            session.iconName = iconName
            session.iconColorName = iconColorName
        }
        persist()
    }

    /// Switching the model (and thereby provider/account) requires a restart
    /// when the session is running; the change is queued for confirmation.
    struct PendingModelChange {
        let sessionID: UUID
        let model: String
    }

    @Published var pendingModelChange: PendingModelChange?

    func changeSessionModel(_ id: UUID, model: String) {
        guard session(id) != nil else { return }
        guard runtimes[id]?.isRunning == true else {
            applySessionModel(id, model: model)
            return
        }
        pendingModelChange = PendingModelChange(sessionID: id, model: model)
    }

    func confirmModelChangeRestart() {
        guard let pending = pendingModelChange else { return }
        pendingModelChange = nil
        applySessionModel(pending.sessionID, model: pending.model)
        restart(pending.sessionID)
    }

    func cancelModelChange() {
        pendingModelChange = nil
    }

    // MARK: - Provider accounts (multiple keys per provider)

    struct PendingAccountChange {
        let sessionID: UUID
        let provider: String
        let account: String?
    }

    @Published var pendingAccountChange: PendingAccountChange?

    func providerAccountNames(for provider: String) -> [String] {
        ProviderAccountStore.accountNames(provider: provider)
    }

    func saveProviderAccount(provider: String, account: String, key: String) -> Bool {
        let name = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !trimmedKey.isEmpty else { return false }
        return ProviderAccountStore.save(provider: provider, account: name, key: trimmedKey)
    }

    func deleteProviderAccount(provider: String, account: String) {
        ProviderAccountStore.delete(provider: provider, account: account)
    }

    func changeSessionAccount(_ id: UUID, provider: String, account: String?) {
        guard session(id) != nil else { return }
        guard runtimes[id]?.isRunning == true else {
            applySessionAccount(id, provider: provider, account: account)
            return
        }
        pendingAccountChange = PendingAccountChange(sessionID: id, provider: provider, account: account)
    }

    func confirmAccountChangeRestart() {
        guard let pending = pendingAccountChange else { return }
        pendingAccountChange = nil
        applySessionAccount(pending.sessionID, provider: pending.provider, account: pending.account)
        restart(pending.sessionID)
    }

    func cancelAccountChange() {
        pendingAccountChange = nil
    }

    private func applySessionAccount(_ id: UUID, provider: String, account: String?) {
        updateSession(id) { session in
            session.providerAccount = account
            session.accountProvider = account == nil ? nil : provider
        }
        persist()
    }

    // MARK: - Launch arguments editing

    struct PendingArgumentsChange {
        let sessionID: UUID
        let arguments: String?
        let customCommand: String?
    }

    @Published var pendingArgumentsChange: PendingArgumentsChange?

    /// Edits launch arguments (or the custom command). Running sessions need
    /// a restart for the change to take effect — queued for confirmation.
    func updateSessionLaunch(_ id: UUID, arguments: String?, customCommand: String?) {
        guard session(id) != nil else { return }
        guard runtimes[id]?.isRunning == true else {
            applySessionLaunch(id, arguments: arguments, customCommand: customCommand)
            return
        }
        pendingArgumentsChange = PendingArgumentsChange(
            sessionID: id,
            arguments: arguments,
            customCommand: customCommand
        )
    }

    func confirmArgumentsChangeRestart() {
        guard let pending = pendingArgumentsChange else { return }
        pendingArgumentsChange = nil
        applySessionLaunch(pending.sessionID, arguments: pending.arguments, customCommand: pending.customCommand)
        restart(pending.sessionID)
    }

    func cancelArgumentsChange() {
        pendingArgumentsChange = nil
    }

    private func applySessionLaunch(_ id: UUID, arguments: String?, customCommand: String?) {
        updateSession(id) { session in
            if let arguments {
                session.arguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let customCommand {
                session.customCommand = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // An account override is provider-scoped: editing the model flag
            // onto another provider would inject the old provider's key.
            if let newProvider = CommandBuilder.modelProvider(for: session),
               let assigned = session.accountProvider, assigned != newProvider {
                session.providerAccount = nil
                session.accountProvider = nil
            }
        }
        persist()
    }

    /// Replaces the `-m` flag in the session's arguments (empty model clears it)
    /// while preserving any other arguments.
    private func applySessionModel(_ id: UUID, model: String) {
        updateSession(id) { session in
            var args = session.arguments
            if let range = args.range(of: #"(^|\s)-m\s+\S+"#, options: .regularExpression) {
                args = args.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespaces)
            }
            let flag = model.isEmpty ? "" : "-m \(model)"
            session.arguments = [args, flag].filter { !$0.isEmpty }.joined(separator: " ")
            // An account override is provider-scoped: switching to a model on
            // another provider would otherwise inject the old provider's key.
            if let modelProvider = model.split(separator: "/").first.map(String.init),
               let assigned = session.accountProvider, assigned != modelProvider {
                session.providerAccount = nil
                session.accountProvider = nil
            }
        }
        persist()
    }

    func bindSession(_ id: UUID, to historySession: HistorySession?) {
        guard let session = session(id) else { return }
        guard historySession == nil || historySession?.source == session.agent else { return }
        requestBinding(id, to: historySession?.sessionID)
    }

    /// Compatibility entry point for older callers and persisted OpenCode UI.
    func bindOpenCodeSession(_ id: UUID, to opencodeSessionID: String?) {
        requestBinding(id, to: opencodeSessionID)
    }

    private func requestBinding(_ id: UUID, to target: String?) {
        guard let session = session(id), session.boundSessionID != target else { return }
        if runtimes[id]?.isRunning == true {
            pendingBindRestart = PendingBindRestart(sessionID: id, target: target)
            return
        }
        applySessionBinding(id, to: target)
    }

    func confirmBindRestart() {
        guard let pending = pendingBindRestart else { return }
        pendingBindRestart = nil
        applySessionBinding(pending.sessionID, to: pending.target)
        restart(pending.sessionID)
    }

    func cancelBindRestart() {
        pendingBindRestart = nil
    }

    private func applySessionBinding(_ id: UUID, to target: String?) {
        updateSession(id) { session in
            session.boundSessionID = target
            session.opencodeSessionID = session.agent == .opencode ? target : nil
        }
        persist()
    }

    private func autoBindOpenCodeSessionIfNeeded(_ id: UUID) {
        guard let session = session(id),
              session.agent == .opencode,
              !session.isTransient,
              session.boundSessionID == nil,
              !sessions.contains(where: { $0.id != id && $0.workingDirectory == session.workingDirectory })
        else { return }
        guard let latestID = try? OpenCodeHistoryStore.latestSessionID(directory: session.workingDirectory) else { return }
        applySessionBinding(id, to: latestID)
    }
    private func detectOpenCodeBindings(_ recentSessions: [String: [HistorySession]]) {
        var taken = Set(sessions.filter { $0.agent == .opencode }.compactMap(\.boundSessionID))
        let unbound = sessions
            .filter {
                $0.agent == .opencode
                    && !$0.isTransient
                    && $0.boundSessionID == nil
                    && runtimes[$0.id]?.isRunning == true
            }
            .sorted {
                (launchDates[$0.id] ?? .distantPast) < (launchDates[$1.id] ?? .distantPast)
            }
        for session in unbound {
            guard let launch = launchDates[session.id] else { continue }
            let match = recentSessions[session.workingDirectory]?
                .filter {
                    $0.source == .opencode
                    && !$0.isSubagent
                    && !taken.contains($0.sessionID)
                    && ($0.timeCreated >= launch || $0.timeUpdated >= launch)
                }
                .sorted(by: {
                    let aNew = $0.timeCreated >= launch
                    let bNew = $1.timeCreated >= launch
                    if aNew != bNew { return aNew }
                    return aNew ? $0.timeCreated < $1.timeCreated : $0.timeUpdated < $1.timeUpdated
                })
                .first
            if let match {
                applySessionBinding(session.id, to: match.sessionID)
                taken.insert(match.sessionID)
            }
        }
    }
    func stopAll() {
        for session in sessions where runtimes[session.id]?.isRunning == true {
            stop(session.id)
        }
    }

    func restartStopped() {
        for session in sessions where runtimes[session.id]?.isRunning != true {
            start(session.id)
        }
    }

    func revealInFinder(_ id: UUID) {
        guard let session = session(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: session.workingDirectory)
        ])
    }

    func copyLaunchCommand(_ id: UUID) {
        guard let session = session(id) else { return }
        let launchCommand = CommandBuilder.command(for: session)
        let command = "cd \(CommandBuilder.shellEscape(session.workingDirectory)) && \(launchCommand)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    func handle(_ event: TerminalRuntimeEvent, for id: UUID) {
        guard session(id) != nil else { return }
        switch event {
        case .started:
            updateSession(id) { $0.lastActivityAt = .now }
            guard sessions.first(where: { $0.id == id })?.activity == .launching else { return }
            updateSession(id) { $0.activity = .running }
        case let .output(bytes):
            pendingOutputBytes[id, default: 0] += bytes
            pendingActivityAt[id] = .now
            // The agent resumed after being flagged idle-finished.
            if sessions.first(where: { $0.id == id })?.activity == .attention {
                idleNotifyArmed.remove(id)
                pendingIdleNotify.remove(id)
                updateSession(id) { $0.activity = .running }
            }
            guard sessions.first(where: { $0.id == id })?.activity == .launching else { return }
            updateSession(id) { $0.activity = .running }
            persist()
        case .userInput:
            lastUserInputAt[id] = .now
            return
        case .focus:
            lastFocusAt[id] = .now
            return
        case .bell:
            if selectedSessionID == id {
                updateSession(id) { $0.lastActivityAt = .now }
                return
            }
            guard session(id)?.activity != .attention else { return }
            updateSession(id) { session in
                session.lastActivityAt = .now
                session.activity = .attention
            }
            NSSound(named: "Glass")?.play()
            persist()
        case let .directory(directory):
            guard FileManager.default.fileExists(atPath: directory) else { return }
            updateSession(id) { $0.workingDirectory = directory }
            persist()
        case .title:
            return
        case let .terminated(exitCode):
            if session(id)?.isTransient == true {
                close(id)
                return
            }
            let wasManual = manuallyStopping.remove(id) != nil
            pendingOutputBytes[id] = nil
            pendingActivityAt[id] = nil
            lastFocusAt[id] = nil
            outputHistory[id] = nil
            lastUserInputAt[id] = nil
            launchDates[id] = nil
            pendingIdleNotify.remove(id)
            idleNotifyArmed.remove(id)
            updateSession(id) { session in
                session.lastActivityAt = .now
                if wasManual {
                    session.activity = .stopped
                } else if exitCode == 0 {
                    session.activity = selectedSessionID == id ? .stopped : .attention
                } else {
                    session.activity = .failed
                }
            }
            if !wasManual, selectedSessionID != id {
                NSSound(named: "Glass")?.play()
            }
        }
        persist()
    }

    func sampleOutputActivity() {
        let previousOrder = pendingActivityAt.isEmpty ? [] : sortedSessions.map(\.id)
        for (id, date) in pendingActivityAt {
            let recentlyFocused = lastFocusAt[id].map {
                date.timeIntervalSince($0) < Self.focusGrace
            } ?? false
            let interacting = lastUserInputAt[id].map {
                date.timeIntervalSince($0) < Self.userInteractionGrace
            } ?? false
            if !recentlyFocused, !interacting {
                updateSessionQuietly(id) { $0.lastActivityAt = date }
            }
        }
        pendingActivityAt.removeAll()
        var working = workingSessionIDs
        for (id, runtime) in runtimes where runtime.isRunning {
            let bytes = pendingOutputBytes[id] ?? 0
            pendingOutputBytes[id] = 0
            let interacting = lastUserInputAt[id].map {
                Date().timeIntervalSince($0) < Self.userInteractionGrace
            } ?? false
            if interacting {
                outputHistory[id] = []
                idleTicks[id] = nil
                pendingIdleNotify.remove(id)
                idleNotifyArmed.remove(id)
                continue
            }
            var history = outputHistory[id] ?? []
            history.append(bytes)
            if history.count > 3 { history.removeFirst(history.count - 3) }
            outputHistory[id] = history
            let recentBytes = history.reduce(0, +)
            if working.contains(id) {
                pendingIdleNotify.remove(id)
                idleNotifyArmed.remove(id)
                if recentBytes < Self.idleByteThreshold {
                    let ticks = (idleTicks[id] ?? 0) + 1
                    idleTicks[id] = ticks
                    if ticks >= Self.idleTickLimit {
                        // Agent went quiet after working. Keep counting idle
                        // ticks; if the silence holds it is treated as
                        // "finished / waiting for input" and notifies.
                        working.remove(id)
                        pendingIdleNotify.insert(id)
                    }
                } else {
                    idleTicks[id] = 0
                }
            } else {
                let ticks = (idleTicks[id] ?? 0) + 1
                idleTicks[id] = ticks
                if recentBytes >= Self.workingByteThreshold {
                    idleTicks[id] = nil
                    pendingIdleNotify.remove(id)
                    idleNotifyArmed.remove(id)
                    working.insert(id)
                } else if pendingIdleNotify.contains(id),
                          ticks >= Self.idleNotifyTickLimit,
                          !idleNotifyArmed.contains(id) {
                    idleNotifyArmed.insert(id)
                    notifyAgentIdle(id)
                }
            }
        }
        for id in idleTicks.keys where runtimes[id]?.isRunning != true {
            idleTicks[id] = nil
            pendingIdleNotify.remove(id)
            idleNotifyArmed.remove(id)
        }
        if working != workingSessionIDs {
            workingSessionIDs = working
        }
        if !previousOrder.isEmpty, sortedSessions.map(\.id) != previousOrder {
            objectWillChange.send()
        }
    }

    private func refreshFirstPrompts() {
        let sessionSnapshot = sessions
        Task.detached(priority: .utility) { [weak self] in
            var promptsBySessionID: [UUID: String] = [:]
            var modelInfoBySessionID: [UUID: OpenCodeModelInfo] = [:]
            let historySessions = HistoryStore.listSessions()
            for session in sessionSnapshot {
                guard let bound = session.boundSessionID else { continue }
                if session.agent == .opencode {
                    let prompt = (try? OpenCodeHistoryStore.firstUserPrompt(sessionID: bound)) ?? nil
                    if let prompt, !prompt.isEmpty {
                        promptsBySessionID[session.id] = prompt
                    }
                    if let info = try? OpenCodeHistoryStore.modelInfo(sessionID: bound) {
                        modelInfoBySessionID[session.id] = info
                    }
                } else if let history = historySessions.first(where: {
                    $0.source == session.agent && $0.sessionID == bound
                }) {
                    promptsBySessionID[session.id] = history.title
                }
            }
            let directories = Array(Set(sessionSnapshot.map(\.workingDirectory)))
            let recentSessions = Self.groupRecentSessions(by: directories, from: historySessions)
            await self?.applyHistory(promptsBySessionID, modelInfoBySessionID, recentSessions)
        }
    }

    private nonisolated static func groupRecentSessions(
        by directories: [String],
        from sessions: [HistorySession]
    ) -> [String: [HistorySession]] {
        var grouped: [String: [HistorySession]] = [:]
        for directory in directories {
            grouped[directory] = sessions
                .filter { !$0.isSubagent && $0.directory == directory }
                .prefix(8)
                .map { $0 }
        }
        return grouped
    }

    @MainActor
    private func applyHistory(
        _ promptsBySessionID: [UUID: String],
        _ modelInfoBySessionID: [UUID: OpenCodeModelInfo],
        _ recentSessions: [String: [OpenCodeHistorySession]]
    ) {
        if promptsBySessionID != firstPrompts {
            firstPrompts = promptsBySessionID
        }
        if modelInfoBySessionID != self.modelInfoBySessionID {
            self.modelInfoBySessionID = modelInfoBySessionID
        }
        if idSequenceChanged(recentSessions, recentSessionsByDirectory) {
            recentSessionsByDirectory = recentSessions
        }
        detectOpenCodeBindings(recentSessions)
    }

    private func idSequenceChanged(
        _ lhs: [String: [OpenCodeHistorySession]],
        _ rhs: [String: [OpenCodeHistorySession]]
    ) -> Bool {
        if Set(lhs.keys) != Set(rhs.keys) { return true }
        for (directory, sessions) in lhs {
            if sessions.map(\.id) != (rhs[directory] ?? []).map(\.id) { return true }
        }
        return false
    }

    private func session(_ id: UUID) -> WorkspaceSession? {
        sessions.first { $0.id == id }
    }

    private func updateSession(_ id: UUID, change: (inout WorkspaceSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        // Notify AFTER the mutation so derived values (attention badge, etc.)
        // reflect the new state, not the previous one.
        change(&sessions[index])
        notifySessionsChanged()
    }

    private func updateSessionQuietly(_ id: UUID, change: (inout WorkspaceSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[index])
    }

    private func notifySessionsChanged() {
        objectWillChange.send()
        updateDockBadge()
    }

    private func uniqueTitle(from title: String) -> String {
        var candidate = "\(title) 2"
        var suffix = 3
        let names = Set(sessions.map(\.title))
        while names.contains(candidate) {
            candidate = "\(title) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func persist() {
        guard canPersistSafely else { return }
        persistence.save(sessions.filter { !$0.isTransient })
    }
}
