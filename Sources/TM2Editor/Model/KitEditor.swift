import Combine
import Foundation

/// Dodatkowy kawałek pliku zmieniony w ramach jednej zmiany.
///
/// Przypisanie sampla z karty rusza dwa miejsca naraz — slot brzmienia
/// (numer i „bank") i wpis w tablicy ścieżek, sto kilka kilobajtów dalej.
/// Dla użytkownika to jedna czynność, więc jedno Cmd+Z ma cofać oba.
struct FragmentZmiany: Equatable {
    let offset: Int
    let oldRaw: [UInt8]
    let newRaw: [UInt8]
}

/// Pojedyncza zmiana wprowadzona przez użytkownika.
///
/// Zmiana jest opisana logicznie (które pole, w którym kicie, w którym
/// triggerze, z jakiej wartości na jaką), a nie bajtowo. Dzięki temu listę
/// zmian da się pokazać człowiekowi w formie „Kit 3 / Trigger 2 / Level:
/// 100 → 84", a nie „bajt 0x1A40: 64 → 54".
struct EditChange: Identifiable, Equatable {
    let id = UUID()
    let fieldID: String
    let fieldLabel: String
    let scope: FieldScope
    let kit: Int
    let trigger: Int
    let oldValue: FieldValue
    let newValue: FieldValue
    let timestamp: Date

    /// Bezwzględny adres pola w pliku.
    let offset: Int
    /// Surowe bajty sprzed i po zmianie.
    ///
    /// Cofanie działa na tych bajtach, a nie na wartościach logicznych, i to
    /// jest różnica, która ma znaczenie w praktyce. Offsety są na tym etapie
    /// zgadywane, więc bajt pod polem o zadeklarowanym zakresie 0…100 może
    /// mieć wartość 200. Gdyby cofanie szło przez `setValue`, próba
    /// przywrócenia takiej wartości poleciałaby błędem walidacji i użytkownik
    /// zostałby z niecofalną zmianą. Wpisanie z powrotem tych samych bajtów
    /// nie może się nie udać.
    let oldRaw: [UInt8]
    let newRaw: [UInt8]

    /// Inne miejsca pliku zmienione razem z tym — cofane i ponawiane razem.
    var dodatkowe: [FragmentZmiany] = []

    /// Opis do wyświetlenia. Interfejs jest po angielsku.
    var summary: String {
        switch scope {
        case .global:
            return "\(fieldLabel): \(oldValue) → \(newValue)"
        case .kit:
            return "Kit \(kit) · \(fieldLabel): \(oldValue) → \(newValue)"
        case .trigger:
            return "Kit \(kit) · Trigger \(trigger) · \(fieldLabel): "
                + "\(oldValue) → \(newValue)"
        }
    }
}

/// Model edycji: jedna lista zmian, cofanie, odroczony zapis.
///
/// Wzorzec przeniesiony z PulsoKita (KitEditor.swift) i sprawdzony w praktyce.
/// Trzy zasady, które warto powtórzyć:
///
/// 1. Jedna lista zmian dla całej sesji edycji — nie osobne stany per widok.
///    Użytkownik ma jedno miejsce, w którym widzi wszystko, co ruszył.
/// 2. Cofanie działa na tej liście, nie na kopiach całego pliku. Cofnięcie to
///    ponowne wpisanie starej wartości, nie przywrócenie snapshotu.
/// 3. Zapis jest odroczony. Nic nie idzie na dysk, dopóki użytkownik świadomie
///    nie kliknie Save — i wtedy idzie do NOWEGO pliku.
@MainActor
final class KitEditor: ObservableObject {

    /// Plik, na którym pracujemy.
    @Published private(set) var file: BackupFile

    /// Historia zmian, od najstarszej.
    @Published private(set) var changes: [EditChange] = []

    /// Zmiany cofnięte — do ponowienia.
    @Published private(set) var redoStack: [EditChange] = []

    /// Ostatni błąd do pokazania użytkownikowi.
    @Published var lastError: String?

    // Zaznaczenia (wybrany kit i trigger) tu NIE MA — siedzi w osobnym
    // obiekcie `EditorSelection`. Dopóki było tutaj, przełączenie triggera
    // ogłaszało zmianę dokumentu i przebudowywało całe okno. Edytor odpowiada
    // za plik; co jest wybrane w interfejsie, to sprawa interfejsu.

    let log: EditorLog

    // Log jest przekazywany jawnie, bez domyślnej wartości. Wyrażenie domyślnego
    // argumentu jest w starszych wersjach Swifta nieizolowane, a `EditorLog()`
    // to inicjalizator @MainActor — na Swifcie 5.9 taki domyślny argument się
    // nie kompiluje.
    init(file: BackupFile, log: EditorLog) {
        self.file = file
        self.log = log
        odswiezNazwyKitow()
    }

    // MARK: - Pamięć podręczna dla listy kitów

