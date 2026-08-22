import SwiftUI

final class TerminalHostView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        for subview in subviews {
            subview.needsDisplay = true
        }
        forceRedrawOfTerminal()
        DispatchQueue.main.async { [weak self] in
            self?.forceRedrawOfTerminal()
        }
    }

    override func layout() {
        super.layout()
        guard let terminal = subviews.first, !bounds.isEmpty else { return }
        Self.resize(terminal, to: bounds.size)
    }

    static func resize(_ terminal: NSView, to size: NSSize) {
        if terminal.frame.size != size {
            terminal.setFrameSize(size)
        }
        if terminal.frame.origin != .zero {
            terminal.setFrameOrigin(.zero)
        }
    }

    /// Layer-backed terminal views lose their backing contents when the
    /// hierarchy is reparented during a layout switch, and a `needsDisplay`
    /// set while the view has no window is swallowed. Clear the stale layer
    /// contents and force a fresh full draw so the terminal never stays black.
    func forceRedrawOfTerminal() {
        for subview in subviews {
            guard subview.window != nil, !subview.bounds.isEmpty else { continue }
            subview.layer?.contents = nil
            subview.needsDisplay = true
            subview.displayIfNeeded()
        }
    }
}

struct TerminalRepresentable: NSViewRepresentable {
    let runtime: TerminalRuntime
    var isFocused: Bool

    final class Coordinator {
        var didFocus = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        attach(in: host)
        return host
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        attach(in: nsView)
        syncTerminalFrame(to: nsView)
        guard isFocused else {
            context.coordinator.didFocus = false
            return
        }
        if runtime.terminalView.window == nil {
            context.coordinator.didFocus = false
        } else if !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                runtime.focus()
            }
        }
    }

    static func dismantleNSView(_ nsView: TerminalHostView, coordinator: Coordinator) {
        nsView.subviews.forEach { $0.removeFromSuperview() }
    }

    /// SwiftUI layout can hand the host a bogus huge frame during grid/focus
    /// transitions (ScrollView proposals), which leaves the terminal and its
    /// pty winsize reporting hundreds of rows/cols. opencode sizes its dialogs
    /// from that reported size, so force the terminal back to the host's real
    /// size on every update. Resizing must go through setFrameSize so
    /// SwiftTerm recomputes cols/rows, updates the pty and requests a redraw;
    /// assigning frame directly bypasses all of that and leaves a black pane.
    private func syncTerminalFrame(to host: TerminalHostView) {
        let terminal = runtime.terminalView
        guard !host.bounds.isEmpty else { return }
        TerminalHostView.resize(terminal, to: host.bounds.size)
    }

    private func attach(in host: TerminalHostView) {
        let terminal = runtime.terminalView
        let moved = terminal.superview !== host
        if moved {
            terminal.removeFromSuperview()
            terminal.autoresizingMask = [.width, .height]
            host.addSubview(terminal)
            if !host.bounds.isEmpty {
                TerminalHostView.resize(terminal, to: host.bounds.size)
            }
        }
        terminal.needsDisplay = true
        if moved {
            host.forceRedrawOfTerminal()
            DispatchQueue.main.async { [weak host] in
                host?.forceRedrawOfTerminal()
            }
        }
    }
}
