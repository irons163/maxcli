import XCTest
@testable import MaxCLI

final class SessionPersistenceTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "MaxCLI.SessionPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    private func makeSession(title: String, arguments: String = "", isTransient: Bool = false) -> WorkspaceSession {
        WorkspaceSession(
            title: title,
            agent: .codex,
            workingDirectory: "/tmp",
            arguments: arguments,
            isTransient: isTransient
        )
    }

    func testLoadWithoutAnyDataReturnsEmptyAndHealthy() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let result = SessionPersistence(defaults: defaults).load()

        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertFalse(result.decodeFailed)
    }

    func testLoadUsesBackupWhenPrimaryMissing() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SessionPersistence(defaults: defaults)

        // The backup is only written when a differing previous store exists.
        persistence.save([makeSession(title: "Backed Up")])
        persistence.save([makeSession(title: "Current")])
        defaults.removeObject(forKey: "maxcli.sessions.v1")

        let result = persistence.load()

        XCTAssertFalse(result.decodeFailed)
        XCTAssertEqual(result.sessions.map(\.title), ["Backed Up"])
    }

    func testSalvagesDecodableRowsFromPartiallyCorruptedStore() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let good: [String: Any] = [
            "id": UUID().uuidString,
            "title": "Good",
            "agent": "codex",
            "workingDirectory": "/tmp",
            "activity": "running",
        ]
        // Missing required fields, so the full-array decode fails but this row salvages.
        let bad: [String: Any] = ["title": "Bad"]
        defaults.set(
            try JSONSerialization.data(withJSONObject: [good, bad]),
            forKey: "maxcli.sessions.v1"
        )

        let result = SessionPersistence(defaults: defaults).load()

        XCTAssertEqual(result.sessions.map(\.title), ["Good"])
        XCTAssertEqual(result.sessions.first?.activity, .stopped)
        XCTAssertFalse(result.decodeFailed, "salvage counts as a healthy read")
    }

    func testFullyCorruptedPrimaryWithoutBackupFailsDecode() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "maxcli.sessions.v1")

        let result = SessionPersistence(defaults: defaults).load()

        XCTAssertTrue(result.decodeFailed)
        XCTAssertTrue(result.sessions.isEmpty)
    }

    func testTransientSessionsNeverPersist() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SessionPersistence(defaults: defaults)

        persistence.save([
            makeSession(title: "Keep"),
            makeSession(title: "Drop", isTransient: true),
        ])

        let loaded = persistence.load()
        XCTAssertEqual(loaded.sessions.map(\.title), ["Keep"])
    }

    func testOneShotArgumentsAreClearedOnLoad() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SessionPersistence(defaults: defaults)

        persistence.save([
            makeSession(title: "Login", arguments: "auth login"),
            makeSession(title: "Logout", arguments: " auth logout "),
            makeSession(title: "Normal", arguments: "--full-auto"),
        ])

        let titles = persistence.load().sessions.reduce(into: [:]) { $0[$1.title] = $1.arguments }
        XCTAssertEqual(titles["Login"], "")
        XCTAssertEqual(titles["Logout"], "")
        XCTAssertEqual(titles["Normal"], "--full-auto")
    }

    func testIdenticalSaveKeepsPreviousBackup() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SessionPersistence(defaults: defaults)

        let first = makeSession(title: "First")
        let second = makeSession(title: "Second")

        persistence.save([first])
        persistence.save([second])
        let backupAfterChange = try XCTUnwrap(defaults.data(forKey: "maxcli.sessions.v1.backup"))

        persistence.save([second])
        XCTAssertEqual(
            try XCTUnwrap(defaults.data(forKey: "maxcli.sessions.v1.backup")),
            backupAfterChange,
            "rewriting identical data must not clobber the previous backup"
        )
    }
}