    /// Nazwy wszystkich kitów, policzone raz.
    ///
    /// Lista kitów ma 99 wierszy i na macOS jest pod spodem tabelą, więc każda
    /// przebudowa widoku przeładowuje ją w całości. Dopóki każdy wiersz sam
    /// dekodował swoją nazwę z pliku, przełączenie czegokolwiek w prawym panelu
    /// kosztowało 99 odczytów UTF-16 plus tyle samo przeszukań listy pól.
    /// Teraz nazwy liczą się raz — przy wczytaniu pliku i po każdej zmianie,
    /// która mogła je ruszyć.
    @Published private(set) var kitNames: [String?] = []

    /// Numery kitów z niezapisanymi zmianami — do kropki przy wierszu.
    /// Liczone raz, zamiast przeszukiwać całą historię zmian w każdym z 99
    /// wierszy osobno.
    @Published private(set) var changedKits: Set<Int> = []

    private func odswiezNazwyKitow() {
        let liczba = max(layout.kitCount, 1)
        guard let field = layout.kitFields.first(where: { $0.id == "kit.name" }),
              field.isMapped else {
            kitNames = Array(repeating: nil, count: liczba)
            return
        }
        kitNames = (1...liczba).map { kit in
            guard let value = file.value(of: field, kit: kit, trigger: 1),
                  let text = value.textValue,
                  !text.isEmpty else { return nil }
            return text
        }
    }

    private func odswiezZnacznikiZmian() {
        changedKits = Set(changes.compactMap { $0.scope == .global ? nil : $0.kit })
    }

    /// Wołane po każdej operacji ruszającej bajty albo historię zmian.
    private func odswiezPamiecPodreczna() {
        odswiezNazwyKitow()
        odswiezZnacznikiZmian()
    }

    // MARK: - Stan

    var layout: BackupLayout { file.layout }

    /// Identyfikator ostatniej zmiany w chwili ostatniego udanego zapisu.
    ///
    /// Świadomie tożsamość zmiany, a nie ich liczba. Licznik dawałby fałszywy
    /// negatyw w sekwencji: zapis trzech zmian, cofnięcie jednej, wprowadzenie
    /// nowej — liczba znowu wynosi trzy, ale zawartość jest inna niż na dysku,
    /// a plakietka „unsaved changes" zgasłaby i przycisk Save As wyszarzył.
    @Published private(set) var savedChangeID: UUID?

    var hasUnsavedChanges: Bool { changes.last?.id != savedChangeID }

    var canUndo: Bool { !changes.isEmpty }

    var canRedo: Bool { !redoStack.isEmpty }

    /// Bajty zmienione względem wczytanego pliku — do podświetlenia
    /// w inspektorze heks.
    var modifiedOffsets: Set<Int> { Set(file.modifiedOffsets()) }

    // MARK: - Odczyt

    func value(of field: FieldSpec, kit: Int, trigger: Int) -> FieldValue? {
        file.value(of: field, kit: kit, trigger: trigger)
    }

    /// Nazwa kitu do listy po lewej. Jeżeli pole nazwy nie jest jeszcze
    /// zmapowane, zwraca `nil` i widok pokazuje sam numer.
    func kitName(_ kit: Int) -> String? {
        guard let field = layout.kitFields.first(where: { $0.id == "kit.name" }),
              field.isMapped,
              let value = file.value(of: field, kit: kit, trigger: 1),
              let text = value.textValue,
              !text.isEmpty else {
            return nil
        }
        return text
    }

    // MARK: - Zapis wartości

    /// Ustawia wartość pola i dopisuje zmianę do listy.
    ///
    /// Zwraca `true`, jeśli zmiana doszła do skutku. Brak zmiany (ta sama
    /// wartość) też zwraca `true`, ale nie zaśmieca listy.
    @discardableResult
    func set(_ value: FieldValue, for field: FieldSpec, kit: Int, trigger: Int) -> Bool {
        guard field.isMapped else {
            lastError = "Field \"\(field.label)\" has no known offset yet. "
                + "Run the differential mapping series first."
            log.append(.warning, "Próba zapisu do niezmapowanego pola \(field.id)")
            return false
        }

        // Parametr efektu ma sens tylko przy tym efekcie, dla którego został
        // opisany: to samo pole +0x1C to DlyTime w DELAY, a RevTime w REVERB.
        // Wartość wpisana dla REVERB i zatwierdzona już po zmianie efektu
        // (np. przy zapisie pliku) trafiłaby w zupełnie inny parametr.
        if let kod = ParametryEfektow.kodEfektu(zID: field.id) {
            guard obslugujeEfektKitu, kitEffect(kit: kit)?.kod == kod else {
                lastError = "\"\(field.label)\" belongs to a different kit effect."
                log.append(.warning, "Pominięto zapis \(field.id) w kicie \(kit):"
                    + " kit ma teraz inny efekt")
                return false
            }
        }

        guard let offset = layout.absoluteOffset(for: field, kit: kit, trigger: trigger),
              let oldRaw = file.slice(at: offset, length: field.encoding.byteLength) else {
            lastError = "Field \"\(field.label)\" points outside the file."
            log.append(.warning, "Adres pola \(field.id) wypada poza plikiem")
            return false
        }

        let current = file.value(of: field, kit: kit, trigger: trigger)
        if let current, current == value {
            return true    // nic się nie zmieniło, nie ma czego notować
        }

        do {
            try file.setValue(value, for: field, kit: kit, trigger: trigger)
        } catch {
            lastError = error.localizedDescription
            log.append(.error, "Zapis pola \(field.id) nie powiódł się:"
                + " \(error.localizedDescription)")
            return false
        }

        guard let newRaw = file.slice(at: offset, length: field.encoding.byteLength) else {
            // Nieosiągalne: ten sam odczyt powiódł się przed zapisem, a plik
            // nie zmienia rozmiaru. Gdyby jednak tu trafiło, plik byłby już
            // zmieniony bez pozycji w historii — czyli zmiana nie do cofnięcia.
            // Musi zostać w logu.
            lastError = "Internal error: could not read back \"\(field.label)\" after writing."
            log.append(.error, "Odczyt po zapisie pola \(field.id) pod adresem"
                + " \(offset) nie powiódł się — zmiana NIE trafiła do historii")
            return false
        }

        let change = EditChange(
            fieldID: field.id,
            fieldLabel: field.label,
            scope: field.scope,
            kit: kit,
            trigger: trigger,
            oldValue: current ?? .number(0),
            newValue: value,
            timestamp: Date(),
            offset: offset,
            oldRaw: oldRaw,
            newRaw: newRaw
        )
        changes.append(change)
        redoStack.removeAll()   // nowa zmiana zamyka gałąź ponowień
        odswiezPamiecPodreczna()
        log.append(.edit, change.summary)
        return true
    }

