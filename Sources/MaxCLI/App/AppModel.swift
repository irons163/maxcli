import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    struct PendingBindRestart {
        let sessionID: UUID
        let target: String?
    }

    @Published private(set) var sessions: [WorkspaceSession]
    @Published var selectedSessionID: UUID?
    @Published var layoutMode: LayoutMode = .focus
    @Published var searchText = ""
    @Published var agentFilter: AgentKind?
    @Published var isShowingNewSession = false
    @Published var isShowingQuickSwitcher = false
    @Published var isShowingHistory = false
    @Published var sidebarVisible = true
    @Published var language: AppLanguage
    @Published private(set) var workingSessionIDs: Set<UUID> = []
    @Published private(set) var firstPrompts: [UUID: String] = [:]
    @Published private(set) var recentSessionsByDirectory: [String: [OpenCodeHistorySession]] = [:]
    @Published var pendingBindRestart: PendingBindRestart?

    private(set) var runtimes: [UUID: TerminalRuntime] = [:]
    let installedAgents: Set<AgentKind>
    private let persistence: SessionPersistence
    private var cancellables = Set<AnyCancellable>()
    private var manuallyStopping = Set<UUID>()
    private var runtimeGenerations: [UUID: UUID] = [:]
    private var pendingOutputBytes: [UUID: Int] = [:]
    private var pendingActivityAt: [UUID: Date] = [:]
    private var lastFocusAt: [UUID: Date] = [:]
    private var outputHistory: [UUID: [Int]] = [:]
    private var idleTicks: [UUID: Int] = [:]
    private var lastUserInputAt: [UUID: Date] = [:]
    private var launchDates: [UUID: Date] = [:]
    private static let workingByteThreshold = 400
    private static let idleByteThreshold = 100
    private static let idleTickLimit = 4
    private static let userInteractionGrace: TimeInterval = 1.5
    private static let focusGrace: TimeInterval = 2.0
    private static let languageKey = "maxcli.language.v1"

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
        let restoredSessions = persistence.load()
        self.persistence = persistence
        self.installedAgents = executableLocator.installedAgents
        self.sessions = restoredSessions
        self.selectedSessionID = restoredSessions.first?.id
        let storedLanguage = UserDefaults.standard.string(forKey: Self.languageKey)
            .flatMap(AppLanguage.init(rawValue:))
        self.language = storedLanguage ?? .system
        $language
            .sink { language in UserDefaults.standard.setValue(language.rawValue, forKey: Self.languageKey) }
            .store(in: &cancellables)
        $sessions
            .sink { [weak self] _ in self?.updateDockBadge() }
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
            switch layoutMode {
            case .active:
                let lhsTime = lhs.lastActivityAt ?? lhs.lastActivatedAt
                let rhsTime = rhs.lastActivityAt ?? rhs.lastActivatedAt
                if lhsTime != rhsTime { return lhsTime > rhsTime }
                return lhs.createdAt < rhs.createdAt
            case .focus, .grid:
                return lhs.createdAt < rhs.createdAt
            }
        }
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

    func runtime(for sessionID: UUID) -> TerminalRuntime? {
        runtimes[sessionID]
    }

    func addSession(_ session: WorkspaceSession) {
        var newSession = session
        newSession.activity = .launching
        sessions.append(newSession)
        select(newSession.id)
        start(newSession.id)
        persist()
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
        let sessions = sortedSessions
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
            isPinned: copy.isPinned
        )
        addSession(copy)
    }

    func togglePin(_ id: UUID) {
        updateSession(id) { $0.isPinned.toggle() }
        persist()
    }

    func bindOpenCodeSession(_ id: UUID, to opencodeSessionID: String?) {
        guard let session = session(id), session.opencodeSessionID != opencodeSessionID else { return }
        if runtimes[id]?.isRunning == true {
            pendingBindRestart = PendingBindRestart(sessionID: id, target: opencodeSessionID)
            return
        }
        applyOpenCodeBinding(id, to: opencodeSessionID)
    }

    func confirmBindRestart() {
        guard let pending = pendingBindRestart else { return }
        pendingBindRestart = nil
        applyOpenCodeBinding(pending.sessionID, to: pending.target)
        restart(pending.sessionID)
    }

    func cancelBindRestart() {
        pendingBindRestart = nil
    }

    private func applyOpenCodeBinding(_ id: UUID, to opencodeSessionID: String?) {
        updateSession(id) { $0.opencodeSessionID = opencodeSessionID }
        persist()
    }

    private func autoBindOpenCodeSessionIfNeeded(_ id: UUID) {
        guard let session = session(id),
              session.agent == .opencode,
              session.opencodeSessionID == nil,
              !sessions.contains(where: { $0.id != id && $0.workingDirectory == session.workingDirectory })
        else { return }
        guard let latestID = try? OpenCodeHistoryStore.latestSessionID(directory: session.workingDirectory) else { return }
        updateSession(id) { $0.opencodeSessionID = latestID }
        persist()
    }
    private func detectOpenCodeBindings(_ recentSessions: [String: [OpenCodeHistorySession]]) {
        var taken = Set(sessions.compactMap(\.opencodeSessionID))
        let unbound = sessions
            .filter {
                $0.agent == .opencode
                    && $0.opencodeSessionID == nil
                    && runtimes[$0.id]?.isRunning == true
            }
            .sorted {
                (launchDates[$0.id] ?? .distantPast) < (launchDates[$1.id] ?? .distantPast)
            }
        for session in unbound {
            guard let launch = launchDates[session.id] else { continue }
            let match = recentSessions[session.workingDirectory]?
                .filter {
                    !$0.isSubagent
                    && !taken.contains($0.id)
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
                updateSession(session.id) { $0.opencodeSessionID = match.id }
                taken.insert(match.id)
                persist()
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
        let command = "cd \(CommandBuilder.shellEscape(session.workingDirectory)) && \(session.launchCommand)"
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
            guard sessions.first(where: { $0.id == id })?.activity == .launching else { return }
            updateSession(id) { $0.activity = .running }
        case .userInput:
            lastUserInputAt[id] = .now
            return
        case .focus:
            lastFocusAt[id] = .now
            return
        case .bell:
            updateSession(id) { $0.lastActivityAt = .now }
            guard selectedSessionID != id else { return }
            updateSession(id) { $0.activity = .attention }
            NSSound(named: "Glass")?.play()
        case let .directory(directory):
            guard FileManager.default.fileExists(atPath: directory) else { return }
            updateSession(id) { $0.workingDirectory = directory }
        case .title:
            break
        case let .terminated(exitCode):
            let wasManual = manuallyStopping.remove(id) != nil
            pendingOutputBytes[id] = nil
            pendingActivityAt[id] = nil
            lastFocusAt[id] = nil
            outputHistory[id] = nil
            lastUserInputAt[id] = nil
            launchDates[id] = nil
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
        for (id, date) in pendingActivityAt {
            let recentlyFocused = lastFocusAt[id].map {
                date.timeIntervalSince($0) < Self.focusGrace
            } ?? false
            let interacting = lastUserInputAt[id].map {
                date.timeIntervalSince($0) < Self.userInteractionGrace
            } ?? false
            if !recentlyFocused, !interacting {
                updateSession(id) { $0.lastActivityAt = date }
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
                continue
            }
            var history = outputHistory[id] ?? []
            history.append(bytes)
            if history.count > 3 { history.removeFirst(history.count - 3) }
            outputHistory[id] = history
            let recentBytes = history.reduce(0, +)
            if working.contains(id) {
                if recentBytes < Self.idleByteThreshold {
                    let ticks = (idleTicks[id] ?? 0) + 1
                    idleTicks[id] = ticks
                    if ticks >= Self.idleTickLimit {
                        working.remove(id)
                        idleTicks[id] = nil
                    }
                } else {
                    idleTicks[id] = 0
                }
            } else if recentBytes >= Self.workingByteThreshold {
                working.insert(id)
            }
        }
        for id in idleTicks.keys where runtimes[id]?.isRunning != true {
            idleTicks[id] = nil
        }
        if working != workingSessionIDs {
            workingSessionIDs = working
        }
    }

    private func refreshFirstPrompts() {
        let directories = Array(Set(sessions.map(\.workingDirectory)))
        Task.detached(priority: .utility) { [weak self] in
            var promptsByDirectory: [String: String] = [:]
            for directory in directories {
                let prompt = (try? OpenCodeHistoryStore.firstUserPrompt(directory: directory)) ?? nil
                promptsByDirectory[directory] = prompt ?? ""
            }
            let recentSessions = Self.groupRecentSessions(by: directories)
            await self?.applyHistory(promptsByDirectory, recentSessions)
        }
    }

    private nonisolated static func groupRecentSessions(by directories: [String]) -> [String: [OpenCodeHistorySession]] {
        guard let sessions = try? OpenCodeHistoryStore.listSessions() else { return [:] }
        var grouped: [String: [OpenCodeHistorySession]] = [:]
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
        _ promptsByDirectory: [String: String],
        _ recentSessions: [String: [OpenCodeHistorySession]]
    ) {
        var map: [UUID: String] = [:]
        for session in sessions {
            if let prompt = promptsByDirectory[session.workingDirectory], !prompt.isEmpty {
                map[session.id] = prompt
            }
        }
        if map != firstPrompts {
            firstPrompts = map
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
        change(&sessions[index])
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
        persistence.save(sessions)
    }
}
