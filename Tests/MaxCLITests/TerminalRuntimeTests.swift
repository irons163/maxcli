import XCTest
@testable import MaxCLI

@MainActor
final class TerminalRuntimeTests: XCTestCase {
    func testRunsCommandInsideAPseudoTerminal() async {
        let terminated = expectation(description: "PTY command terminated")
        var observedStarted = false
        var observedOutput = false
        var observedExitCode: Int32?

        let runtime = TerminalRuntime(sessionID: UUID()) { _, event in
            switch event {
            case .started:
                observedStarted = true
            case .output:
                observedOutput = true
            case let .terminated(code):
                observedExitCode = code
                terminated.fulfill()
            default:
                break
            }
        }
        let session = WorkspaceSession(
            title: "PTY test",
            agent: .custom,
            workingDirectory: FileManager.default.temporaryDirectory.path,
            customCommand: "/usr/bin/printf MAXCLI_PTY_READY"
        )

        runtime.start(session: session)
        await fulfillment(of: [terminated], timeout: 5)

        XCTAssertTrue(observedStarted)
        XCTAssertTrue(observedOutput)
        XCTAssertEqual(observedExitCode, 0)
        XCTAssertFalse(runtime.isRunning)
    }

    func testRunsTwelveConcurrentPseudoTerminals() async {
        let sessionCount = 12
        let allTerminated = expectation(description: "All PTYs terminated")
        allTerminated.expectedFulfillmentCount = sessionCount
        var terminatedIDs = Set<UUID>()
        var runtimes: [TerminalRuntime] = []

        for index in 0..<sessionCount {
            let id = UUID()
            let runtime = TerminalRuntime(sessionID: id) { sessionID, event in
                guard case .terminated = event else { return }
                terminatedIDs.insert(sessionID)
                allTerminated.fulfill()
            }
            let session = WorkspaceSession(
                id: id,
                title: "Concurrent \(index + 1)",
                agent: .custom,
                workingDirectory: FileManager.default.temporaryDirectory.path,
                customCommand: "/bin/sleep 0.2"
            )
            runtimes.append(runtime)
            runtime.start(session: session)
        }

        XCTAssertEqual(runtimes.filter(\.isRunning).count, sessionCount)
        await fulfillment(of: [allTerminated], timeout: 8)
        XCTAssertEqual(terminatedIDs.count, sessionCount)
        XCTAssertTrue(runtimes.allSatisfy { !$0.isRunning })
    }
}