    // MARK: - Typ pada

    /// Rekordy ustawień wejść: cztery po 15 B od 0x40 (zmierzone, wpis (s)
    /// dziennika). Rekord 1 i 3 to pierwsze pady gniazd, 2 i 4 — drugie pady,
    /// używane tylko w trybie PADx2.
    private static let poczatekRekordowWejsc = 0x40
    private static let dlugoscRekorduWejscia = 15

    private static func adresRekordu(_ rekord: Int) -> Int {
        poczatekRekordowWejsc + (rekord - 1) * dlugoscRekorduWejscia
    }

    /// Czy układ zna ustawienia wejść. Bez tego (np. przy pustym układzie
    /// `unmappedTM2`) zmiana typu nie może być dostępna — pisalibyśmy na ślepo.
    var obslugujeTypPada: Bool {
        layout.globalFields.contains { $0.id.hasPrefix("trigset.") }
    }

    /// Typ pada w rekordzie 1…4 albo `nil`, gdy w pliku stoi kod spoza
    /// zmierzonej tablicy — wtedy edytor go nie nazywa i nie udaje, że wie.
    func padType(rekord: Int) -> TypPada? {
        guard obslugujeTypPada, (1...4).contains(rekord),
              let bajt = file.byte(at: Self.adresRekordu(rekord) + TypyPadow.poczatekWRekordzie)
        else { return nil }
        return TypyPadow.typ(kod: Int(bajt))
    }

    /// Zmienia typ pada DOKŁADNIE tak, jak robi to moduł: wpisuje kod typu
    /// i jego wartości domyślne (Sensitivity, Threshold, Curve, Retrig Cancel,
    /// H/R Adjust, Rim Gain, Noise Cancel oraz dwa bajty wyliczane z typu),
    /// a XTLK Cancel i Input zostawia nietknięte.
    ///
    /// Do tej pory Type był świadomie poza edycją: zapisanie samego kodu
    /// zostawiłoby w pliku komplet parametrów od poprzedniego pada, którego
    /// moduł nigdy by sam nie ustawił. Tablica wartości domyślnych dla
    /// wszystkich 36 typów to usuwa.
    ///
    /// Cała zmiana to JEDNA pozycja na liście zmian (11 bajtów naraz), więc
    /// jedno cofnięcie przywraca typ razem ze wszystkimi parametrami, które
    /// ze sobą pociągnął — w tym te, które użytkownik dostroił ręcznie.
    @discardableResult
    func setPadType(_ typ: TypPada, rekord: Int) -> Bool {
        guard obslugujeTypPada, (1...4).contains(rekord) else {
            lastError = "Pad type cannot be edited with this layout."
            return false
        }
        let start = Self.adresRekordu(rekord) + TypyPadow.poczatekWRekordzie
        guard let stare = file.slice(at: start, length: TypyPadow.dlugosc) else {
            lastError = "Trigger settings point outside the file."
            log.append(.warning, "Rekord wejścia \(rekord) wypada poza plikiem")
            return false
        }
        let xtlk = stare[TypyPadow.pozycjaXTLK - TypyPadow.poczatekWRekordzie]
        let nowe = typ.bajtyRekordu(zachowujacXTLK: xtlk)
        guard nowe != stare else { return true }

        do {
            try file.setSlice(nowe, at: start)
        } catch {
            lastError = error.localizedDescription
            log.append(.error, "Zmiana typu pada nie powiodła się: \(error.localizedDescription)")
            return false
        }

        let poprzedni = TypyPadow.typ(kod: Int(stare[0]))?.nazwa ?? "#\(stare[0])"
        let change = EditChange(
            fieldID: "trigset.\(rekord).type",
            fieldLabel: "Pad Type — \(Self.nazwaRekordu(rekord))",
            scope: .global,
            kit: 1,
            trigger: rekord,
            oldValue: .text(poprzedni),
            newValue: .text(typ.nazwa),
            timestamp: Date(),
            offset: start,
            oldRaw: stare,
            newRaw: nowe
        )
        changes.append(change)
        redoStack.removeAll()
        odswiezPamiecPodreczna()
        log.append(.edit, change.summary + " (z wartościami domyślnymi typu)")
        return true
    }

