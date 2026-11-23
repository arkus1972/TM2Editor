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

    /// Otwiera backup. Plik TM-2 spoza projektu najpierw dostaje projekt —
    /// folder ze strukturą karty, do którego trafia kopia backupu i wszystkie
    /// sample, których używa (patrz `ProjektTM2`). Oryginał zostaje nietknięty.
    func open(url: URL) {
        let rozmiar = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard rozmiar == 124_748, !ProjektTM2.czyWProjekcie(url) else {
            // Plik już w projekcie albo nie wygląda na backup TM-2 (wtedy
            // tylko podgląd, jak dotąd) — otwieramy wprost.
            projekt = ProjektTM2.czyWProjekcie(url)
                ? url.deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                : nil
            otworzPlik(url: url)
            return
        }
        do {
            let zrodloWave = KartaSD.folderWave(dlaBackupu: url) ?? KartaSD.zapamietanyFolderWave
            let zalozony = try ProjektTM2.zaloz(dla: url, zrodloWave: zrodloWave)
            projekt = zalozony.korzen
            log.append(.info, "Projekt: \(zalozony.korzen.path) — skopiowano"
                + " \(zalozony.skopiowane) sampli z karty")
            otworzPlik(url: zalozony.backup)
            if !zalozony.brakujace.isEmpty {
                let lista = zalozony.brakujace.prefix(10).joined(separator: ", ")
                errorMessage = "\(zalozony.brakujace.count) sample file(s) used by this backup were not "
                    + "found, so they are not in the project: \(lista). Open the backup straight "
                    + "from the SD card (ROLAND/TM-2/Backup) to bring them along."
                log.append(.warning, "Brak sampli: " + zalozony.brakujace.joined(separator: ", "))
            }
        } catch {
            errorMessage = "Could not create the project folder: \(error.localizedDescription)"
            log.append(.error, "Nie udało się założyć projektu: \(error)")
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
