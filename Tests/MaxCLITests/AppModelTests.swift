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

    func testActiveModeSortsNewestActivityFirst() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.addSession(makeSession(title: "First"))
        model.addSession(makeSession(title: "Second"))

        model.layoutMode = .active
        model.select(model.sessions[1].id)
        model.handle(.bell, for: model.sessions[0].id)

        XCTAssertEqual(model.sortedSessions.map(\.title), ["First", "Second"])
    }

    func testActiveModeFallsBackToMostRecentActivation() throws {
        let suite = "MaxCLI.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = makeSession(title: "First")
        var second = makeSession(title: "Second")
        second.lastActivatedAt = first.lastActivatedAt.addingTimeInterval(60)
        SessionPersistence(defaults: defaults).save([first, second])

        let model = AppModel(
            persistence: SessionPersistence(defaults: defaults),
            executableLocator: ExecutableLocator()
        )
        model.layoutMode = .active

        XCTAssertEqual(model.sortedSessions.map(\.title), ["Second", "First"])
    }

    func testActiveModeKeepsPinnedFirst() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
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
        defer { defaults.removePersistentDomain(forName: suite) }
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
        defer { defaults.removePersistentDomain(forName: suite) }
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
        defer { defaults.removePersistentDomain(forName: suite) }
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
        defer { defaults.removePersistentDomain(forName: suite) }
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
}