    /// Czy moduł pokazuje to pole przy obecnych ustawieniach gniazda.
    ///
    /// Tam, gdzie moduł wyświetla „--", edytor pola nie pokazuje — inaczej
    /// dałoby się wpisać wartość, której moduł sam nigdy by nie ustawił
    /// (np. Noise Cancel dla PAD2). Reguły są wyłącznie te zmierzone:
    /// - Rim Gain i H/R Adjust: tylko przy Input = HEAD&RIM,
    /// - Noise Cancel: tylko przy HEAD&RIM i typie RT-30K albo RT-30HR.
    /// Pozostałe pola są zawsze widoczne.
    func czyModulPokazujePole(_ field: FieldSpec) -> Bool {
        let id = field.id
        guard id.hasPrefix("jack."),
              let numer = Int(id.dropFirst("jack.".count).prefix { $0.isNumber }),
              (1...2).contains(numer) else { return true }

        let rekordGlowny = numer * 2 - 1
        let headRim: Bool = {
            guard let input = file.byte(at: Self.adresRekordu(rekordGlowny)) else { return true }
            return input == 0
        }()

        if id.hasSuffix(".rimGain") || id.hasSuffix(".hrAdjust") {
            return headRim
        }
        if id.hasSuffix(".noiseCancel") {
            let typ = padType(rekord: rekordGlowny)?.nazwa
            return headRim && (typ == "RT-30K" || typ == "RT-30HR")
        }
        return true
    }

    private static func nazwaRekordu(_ rekord: Int) -> String {
        let gniazdo = (rekord - 1) / 2 + 1
        return rekord % 2 == 1 ? "TRIG IN \(gniazdo)" : "TRIG IN \(gniazdo) pad 2"
    }

    // MARK: - Efekt kitu

    /// Czy układ zna strefę efektu kitu — czyli czy to jest zmierzona geometria
    /// (blok kitu 234 B). Bez tego zmiana efektu pisałaby na ślepo.
    var obslugujeEfektKitu: Bool {
        layout.canAddressKits && layout.kitStride == 234
    }

    /// Czy slot gra brzmienie wewnętrzne — wtedy numer instrumentu to pozycja
    /// na liście z Sound List i można pokazać nazwę.
    ///
    /// POTWIERDZONE 2026-11-23 (`wav-1.bin`): przypisanie pliku WAV z karty
    /// zmieniło +0x02 z 1 na 2. Czyli 1 = brzmienie wewnętrzne, 2 = karta.
    ///
    /// Kryterium: +0x02 slotu = 1. Tak jest w KAŻDYM slocie każdego backupu
    /// Arka (wszystkie grają brzmienia wewnętrzne). Jak wygląda slot z plikiem
    /// WAV z karty, nie zmierzyliśmy — ale skoro to pole stoi zaraz za numerem
    /// instrumentu i nigdy nie jest inne niż 1, to najlepszy kandydat na
    /// „bank". Przy każdej innej wartości edytor woli pokazać gołą liczbę,
    /// niż przypisać plikowi z karty nazwę brzmienia fabrycznego.
    func brzmienieWewnetrzne(kit: Int, trigger: Int) -> Bool {
        guard let poczatek = layout.triggerOrigin(kit: kit, trigger: trigger),
              let bajty = file.slice(at: poczatek + 0x02, length: 2) else { return false }
        return bajty == [1, 0]
    }

    // MARK: - Sample z karty SD

    /// Tablica ścieżek do plików WAV: 396 wpisów po 256 B (99 kitów × 4 pady),
    /// zaraz za blokiem kitów. To był „obszar ~101 KB zer" — zmierzone
    /// 2026-11-23 (`wav-1.bin`, `wave-2.bin`): przypisanie TEST_A.wav do kitu 70,
    /// TRIG IN 1 head wpisało tekst `TEST_A.wav` pod 0x5AFA + (69·4 + 0)·256,
    /// rim — wpis następny, `TESTY/TEST_C.wav` z podfolderem — kolejny.
    ///
    /// Ścieżka względem `ROLAND/TM-2/WAVE`, ASCII, separator „/", zakończona
    /// zerem. ZA zerem moduł zostawia śmieci z poprzedniego wpisu („TEST_A.wav",
    /// zero, „C.wav") — czytamy tylko do pierwszego zera.
    ///
    /// Moduł szuka pliku PO NAZWIE: dodanie TEST_0.wav, który alfabetycznie
    /// staje przed TEST_A.wav, nie zmieniło tego, co gra pad.
    static let poczatekSciezekWav = 0x5AFA
    static let dlugoscSciezkiWav = 256

