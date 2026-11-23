import AppKit
import Combine
import Foundation
import SwiftUI

/// Stan całej aplikacji.
///
/// Trzyma otwarty plik, profil modułu i log. Widoki nie znają się nawzajem —
/// wszystkie rozmawiają przez ten obiekt.
@MainActor
final class AppModel: ObservableObject {

    /// Profil sprzętu. Na razie jeden, ale wydzielony od początku.
    let profile: ModuleProfile = .tm2

    /// Log wspólny dla całej sesji.
    let log = EditorLog()

    /// Zaznaczenie w interfejsie: wybrany kit i trigger.
    ///
    /// Zwykłe `let`, a nie `@Published` — inaczej zmiana zaznaczenia znowu
    /// ogłaszałaby zmianę całego modelu aplikacji i wracalibyśmy do punktu
    /// wyjścia. Widoki, które od zaznaczenia zależą, obserwują ten obiekt
    /// same, bezpośrednio.
    let selection = EditorSelection()

    /// Własny obrazek w tle — tylko na tym komputerze, nigdy w projekcie.
    /// Zwykłe `let`, z tego samego powodu co zaznaczenie: zmiana tła nie ma
    /// ogłaszać zmiany całego modelu aplikacji.
    let tlo = WlasneTlo()

    /// Edytor otwartego pliku. `nil` = nic nie jest otwarte.
    ///
    /// Zmiany WEWNĄTRZ edytora są przekazywane dalej ręcznie. Bez tego pozycje
    /// Undo/Redo w menu aplikacji zostałyby wyszarzone na stałe: scena patrzy
    /// na AppModel, a AppModel sam z siebie zauważa tylko podmianę referencji,
    /// nie dopisanie zmiany do listy w KitEditorze.
    @Published var editor: KitEditor? {
        didSet {
            subskrypcjaEdytora = editor?.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }

    private var subskrypcjaEdytora: AnyCancellable?

    /// Ostrzeżenia z walidacji ostatnio wczytanego pliku.
    @Published var validationWarnings: [String] = []

    /// Komunikat błędu do pokazania w arkuszu.
    @Published var errorMessage: String?

    /// Który panel jest aktywny.
    @Published var selectedTab: Tab = .kits

    enum Tab: String, CaseIterable, Identifiable {
        case kits
        case hex
        case layout
        case log

        var id: String { rawValue }

        /// Etykiety w interfejsie są po angielsku.
        var displayName: String {
            switch self {
            case .kits: return "Kits"
            case .hex: return "Hex Inspector"
            case .layout: return "Layout"
            case .log: return "Log"
            }
        }

        var symbolName: String {
            switch self {
            case .kits: return "square.grid.2x2"
            case .hex: return "number"
            case .layout: return "map"
            case .log: return "list.bullet.rectangle"
            }
        }
    }

    init() {
        log.append(.info, "Uruchomiono edytor \(profile.modelName)")
        log.append(.info, "Tryb pracy: plik BACKUP z karty SD "
            + "(edycja po MIDI niedostępna — brak opublikowanej mapy SysEx)")
    }

    // MARK: - Otwieranie i zapisywanie

    /// Wczytuje plik BACKUP. Układ startowy jest niezmapowany — dopóki seria
    /// mapowania nie jest zrobiona, aplikacja pokazuje plik, ale nie udaje,
    /// że rozumie jego zawartość.
    /// Folder projektu otwartego backupu (Dokumenty › TM-2 Editor › …).
    @Published var projekt: URL?

    /// Skąd otwarto backup, zanim powstała obok niego struktura karty (plik
    /// luzem). Stąd Save As dociąga sample, których projekt nie ma.
    var oryginalBackupu: URL?

    /// Okno Tools › Even Out Sample Levels…
    @Published var pokazWyrownanie = false

    /// Czy otwarty plik to kopia założona przez edytor (backup luzem) — tylko
    /// wtedy Save As aktualizuje ją na miejscu. Plik otwarty z karty to
    /// ORYGINAŁ i nigdy nie jest nadpisywany.
    var kopiaRobocza = false

    /// Otwiera backup.
    ///  - W strukturze `ROLAND/TM-2/Backup` (karta, kopia karty): praca na
    ///    miejscu — nic nie kopiujemy, sample idą do tamtejszego WAVE.
    ///  - Luzem: obok pliku powstaje `<nazwa> TM-2` ze strukturą karty, kopią
    ///    backupu i samplami, które da się znaleźć (patrz `ProjektTM2`).
    ///  - Plik, który nie ma rozmiaru backupu TM-2: tylko podgląd, jak dotąd.
    func open(url: URL) {
        let rozmiar = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        oryginalBackupu = nil
        kopiaRobocza = false
        guard rozmiar == 124_748 else {
            projekt = nil
            otworzPlik(url: url)
            return
        }
        if let korzen = ProjektTM2.korzenStruktury(dlaBackupu: url) {
            projekt = korzen
            otworzPlik(url: url)
            if let wave = editor?.folderWave, let bajty = editor?.file.bytes {
                let brakujace = ProjektTM2.brakujaceSample(w: bajty, wave: wave)
                if !brakujace.isEmpty {
                    log.append(.warning, "Brak sampli: " + brakujace.joined(separator: ", "))
                    zapytajOBrakujace(brakujace)
                }
            }
            return
        }
        do {
            let zalozony = try ProjektTM2.zaloz(dla: url, zrodloWave: KartaSD.zapamietanyFolderWave)
            projekt = zalozony.korzen
            oryginalBackupu = url
            kopiaRobocza = true
            log.append(.info, "Projekt: \(zalozony.korzen.path) — skopiowano"
                + " \(zalozony.skopiowane) sampli z karty")
            otworzPlik(url: zalozony.backup)
            if !zalozony.brakujace.isEmpty {
                log.append(.warning, "Brak sampli: " + zalozony.brakujace.joined(separator: ", "))
                zapytajOBrakujace(zalozony.brakujace)
            }
        } catch {
            errorMessage = "Could not create the project folder: \(error.localizedDescription)"
            log.append(.error, "Nie udało się założyć projektu: \(error)")
        }
    }

    /// File › Find Missing Samples… — to samo pytanie w dowolnej chwili.
    func znajdzBrakujaceSample() {
        guard let editor, let wave = editor.folderWave, projekt != nil else { return }
        let brakujace = ProjektTM2.brakujaceSample(w: editor.file.bytes, wave: wave)
        guard !brakujace.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "All samples are in the project"
            alert.informativeText = "Every WAV file this backup uses is in \(wave.path)."
            alert.runModal()
            return
        }
        zapytajOBrakujace(brakujace)
    }

