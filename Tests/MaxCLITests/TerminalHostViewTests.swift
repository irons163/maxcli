import XCTest
@testable import MaxCLI

@MainActor
final class TerminalHostViewTests: XCTestCase {
    func testResizeSetsFrameSizeAndZeroOrigin() {
        let host = TerminalHostView()
        host.frame = NSRect(x: 10, y: 20, width: 100, height: 50)

        TerminalHostView.resize(host, to: NSSize(width: 300, height: 200))

        XCTAssertEqual(host.frame.size, NSSize(width: 300, height: 200))
        XCTAssertEqual(host.frame.origin, .zero)
    }

    func testResizeIsIdempotentWhenAlreadyMatching() {
        let terminal = TerminalHostView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))

        TerminalHostView.resize(terminal, to: NSSize(width: 120, height: 80))

        XCTAssertEqual(terminal.frame, NSRect(x: 0, y: 0, width: 120, height: 80))
    }

    func testResizeOnlyFixesOriginWhenSizeAlreadyMatches() {
        let terminal = TerminalHostView(frame: NSRect(x: 5, y: 7, width: 120, height: 80))

        TerminalHostView.resize(terminal, to: NSSize(width: 120, height: 80))

        XCTAssertEqual(terminal.frame.size, NSSize(width: 120, height: 80))
        XCTAssertEqual(terminal.frame.origin, .zero)
    }

    func testLayoutSizesTerminalSubviewToHostBounds() {
        let host = TerminalHostView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        let terminal = TerminalHostView(frame: .zero)
        host.addSubview(terminal)

        host.layout()

        XCTAssertEqual(terminal.frame.size, NSSize(width: 640, height: 400))
    }

    func testLayoutIgnoresEmptyBounds() {
        let host = TerminalHostView(frame: .zero)
        let terminal = TerminalHostView(frame: NSRect(x: 3, y: 3, width: 50, height: 50))
        host.addSubview(terminal)

        host.layout()

        XCTAssertEqual(terminal.frame, NSRect(x: 3, y: 3, width: 50, height: 50), "empty bounds must not clobber the terminal frame")
    }

    func testForceRedrawWithoutWindowDoesNotCrash() {
        let host = TerminalHostView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let terminal = TerminalHostView(frame: host.bounds)
        host.addSubview(terminal)

        host.forceRedrawOfTerminal()

        XCTAssertEqual(host.subviews.count, 1, "view stays intact without a window")
    }

    /// The production path goes through TerminalRepresentable.attach(in:) which
    /// calls TerminalHostView.resize with the host bounds; simulate that flow
    /// directly since NSViewRepresentableContext cannot be built in tests.
    func testAttachFlowResizesRuntimeTerminalToHostBounds() {
        let runtime = TerminalRuntime(sessionID: UUID()) { _, _ in }
        defer { runtime.stop() }
        let host = TerminalHostView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let terminal = runtime.terminalView
        terminal.removeFromSuperview()
        terminal.autoresizingMask = [.width, .height]
        host.addSubview(terminal)
        TerminalHostView.resize(terminal, to: host.bounds.size)

        XCTAssertEqual(terminal.frame.size, NSSize(width: 800, height: 600))
        XCTAssertTrue(host.subviews.contains { $0 === terminal })
    }
}