    /// Ścieżka sampla z karty przypisanego do padu albo `nil`, gdy pad gra
    /// brzmienie wewnętrzne (albo układ nie jest tym zmierzonym).
    func sciezkaSampla(kit: Int, trigger: Int) -> String? {
        guard layout.kitStride == 234, layout.kitBlockOrigin == 0x7C,
              (1...99).contains(kit), (1...4).contains(trigger),
              let poczatek = layout.triggerOrigin(kit: kit, trigger: trigger),
              file.slice(at: poczatek + 0x02, length: 2) == [2, 0]
        else { return nil }
        let adres = Self.poczatekSciezekWav
            + ((kit - 1) * 4 + (trigger - 1)) * Self.dlugoscSciezkiWav
        guard let wpis = file.slice(at: adres, length: Self.dlugoscSciezkiWav) else { return nil }
        let tekst = wpis.prefix { $0 != 0 }
        guard !tekst.isEmpty else { return nil }
        return String(decoding: tekst, as: UTF8.self)
    }

    /// Czy układ to zmierzona geometria — tylko wtedy wolno zmieniać
    /// brzmienie przez „bank" i tablicę ścieżek.
    var obslugujeBrzmienia: Bool {
        layout.kitStride == 234 && layout.kitBlockOrigin == 0x7C
            && layout.triggerStride == 42 && file.size == 124_748
    }

    /// Numer brzmienia wewnętrznego w slocie (0…161), surowy z +0x00.
    func numerBrzmienia(kit: Int, trigger: Int) -> Int {
        guard let poczatek = layout.triggerOrigin(kit: kit, trigger: trigger),
              let b = file.slice(at: poczatek, length: 2) else { return 0 }
        return Int(b[0]) | (Int(b[1]) << 8)
    }

    /// Folder WAVE, do którego idą sample: obok backupu, jeśli otwarto go
    /// z karty (albo z kopii folderu ROLAND), a jeśli nie — wskazany wcześniej
    /// ręcznie i zapamiętany.
    var folderWave: URL? {
        file.sourceURL.flatMap { KartaSD.folderWave(dlaBackupu: $0) }
            ?? KartaSD.zapamietanyFolderWave
    }

    /// Przypisuje padowi plik WAV z karty: slot dostaje „bank" 2 (karta)
    /// i numer 0, a tablica ścieżek — ścieżkę względem `ROLAND/TM-2/WAVE`.
    ///
    /// Numer 0 a nie to, co wpisuje moduł (161, 154): sprawdzone na sprzęcie
    /// 2026-11-23 plikiem `wav-test` — moduł grał oba sample z numerem 0,
    /// więc szuka pliku wyłącznie po ścieżce.
    ///
    /// Wpis ścieżki jest czyszczony do zera na całej długości — moduł zostawia
    /// za zerem śmieci, edytor nie musi.
    @discardableResult
    func przypiszSampel(sciezka: String, kit: Int, trigger: Int) -> Bool {
        let bajtySciezki = Array(sciezka.utf8)
        guard !bajtySciezki.isEmpty, bajtySciezki.count < Self.dlugoscSciezkiWav,
              bajtySciezki.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else {
            lastError = "The file path must be plain ASCII and shorter than 256 characters."
            return false
        }
        var nowyWpis = [UInt8](repeating: 0, count: Self.dlugoscSciezkiWav)
        nowyWpis.replaceSubrange(0..<bajtySciezki.count, with: bajtySciezki)
        let opisPoprzedni = opisBrzmienia(kit: kit, trigger: trigger)
        return zapiszBrzmienie(slot: [0, 0, 2, 0], wpis: nowyWpis, kit: kit, trigger: trigger,
                               stary: opisPoprzedni, nowy: "SD: " + sciezka)
    }

    /// Wraca do brzmienia wewnętrznego o numerze 0…161 (numer z listy − 1).
    /// Wpisu w tablicy ścieżek nie rusza — przy „banku" 1 moduł go nie czyta.
    @discardableResult
    func ustawBrzmienieWewnetrzne(numer: Int, kit: Int, trigger: Int) -> Bool {
        guard Instrumenty.nazwy.indices.contains(numer) else {
            lastError = "Unknown internal sound #\(numer)."
            return false
        }
        return zapiszBrzmienie(slot: [UInt8(numer & 0xFF), UInt8(numer >> 8), 1, 0], wpis: nil,
                               kit: kit, trigger: trigger,
                               stary: opisBrzmienia(kit: kit, trigger: trigger),
                               nowy: Instrumenty.nazwy[numer])
    }

    private func opisBrzmienia(kit: Int, trigger: Int) -> String {
        if let sciezka = sciezkaSampla(kit: kit, trigger: trigger) { return "SD: " + sciezka }
        guard let poczatek = layout.triggerOrigin(kit: kit, trigger: trigger),
              let b = file.slice(at: poczatek, length: 2) else { return "?" }
        let numer = Int(b[0]) | (Int(b[1]) << 8)
        return Instrumenty.nazwy.indices.contains(numer) ? Instrumenty.nazwy[numer] : "#\(numer)"
    }

