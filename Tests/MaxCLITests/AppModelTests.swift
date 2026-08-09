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
}
