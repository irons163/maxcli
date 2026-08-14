import XCTest
@testable import MaxCLI

final class OpenCodeHistoryStoreTests: XCTestCase {
    private func requireDatabase() throws -> URL {
        let url = try XCTUnwrap(OpenCodeHistoryStore.databaseURL, "opencode database not found; skipping")
        return url
    }

    func testListSessionsReadsFullHistory() throws {
        _ = try requireDatabase()

        let sessions = try OpenCodeHistoryStore.listSessions()

        XCTAssertFalse(sessions.isEmpty, "expected at least one opencode session")
        for session in sessions {
            XCTAssertFalse(session.id.isEmpty)
            XCTAssertFalse(session.title.isEmpty)
            XCTAssertTrue(session.messageCount >= 0)
        }
    }

    func testTranscriptContainsFullMessageHistory() throws {
        _ = try requireDatabase()

        let sessions = try OpenCodeHistoryStore.listSessions()
        guard let long = sessions.first(where: { $0.messageCount > 10 }) ?? sessions.first else {
            throw XCTSkip("no session with enough messages")
        }

        let transcript = try OpenCodeHistoryStore.transcript(for: long.id)

        XCTAssertEqual(transcript.messages.count, long.messageCount)
        XCTAssertEqual(transcript.session.id, long.id)

        let displayable = transcript.messages.flatMap(\.parts).filter(\.isDisplayable)
        XCTAssertFalse(displayable.isEmpty, "expected displayable parts")
        XCTAssertTrue(
            displayable.contains { $0.kind == .text && $0.text?.isEmpty == false },
            "expected at least one non-empty text part"
        )

        let texts = displayable.compactMap(\.text)
        let joined = texts.joined(separator: "\n")
        XCTAssertTrue(joined.count > 0)
        XCTAssertLessThan(joined.count, 10_000_000)
    }
}