    private func zapiszBrzmienie(slot nowySlot: [UInt8], wpis nowyWpis: [UInt8]?,
                                 kit: Int, trigger: Int, stary: String, nowy: String) -> Bool {
        guard obslugujeBrzmienia,
              (1...99).contains(kit), (1...4).contains(trigger),
              let poczatek = layout.triggerOrigin(kit: kit, trigger: trigger),
              let staryslot = file.slice(at: poczatek, length: 4) else {
            lastError = "Sounds cannot be changed with this layout."
            return false
        }
        let adresWpisu = Self.poczatekSciezekWav
            + ((kit - 1) * 4 + (trigger - 1)) * Self.dlugoscSciezkiWav
        var dodatkowe: [FragmentZmiany] = []
        if let nowyWpis {
            guard let staryWpis = file.slice(at: adresWpisu, length: Self.dlugoscSciezkiWav) else {
                lastError = "The sample table points outside the file."
                return false
            }
            if staryWpis != nowyWpis {
                dodatkowe.append(FragmentZmiany(offset: adresWpisu, oldRaw: staryWpis, newRaw: nowyWpis))
            }
        }
        guard staryslot != nowySlot || !dodatkowe.isEmpty else { return true }

        do {
            try file.setSlice(nowySlot, at: poczatek)
            for fragment in dodatkowe {
                try file.setSlice(fragment.newRaw, at: fragment.offset)
            }
        } catch {
            // Cofamy to, co zdążyło wejść — plik nie może zostać w pół drogi.
            try? file.setSlice(staryslot, at: poczatek)
            for fragment in dodatkowe {
                try? file.setSlice(fragment.oldRaw, at: fragment.offset)
            }
            lastError = error.localizedDescription
            log.append(.error, "Zmiana brzmienia nie powiodła się: \(error.localizedDescription)")
            return false
        }

        let change = EditChange(
            fieldID: "trig.instrument",
            fieldLabel: "Instrument",
            scope: .trigger,
            kit: kit,
            trigger: trigger,
            oldValue: .text(stary),
            newValue: .text(nowy),
            timestamp: Date(),
            offset: poczatek,
            oldRaw: staryslot,
            newRaw: nowySlot,
            dodatkowe: dodatkowe
        )
        changes.append(change)
        redoStack.removeAll()
        odswiezPamiecPodreczna()
        log.append(.edit, change.summary)
        return true
    }

    /// Parametry bieżącego efektu kitu, w kolejności z wyświetlacza modułu.
    /// THRU i efekt spoza tablicy — pusta lista.
    func kitEffectParameters(kit: Int) -> [FieldSpec] {
        guard let efekt = kitEffect(kit: kit) else { return [] }
        return ParametryEfektow.parametry(kodEfektu: efekt.kod)
    }

    /// Efekt kitu albo `nil`, gdy w pliku stoi kod spoza zmierzonej tablicy.
    func kitEffect(kit: Int) -> TypEfektu? {
        guard obslugujeEfektKitu,
              let poczatek = layout.kitOrigin(kit: kit),
              let bajty = file.slice(at: poczatek + TypyEfektow.poczatekWKicie, length: 2)
        else { return nil }
        return TypyEfektow.typ(kod: Int(bajty[0]) | (Int(bajty[1]) << 8))
    }

    /// Zmienia efekt kitu tak, jak robi to moduł: typ i wartości domyślne
    /// wszystkich 20 pól parametrów naraz. Parametry poprzedniego efektu nie
    /// mają znaczenia dla nowego — znaczenie pól zależy od typu — więc
    /// zostawienie ich dałoby stan, którego moduł sam nigdy by nie ustawił.
    ///
    /// Jedna pozycja na liście zmian (42 bajty), jedno cofnięcie przywraca
    /// efekt razem z jego parametrami.
    @discardableResult
    func setKitEffect(_ efekt: TypEfektu, kit: Int) -> Bool {
        guard obslugujeEfektKitu, let poczatek = layout.kitOrigin(kit: kit) else {
            lastError = "Kit effect cannot be edited with this layout."
            return false
        }
        let start = poczatek + TypyEfektow.poczatekWKicie
        guard let stare = file.slice(at: start, length: TypyEfektow.dlugosc) else {
            lastError = "Kit effect points outside the file."
            log.append(.warning, "Strefa efektu kitu \(kit) wypada poza plikiem")
            return false
        }
        let nowe = efekt.bajtyStrefy
        guard nowe != stare else { return true }

        do {
            try file.setSlice(nowe, at: start)
        } catch {
            lastError = error.localizedDescription
            log.append(.error, "Zmiana efektu kitu nie powiodła się: \(error.localizedDescription)")
            return false
        }

        let staryKod = Int(stare[0]) | (Int(stare[1]) << 8)
        let poprzedni = TypyEfektow.typ(kod: staryKod)?.nazwa ?? "#\(staryKod)"
        let change = EditChange(
            fieldID: "kit.effect.type",
            fieldLabel: "Kit Effect",
            scope: .kit,
            kit: kit,
            trigger: 1,
            oldValue: .text(poprzedni),
            newValue: .text(efekt.nazwa),
            timestamp: Date(),
            offset: start,
            oldRaw: stare,
            newRaw: nowe
        )
        changes.append(change)
        redoStack.removeAll()
        odswiezPamiecPodreczna()
        log.append(.edit, change.summary + " (z wartościami domyślnymi efektu)")
        return true
    }

