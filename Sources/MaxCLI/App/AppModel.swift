import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [WorkspaceSession]
    @Published var selectedSessionID: UUID?
    @Published var layoutMode: LayoutMode = .focus
    @Published var searchText = ""
    @Published var agentFilter: AgentKind?
    @Published var isShowingNewSession = false
    @Published var isShowingQuickSwitcher = false
    @Published var isShowingHistory = false
    @Published var sidebarVisible = true
    @Published private(set) var workingSessionIDs: Set<UUID> = []
    @Published private(set) var firstPrompts: [UUID: String] = [:]

    private(set) var runtimes: [UUID: TerminalRuntime] = [:]
    let installedAgents: Set<AgentKind>
    private let persistence: SessionPersistence
    private var manuallyStopping = Set<UUID>()
    private var runtimeGenerations: [UUID: UUID] = [:]
    private var pendingOutputBytes: [UUID: Int] = [:]
    private var outputHistory: [UUID: [Int]] = [:]
    private var idleTicks: [UUID: Int] = [:]
    private static let workingByteThreshold = 400
    private static let idleByteThreshold = 100
    private static let idleTickLimit = 4

    init(
        persistence: SessionPersistence = SessionPersistence(),
        executableLocator: ExecutableLocator = ExecutableLocator()
    ) {
        let restoredSessions = persistence.load()
        self.persistence = persistence
        self.installedAgents = executableLocator.installedAgents
        self.sessions = restoredSessions
        self.selectedSessionID = restoredSessions.first?.id
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
            return lhs.createdAt < rhs.createdAt
        }
    }

    var runningCount: Int {
        sessions.filter { runtimes[$0.id]?.isRunning == true }.count
    }

    var attentionCount: Int {
        sessions.filter { $0.activity == .attention || $0.activity == .failed }.count
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
        guard let session = session(id) else { return }
        if runtimes[id]?.isRunning == true {
            select(id)
            return
        }

        runtimes[id] = nil
        updateSession(id) { $0.activity = .launching }
        let generation = UUID()
        runtimeGenerations[id] = generation
        let runtime = TerminalRuntime(sessionID: id) { [weak self] sessionID, event in
            guard self?.runtimeGenerations[sessionID] == generation else { return }
            self?.handle(event, for: sessionID)
        }
        runtimes[id] = runtime
        runtime.start(session: session)
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
            isPinned: copy.isPinned
        )
        addSession(copy)
    }

    func togglePin(_ id: UUID) {
        updateSession(id) { $0.isPinned.toggle() }
        persist()
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

    private func handle(_ event: TerminalRuntimeEvent, for id: UUID) {
        guard session(id) != nil else { return }
        switch event {
        case .started:
            guard sessions.first(where: { $0.id == id })?.activity == .launching else { return }
            updateSession(id) { $0.activity = .running }
        case let .output(bytes):
            pendingOutputBytes[id, default: 0] += bytes
            guard sessions.first(where: { $0.id == id })?.activity == .launching else { return }
            updateSession(id) { $0.activity = .running }
        case .bell:
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
            outputHistory[id] = nil
            updateSession(id) { session in
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

    private func sampleOutputActivity() {
        var working = workingSessionIDs
        for (id, runtime) in runtimes where runtime.isRunning {
            var history = outputHistory[id] ?? []
            history.append(pendingOutputBytes[id] ?? 0)
            if history.count > 3 { history.removeFirst(history.count - 3) }
            outputHistory[id] = history
            pendingOutputBytes[id] = 0
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
            await self?.applyFirstPrompts(promptsByDirectory)
        }
    }

    @MainActor
    private func applyFirstPrompts(_ promptsByDirectory: [String: String]) {
        var map: [UUID: String] = [:]
        for session in sessions {
            if let prompt = promptsByDirectory[session.workingDirectory], !prompt.isEmpty {
                map[session.id] = prompt
            }
        }
        if map != firstPrompts {
            firstPrompts = map
        }
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
