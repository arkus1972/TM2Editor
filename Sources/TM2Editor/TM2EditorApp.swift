import AppKit
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

                Button("Show Project in Finder") {
                    if let projekt = model.projekt {
                        NSWorkspace.shared.activateFileViewerSelecting([projekt])
                    }
                }
                .disabled(model.projekt == nil)

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

            // Własne tło. W menu View, bo dotyczy wyglądu, nie pliku.
            // Bez blokowania „Remove" przy braku tła: menu nie obserwuje
            // obiektu tła, więc stan wyszarzenia mógłby kłamać — a usunięcie
            // nieistniejącego tła po prostu niczego nie robi.
            CommandGroup(after: .sidebar) {
                Button("Choose Background Image…") {
                    model.tlo.wybierz(log: model.log)
                }
                Button("Remove Background Image") {
                    model.tlo.usun(log: model.log)
                }
            }
        }

        Settings {
            AboutView()
                .environmentObject(model)
        }
    }
}
