import SwiftUI

@main
struct MaxCLIApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 580)
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") {
                    model.isShowingNewSession = true
                }
                .keyboardShortcut("n")
            }

            CommandMenu("Sessions") {
                Button("Quick Switcher…") {
                    model.isShowingQuickSwitcher = true
                }
                .keyboardShortcut("k")

                Button("Previous Session") {
                    model.selectNext(offset: -1)
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button("Next Session") {
                    model.selectNext(offset: 1)
                }
                .keyboardShortcut("]", modifiers: [.command])

                Divider()

                Button("Duplicate Session") {
                    model.duplicateSelected()
                }
                .keyboardShortcut("d")
                .disabled(model.selectedSession == nil)

                Button("Restart Session") {
                    if let id = model.selectedSessionID { model.restart(id) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedSession == nil)

                Button("Stop Session") {
                    if let id = model.selectedSessionID { model.stop(id) }
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(model.selectedSession == nil)

                Divider()

                ForEach(0..<9, id: \.self) { index in
                    Button("Session \(index + 1)") {
                        model.selectSession(at: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }

            CommandMenu("Layout") {
                Picker("Layout", selection: $model.layoutMode) {
                    ForEach(LayoutMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Button("Toggle Grid") {
                    model.layoutMode = model.layoutMode == .focus ? .grid : .focus
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}
