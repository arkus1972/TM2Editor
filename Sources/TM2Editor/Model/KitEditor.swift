import Combine
import Foundation

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

    // MARK: - Cofanie i ponawianie

    func undo() {
        guard let change = changes.popLast() else { return }
        do {
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
    private var niezatwierdzonyTekst: [String: (pole: FieldSpec, kit: Int,
                                                trigger: Int, tekst: String)] = [:]

    /// Klucz jest trójką pole-kit-trigger, bo ten sam `FieldSpec` obsługuje
    /// wszystkie kity i triggery.
    private func kluczTekstu(_ field: FieldSpec, kit: Int, trigger: Int) -> String {
        "\(field.id)#\(kit)#\(trigger)"
    }

    func rememberPendingText(_ tekst: String, for field: FieldSpec,
                             kit: Int, trigger: Int) {
        niezatwierdzonyTekst[kluczTekstu(field, kit: kit, trigger: trigger)] =
            (field, kit, trigger, tekst)
    }

    func forgetPendingText(for field: FieldSpec, kit: Int, trigger: Int) {
        niezatwierdzonyTekst[kluczTekstu(field, kit: kit, trigger: trigger)] = nil
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

        var zapisane = 0
        for wpis in oczekujace {
            let przed = changes.count
            set(.text(wpis.tekst), for: wpis.pole, kit: wpis.kit, trigger: wpis.trigger)
            if changes.count != przed { zapisane += 1 }
        }
        if zapisane > 0 {
            log.append(.info, "Zatwierdzono \(zapisane) niewysłanych zmian"
                + " w polach tekstowych przed zapisem")
        }
        return zapisane
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
