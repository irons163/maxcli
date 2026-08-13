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
}