    // MARK: - Cofanie i ponawianie

    func undo() {
        guard let change = changes.popLast() else { return }
        do {
            // Od końca — odwrotnie niż przy zapisie.
            for fragment in change.dodatkowe.reversed() {
                try file.setSlice(fragment.oldRaw, at: fragment.offset)
            }
            try file.setSlice(change.oldRaw, at: change.offset)
            redoStack.append(change)
            lastError = nil
            odswiezPamiecPodreczna()
            log.append(.undo, "Cofnięto: \(change.summary)")
        } catch {
            // Ta gałąź jest w praktyce nieosiągalna: `oldRaw` zostało odczytane
            // spod tego samego adresu i o tej samej długości, a plik nie zmienia
            // rozmiaru. Zostaje jako pas bezpieczeństwa.
            //
            // Zmiany NIE wkładamy z powrotem na stos. Gdyby wracała, `canUndo`
            // nigdy by nie zgasło i `revertAll()` kręciłby się w nieskończoność,
            // wieszając całe okno. Koszt tej decyzji: przy błędzie zmiana znika
            // i z historii, i ze stosu ponowień, a plik zostaje zmodyfikowany —
            // dlatego wpis do logu jest tu obowiązkowy.
            lastError = error.localizedDescription
            log.append(.error, "Cofanie nie powiodło się (\(change.fieldID)):"
                + " \(error.localizedDescription)")
        }
    }

    func redo() {
        guard let change = redoStack.popLast() else { return }
        do {
            try file.setSlice(change.newRaw, at: change.offset)
            for fragment in change.dodatkowe {
                try file.setSlice(fragment.newRaw, at: fragment.offset)
            }
            changes.append(change)
            lastError = nil
            odswiezPamiecPodreczna()
            log.append(.edit, "Ponowiono: \(change.summary)")
        } catch {
            // Ta sama zasada co przy cofaniu — nie zapętlamy się.
            lastError = error.localizedDescription
            log.append(.error, "Ponowienie nie powiodło się"
                + " (\(change.fieldID)): \(error.localizedDescription)")
        }
    }

    /// Cofa wszystko naraz. Przywraca dokładnie wczytany plik.
    func revertAll() {
        // „Cofnij wszystko" obejmuje też tekst wpisany, a jeszcze
        // niezatwierdzony — inaczej wróciłby przy najbliższym zapisie
        // i odtworzył zmianę, którą użytkownik właśnie wycofał.
        niezatwierdzonyTekst.removeAll()
        odswiezZnacznikTekstu()

        // Twardy ogranicznik pętli, niezależny od tego, czy `undo()` zdejmuje
        // zmianę ze stosu. Lepiej wyjść z niepełnym cofnięciem i zapisać to
        // w logu niż zawiesić program.
        var pozostalo = changes.count
        while canUndo && pozostalo > 0 {
            undo()
            pozostalo -= 1
        }
        redoStack.removeAll()
        if changes.isEmpty {
            log.append(.undo, "Cofnięto wszystkie zmiany")
        } else {
            log.append(.warning, "Cofnięto część zmian; \(changes.count)"
                + " nie dało się przywrócić — szczegóły powyżej")
        }
    }

    // MARK: - Zapis pliku

    /// Zapisuje do nowego pliku. Nigdy nie nadpisuje oryginału z karty —
    /// to jest twarda zasada projektu, nie preferencja.
    // MARK: - Niezatwierdzony tekst

    /// Tekst wpisany w pole, ale jeszcze niezatwierdzony Enterem.
    ///
    /// Pola tekstowe mają bufor, żeby każda wpisana litera nie trafiała na
    /// listę zmian jako osobna pozycja. Kosztem jest pułapka, w którą Arek
    /// wpadł przy pierwszym teście na sprzęcie: wpisał nazwę kitu, kliknął
    /// „Save As…" bez Entera i w zapisanym pliku została stara nazwa.
    /// Parametry liczbowe się zapisały, nazwa nie — najgorszy możliwy rodzaj
    /// niespójności, bo wygląda na błąd zapisu nazw.
    ///
    /// Dlatego widok melduje tu każdą zmianę w buforze, a zapis opróżnia
    /// rejestr, zanim ruszy bajty. Celowo NIE jest to `@Published`: wpis
    /// leci przy każdym naciśnięciu klawisza i nie ma po co przerysowywać
    /// z tego powodu widoku.
    ///
    /// Od wprowadzenia pól liczbowych z wpisywaniem z klawiatury rejestr
    /// trzyma też liczby — ta sama pułapka dotyczy „300" wpisanego w Offset
    /// i niezatwierdzonego przed kliknięciem „Save As…".
    private var niezatwierdzonyTekst: [String: (pole: FieldSpec, kit: Int,
                                                trigger: Int, wartosc: FieldValue)] = [:]

