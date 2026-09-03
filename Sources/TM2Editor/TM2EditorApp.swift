import SwiftUI

/// Punkt wejścia aplikacji.
///
/// Uwaga dla SwiftPM: plik z `@main` NIE może się nazywać `main.swift` —
/// wtedy Swift traktuje go jako skrypt najwyższego poziomu i atrybut `@main`
/// jest błędem. Stąd nazwa TM2EditorApp.swift.
@main
struct TM2EditorApp: App {

    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .newItem) {
                Button("Open Backup File…") {
                    model.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save As…") {
                    model.presentSavePanel()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!model.hasOpenFile)

                Divider()

                Button("Close File") {
                    model.close()
                }
                .disabled(!model.hasOpenFile)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.editor?.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.editor?.canUndo != true)

                Button("Redo") { model.editor?.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(model.editor?.canRedo != true)

                Divider()

                Button("Revert All Changes") { model.editor?.revertAll() }
                    .disabled(model.editor?.canUndo != true)
            }
        }

        Settings {
            AboutView()
                .environmentObject(model)
        }
    }
}
