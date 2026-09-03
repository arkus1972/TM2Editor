import AppKit
import Foundation

/// Okna wyboru pliku.
///
/// Świadomie AppKit, a nie `.fileImporter` ze SwiftUI: plik BACKUP TM-2 nie ma
/// znanego rozszerzenia ani typu UTI, więc filtrowanie po typach byłoby
/// zgadywaniem. NSOpenPanel pozwala po prostu wpuścić każdy plik.
@MainActor
extension AppModel {

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open TM-2 Backup File"
        panel.message = "Select a backup file saved from the TM-2 SD card. "
            + "The file is opened read-only; the original is never modified."
        panel.prompt = "Open"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // Bez filtra po typach — nie znamy jeszcze rozszerzenia plików BACKUP.
        panel.allowsOtherFileTypes = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func presentSavePanel() {
        guard let editor else { return }

        let panel = NSSavePanel()
        panel.title = "Save Edited Backup"
        panel.message = "The edited backup is written to a NEW file. "
            + "Keep the original on the card untouched until the module has "
            + "accepted the edited copy."
        panel.prompt = "Save"
        panel.canCreateDirectories = true

        let originalName = editor.file.sourceURL?.deletingPathExtension().lastPathComponent
            ?? "TM2-BACKUP"
        let ext = editor.file.sourceURL?.pathExtension ?? ""
        panel.nameFieldStringValue = ext.isEmpty
            ? "\(originalName)-edited"
            : "\(originalName)-edited.\(ext)"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(to: url)
    }

    /// Zapis logu obok plików serii mapowania. Protokół wymaga notatki „co
    /// dokładnie zmienione i z jakiej wartości na jaką" — łatwiej ją zapisać
    /// niż przepisać z ekranu.
    func presentLogExportPanel() {
        let panel = NSSavePanel()
        panel.title = "Export Log"
        panel.nameFieldStringValue = "tm2-editor-log.txt"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try log.plainText().write(to: url, atomically: true, encoding: .utf8)
            log.append(.info, "Zapisano log do \(url.lastPathComponent)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
