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

    /// Aktualnie wybrany kit (numerowany od 1, jak w module).
    @Published var selectedKit: Int = 1

    /// Aktualnie wybrany trigger (numerowany od 1).
    @Published var selectedTrigger: Int = 1

    let log: EditorLog

    // Log jest przekazywany jawnie, bez domyślnej wartości. Wyrażenie domyślnego
    // argumentu jest w starszych wersjach Swifta nieizolowane, a `EditorLog()`
    // to inicjalizator @MainActor — na Swifcie 5.9 taki domyślny argument się
    // nie kompiluje.
    init(file: BackupFile, log: EditorLog) {
        self.file = file
        self.log = log
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

    func value(of field: FieldSpec) -> FieldValue? {
        file.value(of: field, kit: selectedKit, trigger: selectedTrigger)
    }

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
    func set(_ value: FieldValue, for field: FieldSpec) -> Bool {
        set(value, for: field, kit: selectedKit, trigger: selectedTrigger)
    }

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
    func save(to url: URL) {
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
