import SwiftUI

final class TerminalHostView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        subviews.forEach { $0.needsDisplay = true }
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

    private func attach(in host: TerminalHostView) {
        let terminal = runtime.terminalView
        if terminal.superview !== host {
            terminal.removeFromSuperview()
            terminal.frame = host.bounds
            terminal.autoresizingMask = [.width, .height]
            host.addSubview(terminal)
        }
        terminal.needsDisplay = true
    }
}
