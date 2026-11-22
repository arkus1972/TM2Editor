import XCTest
@testable import TM2Editor

/// Testy modelu edycji.
///
/// Najważniejszy jest tu `testCofanieDzialaNaWartosciSpozaZakresu`. Pilnuje
/// sytuacji, która przy zgadywanych offsetach jest normą, a nie wyjątkiem:
/// bajt pod polem o zadeklarowanym zakresie 0…100 ma wartość 200, bo offset
/// jest jeszcze niepewny. Gdyby cofanie odtwarzało wartość logiczną, taka
/// zmiana byłaby niecofalna, a `revertAll()` zapętliłby się i zawiesił okno.
@MainActor
final class KitEditorTests: XCTestCase {

    private let header = 64
    private let kitSize = 128
    private let levelOffset = 32

    private func makeLayout() -> BackupLayout {
        var layout = BackupLayout.unmappedTM2
        layout.kitBlockOrigin = header
        layout.kitStride = kitSize
        layout.triggerBlockOrigin = levelOffset
        layout.triggerStride = 16

        for index in layout.kitFields.indices where layout.kitFields[index].id == "kit.name" {
            layout.kitFields[index].offset = 0
        }
        for index in layout.triggerFields.indices where layout.triggerFields[index].id == "trig.level" {
            layout.triggerFields[index].offset = 0
        }
        return layout
    }

