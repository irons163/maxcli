import SwiftUI

final class TerminalHostView: NSView {
    private var redrawGeneration = 0
    /// The terminal this host last attached. A view being removed (e.g. a
    /// grid cell during a layout switch) can receive one final updateNSView
    /// that steals the terminal back after the new host claimed it, leaving
    /// the visible host empty (black pane). The redraw schedule re-claims it.
    private weak var claimedTerminal: NSView?

    func claim(_ terminal: NSView) {
        claimedTerminal = terminal
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            redrawGeneration &+= 1
            return
        }
        for subview in subviews {
            subview.needsDisplay = true
        }
        forceRedrawOfTerminal()
        scheduleRedrawAfterAttachment()
    }

    override func layout() {
        super.layout()
        guard let terminal = subviews.first, !bounds.isEmpty else { return }
        let oldSize = terminal.frame.size
        Self.resize(terminal, to: bounds.size)
        if oldSize != bounds.size {
        }
        // During a grid→focus transition the host settles into its final size
        // after the rehost redraws have already run; a size change here means
        // the terminal was resized without a matching repaint.
        if oldSize != bounds.size, window != nil {
            forceRedrawOfTerminal()
        }
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

    /// Re-claims the terminal if a dying view's final update stole it back or
    /// a dismantle orphaned it (superview == nil).
    func reclaimTerminalIfNeeded() {
        guard let terminal = claimedTerminal else { return }
        guard terminal.superview !== self else { return }
        terminal.removeFromSuperview()
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal)
        if !bounds.isEmpty {
            Self.resize(terminal, to: bounds.size)
        }
        terminal.needsDisplay = true
    }

    /// SwiftUI may attach the host before its final grid cell size and window
    /// backing are ready. Retry across a few main-runloop turns (with growing
    /// delays so a grid→focus transition fully settles) so a rehosted terminal
    /// is redrawn after both have settled.
    func scheduleRedrawAfterAttachment() {
        redrawGeneration &+= 1
        let generation = redrawGeneration
        scheduleRedraw(generation: generation, attempt: 0)
    }

    private let redrawDelays: [Double] = [0, 0.08, 0.2, 0.35]

    private func scheduleRedraw(generation: Int, attempt: Int) {
        guard attempt < redrawDelays.count else { return }
        let delay = redrawDelays[attempt]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.redrawGeneration == generation else { return }
            guard self.window != nil else {
                self.scheduleRedraw(generation: generation, attempt: attempt + 1)
                return
            }
            self.reclaimTerminalIfNeeded()
            self.layoutSubtreeIfNeeded()
            self.forceRedrawOfTerminal()
            self.scheduleRedraw(generation: generation, attempt: attempt + 1)
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
            host.claim(terminal)
            if !host.bounds.isEmpty {
                TerminalHostView.resize(terminal, to: host.bounds.size)
            }
        }
        terminal.needsDisplay = true
        if moved {
            host.forceRedrawOfTerminal()
            host.scheduleRedrawAfterAttachment()
        }
    }
}
