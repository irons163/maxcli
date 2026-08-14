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
                Button {
                    model.isShowingNewSession = true
                } label: {
                    Text(model.tr("menu.newSession"))
                }
                .keyboardShortcut("n")
            }

            CommandMenu(Text(model.tr("menu.sessions"))) {
                Button {
                    model.isShowingQuickSwitcher = true
                } label: {
                    Text(model.tr("menu.quickSwitcher"))
                }
                .keyboardShortcut("k")

                Divider()

                Button {
                    model.isShowingHistory = true
                } label: {
                    Text(model.tr("menu.opencodeHistory"))
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button {
                    model.selectNext(offset: -1)
                } label: {
                    Text(model.tr("menu.previousSession"))
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button {
                    model.selectNext(offset: 1)
                } label: {
                    Text(model.tr("menu.nextSession"))
                }
                .keyboardShortcut("]", modifiers: [.command])

                Divider()

                Button {
                    model.duplicateSelected()
                } label: {
                    Text(model.tr("menu.duplicateSession"))
                }
                .keyboardShortcut("d")
                .disabled(model.selectedSession == nil)

                Button {
                    if let id = model.selectedSessionID { model.restart(id) }
                } label: {
                    Text(model.tr("menu.restartSession"))
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedSession == nil)

                Button {
                    if let id = model.selectedSessionID { model.stop(id) }
                } label: {
                    Text(model.tr("menu.stopSession"))
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(model.selectedSession == nil)

                Divider()

                ForEach(0..<9, id: \.self) { index in
                    Button {
                        model.selectSession(at: index)
                    } label: {
                        Text(model.trf("menu.sessionNumber", index + 1))
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }

            CommandMenu(Text(model.tr("menu.layout"))) {
                Picker(selection: $model.layoutMode) {
                    ForEach(LayoutMode.allCases) { mode in
                        Label(model.tr(mode.titleKey), systemImage: mode.symbolName)
                            .tag(mode)
                    }
                } label: {
                    Text(model.tr("menu.layout"))
                }
                .pickerStyle(.inline)

                Divider()

                Button {
                    model.layoutMode = model.layoutMode.next
                } label: {
                    Text(model.tr("menu.cycleLayout"))
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }

            CommandMenu(Text(model.tr("menu.language"))) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        model.language = language
                    } label: {
                        if model.language == language {
                            Label(languageLabel(language), systemImage: "checkmark")
                        } else {
                            Text(languageLabel(language))
                        }
                    }
                }
            }
        }
    }

    private func languageLabel(_ language: AppLanguage) -> String {
        language == .system ? model.tr("language.system") : language.displayName
    }
}
