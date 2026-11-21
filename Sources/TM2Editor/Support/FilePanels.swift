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

        panel.nameFieldStringValue = NazwaZapisu.propozycja(
            dlaPliku: editor.file.sourceURL?.lastPathComponent)

        // Katalog ten sam, co plik źródłowy — czyli przy pliku z karty od razu
        // katalog Backup, gdzie moduł swoich backupów szuka.
        if let katalog = editor.file.sourceURL?.deletingLastPathComponent() {
            panel.directoryURL = katalog
        }

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

/// Jak nazwać plik, który zapisuje edytor.
///
/// Nie jest to kosmetyka. Moduł szuka backupów po WZORCU NAZWY: na karcie,
/// w katalogu `ROLAND/TM-2/Backup`, leżą pliki `BKUP-001.TM0`. Plik nazwany
/// inaczej — a tak właśnie wyglądała wcześniejsza propozycja edytora,
/// `BKUP-001-edited.TM0` — po prostu nie pojawi się na liście przy
/// BACKUP LOAD. Użytkownik zobaczyłby, że „nic się nie zapisało", choć plik
/// leży na karcie.
///
/// Dlatego przy pliku w formacie modułu proponujemy KOLEJNY numer. Oryginał
/// zostaje nietknięty, a edytowana wersja pojawia się w module jako osobny
/// backup — można ją wczytać, porównać i w razie czego wrócić do poprzedniej.
enum NazwaZapisu {

    /// Wzorzec nazwy używany przez moduł: `BKUP-001.TM0`.
    static func propozycja(dlaPliku nazwa: String?) -> String {
        guard let nazwa, !nazwa.isEmpty else { return "TM2-BACKUP-edited" }

        if let numer = numerBackupu(nazwa), numer < 999 {
            return String(format: "BKUP-%03d.TM0", numer + 1)
        }

        // Plik spoza karty (albo numer na granicy): zostaje dopisek, żeby
        // niczego nie nadpisać. Taka nazwa nie będzie widoczna w module,
        // ale to i tak nie jest plik z jego katalogu.
        let url = URL(fileURLWithPath: nazwa)
        let rdzen = url.deletingPathExtension().lastPathComponent
        let rozszerzenie = url.pathExtension
        return rozszerzenie.isEmpty
            ? "\(rdzen)-edited"
            : "\(rdzen)-edited.\(rozszerzenie)"
    }

    /// Numer z nazwy `BKUP-NNN.TM0`, albo `nil`, jeśli to nie ten wzorzec.
    /// Wielkość liter nie ma znaczenia — karta bywa sformatowana tak, że
    /// pokazuje nazwy wersalikami.
    static func numerBackupu(_ nazwa: String) -> Int? {
        let url = URL(fileURLWithPath: nazwa)
        guard url.pathExtension.lowercased() == "tm0" else { return nil }

        let rdzen = url.deletingPathExtension().lastPathComponent
        let czesci = rdzen.split(separator: "-")
        guard czesci.count == 2,
              czesci[0].lowercased() == "bkup",
              czesci[1].count == 3,
              let numer = Int(czesci[1]),
              numer >= 0 else { return nil }
        return numer
    }
}
