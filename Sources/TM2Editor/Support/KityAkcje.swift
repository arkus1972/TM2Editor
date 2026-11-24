import AppKit
import Foundation

/// Polecenia menu Kit i File › New Backup — okna wyboru i potwierdzenia.
/// Sama robota na bajtach jest w `KitEditor` i `NowyBackup`.
extension AppModel {

    // MARK: - Kopiowanie i zamiana

    /// Lista kitów do wyboru celu (bez bieżącego).
    private func wyborKitu(pomin: Int) -> NSPopUpButton {
        let lista = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26), pullsDown: false)
        for kit in 1...99 where kit != pomin {
            lista.addItem(withTitle: String(format: "%02d  ", kit) + (editor?.kitName(kit) ?? ""))
            lista.lastItem?.tag = kit
        }
        return lista
    }

    func kopiujKitDo() { kopiujLubZamien(zamiana: false) }
    func zamienKitZ() { kopiujLubZamien(zamiana: true) }

    private func kopiujLubZamien(zamiana: Bool) {
        guard let editor else { return }
        let z = selection.kit
        let nazwa = "kit \(z) (\(editor.kitName(z) ?? "—"))"
        let lista = wyborKitu(pomin: z)
        let alert = NSAlert()
        alert.messageText = zamiana ? "Swap Kits" : "Copy Kit"
        alert.informativeText = zamiana
            ? "Exchange \(nazwa) with another kit, including the WAV file names."
            : "Copy \(nazwa) with its effect, sounds and WAV file names onto another kit. "
                + "That kit will be replaced. You can undo it."
        alert.accessoryView = lista
        alert.addButton(withTitle: zamiana ? "Swap" : "Copy")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let cel = lista.selectedItem?.tag else { return }
        let ok = zamiana ? editor.zamienKity(z, cel) : editor.kopiujKit(z: z, do: cel)
        if ok {
            selection.kit = cel
        } else if let blad = editor.lastError {
            errorMessage = blad
        }
    }

    // MARK: - Presety

    func zapiszPresetKitu() {
        guard let editor else { return }
        let kit = selection.kit
        let pole = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        pole.stringValue = editor.kitName(kit) ?? "Kit \(kit)"
        let alert = NSAlert()
        alert.messageText = "Save Kit as Preset"
        alert.informativeText = "The preset keeps this kit's name, effect, four sounds and WAV file names. "
            + "System and trigger settings are not included."
        alert.accessoryView = pole
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = pole
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let nazwa = pole.stringValue.trimmingCharacters(in: .whitespaces)
        guard !nazwa.isEmpty, let preset = editor.presetKitu(kit, nazwa: nazwa) else { return }
        var lista = BibliotekaPresetow.wczytaj()
        lista.insert(preset, at: 0)
        do {
            try BibliotekaPresetow.zapisz(lista)
            log.append(.info, "Zapisano preset „\(nazwa)” z kitu \(kit)")
        } catch {
            errorMessage = "Could not save the preset: \(error.localizedDescription)"
        }
    }

    // MARK: - Nowy backup

    /// File › New Backup… / New Factory Backup…: projekt ze strukturą karty
    /// i backupem BKUP-001.TM0. Pusty: 99 × „New Kit", ustawienia SYSTEM
    /// i wejść z otwartego backupu. Fabryczny: stan jak po FACTORY RESET.
    func nowyBackup(fabryczny: Bool = false) {
        if let editor, editor.hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "Discard unsaved changes?"
            alert.informativeText = "The open backup has changes that are not saved yet."
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let panel = NSSavePanel()
        panel.title = fabryczny ? "New Factory Backup" : "New TM-2 Backup"
        panel.message = fabryczny
            ? "The editor creates a folder with the SD card structure (ROLAND/TM-2) and a backup with "
                + "the factory settings: the 50 factory kits and factory system and trigger settings, "
                + "exactly as after FACTORY RESET. The module is not erased — load it with BACKUP LOAD."
            : "The editor creates a folder with the SD card structure (ROLAND/TM-2) and a new "
                + "backup with 99 empty kits. System and trigger settings are taken from the open backup."
        panel.nameFieldLabel = "Folder name:"
        panel.nameFieldStringValue = fabryczny ? "TM-2 Factory Backup" : "New TM-2 Backup"
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let korzen = panel.url else { return }

        let fm = FileManager.default
        guard !fm.fileExists(atPath: korzen.path) else {
            errorMessage = "\(korzen.lastPathComponent) already exists. Choose another name — "
                + "the editor never replaces existing files."
            return
        }
        do {
            let tm2 = korzen.appendingPathComponent("ROLAND/TM-2", isDirectory: true)
            let backupy = tm2.appendingPathComponent("Backup", isDirectory: true)
            try fm.createDirectory(at: backupy, withIntermediateDirectories: true)
            try fm.createDirectory(at: tm2.appendingPathComponent("WAVE", isDirectory: true),
                                   withIntermediateDirectories: true)
            let plik = backupy.appendingPathComponent("BKUP-001.TM0")
            let bajty = fabryczny ? NowyBackup.fabryczny() : NowyBackup.bajty(naglowekZ: editor?.file.bytes)
            try Data(bajty).write(to: plik, options: .withoutOverwriting)
            log.append(.info, "Nowy backup: \(plik.path)")
            open(url: plik)
        } catch {
            errorMessage = "Could not create the new backup: \(error.localizedDescription)"
        }
    }
}
