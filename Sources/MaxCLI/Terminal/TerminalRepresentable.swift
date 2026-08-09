import SwiftUI

struct TerminalRepresentable: NSViewRepresentable {
    let runtime: TerminalRuntime
    var isFocused: Bool

    func makeNSView(context: Context) -> ManagedTerminalView {
        runtime.terminalView
    }

    func updateNSView(_ nsView: ManagedTerminalView, context: Context) {
        guard isFocused else { return }
        DispatchQueue.main.async {
            runtime.focus()
        }
    }
}