    /// Plik backupu trzyma tylko NAZWY sampli — dźwięk leży osobno, w WAVE
    /// na karcie. Gdy backup otwarto bez karty obok, pytamy, gdzie są pliki,
    /// i dociągamy je do projektu.
    /// Przed Save As: projekt ma mieć wszystkie sample, których backup
    /// używa. Brakujące najpierw po cichu z miejsca, skąd otwarto backup,
    /// i z zapamiętanej karty; czego tam nie ma — pytanie „Locate Samples…".
    /// Zwraca `false`, gdy użytkownik przerwał (Not Now / Cancel) i czegoś
    /// dalej brakuje — wtedy Save As pyta, czy zapisać mimo to.
    func uzupelnijSampleProjektu() -> Bool {
        guard let editor, let wave = editor.folderWave, projekt != nil else { return true }
        var brakujace = ProjektTM2.brakujaceSample(w: editor.file.bytes, wave: wave)
        guard !brakujace.isEmpty else { return true }

        let zrodla = [oryginalBackupu.flatMap { KartaSD.folderWave(dlaBackupu: $0) },
                      KartaSD.zapamietanyFolderWave].compactMap { $0 }
        for zrodlo in zrodla where !brakujace.isEmpty {
            let wynik = ProjektTM2.dociagnij(brakujace, zWybranego: zrodlo, doWave: wave)
            if wynik.skopiowane > 0 {
                log.append(.info, "Save As: dociągnięto \(wynik.skopiowane) sampli z \(zrodlo.path)")
            }
            brakujace = wynik.nadal
        }
        if !brakujace.isEmpty {
            zapytajOBrakujace(brakujace)
            brakujace = ProjektTM2.brakujaceSample(w: editor.file.bytes, wave: wave)
        }
        guard !brakujace.isEmpty else { return true }

        let alert = NSAlert()
        alert.messageText = "Save without \(brakujace.count) sample file(s)?"
        alert.informativeText = "Pads that use them will show NO WAVE on the module until the files "
            + "are in ROLAND/TM-2/WAVE on the card: " + brakujace.prefix(8).joined(separator: ", ")
        alert.addButton(withTitle: "Save Anyway")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func zapytajOBrakujace(_ brakujace: [String]) {
        guard let wave = editor?.folderWave else { return }
        var zostalo = brakujace
        while !zostalo.isEmpty {
            let alert = NSAlert()
            alert.messageText = "\(zostalo.count) sample file(s) not found"
            alert.informativeText = "A backup file stores only the NAMES of the samples — the sound "
                + "itself lives in ROLAND/TM-2/WAVE on the SD card. Show the editor where the "
                + "files are (the SD card, a copy of it, or any folder with them) and they will "
                + "be copied into the project.\n\nMissing: "
                + zostalo.prefix(8).joined(separator: ", ")
                + (zostalo.count > 8 ? " …" : "")
            alert.addButton(withTitle: "Locate Samples…")
            alert.addButton(withTitle: "Not Now")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let panel = NSOpenPanel()
            panel.title = "Where Are the Samples?"
            panel.message = "Choose the SD card, a copy of its ROLAND folder, or any folder with the WAV files."
            panel.prompt = "Copy From Here"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let wybrany = panel.url else { return }

            let wynik = ProjektTM2.dociagnij(zostalo, zWybranego: wybrany, doWave: wave)
            if let waveKarty = KartaSD.folderWave(zWybranego: wybrany) {
                KartaSD.zapamietanyFolderWave = waveKarty
            }
            log.append(.info, "Dociągnięto \(wynik.skopiowane) sampli z \(wybrany.path)")
            zostalo = wynik.nadal
            // Lista sampli w widoku odświeży się przy następnym rysowaniu;
            // dla pewności sygnał zmiany.
            editor?.objectWillChange.send()
        }
    }

    private func otworzPlik(url: URL) {
        do {
            let layout = LayoutStore.loadOrDefault(log: log)
            let file = try BackupFile(contentsOf: url, layout: layout)
            let editor = KitEditor(file: file, log: log)
            self.editor = editor
            self.validationWarnings = file.validate()

            // Stajemy na kicie, który był wybrany na module w chwili zapisu.
            // Wcześniej edytor zawsze startował od kitu 1 i to realnie mylilo:
            // po wczytaniu backupu z parametrami zmienionymi na kicie 40
            // pierwszy ekran pokazywał nietknięte wartości kitu 1 i wyglądało
            // to jak błąd odczytu. Plik wie, nad czym się pracowało — wystarczy
            // z tego skorzystać.
            self.selection.reset()
            if let biezacy = file.kitSelectedOnModule {
                self.selection.kit = biezacy
                log.append(.info, "Moduł miał wybrany kit \(biezacy)"
                    + " — edytor staje na nim")
            }

            log.append(.info, "Wczytano \(url.lastPathComponent) "
                + "(\(file.size) bajtów)")
            if layout.canAddressKits {
                log.append(.info, "Układ rozpoznany: kit 1 pod "
                    + String(format: "0x%X", layout.kitBlockOrigin ?? 0)
                    + ", stride \(layout.kitStride ?? 0) B")
            } else {
                log.append(.warning, "Układ pliku nieznany — tryb wyłącznie "
                    + "do podglądu. Wykonaj serię mapowania różnicowego "
                    + "(narzędzie tools/tm2diff.py).")
            }
            for warning in validationWarnings {
                log.append(.warning, warning)
            }
        } catch {
            errorMessage = error.localizedDescription
            log.append(.error, "Nie udało się wczytać pliku: \(error)")
        }
    }

    func save(to url: URL) {
        editor?.save(to: url)
        if let message = editor?.lastError {
            errorMessage = message
        }
    }

    func close() {
        editor = nil
        projekt = nil
        oryginalBackupu = nil
        kopiaRobocza = false
        validationWarnings = []
        log.append(.info, "Zamknięto plik")
    }

    var hasOpenFile: Bool { editor != nil }
}

/// Wczytywanie i zapisywanie opisu układu.
///
/// Układ jest danymi, więc siedzi w pliku JSON obok aplikacji, a nie w kodzie.
/// Kiedy z analizatora wyjdą offsety, wystarczy podmienić ten plik — bez
/// rekompilacji i bez nowego wydania.
enum LayoutStore {