    private func makeBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: header + 99 * kitSize + 4)
        for kit in 0..<99 {
            let base = header + kit * kitSize
            let name = Array("KIT\(String(format: "%02d", kit + 1))   ".utf8).prefix(8)
            for (index, byte) in name.enumerated() {
                bytes[base + index] = byte
            }
            bytes[base + levelOffset] = 100
        }
        return bytes
    }

    private func makeEditor(bytes: [UInt8]? = nil) -> KitEditor {
        let layout = makeLayout()
        let file = BackupFile(bytes: bytes ?? makeBytes(), layout: layout)
        return KitEditor(file: file, log: EditorLog())
    }

    private func levelField(_ editor: KitEditor) -> FieldSpec {
        // W testach wolno wymusić — brak tego pola oznaczałby błąd w profilu,
        // a nie sytuację do obsłużenia.
        // swiftlint:disable:next force_unwrapping
        return editor.layout.triggerFields.first { $0.id == "trig.level" }!
    }

    // MARK: - Podstawy

    func testZapisTworzyPozycjeNaLiscieZmian() {
        let editor = makeEditor()
        let field = levelField(editor)

        XCTAssertTrue(editor.set(.number(50), for: field, kit: 1, trigger: 1))
        XCTAssertEqual(editor.changes.count, 1)
        XCTAssertTrue(editor.canUndo)
        XCTAssertFalse(editor.canRedo)
        XCTAssertTrue(editor.hasUnsavedChanges)
    }

    func testZapisTejSamejWartosciNieZasmiecaListy() {
        let editor = makeEditor()
        let field = levelField(editor)

        XCTAssertTrue(editor.set(.number(100), for: field, kit: 1, trigger: 1))
        XCTAssertEqual(editor.changes.count, 0)
    }

    func testZapisDoNiezmapowanegoPolaJestOdrzucany() {
        let file = BackupFile(bytes: makeBytes(), layout: .unmappedTM2)
        let editor = KitEditor(file: file, log: EditorLog())
        guard let field = editor.layout.triggerFields.first(where: { $0.id == "trig.level" }) else {
            return XCTFail("Brak pola trig.level")
        }
        XCTAssertFalse(editor.set(.number(50), for: field, kit: 1, trigger: 1))
        XCTAssertEqual(editor.changes.count, 0)
        XCTAssertNotNil(editor.lastError)
    }

    // MARK: - Cofanie i ponawianie

    func testCofanieOdtwarzaBajtCoDoBajtu() {
        let bytes = makeBytes()
        let editor = makeEditor(bytes: bytes)
        let field = levelField(editor)

        editor.set(.number(50), for: field, kit: 4, trigger: 2)
        XCTAssertNotEqual(editor.file.bytes, bytes)

        editor.undo()
        XCTAssertEqual(editor.file.bytes, bytes)
        XCTAssertFalse(editor.canUndo)
        XCTAssertTrue(editor.canRedo)
    }

    func testPonowienieWracaDoZmienionegoStanu() {
        let editor = makeEditor()
        let field = levelField(editor)

        editor.set(.number(50), for: field, kit: 1, trigger: 1)
        let poZmianie = editor.file.bytes
        editor.undo()
        editor.redo()

        XCTAssertEqual(editor.file.bytes, poZmianie)
        XCTAssertTrue(editor.canUndo)
        XCTAssertFalse(editor.canRedo)
    }

    func testNowaZmianaZamykaGalazPonowien() {
        let editor = makeEditor()
        let field = levelField(editor)

        editor.set(.number(50), for: field, kit: 1, trigger: 1)
        editor.undo()
        XCTAssertTrue(editor.canRedo)

        editor.set(.number(60), for: field, kit: 1, trigger: 1)
        XCTAssertFalse(editor.canRedo)
    }

    /// Test regresyjny: bajt spoza zadeklarowanego zakresu.
    func testCofanieDzialaNaWartosciSpozaZakresu() {
        var bytes = makeBytes()
        let adresPoziomu = header + levelOffset      // kit 1, trigger 1
        bytes[adresPoziomu] = 200                    // poza zakresem 0…100
        let editor = makeEditor(bytes: bytes)
        let field = levelField(editor)

        XCTAssertTrue(editor.set(.number(50), for: field, kit: 1, trigger: 1))
        editor.undo()

        XCTAssertEqual(editor.file.byte(at: adresPoziomu), 200,
                       "Cofanie musi przywrócić surowy bajt, także taki, "
                        + "którego walidacja zapisu by nie przepuściła.")
        XCTAssertFalse(editor.canUndo)
    }

    /// Test regresyjny: `revertAll()` musi się zakończyć.
    func testRevertAllZawszeSieKonczy() {
        var bytes = makeBytes()
        bytes[header + levelOffset] = 200
        bytes[header + kitSize + levelOffset] = 250
        let editor = makeEditor(bytes: bytes)
        let field = levelField(editor)
        let stanPoczatkowy = editor.file.bytes

        editor.set(.number(10), for: field, kit: 1, trigger: 1)
        editor.set(.number(20), for: field, kit: 2, trigger: 1)
        editor.set(.number(30), for: field, kit: 3, trigger: 1)

        editor.revertAll()

        XCTAssertFalse(editor.canUndo)
        XCTAssertEqual(editor.file.bytes, stanPoczatkowy)
    }

    // MARK: - Zapis

    func testOdmowaNadpisaniaOryginalu() {
        let katalog = FileManager.default.temporaryDirectory
        let url = katalog.appendingPathComponent("tm2-test-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNoThrow(try Data(makeBytes()).write(to: url))

        guard let file = try? BackupFile(contentsOf: url, layout: makeLayout()) else {
            return XCTFail("Nie udało się wczytać pliku testowego")
        }
        let editor = KitEditor(file: file, log: EditorLog())
        editor.set(.number(50), for: levelField(editor), kit: 1, trigger: 1)

        editor.save(to: url)

        XCTAssertNotNil(editor.lastError, "Zapis pod ścieżkę oryginału musi zostać odrzucony.")
        let naDysku = try? Data(contentsOf: url)
        XCTAssertEqual(naDysku.map { [UInt8]($0) }, makeBytes(),
                       "Plik źródłowy nie mógł zostać zmieniony.")
    }

    /// Test regresyjny: po zapisie, cofnięciu i nowej edycji liczba zmian
    /// wraca do tej samej wartości, ale zawartość jest inna niż na dysku.
    /// Plakietka „unsaved changes" musi się zapalić.
    func testCofniecieINowaEdycjaZnowuOznaczajaNiezapisaneZmiany() {
        let editor = makeEditor()
        let field = levelField(editor)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm2-out-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        editor.set(.number(10), for: field, kit: 1, trigger: 1)
        editor.set(.number(20), for: field, kit: 2, trigger: 1)
        editor.set(.number(30), for: field, kit: 3, trigger: 1)
        editor.save(to: url)
        XCTAssertFalse(editor.hasUnsavedChanges)

        editor.undo()
        XCTAssertTrue(editor.hasUnsavedChanges, "Cofnięcie po zapisie to zmiana.")

        editor.set(.number(99), for: field, kit: 3, trigger: 1)
        XCTAssertEqual(editor.changes.count, 3, "Liczba zmian wróciła do trzech...")
        XCTAssertTrue(editor.hasUnsavedChanges,
                      "...ale zawartość jest inna niż zapisana na dysk.")
    }

    func testCofniecieDoStanuZapisanegoGasiPlakietke() {
        let editor = makeEditor()
        let field = levelField(editor)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm2-out-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        editor.set(.number(10), for: field, kit: 1, trigger: 1)
        editor.save(to: url)
        editor.set(.number(20), for: field, kit: 2, trigger: 1)
        XCTAssertTrue(editor.hasUnsavedChanges)

        editor.undo()
        XCTAssertFalse(editor.hasUnsavedChanges)
    }

    func testZapisDoNowegoPlikuGasiPlakietkeNiezapisanychZmian() {
        let editor = makeEditor()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm2-out-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        editor.set(.number(50), for: levelField(editor), kit: 1, trigger: 1)
        XCTAssertTrue(editor.hasUnsavedChanges)

        editor.save(to: url)

        XCTAssertNil(editor.lastError)
        XCTAssertFalse(editor.hasUnsavedChanges)
        XCTAssertEqual(editor.changes.count, 1, "Historia zmian ma zostać.")
    }

    // MARK: - Bufory dla listy kitów

    /// Lista 99 kitów nie dekoduje już nazw wiersz po wierszu — bierze je
    /// z bufora. Bufor musi mówić dokładnie to samo, co odczyt wprost;
    /// inaczej optymalizacja zamienia się w cichy błąd wyświetlania.
    func testBuforNazwZgadzaSieZOdczytemWprost() {
        let editor = makeEditor()
        XCTAssertEqual(editor.kitNames.count, max(editor.layout.kitCount, 1))
        for kit in 1...editor.layout.kitCount {
            XCTAssertEqual(editor.kitNames[kit - 1], editor.kitName(kit),
                           "Bufor rozjechał się z odczytem dla kitu \(kit).")
        }
    }

    /// Zmiana nazwy musi być widoczna w buforze od razu, bez ponownego
    /// wczytywania pliku.
    func testBuforNazwNadazaZaEdycjaINadCofnieciem() {
        let editor = makeEditor()
        guard let nameField = editor.layout.kitFields.first(where: { $0.id == "kit.name" }),
              nameField.isMapped else {
            XCTFail("Profil testowy ma mieć zmapowane kit.name.")
            return
        }
        let przed = editor.kitNames[6]

        editor.set(.text("NOWA"), for: nameField, kit: 7, trigger: 1)
        XCTAssertEqual(editor.kitNames[6], editor.kitName(7))
        XCTAssertNotEqual(editor.kitNames[6], przed,
                          "Bufor pokazuje starą nazwę po edycji.")

        editor.undo()
        XCTAssertEqual(editor.kitNames[6], przed,
                       "Bufor nie wrócił do stanu przed edycją.")
    }

    /// Kropka przy wierszu bierze się z gotowego zbioru, nie z liniowego
    /// przeszukiwania historii w każdym z 99 wierszy.
    func testZbiorZmienionychKitowNadazaZaHistoria() {
        let editor = makeEditor()
        XCTAssertTrue(editor.changedKits.isEmpty)

        editor.set(.number(42), for: levelField(editor), kit: 5, trigger: 1)
        XCTAssertEqual(editor.changedKits, [5])

        editor.set(.number(43), for: levelField(editor), kit: 9, trigger: 1)
        XCTAssertEqual(editor.changedKits, [5, 9])

        editor.undo()
        XCTAssertEqual(editor.changedKits, [5],
                       "Cofnięcie ma zdjąć kropkę z kitu 9.")

        editor.redo()
        XCTAssertEqual(editor.changedKits, [5, 9],
                       "Ponowienie ma kropkę przywrócić.")
    }

    // MARK: - Zaznaczenie

    /// Zaznaczenie to osobny obiekt, nie część edytora. Ten test pilnuje
    /// przede wszystkim tego, że edytor go nie zna — gdyby ktoś kiedyś
    /// dopisał `selectedKit` z powrotem do `KitEditor`, przełączanie
    /// triggerów znowu zaczęłoby przebudowywać całe okno.
    func testZaznaczenieStartujeOdPierwszegoKituITriggera() {
        let selection = EditorSelection()
        XCTAssertEqual(selection.kit, 1)
        XCTAssertEqual(selection.trigger, 1)

        selection.kit = 42
        selection.trigger = 3
        selection.reset()

        XCTAssertEqual(selection.kit, 1, "Nowy plik ma startować od kitu 1.")
        XCTAssertEqual(selection.trigger, 1)
    }

    // MARK: - Niezatwierdzony tekst

    private func nameField(_ editor: KitEditor) -> FieldSpec {
        // swiftlint:disable:next force_unwrapping
        return editor.layout.kitFields.first { $0.id == "kit.name" }!
    }

    /// Pierwszy test edytora na prawdziwym sprzęcie wyłapał to: Arek wpisał
    /// nazwę kitu, kliknął „Save As…" bez naciśnięcia Entera i w zapisanym
    /// pliku została stara nazwa, choć parametry liczbowe zapisały się
    /// poprawnie. Zapis musi brać to, co użytkownik widzi na ekranie.
    func testZapisZatwierdzaTekstWpisanyBezEntera() throws {
        let editor = makeEditor()
        let pole = nameField(editor)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm2-out-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        editor.rememberPendingText("DUPAKIT", for: pole, kit: 99, trigger: 1)
        XCTAssertTrue(editor.changes.isEmpty, "Sam bufor nie jest jeszcze zmianą.")

        editor.save(to: url)

        XCTAssertNil(editor.lastError)
        XCTAssertEqual(editor.kitName(99), "DUPAKIT",
                       "Zapis miał zatwierdzić tekst z bufora.")
        XCTAssertEqual(editor.kitNames[98], "DUPAKIT",
                       "Lista kitów ma pokazać nową nazwę.")

        // I to samo w pliku na dysku, nie tylko w pamięci.
        let zapisane = try Data(contentsOf: url)
        let odczytany = BackupFile(bytes: [UInt8](zapisane), layout: editor.layout)
        XCTAssertEqual(odczytany.value(of: pole, kit: 99, trigger: 1)?.textValue,
                       "DUPAKIT")
    }

    /// Bufor jest jednorazowy: po zatwierdzeniu nie może wrócić przy
    /// następnym zapisie i cofnąć ręcznej edycji zrobionej w międzyczasie.
    func testZatwierdzonyTekstNieWracaPrzyKolejnymZapisie() {
        let editor = makeEditor()
        let pole = nameField(editor)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm2-out-\(UUID().uuidString).bin")
        let drugi = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm2-out-\(UUID().uuidString).bin")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: drugi)
        }

        editor.rememberPendingText("PIERWSZA", for: pole, kit: 5, trigger: 1)
        editor.save(to: url)
        XCTAssertEqual(editor.kitName(5), "PIERWSZA")

        editor.set(.text("DRUGA"), for: pole, kit: 5, trigger: 1)
        editor.save(to: drugi)
        XCTAssertEqual(editor.kitName(5), "DRUGA",
                       "Stary bufor nie może wrócić i nadpisać nowszej edycji.")
    }

    /// Zapominanie bufora (np. po Enterze) ma działać — inaczej zapis
    /// dopisywałby do listy zmian drugą, identyczną pozycję.
    func testZapomnianyBuforNieJestJuzZapisywany() {
        let editor = makeEditor()
        let pole = nameField(editor)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm2-out-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        editor.rememberPendingText("ABC", for: pole, kit: 3, trigger: 1)
        editor.forgetPendingText(for: pole, kit: 3, trigger: 1)
        editor.save(to: url)

        XCTAssertTrue(editor.changes.isEmpty,
                      "Porzucony bufor nie może trafić do pliku.")
    }

    /// Przycisk „Save As…" jest wyszarzony, dopóki nie ma czego zapisać.
    /// Sam wpisany tekst, jeszcze bez Entera, też jest powodem do zapisu —
    /// inaczej po samej zmianie nazwy kitu nie dało się jej zapisać w ogóle.
    func testSamWpisanyTekstWystarczyZebyBylCoZapisac() {
        let editor = makeEditor()
        let pole = nameField(editor)
        XCTAssertFalse(editor.hasUnsavedChanges)
        XCTAssertFalse(editor.hasPendingText)

        editor.rememberPendingText("DUPAKIT", for: pole, kit: 99, trigger: 1)
        XCTAssertTrue(editor.hasPendingText,
                      "Wpisany tekst ma odblokować zapis.")
        XCTAssertFalse(editor.hasUnsavedChanges,
                       "...ale sam w sobie nie jest jeszcze zmianą na liście.")

        editor.forgetPendingText(for: pole, kit: 99, trigger: 1)
        XCTAssertFalse(editor.hasPendingText)
    }

    /// „Cofnij wszystko" ma gasić także znacznik wpisanego tekstu.
    func testCofnieciewszystkiegoGasiZnacznikTekstu() {
        let editor = makeEditor()
        editor.rememberPendingText("ABC", for: nameField(editor), kit: 2, trigger: 1)
        XCTAssertTrue(editor.hasPendingText)

        editor.revertAll()
        XCTAssertFalse(editor.hasPendingText)
    }

    /// Ta sama pułapka co z nazwą kitu, tylko dla liczb: „300" wpisane w pole
    /// i niezatwierdzone przed „Save As…" musi trafić do pliku.
    func testZapisZatwierdzaLiczbeWpisanaBezEntera() {
        let editor = makeEditor()
        let pole = levelField(editor)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm2-out-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        editor.rememberPendingNumber(42, for: pole, kit: 12, trigger: 1)
        XCTAssertTrue(editor.hasPendingText, "Wpisana liczba ma odblokować zapis.")
        XCTAssertTrue(editor.changes.isEmpty)

        editor.save(to: url)

        XCTAssertEqual(editor.value(of: pole, kit: 12, trigger: 1)?.numberValue, 42)
        XCTAssertFalse(editor.hasPendingText)
    }
}
