import XCTest
@testable import MaxCLI

@MainActor
final class AppModelTests: XCTestCase {
    func testManagesTwelveSessionsWithStableNumericOrder() throws {
        let suite = "MaxCLI.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            persistence: SessionPersistence(defaults: defaults),
            executableLocator: ExecutableLocator()
        )
        defer { closeAllSessions(model) }

        for index in 1...12 {
            model.addSession(
                WorkspaceSession(
                    title: "Session \(index)",
                    agent: .custom,
                    workingDirectory: FileManager.default.temporaryDirectory.path,
                    customCommand: "/bin/sleep 2"
                )
            )
        }

        XCTAssertEqual(model.sessions.count, 12)
        XCTAssertEqual(model.runtimes.count, 12)
        XCTAssertEqual(model.runningCount, 12)

        model.selectSession(at: 0)
        XCTAssertEqual(model.selectedSession?.title, "Session 1")
        model.selectSession(at: 8)
        XCTAssertEqual(model.selectedSession?.title, "Session 9")
        XCTAssertEqual(model.sortedSessions.map(\.title), (1...12).map { "Session \($0)" })

        model.stopAll()
        XCTAssertEqual(model.runningCount, 0)
        XCTAssertTrue(model.sessions.allSatisfy { $0.activity == .stopped })
    }

    private func makeModel() throws -> (AppModel, UserDefaults, String) {
        let suite = "MaxCLI.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = AppModel(
            persistence: SessionPersistence(defaults: defaults),
            executableLocator: ExecutableLocator()
        )
        return (model, defaults, suite)
    }

    private func makeSession(title: String) -> WorkspaceSession {
        WorkspaceSession(
            title: title,
            agent: .custom,
            workingDirectory: FileManager.default.temporaryDirectory.path,
            customCommand: "/bin/sleep 2"
        )
    }

    /// Adds one live session per given title using a long-running sleep command.
    private func makeModelWithRunningSession(
        titles: [String],
        command: String = "/bin/sleep 4"
    ) throws -> AppModel {
        let (model, defaults, suite) = try makeModel()
        defaults.removePersistentDomain(forName: suite)
        for title in titles {
            model.addSession(
                WorkspaceSession(
                    title: title,
                    agent: .custom,
                    workingDirectory: FileManager.default.temporaryDirectory.path,
                    customCommand: command
                )
            )
        }
        return model
    }

    private func makeModelWithRunningSession(
        title: String = "Session",
        command: String = "/bin/sleep 4"
    ) throws -> AppModel {
        try makeModelWithRunningSession(titles: [title], command: command)
    }

    func testActiveModeKeepsStableOrderWhenActivityChanges() throws {
        let model = try makeModelWithRunningSession(titles: ["First", "Second"])
        let ids = Dictionary(uniqueKeysWithValues: model.sessions.map { ($0.title, $0.id) })
        defer {
            closeAllSessions(model)
        }

        model.layoutMode = .active
        for id in [ids["Second"]!, ids["First"]!, ids["Second"]!, ids["First"]!] {
            model.handle(.output(100), for: id)
            model.sampleOutputActivity()
            XCTAssertEqual(model.activeSessions.map(\.title), ["First", "Second"])
        }

        model.handle(.bell, for: ids["Second"]!)
        XCTAssertEqual(model.activeSessions.map(\.title), ["First", "Second"])
    }

    func testActiveModeUsesManualOrderInsteadOfRecentActivation() throws {
        let suite = "MaxCLI.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = makeSession(title: "First")
        first.manualOrder = 0
        var second = makeSession(title: "Second")
        second.manualOrder = 1
        second.lastActivatedAt = first.lastActivatedAt.addingTimeInterval(60)
        SessionPersistence(defaults: defaults).save([first, second])

        let model = AppModel(
            persistence: SessionPersistence(defaults: defaults),
            executableLocator: ExecutableLocator()
        )
        model.layoutMode = .active

        XCTAssertEqual(model.sortedSessions.map(\.title), ["First", "Second"])
    }

    func testActiveModeKeepsPinnedFirst() throws {
        let (model, defaults, suite) = try makeModel()
        defer {
            defaults.removePersistentDomain(forName: suite)
            closeAllSessions(model)
        }
        model.addSession(makeSession(title: "First"))
        model.addSession(makeSession(title: "Second"))

        model.layoutMode = .active
        model.togglePin(model.sessions[0].id)
        model.select(model.sessions[1].id)
        model.handle(.bell, for: model.sessions[1].id)

        XCTAssertEqual(model.sortedSessions.map(\.title), ["First", "Second"])
    }

    func testFocusModeKeepsCreationOrder() throws {
        let (model, defaults, suite) = try makeModel()
        defer {
            defaults.removePersistentDomain(forName: suite)
            closeAllSessions(model)
        }
        model.addSession(makeSession(title: "First"))
        model.addSession(makeSession(title: "Second"))

        model.layoutMode = .active
        model.select(model.sessions[0].id)
        model.handle(.bell, for: model.sessions[0].id)
        model.layoutMode = .focus

        XCTAssertEqual(model.sortedSessions.map(\.title), ["First", "Second"])
    }

    func testOutputCountsAsUpdate() throws {
        let (model, defaults, suite) = try makeModel()
        defer {
            defaults.removePersistentDomain(forName: suite)
            closeAllSessions(model)
        }
        model.addSession(makeSession(title: "First"))
        let id = model.sessions[0].id
        let baseline = try XCTUnwrap(model.sessions[0].lastActivityAt)

        model.handle(.output(100), for: id)
        model.sampleOutputActivity()

        let updated = try XCTUnwrap(model.sessions[0].lastActivityAt)
        XCTAssertGreaterThan(updated, baseline)
    }

    func testFocusDoesNotCountAsUpdate() throws {
        let (model, defaults, suite) = try makeModel()
        defer {
            defaults.removePersistentDomain(forName: suite)
            closeAllSessions(model)
        }
        model.addSession(makeSession(title: "First"))
        let id = model.sessions[0].id
        let baseline = model.sessions[0].lastActivityAt

        model.handle(.output(100), for: id)
        model.handle(.focus(true), for: id)
        model.sampleOutputActivity()

        XCTAssertEqual(model.sessions[0].lastActivityAt, baseline)
    }

    func testTypingDoesNotCountAsUpdate() throws {
        let (model, defaults, suite) = try makeModel()
        defer {
            defaults.removePersistentDomain(forName: suite)
            closeAllSessions(model)
        }
        model.addSession(makeSession(title: "First"))
        let id = model.sessions[0].id
        let baseline = model.sessions[0].lastActivityAt

        model.handle(.output(100), for: id)
        model.handle(.userInput, for: id)
        model.sampleOutputActivity()

        XCTAssertEqual(model.sessions[0].lastActivityAt, baseline)
    }

    // MARK: - Persistence resilience

    func testLoadsLegacyFormatWithoutNewFields() throws {
        let suite = "MaxCLI.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let id = UUID().uuidString
        let now = Date().timeIntervalSinceReferenceDate
        let legacy: [[String: Any]] = [
            [
                "id": id,
                "title": "Legacy Session",
                "agent": "opencode",
                "workingDirectory": "/tmp/legacy",
                "arguments": "",
                "customCommand": "",
                "isPinned": false,
                "createdAt": now,
                "lastActivatedAt": now,
                "activity": "running",
            ]
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "maxcli.sessions.v1")

        let result = SessionPersistence(defaults: defaults).load()

        XCTAssertFalse(result.decodeFailed)
        let session = try XCTUnwrap(result.sessions.first)
        XCTAssertEqual(session.id.uuidString, id)
        XCTAssertEqual(session.title, "Legacy Session")
        XCTAssertEqual(session.agent, .opencode)
        XCTAssertEqual(session.workingDirectory, "/tmp/legacy")
        XCTAssertEqual(session.activity, .stopped)
        XCTAssertFalse(session.isTransient)
        XCTAssertFalse(session.isPinned)
        XCTAssertNil(session.manualOrder)
    }

    func testSavePreservesPreviousDataAsBackup() throws {
        let suite = "MaxCLI.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SessionPersistence(defaults: defaults)

        persistence.save([makeSession(title: "First")])
        persistence.save([makeSession(title: "Second")])

        let result = persistence.load()
        XCTAssertEqual(result.sessions.map(\.title), ["Second"])
        let backupData = try XCTUnwrap(defaults.data(forKey: "maxcli.sessions.v1.backup"))
        let backup = try JSONDecoder().decode([WorkspaceSession].self, from: backupData)
        XCTAssertEqual(backup.map(\.title), ["First"])
    }

    func testLoadFallsBackToBackupWhenPrimaryCorrupted() throws {
        let suite = "MaxCLI.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SessionPersistence(defaults: defaults)

        persistence.save([makeSession(title: "First")])
        persistence.save([makeSession(title: "Second")])
        defaults.set(Data("not json".utf8), forKey: "maxcli.sessions.v1")

        let result = persistence.load()

        XCTAssertTrue(result.decodeFailed)
        XCTAssertEqual(result.sessions.map(\.title), ["First"])
    }

    func testAppModelRefusesToOverwriteUndecodableStore() throws {
        let suite = "MaxCLI.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let raw = Data("not json".utf8)
        defaults.set(raw, forKey: "maxcli.sessions.v1")

        let model = AppModel(
            persistence: SessionPersistence(defaults: defaults),
            executableLocator: ExecutableLocator()
        )
        XCTAssertTrue(model.sessions.isEmpty)

        model.close(UUID())
        XCTAssertEqual(defaults.data(forKey: "maxcli.sessions.v1"), raw)

        model.addSession(makeSession(title: "New"))
        let loaded = SessionPersistence(defaults: defaults).load()
        XCTAssertEqual(loaded.sessions.map(\.title), ["New"])
    }

    // MARK: - Filtering & search

    func testVisibleSessionsFilterBySearchTextAndAgent() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.addSession(
            WorkspaceSession(
                title: "Web",
                agent: .codex,
                workingDirectory: "/tmp/web-project",
                arguments: "--watch"
            )
        )
        model.addSession(makeSession(title: "Docs"))

        XCTAssertEqual(Set(model.visibleSessions.map(\.title)), ["Web", "Docs"])

        model.searchText = "web"
        XCTAssertEqual(model.visibleSessions.map(\.title), ["Web"])

        model.searchText = "  WEB  "
        XCTAssertEqual(model.visibleSessions.map(\.title), ["Web"], "search trims and ignores case")

        model.searchText = "--watch"
        XCTAssertEqual(model.visibleSessions.map(\.title), ["Web"], "search covers launch command")

        model.searchText = "/tmp/web-project"
        XCTAssertEqual(model.visibleSessions.map(\.title), ["Web"], "search covers directory")

        model.searchText = ""
        model.agentFilter = .custom
        XCTAssertEqual(Set(model.visibleSessions.map(\.title)), ["Docs"])

        model.searchText = "web"
        XCTAssertTrue(model.visibleSessions.isEmpty, "agent filter and search compose")
    }

    func testActiveSessionsIncludesLiveStatesOnly() throws {
        let model = try makeModelWithRunningSession(titles: ["Live", "Needs", "Dead"])
        defer { closeAllSessions(model) }
        let ids = Dictionary(uniqueKeysWithValues: model.sessions.map { ($0.title, $0.id) })

        model.handle(.bell, for: ids["Needs"]!)
        model.handle(.terminated(1), for: ids["Dead"]!)

        XCTAssertEqual(Set(model.activeSessions.map(\.title)), ["Live", "Needs"])
        XCTAssertEqual(
            model.attentionCount,
            2,
            "attention count covers both attention and failed states"
        )
    }

    func testRepeatedBackgroundBellDoesNotRetriggerAttention() throws {
        let model = try makeModelWithRunningSession(titles: ["Live", "Other"])
        defer { closeAllSessions(model) }
        let ids = Dictionary(uniqueKeysWithValues: model.sessions.map { ($0.title, $0.id) })
        let liveID = try XCTUnwrap(ids["Live"])
        model.select(ids["Other"]!)

        model.handle(.bell, for: liveID)
        let firstBellAt = try XCTUnwrap(model.sessions.first { $0.id == liveID }?.lastActivityAt)
        XCTAssertEqual(model.sessions.first { $0.id == liveID }?.activity, .attention)

        model.handle(.bell, for: liveID)

        XCTAssertEqual(
            model.sessions.first { $0.id == liveID }?.lastActivityAt,
            firstBellAt,
            "repeated bell events do not republish an already-attention session"
        )

        model.select(liveID)
        model.select(ids["Other"]!)
        model.handle(.bell, for: liveID)
        XCTAssertGreaterThan(
            model.sessions.first { $0.id == liveID }?.lastActivityAt ?? .distantPast,
            firstBellAt,
            "a new bell after attention is cleared is handled again"
        )
    }

    // MARK: - Manual ordering

    func testMoveSessionReordersUnpinnedSessionsAndPersistsOrder() throws {
        let (model, defaults, suite) = try makeModel()
        defer {
            defaults.removePersistentDomain(forName: suite)
            closeAllSessions(model)
        }
        for title in ["A", "B", "C"] {
            model.addSession(makeSession(title: title))
        }
        let ids = Dictionary(uniqueKeysWithValues: model.sessions.map { ($0.title, $0.id) })

        model.moveSession(ids["C"]!, before: ids["A"]!)
        XCTAssertEqual(model.sortedSessions.map(\.title), ["C", "A", "B"])

        model.moveSession(ids["A"]!, relativeTo: ids["B"]!, after: true)
        XCTAssertEqual(model.sortedSessions.map(\.title), ["C", "B", "A"])

        let stored = SessionPersistence(defaults: defaults).load().sessions
            .sorted { ($0.manualOrder ?? .max) < ($1.manualOrder ?? .max) }
        XCTAssertEqual(stored.map(\.title), ["C", "B", "A"], "manual order survives relaunch")
    }

    func testMoveSessionKeepsPinnedSessionsOutOfTheFlow() throws {
        let model = try makeModelWithRunningSession(titles: ["Pinned", "A", "B"])
        defer { closeAllSessions(model) }
        let ids = Dictionary(uniqueKeysWithValues: model.sessions.map { ($0.title, $0.id) })
        model.togglePin(ids["Pinned"]!)

        model.moveSession(ids["B"]!, before: ids["A"]!)

        XCTAssertEqual(model.sortedSessions.map(\.title), ["Pinned", "B", "A"])
        XCTAssertNil(
            model.sessions.first { $0.title == "Pinned" }?.manualOrder,
            "pinned rows sort by pin state, untouched by drag reorder"
        )
    }

    func testMoveSessionIgnoresSelfReferenceAndUnknownIDs() throws {
        let model = try makeModelWithRunningSession(titles: ["A", "B"])
        defer { closeAllSessions(model) }
        let ids = Dictionary(uniqueKeysWithValues: model.sessions.map { ($0.title, $0.id) })

        model.moveSession(ids["A"]!, relativeTo: ids["A"]!, after: true)
        model.moveSession(UUID(), relativeTo: ids["A"]!, after: true)
        model.moveSession(ids["A"]!, relativeTo: UUID(), after: true)

        XCTAssertEqual(model.sortedSessions.map(\.title), ["A", "B"])
    }

    // MARK: - Duplicate & unique titles

    func testDuplicateSelectedCopiesFieldsWithUniqueTitle() throws {
        let model = try makeModelWithRunningSession(title: "API")
        defer { closeAllSessions(model) }
        model.togglePin(model.sessions[0].id)
        let original = model.sessions[0]

        model.duplicateSelected()
        model.duplicateSelected()

        XCTAssertEqual(model.sessions.count, 3)
        XCTAssertEqual(
            model.sortedSessions.map(\.title),
            ["API", "API 2", "API 2 2"],
            "each duplicate bases its unique title on the current selection"
        )
        for copy in model.sessions.dropFirst() {
            XCTAssertEqual(copy.workingDirectory, original.workingDirectory)
            XCTAssertEqual(copy.arguments, original.arguments)
            XCTAssertEqual(copy.customCommand, original.customCommand)
            XCTAssertEqual(copy.isPinned, original.isPinned)
            XCTAssertEqual(copy.agent, original.agent)
            XCTAssertTrue(
                [.launching, .running].contains(copy.activity),
                "duplicate starts its own live process"
            )
            XCTAssertFalse(copy.isTransient)
        }
    }

    // MARK: - Selection navigation

    func testSelectNextWrapsAroundInBothDirections() throws {
        let model = try makeModelWithRunningSession(titles: ["A", "B", "C"])
        defer { closeAllSessions(model) }

        model.selectSession(at: 2)
        model.selectNext(offset: 1)
        XCTAssertEqual(model.selectedSession?.title, "A")

        model.selectNext(offset: -1)
        XCTAssertEqual(model.selectedSession?.title, "C")

        model.selectNext(offset: 3)
        XCTAssertEqual(model.selectedSession?.title, "C", "full-cycle offset lands back on selection")
    }

    func testSelectionGuardsAgainstInvalidInput() throws {
        let model = try makeModelWithRunningSession(title: "Solo")
        defer { closeAllSessions(model) }
        let selected = model.selectedSessionID

        model.select(UUID())
        XCTAssertEqual(model.selectedSessionID, selected)

        model.selectSession(at: 99)
        XCTAssertEqual(model.selectedSessionID, selected)

        model.selectSession(at: -1)
        XCTAssertEqual(model.selectedSessionID, selected)

        model.togglePin(UUID())
        model.stop(UUID())
        XCTAssertEqual(model.selectedSessionID, selected)
        XCTAssertEqual(model.sessions.count, 1)
    }

    func testOperationsOnEmptyModelAreHarmless() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        model.selectNext(offset: 1)
        model.selectSession(at: 0)
        model.duplicateSelected()
        model.stopAll()
        model.restartStopped()

        XCTAssertNil(model.selectedSessionID)
        XCTAssertTrue(model.visibleSessions.isEmpty)
    }

    func testSelectClearsAttentionDependingOnRuntimeState() throws {
        let suite = "MaxCLI.AppModelTests.Dormant.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var dormant = makeSession(title: "Dormant")
        dormant.activity = .attention
        SessionPersistence(defaults: defaults).save([dormant])
        let reloaded = AppModel(
            persistence: SessionPersistence(defaults: defaults),
            executableLocator: ExecutableLocator()
        )

        reloaded.select(reloaded.sessions[0].id)
        XCTAssertEqual(reloaded.sessions[0].activity, .stopped, "no runtime means stopped")

        let live = try makeModelWithRunningSession(titles: ["Live", "Other"])
        defer { closeAllSessions(live) }
        let ids = Dictionary(uniqueKeysWithValues: live.sessions.map { ($0.title, $0.id) })
        live.select(ids["Other"]!)
        live.handle(.bell, for: ids["Live"]!)
        XCTAssertEqual(live.sessions[0].activity, .attention)
        live.select(ids["Live"]!)
        XCTAssertEqual(
            live.sessions.filter { $0.id == ids["Live"] }.first?.activity,
            .running,
            "a live runtime restores running"
        )
    }

    // MARK: - Close semantics

    func testCloseRemovesRuntimeAndReselectsFirstRemaining() throws {
        let model = try makeModelWithRunningSession(titles: ["A", "B", "C"])
        defer { closeAllSessions(model) }
        let middleID = try XCTUnwrap(model.sessions.first { $0.title == "B" }?.id)
        model.select(middleID)
        XCTAssertNotNil(model.runtime(for: middleID))

        model.close(middleID)

        XCTAssertNil(model.runtime(for: middleID))
        XCTAssertFalse(model.sessions.contains { $0.id == middleID })
        XCTAssertEqual(model.selectedSession?.title, "A")
    }

    func testClosingUnknownIDIsHarmless() throws {
        let model = try makeModelWithRunningSession(title: "Solo")
        defer { closeAllSessions(model) }
        let count = model.sessions.count
        let selected = model.selectedSessionID

        model.close(UUID())

        XCTAssertEqual(model.sessions.count, count)
        XCTAssertEqual(model.selectedSessionID, selected)
    }

    // MARK: - Runtime event state machine

    func testTerminatedEventsDriveActivityStates() throws {
        let model = try makeModelWithRunningSession(titles: ["S1", "S2", "S3"])
        defer { closeAllSessions(model) }
        let ids = Dictionary(uniqueKeysWithValues: model.sessions.map { ($0.title, $0.id) })

        model.handle(.terminated(0), for: ids["S1"]!)
        XCTAssertEqual(
            model.sessions.first { $0.id == ids["S1"] }?.activity,
            .attention,
            "background clean exits ask for attention"
        )

        model.select(ids["S2"]!)
        model.handle(.terminated(0), for: ids["S2"]!)
        XCTAssertEqual(
            model.sessions.first { $0.id == ids["S2"] }?.activity,
            .stopped,
            "clean exit on the selected session just stops"
        )

        model.handle(.terminated(1), for: ids["S3"]!)
        XCTAssertEqual(
            model.sessions.first { $0.id == ids["S3"] }?.activity,
            .failed,
            "nonzero exits fail loudly even when selected"
        )
    }

    func testManualStopEndsAsStoppedRegardlessOfSignal() async throws {
        let model = try makeModelWithRunningSession(title: "Killed")
        defer { closeAllSessions(model) }
        let id = model.sessions[0].id

        model.stop(id)

        let stopped = expectation(description: "manual stop lands on .stopped")
        Task { @MainActor in
            while model.sessions.first?.activity != .stopped {
                try? await Task.sleep(for: .milliseconds(50))
            }
            stopped.fulfill()
        }
        await fulfillment(of: [stopped], timeout: 10)

        XCTAssertEqual(
            model.sessions[0].activity,
            .stopped,
            "SIGTERM from a manual stop must never surface as failed"
        )
    }

    func testStopWithoutRuntimeMarksStopped() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        model.stop(UUID())
        model.stopAll()
        model.restartStopped()

        XCTAssertTrue(model.sessions.isEmpty)
    }

    func testTransientSessionClosesItselfOnTermination() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        model.runOpenCodeAuth("login")
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions[0].title, "opencode login")
        XCTAssertTrue(model.sessions[0].isTransient)
        XCTAssertTrue(
            SessionPersistence(defaults: defaults).load().sessions.isEmpty,
            "transient auth runs never persist"
        )

        model.handle(.terminated(0), for: model.sessions[0].id)
        XCTAssertTrue(model.sessions.isEmpty, "one-shot sessions vanish after exiting")
    }

    func testOutputDoesNotDowngradeRunningSession() throws {
        let model = try makeModelWithRunningSession(title: "Fresh")
        defer { closeAllSessions(model) }
        let id = model.sessions[0].id

        model.handle(.started, for: id)
        model.handle(.output(64), for: id)

        XCTAssertEqual(model.sessions[0].activity, .running)
    }

    func testEventsForUnknownSessionsAreIgnored() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        model.handle(.started, for: UUID())
        model.handle(.output(100), for: UUID())
        model.handle(.terminated(0), for: UUID())
        model.handle(.directory("/tmp"), for: UUID())
        model.handle(.bell, for: UUID())
        model.handle(.userInput, for: UUID())
        model.handle(.focus(true), for: UUID())
        model.handle(.title("ignored"), for: UUID())

        XCTAssertTrue(model.sessions.isEmpty)
    }

    func testDirectoryEventUpdatesWorkingDirectoryOnlyForExistingPaths() throws {
        let model = try makeModelWithRunningSession(title: "Navigator")
        defer { closeAllSessions(model) }
        let id = model.sessions[0].id

        let realDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("maxcli-cwd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: realDir.path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: realDir.path) }

        model.handle(.directory(realDir.path), for: id)
        XCTAssertEqual(model.sessions[0].workingDirectory, realDir.path)

        model.handle(.directory("/nonexistent-maxcli-path"), for: id)
        XCTAssertEqual(model.sessions[0].workingDirectory, realDir.path)
    }

    // MARK: - OpenCode binding

    func testBindAppliesImmediatelyWhenRuntimeIsStopped() throws {
        let suite = "MaxCLI.AppModelTests.Bind.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SessionPersistence(defaults: defaults).save([
            WorkspaceSession(
                title: "OC",
                agent: .opencode,
                workingDirectory: "/tmp/proj"
            )
        ])
        let model = AppModel(
            persistence: SessionPersistence(defaults: defaults),
            executableLocator: ExecutableLocator()
        )
        let id = model.sessions[0].id

        model.bindOpenCodeSession(id, to: "sess_bound")
        XCTAssertEqual(model.sessions[0].opencodeSessionID, "sess_bound")
        XCTAssertNil(model.pendingBindRestart)
        XCTAssertEqual(
            SessionPersistence(defaults: defaults).load().sessions[0].opencodeSessionID,
            "sess_bound",
            "binding persists immediately when nothing is running"
        )

        model.bindOpenCodeSession(id, to: "sess_bound")
        XCTAssertNil(model.pendingBindRestart, "binding to the same value is a no-op")

        model.bindOpenCodeSession(id, to: nil)
        XCTAssertNil(model.sessions[0].opencodeSessionID)
    }

    func testBindWhileRunningWaitsForConfirmOrCancel() throws {
        let model = try makeModelWithRunningSession(command: "/bin/sleep 6")
        defer { closeAllSessions(model) }
        let id = model.sessions[0].id
        let runtimeBefore = model.runtime(for: id)

        model.bindOpenCodeSession(id, to: "sess_deferred")
        XCTAssertNotNil(model.pendingBindRestart)
        XCTAssertEqual(model.pendingBindRestart?.sessionID, id)
        XCTAssertNil(model.sessions[0].opencodeSessionID, "binding waits for restart confirmation")

        model.cancelBindRestart()
        XCTAssertNil(model.pendingBindRestart)
        XCTAssertNil(model.sessions[0].opencodeSessionID)

        model.bindOpenCodeSession(id, to: "sess_applied")
        model.confirmBindRestart()

        XCTAssertEqual(model.sessions[0].opencodeSessionID, "sess_applied")
        XCTAssertNil(model.pendingBindRestart)
        XCTAssertFalse(model.runtime(for: id) === runtimeBefore, "confirm restarts the session")
    }

    // MARK: - Bulk operations

    func testStopAllThenRestartStoppedRestoresEverything() throws {
        let model = try makeModelWithRunningSession(titles: ["R1", "R2"])
        defer { closeAllSessions(model) }

        model.stopAll()
        XCTAssertEqual(model.runningCount, 0)
        XCTAssertTrue(model.sessions.allSatisfy { $0.activity == .stopped })

        model.restartStopped()
        XCTAssertEqual(model.runningCount, 2)
    }

    // MARK: - Localization

    func testLanguageSelectionPersistsAndLocalizesStrings() throws {
        let standardKey = "maxcli.language.v1"
        let original = UserDefaults.standard.object(forKey: standardKey)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: standardKey)
            } else {
                UserDefaults.standard.removeObject(forKey: standardKey)
            }
        }

        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        model.language = .ja
        XCTAssertEqual(UserDefaults.standard.string(forKey: standardKey), "ja")

        model.language = .en
        XCTAssertEqual(model.tr("menu.layout.focus"), "Focus")
        XCTAssertEqual(model.trf("pane.startAgent", "Codex"), "Start Codex")

        model.language = .zhHant
        XCTAssertEqual(model.tr("menu.layout.focus"), "專注")
        XCTAssertEqual(model.trf("pane.startAgent", "Codex"), "啟動 Codex")

        model.language = .system
        XCTAssertEqual(UserDefaults.standard.string(forKey: standardKey), "system")
    }
}

@MainActor
private func closeAllSessions(_ model: AppModel) {
    for session in Array(model.sessions) {
        model.close(session.id)
    }
}