    static let fileName = "tm2-layout.json"

    /// Katalog na dane aplikacji w katalogu domowym użytkownika.
    static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("TM2Editor", isDirectory: true)
    }

    static var fileURL: URL? {
        directory?.appendingPathComponent(fileName)
    }

    /// Wczytuje układ z pliku, a jak go nie ma — zwraca ostatni znany,
    /// potwierdzony na sprzęcie stan (`mapped2026_09_02`), nie pusty
    /// `unmappedTM2`. Plik JSON, jeśli istnieje, i tak ma pierwszeństwo —
    /// to on jest miejscem na kolejne odkrycia z mapowania różnicowego, bez
    /// potrzeby nowego wydania aplikacji.
    @MainActor
    static func loadOrDefault(log: EditorLog) -> BackupLayout {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            return .mapped2026_09_02
        }
        do {
            let data = try Data(contentsOf: url)
            var layout = try JSONDecoder().decode(BackupLayout.self, from: data)

            // Plik układu jest wypełniany ręcznie w trakcie mapowania, więc
            // musi być traktowany jak wejście od użytkownika. Zero albo liczba
            // ujemna w polach licznikowych dałaby zakres 1...0, a to jest
            // natychmiastowe wywalenie programu przy budowaniu listy kitów.
            if layout.kitCount < 1 || layout.triggerCount < 1 {
                log.append(.error, "Plik układu podaje kitCount=\(layout.kitCount),"
                    + " triggerCount=\(layout.triggerCount) — poprawiam do wartości"
                    + " minimalnych, sprawdź tm2-layout.json")
                layout.kitCount = max(layout.kitCount, 1)
                layout.triggerCount = max(layout.triggerCount, 1)
            }

            // Stride'y nie wywalą programu, ale zerowy albo ujemny sprawi, że
            // wszystkie adresy wypadną poza plikiem i edytor bez wyjaśnienia
            // pokaże same puste pola. Lepiej to nazwać.
            if let stride = layout.kitStride, stride <= 0 {
                log.append(.warning, "kitStride = \(stride) — wszystkie adresy"
                    + " kitów wypadną poza plikiem; popraw tm2-layout.json")
            }
            if let stride = layout.triggerStride, stride <= 0 {
                log.append(.warning, "triggerStride = \(stride) — wszystkie"
                    + " adresy triggerów wypadną poza plikiem;"
                    + " popraw tm2-layout.json")
            }

            log.append(.info, "Wczytano opis układu z \(url.lastPathComponent) "
                + "(wersja \(layout.layoutVersion), "
                + "\(layout.mappedFieldCount)/\(layout.totalFieldCount) pól zmapowanych)")
            return layout
        } catch {
            log.append(.error, "Plik układu jest uszkodzony, używam pustego: \(error)")
            return .unmappedTM2
        }
    }

    static func save(_ layout: BackupLayout) throws {
        guard let directory, let fileURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: fileURL, options: .atomic)
    }
}