    /// Czy w buforach czeka jakiś tekst. To jedyna rzecz z rejestru, która
    /// musi być widoczna dla widoków: bez niej przycisk „Save As…" zostaje
    /// wyszarzony po samej zmianie nazwy i nie da się jej w ogóle zapisać.
    ///
    /// Ustawiane TYLKO przy faktycznej zmianie wartości. `@Published` ogłasza
    /// zapis niezależnie od tego, czy coś się zmieniło, więc przypisywanie
    /// `true` przy każdym naciśnięciu klawisza przebudowywałoby okno przy
    /// każdej literze — czyli dokładnie to, przed czym bufor miał chronić.
    @Published private(set) var hasPendingText: Bool = false

    private func odswiezZnacznikTekstu() {
        let teraz = !niezatwierdzonyTekst.isEmpty
        if hasPendingText != teraz { hasPendingText = teraz }
    }

    /// Klucz jest trójką pole-kit-trigger, bo ten sam `FieldSpec` obsługuje
    /// wszystkie kity i triggery.
    private func kluczTekstu(_ field: FieldSpec, kit: Int, trigger: Int) -> String {
        "\(field.id)#\(kit)#\(trigger)"
    }

    func rememberPendingText(_ tekst: String, for field: FieldSpec,
                             kit: Int, trigger: Int) {
        niezatwierdzonyTekst[kluczTekstu(field, kit: kit, trigger: trigger)] =
            (field, kit, trigger, .text(tekst))
        odswiezZnacznikTekstu()
    }

    /// Liczba wpisana z klawiatury, już przeliczona z postaci ekranowej
    /// („R15", „300.0 ms") na wartość pola, ale jeszcze niezatwierdzona.
    func rememberPendingNumber(_ liczba: Int, for field: FieldSpec,
                               kit: Int, trigger: Int) {
        niezatwierdzonyTekst[kluczTekstu(field, kit: kit, trigger: trigger)] =
            (field, kit, trigger, .number(liczba))
        odswiezZnacznikTekstu()
    }

    func forgetPendingText(for field: FieldSpec, kit: Int, trigger: Int) {
        niezatwierdzonyTekst[kluczTekstu(field, kit: kit, trigger: trigger)] = nil
        odswiezZnacznikTekstu()
    }

    /// Zapisuje wszystko, co czeka w buforach pól tekstowych.
    /// Zwraca liczbę pól, które faktycznie zmieniły wartość.
    @discardableResult
    func flushPendingText() -> Int {
        guard !niezatwierdzonyTekst.isEmpty else { return 0 }
        // Kolejność deterministyczna, żeby log i lista zmian wyglądały tak
        // samo przy każdym uruchomieniu.
        let oczekujace = niezatwierdzonyTekst.keys.sorted().compactMap {
            niezatwierdzonyTekst[$0]
        }
        niezatwierdzonyTekst.removeAll()
        odswiezZnacznikTekstu()

        var zapisane = 0
        for wpis in oczekujace {
            let przed = changes.count
            set(wpis.wartosc, for: wpis.pole, kit: wpis.kit, trigger: wpis.trigger)
            if changes.count != przed { zapisane += 1 }
        }
        if zapisane > 0 {
            log.append(.info, "Zatwierdzono \(zapisane) niewysłanych zmian"
                + " wpisanych z klawiatury przed zapisem")
        }
        return zapisane
    }

    /// Po zapisie całości przez projekt (Save As do struktury modułu) —
    /// plakietka niezapisanych zmian gaśnie tak samo jak po `save(to:)`.
    func oznaczJakoZapisane() {
        savedChangeID = changes.last?.id
    }

    func save(to url: URL) {
        // Tekst wpisany bez Entera też jest zmianą, której użytkownik
        // oczekuje w pliku.
        flushPendingText()

        // Porównanie URL-i jest tekstowe, więc /Volumes/SD/BACKUP i
        // /Volumes/SD/./BACKUP byłyby „różne", mimo że to ten sam plik.
        // Przy zasadzie „nigdy nie nadpisujemy oryginału" to za mało —
        // normalizujemy obie ścieżki i rozwijamy dowiązania.
        let zrodlo = file.sourceURL?.standardizedFileURL.resolvingSymlinksInPath()
        let cel = url.standardizedFileURL.resolvingSymlinksInPath()
        if let zrodlo, zrodlo == cel {
            lastError = "Refusing to overwrite the original backup. "
                + "Choose a different file name."
            log.append(.warning, "Odmowa nadpisania oryginału: \(url.lastPathComponent)")
            return
        }
        do {
            try file.write(to: url)
            savedChangeID = changes.last?.id
            log.append(.info, "Zapisano \(changes.count) zmian do "
                + "\(url.lastPathComponent)")
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.append(.error, "Zapis pliku nie powiódł się: \(error)")
        }
    }

    // MARK: - Pomocnicze

    /// Wyszukanie pola po identyfikatorze. Przydatne przy pokazywaniu historii
    /// zmian i przy testach; samo cofanie go nie potrzebuje, bo pracuje na
    /// zapamiętanych bajtach.
    func field(withID id: String) -> FieldSpec? {
        layout.globalFields.first { $0.id == id }
            ?? layout.kitFields.first { $0.id == id }
            ?? layout.triggerFields.first { $0.id == id }
    }
}
