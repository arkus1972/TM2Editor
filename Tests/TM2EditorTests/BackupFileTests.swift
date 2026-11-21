import XCTest
@testable import TM2Editor

/// Testy działają na sztucznym pliku o znanym układzie — tym samym, który
/// generuje `tools/tm2diff.py gen`. Dzięki temu sprawdzamy warstwę odczytu
/// i zapisu, zanim jeszcze poznamy prawdziwy format pliku BACKUP.
final class BackupFileTests: XCTestCase {

    // Układ pliku testowego, celowo taki sam jak w generatorze.
    private let header = 64
    private let kitSize = 128
    private let nameOffset = 0
    private let nameLength = 8
    private let levelOffset = 32

    private func makeLayout() -> BackupLayout {
        var layout = BackupLayout.unmappedTM2
        layout.kitBlockOrigin = header
        layout.kitStride = kitSize
        layout.kitCount = 99
        layout.triggerBlockOrigin = 40
        layout.triggerStride = 16
        layout.triggerCount = 4

        for index in layout.kitFields.indices where layout.kitFields[index].id == "kit.name" {
            layout.kitFields[index].offset = nameOffset
        }
        for index in layout.triggerFields.indices where layout.triggerFields[index].id == "trig.level" {
            layout.triggerFields[index].offset = 0
        }
        return layout
    }

    private func makeBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: header + 99 * kitSize + 4)
        bytes[0] = 0x54; bytes[1] = 0x4D; bytes[2] = 0x32; bytes[3] = 0x42   // "TM2B"
        for kit in 0..<99 {
            let base = header + kit * kitSize
            let name = Array("KIT\(String(format: "%02d", kit + 1))   ".utf8).prefix(nameLength)
            for (index, byte) in name.enumerated() {
                bytes[base + nameOffset + index] = byte
            }
            bytes[base + levelOffset] = 100
        }
        return bytes
    }

    // MARK: - Adresowanie

    func testKitOriginUsesStride() {
        let layout = makeLayout()
        XCTAssertEqual(layout.kitOrigin(kit: 1), header)
        XCTAssertEqual(layout.kitOrigin(kit: 2), header + kitSize)
        XCTAssertEqual(layout.kitOrigin(kit: 99), header + 98 * kitSize)
    }

    func testKitOriginRejectsOutOfRange() {
        let layout = makeLayout()
        XCTAssertNil(layout.kitOrigin(kit: 0))
        XCTAssertNil(layout.kitOrigin(kit: 100))
    }

    func testTriggerOriginCombinesBothStrides() {
        let layout = makeLayout()
        XCTAssertEqual(layout.triggerOrigin(kit: 1, trigger: 1), header + 40)
        XCTAssertEqual(layout.triggerOrigin(kit: 1, trigger: 3), header + 40 + 32)
        XCTAssertEqual(layout.triggerOrigin(kit: 2, trigger: 1), header + kitSize + 40)
    }

    func testUnmappedLayoutCannotAddress() {
        let layout = BackupLayout.unmappedTM2
        XCTAssertFalse(layout.canAddressKits)
        XCTAssertNil(layout.kitOrigin(kit: 1))
    }

    // MARK: - Odczyt

    func testReadsKitName() {
        let file = BackupFile(bytes: makeBytes(), layout: makeLayout())
        guard let field = file.layout.kitFields.first(where: { $0.id == "kit.name" }) else {
            return XCTFail("Brak pola kit.name")
        }
        XCTAssertEqual(file.value(of: field, kit: 1)?.textValue, "KIT01")
        XCTAssertEqual(file.value(of: field, kit: 7)?.textValue, "KIT07")
    }

    func testUnmappedFieldReadsAsNil() {
        let file = BackupFile(bytes: makeBytes(), layout: BackupLayout.unmappedTM2)
        guard let field = file.layout.kitFields.first(where: { $0.id == "kit.name" }) else {
            return XCTFail("Brak pola kit.name")
        }
        XCTAssertNil(file.value(of: field, kit: 1))
    }

    // MARK: - Zapis

    func testWritesUnsignedValue() throws {
        var file = BackupFile(bytes: makeBytes(), layout: makeLayout())
        guard let field = file.layout.triggerFields.first(where: { $0.id == "trig.level" }) else {
            return XCTFail("Brak pola trig.level")
        }
        try file.setValue(.number(42), for: field, kit: 3, trigger: 2)
        XCTAssertEqual(file.value(of: field, kit: 3, trigger: 2)?.numberValue, 42)
        // Sąsiedni kit nie może się ruszyć.
        XCTAssertNotEqual(file.value(of: field, kit: 4, trigger: 2)?.numberValue, 42)
    }

    func testRejectsValueOutOfRange() {
        var file = BackupFile(bytes: makeBytes(), layout: makeLayout())
        guard let field = file.layout.triggerFields.first(where: { $0.id == "trig.level" }) else {
            return XCTFail("Brak pola trig.level")
        }
        XCTAssertThrowsError(try file.setValue(.number(250), for: field, kit: 1, trigger: 1))
    }

    func testRejectsWriteToUnmappedField() {
        var file = BackupFile(bytes: makeBytes(), layout: BackupLayout.unmappedTM2)
        guard let field = file.layout.kitFields.first(where: { $0.id == "kit.name" }) else {
            return XCTFail("Brak pola kit.name")
        }
        XCTAssertThrowsError(try file.setValue(.text("TEST"), for: field, kit: 1))
    }

    func testAsciiWritePadsWithSpaces() throws {
        var file = BackupFile(bytes: makeBytes(), layout: makeLayout())
        guard let field = file.layout.kitFields.first(where: { $0.id == "kit.name" }) else {
            return XCTFail("Brak pola kit.name")
        }
        try file.setValue(.text("AB"), for: field, kit: 1)
        let raw = file.slice(at: header, length: nameLength)
        XCTAssertEqual(raw, [0x41, 0x42, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20])
        XCTAssertEqual(file.value(of: field, kit: 1)?.textValue, "AB")
    }

    func testAsciiWriteRejectsTooLongText() {
        var file = BackupFile(bytes: makeBytes(), layout: makeLayout())
        guard let field = file.layout.kitFields.first(where: { $0.id == "kit.name" }) else {
            return XCTFail("Brak pola kit.name")
        }
        XCTAssertThrowsError(try file.setValue(.text("TOODAMNLONG"), for: field, kit: 1))
    }

    // MARK: - Kodowanie z przesunięciem

    func testBiasedEncodingRoundTrip() throws {
        var layout = makeLayout()
        layout.globalFields = [
            FieldSpec(id: "test.pan", label: "Pan", scope: .global, group: .system,
                      offset: 10, encoding: .biased(bias: 64, min: -32, max: 32), note: nil)
        ]
        var file = BackupFile(bytes: makeBytes(), layout: layout)
        let field = layout.globalFields[0]

        try file.setValue(.number(0), for: field)
        XCTAssertEqual(file.byte(at: 10), 64)

        try file.setValue(.number(-32), for: field)
        XCTAssertEqual(file.byte(at: 10), 32)
        XCTAssertEqual(file.value(of: field)?.numberValue, -32)

        try file.setValue(.number(32), for: field)
        XCTAssertEqual(file.byte(at: 10), 96)
    }

    // MARK: - Szum i różnice

    func testNoiseRangesAreExcludedFromDiff() throws {
        var layout = makeLayout()
        layout.noiseRanges = [ByteRange(start: 4, end: 7)]
        var file = BackupFile(bytes: makeBytes(), layout: layout)

        try file.setByte(0xFF, at: 5)     // w zakresie szumu
        try file.setByte(0xFF, at: 20)    // poza

        let modified = file.modifiedOffsets()
        XCTAssertFalse(modified.contains(5))
        XCTAssertTrue(modified.contains(20))
    }

    // MARK: - UTF-16LE (nazwa kitu w prawdziwym pliku BACKUP)

    /// Regresja dla znaleziska z 2026-09-02: nazwy kitów w prawdziwym pliku
    /// są UTF-16LE, nie ASCII. Ten test sprawdza kodowanie niezależnie od
    /// `mapped2026_09_02`, na sztucznym polu, żeby awaria w jednym nie
    /// maskowała awarii w drugim.
    func testUtf16LERoundTrip() throws {
        let field = FieldSpec(id: "test.name16", label: "Name", scope: .global,
                              group: .kit, offset: 0, encoding: .utf16LE(length: 22), note: nil)
        var layout = BackupLayout.unmappedTM2
        layout.globalFields = [field]
        var file = BackupFile(bytes: [UInt8](repeating: 0xFF, count: 32), layout: layout)

        try file.setValue(.text("Claps!"), for: field)
        XCTAssertEqual(file.value(of: field)?.textValue, "Claps!")

        // "Cl" w UTF-16LE: bajt niski, potem 0x00, na przemian.
        XCTAssertEqual(file.slice(at: 0, length: 4), [0x43, 0x00, 0x6C, 0x00])

        // Dopełnienie spacjami (0x0020), nie zerami -- tak jak w prawdziwym
        // pliku ("New Kit    " z odstępami, nie zerami po nazwie).
        XCTAssertEqual(file.slice(at: 12, length: 2), [0x20, 0x00])
    }

    func testUtf16LERejectsTooLongText() {
        let field = FieldSpec(id: "test.name16", label: "Name", scope: .global,
                              group: .kit, offset: 0, encoding: .utf16LE(length: 4), note: nil)
        var layout = BackupLayout.unmappedTM2
        layout.globalFields = [field]
        var file = BackupFile(bytes: [UInt8](repeating: 0, count: 8), layout: layout)
        XCTAssertThrowsError(try file.setValue(.text("TooLong"), for: field))
    }

    // MARK: - Bezpieczeństwo układu potwierdzonego na sprzęcie

    /// Pilnuje, żeby cztery sloty brzmień mieściły się w bloku kitu.
    ///
    /// To jest następca testu, który wcześniej bronił `triggerCount = 2`.
    /// Tamten opisywał model obalony 2026-11-21 (dwa rekordy po 84 B);
    /// dziś wiemy, że slotów są cztery po 42 B i mieszczą się bez konfliktu.
    /// Pilnowana zasada została jednak ta sama i jest to zasada bezpieczeństwa:
    /// **ostatni slot nie może wyjść poza blok kitu**, bo zapis wszedłby
    /// w dane sąsiada.
    func testFourTriggerSlotsFitExactlyInsideKitBlock() {
        let layout = BackupLayout.mapped2026_09_02

        guard let kitStride = layout.kitStride,
              let trigOrigin = layout.triggerBlockOrigin,
              let trigStride = layout.triggerStride
        else {
            return XCTFail("Brakuje geometrii w mapped2026_09_02.")
        }

        XCTAssertEqual(layout.triggerCount, 4,
            "Cztery sloty: head i rim obu gniazd TRIG IN.")

        let koniecOstatniegoSlotu = trigOrigin + layout.triggerCount * trigStride
        XCTAssertEqual(koniecOstatniegoSlotu, kitStride,
            "Sloty mają domykać blok kitu co do bajtu: 0x42 + 4×42 = 234.")

        // Pierwszy slot następnego kitu musi wypaść dokładnie tam, gdzie
        // zaczyna się następny blok -- czyli na jego nazwie, nie w środku
        // danych poprzedniego.
        guard let slot1Kit2 = layout.triggerOrigin(kit: 2, trigger: 1),
              let kit2 = layout.kitOrigin(kit: 2) else {
            return XCTFail("Nie da się policzyć adresów dla kitu 2.")
        }
        XCTAssertEqual(slot1Kit2, kit2 + trigOrigin)
    }

    /// Adresy zmierzone na module muszą wychodzić z geometrii co do bajtu.
    /// Liczby wzięte z realnych pomiarów na kicie 40, nie z rachunku na kartce.
    func testMeasuredAddressesForKit40() {
        let layout = BackupLayout.mapped2026_09_02

        XCTAssertEqual(layout.kitOrigin(kit: 40), 9250,
            "Nazwa kitu 40 -- widoczna w edytorze jako 0x2422 (9250).")
        XCTAssertEqual(layout.triggerOrigin(kit: 40, trigger: 1), 9316,
            "TRIG IN 1 head -- tam siedzi Instrument zmierzony we wrześniu.")
        XCTAssertEqual(layout.triggerOrigin(kit: 40, trigger: 3), 9400,
            "TRIG IN 2 head -- tam wylądował Level=7 z pomiaru 2026-11-21.")

        guard let level = layout.triggerFields.first(where: { $0.id == "trig.level" }),
              let offset = layout.absoluteOffset(for: level, kit: 40, trigger: 3) else {
            return XCTFail("Brak pola trig.level albo nie da się policzyć adresu.")
        }
        XCTAssertEqual(offset, 9404, "Zmierzony adres Level dla TRIG IN 2 head.")
    }

    // MARK: - Liczby 16-bit ze znakiem (Pitch w prawdziwym pliku)

    /// Wzorce bajtów wzięte z prawdziwych pomiarów na module (2026-09-04),
    /// nie wymyślone: +120 dało `78 00`, −120 dało `88 FF`, a w pliku bazowym
    /// kit 1 / trigger 2 ma fabrycznie `FE FF` = −2.
    func testSigned16LEMatchesMeasuredBytePatterns() throws {
        let field = FieldSpec(id: "test.pitch", label: "Pitch", scope: .global,
                              group: .sound, offset: 0,
                              encoding: .signed16LE(min: -120, max: 120), note: nil)
        var layout = BackupLayout.unmappedTM2
        layout.globalFields = [field]
        var file = BackupFile(bytes: [UInt8](repeating: 0xAA, count: 8), layout: layout)

        try file.setValue(.number(120), for: field)
        XCTAssertEqual(file.slice(at: 0, length: 2), [0x78, 0x00])
        XCTAssertEqual(file.value(of: field)?.numberValue, 120)

        try file.setValue(.number(-120), for: field)
        XCTAssertEqual(file.slice(at: 0, length: 2), [0x88, 0xFF])
        XCTAssertEqual(file.value(of: field)?.numberValue, -120)

        try file.setValue(.number(-2), for: field)
        XCTAssertEqual(file.slice(at: 0, length: 2), [0xFE, 0xFF])
        XCTAssertEqual(file.value(of: field)?.numberValue, -2)

        try file.setValue(.number(0), for: field)
        XCTAssertEqual(file.slice(at: 0, length: 2), [0x00, 0x00])
        XCTAssertEqual(file.value(of: field)?.numberValue, 0)
    }

    func testSigned16LERejectsValueOutsideDeclaredRange() {
        let field = FieldSpec(id: "test.pitch", label: "Pitch", scope: .global,
                              group: .sound, offset: 0,
                              encoding: .signed16LE(min: -120, max: 120), note: nil)
        var layout = BackupLayout.unmappedTM2
        layout.globalFields = [field]
        var file = BackupFile(bytes: [UInt8](repeating: 0, count: 8), layout: layout)

        XCTAssertThrowsError(try file.setValue(.number(121), for: field))
        XCTAssertThrowsError(try file.setValue(.number(-121), for: field))
    }

    // MARK: - Zgodność layoutu ze zmierzonymi offsetami

    /// Offsety pól wewnątrz slotu brzmienia. Liczby mają pokrycie w dzienniku
    /// mapowania — jeśli test zacznie padać, ktoś zmienił layout bez pomiaru.
    func testMappedLayoutMatchesMeasuredSoundSlot() {
        let layout = BackupLayout.mapped2026_09_02

        func field(_ id: String) -> FieldSpec? {
            layout.triggerFields.first(where: { $0.id == id })
        }

        XCTAssertEqual(field("trig.instrument")?.offset, 0)
        XCTAssertEqual(field("trig.level")?.offset, 4)
        XCTAssertEqual(field("trig.pitch")?.offset, 6)
        XCTAssertEqual(field("trig.pan")?.offset, 8)
        XCTAssertEqual(field("trig.loop")?.offset, 14)
        XCTAssertEqual(field("trig.offset")?.offset, 26)

        XCTAssertEqual(field("trig.pitch")?.encoding, .signed16LE(min: -120, max: 120))
        XCTAssertEqual(field("trig.pan")?.encoding, .biased(bias: 15, min: -15, max: 15))
        XCTAssertEqual(field("trig.loop")?.encoding, .boolean)
        XCTAssertEqual(field("trig.offset")?.encoding, .unsigned16LE(min: 0, max: 3000))

        // Żadne pole nie może wystawać poza 42-bajtowy slot -- gdyby wystawało,
        // zapis wszedłby w sąsiedni slot (czyli w rim zamiast w head).
        for spec in layout.triggerFields {
            guard let offset = spec.offset else { continue }
            XCTAssertLessThanOrEqual(offset + spec.encoding.byteLength,
                                     layout.triggerStride ?? 0,
                                     "Pole \(spec.id) wychodzi poza slot brzmienia.")
        }
    }

    /// Ustawienia wejść triggerowych są GLOBALNE, nie kitowe — po cztery
    /// rekordy po 15 B pod 0x40. Zmierzone: Sensitivity pod +0x02.
    func testGlobalTriggerSettingsAreMapped() {
        let layout = BackupLayout.mapped2026_09_02
        let oczekiwane = [0x42, 0x51, 0x60, 0x6F]

        for (numer, adres) in oczekiwane.enumerated() {
            let id = "trigset.\(numer + 1).sensitivity"
            let pole = layout.globalFields.first(where: { $0.id == id })
            XCTAssertEqual(pole?.offset, adres,
                "Sensitivity \(id) ma siedzieć pod 0x\(String(adres, radix: 16)).")
            XCTAssertEqual(pole?.scope, .global,
                "Ustawienia wejścia nie zależą od kitu.")
        }
    }

    /// Pomiar `trigger_max.bin` / `trigger_min.bin` (2026-11-21): wszystkie
    /// parametry wejścia TRIG IN 1 head na maksimum, potem na minimum.
    /// Zmieniły się wyłącznie bajty +0x01…+0x0A pierwszego rekordu, a to
    /// daje i adresy pól, i ich zakresy.
    func testMeasuredTriggerInputRecordLayout() {
        let layout = BackupLayout.mapped2026_09_02

        // offset w rekordzie -> (nazwa pola w id, zakres)
        let oczekiwane: [(Int, String, ClosedRange<Int>)] = [
            (0x02, "sensitivity", 1...32),
            (0x03, "threshold", 0...31),
            (0x04, "curve", 0...6),
            (0x06, "rimGain", 1...16),
            // H/R Adjust siedzi pod +0x08, a nie +0x07: tak powiedział odczyt
            // z wyświetlacza (80 przy surowym 80), a nie kolejność menu.
            (0x08, "hrAdjust", 20...80),
        ]

        for numer in 1...4 {
            let bazaRekordu = 0x40 + (numer - 1) * 15
            for (wRekordzie, nazwa, zakres) in oczekiwane {
                let id = "trigset.\(numer).\(nazwa)"
                guard let pole = layout.globalFields.first(where: { $0.id == id }) else {
                    XCTFail("Brak pola \(id).")
                    continue
                }
                XCTAssertEqual(pole.offset, bazaRekordu + wRekordzie,
                    "\(id) ma siedzieć pod 0x\(String(bazaRekordu + wRekordzie, radix: 16)).")
                XCTAssertEqual(pole.scope, .global)
                XCTAssertEqual(pole.encoding.numericRange, zakres,
                    "Zakres \(id) ma być wzięty wprost z pomiaru.")
            }
        }
    }

    /// `Type` jest zmapowany (wiemy, że to +0x01), ale CELOWO nie jest
    /// wystawiony do edycji: zmiana typu pada przestawia w module wartości
    /// pozostałych parametrów, a edytor pliku nie zna tych wartości
    /// domyślnych. Ten test pilnuje, żeby nie wrócił tu przez przypadek.
    func testPadTypeIsDeliberatelyNotEditable() {
        let layout = BackupLayout.mapped2026_09_02
        for numer in 1...4 {
            XCTAssertNil(layout.globalFields.first(where: { $0.id == "trigset.\(numer).type" }),
                "Type nie może być edytowalny, dopóki nie znamy tablicy"
                    + " wartości domyślnych dla każdego typu pada.")
        }
    }

    /// Retrig Cancel też zostaje poza edycją, ale z innego powodu niż Type:
    /// wyświetlacz pokazał 16 przy surowym 40 i 1 przy surowym 16, więc
    /// 15 kroków na ekranie rozkłada się na 24 w pliku. Skala nie jest
    /// liniowa, a wpisanie wartości spoza tablicy modułu dałoby stan,
    /// którego sprzęt sam nigdy by nie ustawił.
    func testRetrigCancelIsDeliberatelyNotEditable() {
        let layout = BackupLayout.mapped2026_09_02
        for numer in 1...4 {
            XCTAssertNil(
                layout.globalFields.first(where: { $0.id == "trigset.\(numer).retrigCancel" }),
                "Retrig Cancel nie może być edytowalny, dopóki nie znamy"
                    + " tablicy przeliczeń.")
        }
    }

    /// Rim Gain pokazuje połowę wartości surowej. Zmierzone: raw 16 to „8.0”
    /// na wyświetlaczu modułu.
    func testRimGainIsShownAsHalfOfRawValue() {
        let layout = BackupLayout.mapped2026_09_02
        guard let pole = layout.globalFields.first(where: { $0.id == "trigset.1.rimGain" }) else {
            XCTFail("Brak pola trigset.1.rimgain.")
            return
        }
        XCTAssertEqual(pole.display, .scaled(divisor: 2, fractionDigits: 1, unit: ""))
        XCTAssertEqual(pole.display?.text(for: 16), "8.0")
        XCTAssertEqual(pole.display?.text(for: 1), "0.5")
    }

    /// Pusta jednostka nie zostawia wiszącej spacji na końcu wartości.
    func testScaledDisplayWithoutUnitHasNoTrailingSpace() {
        let bezJednostki = FieldDisplay.scaled(divisor: 2, fractionDigits: 1, unit: "")
        XCTAssertEqual(bezJednostki.text(for: 9), "4.5")
        let zJednostka = FieldDisplay.scaled(divisor: 10, fractionDigits: 1, unit: "ms")
        XCTAssertEqual(zJednostka.text(for: 3000), "300.0 ms")
    }

    /// Każde pole ustawień wejścia musi zostać wewnątrz swojego
    /// 15-bajtowego rekordu. Pomyłka o jeden bajt wpisywałaby ustawienie
    /// jednego triggera do rekordu następnego.
    func testTriggerInputFieldsStayInsideTheirRecord() {
        let layout = BackupLayout.mapped2026_09_02
        let ustawienia = layout.globalFields.filter { $0.id.hasPrefix("trigset.") }
        XCTAssertFalse(ustawienia.isEmpty)

        for pole in ustawienia {
            guard let offset = pole.offset else {
                XCTFail("\(pole.id) bez adresu.")
                continue
            }
            let wStrefie = offset - 0x40
            XCTAssertTrue(wStrefie >= 0 && wStrefie < 4 * 15,
                          "\(pole.id) wypada poza strefę ustawień wejść.")
            XCTAssertTrue(wStrefie % 15 + pole.encoding.byteLength <= 15,
                          "\(pole.id) wystaje za koniec swojego rekordu.")
        }
    }

    /// Pomiar `kit40-inst.bin`: komplet parametrów brzmienia ustawiony na
    /// skrajne i RÓŻNE wartości naraz, żeby żadnego nie dało się pomylić
    /// z innym.
    func testMeasuredSoundSlotFieldsFromKit40() {
        let layout = BackupLayout.mapped2026_09_02
        func pole(_ id: String) -> FieldSpec? {
            layout.triggerFields.first { $0.id == id }
        }

        XCTAssertEqual(pole("trig.muteGroup")?.offset, 0x0A)
        XCTAssertEqual(pole("trig.note")?.offset, 0x0C)
        XCTAssertEqual(pole("trig.dynamics")?.offset, 0x10)

        // Note# zmierzone na górnej granicy: wyświetlacz 127, plik 127.
        XCTAssertEqual(pole("trig.note")?.encoding.numericRange, 0...127)

        // Dynamics to pierwsza lista nazw w tym projekcie. MAX = 4,
        // zmierzone; nazwy i kolejność z instrukcji.
        XCTAssertEqual(pole("trig.dynamics")?.encoding,
                       .enumeration(values: ["LINEAR", "LOUD 1", "LOUD 2",
                                             "LOUD 3", "MAX"]))
        XCTAssertEqual(pole("trig.dynamics")?.encoding.numericRange, 0...4)
    }

    /// Type, Sensitivity, Threshold, Retrig Cancel i Mask Time były
    /// w `unmappedTM2` zgadnięte jako parametry brzmienia. Pomiary
    /// umieściły je w globalnym rekordzie ustawień wejścia, więc
    /// w zmierzonym układzie nie mogą już wisieć w slocie.
    func testFieldsProvenGlobalAreGoneFromTheSoundSlot() {
        let layout = BackupLayout.mapped2026_09_02
        for id in ["trig.type", "trig.sensitivity", "trig.threshold",
                   "trig.retrigCancel", "trig.maskTime"] {
            XCTAssertNil(layout.triggerFields.first { $0.id == id },
                         "\(id) należy do ustawień wejścia, nie do slotu brzmienia.")
        }

        // A w pustym układzie mają zostać — zależą od niego inne testy.
        let pusty = BackupLayout.unmappedTM2
        XCTAssertNotNil(pusty.triggerFields.first { $0.id == "trig.sensitivity" })
    }

    /// Po wczytaniu pliku edytor ma stanąć na kicie, który był wybrany
    /// na module — nie zawsze na kicie 1. Wartość w pliku jest liczona
    /// od zera, numer kitu od jedynki.
    func testKitSelectedOnModuleIsReadFromTheFile() {
        var layout = BackupLayout.mapped2026_09_02
        XCTAssertEqual(layout.currentKitPointerOffset, 0x36)

        var bytes = [UInt8](repeating: 0, count: 124_748)
        bytes[0x36] = 39                      // kit 40, liczony od zera
        let plik = BackupFile(bytes: bytes, layout: layout)
        XCTAssertEqual(plik.kitSelectedOnModule, 40)

        bytes[0x36] = 0
        XCTAssertEqual(BackupFile(bytes: bytes, layout: layout).kitSelectedOnModule, 1)

        // Wartość spoza liczby kitów to znak, że coś jest nie tak z plikiem
        // albo z offsetem. Wtedy ani nie zgadujemy, ani nie przycinamy.
        bytes[0x36] = 200
        XCTAssertNil(BackupFile(bytes: bytes, layout: layout).kitSelectedOnModule)

        // Układ, który tego bajtu nie zna, nie udaje, że wie.
        layout.currentKitPointerOffset = nil
        bytes[0x36] = 39
        XCTAssertNil(BackupFile(bytes: bytes, layout: layout).kitSelectedOnModule)
    }

    /// `unmappedTM2` ma zostać nietknięty — zależą od niego pozostałe testy
    /// i tryb pracy „jeszcze nic nie wiem o formacie".
    func testUnmappedLayoutStaysUnmapped() {
        let layout = BackupLayout.unmappedTM2
        XCTAssertNil(layout.triggerFields.first(where: { $0.id == "trig.pitch" })?.offset)
        XCTAssertNil(layout.triggerFields.first(where: { $0.id == "trig.pan" })?.offset)
        XCTAssertNil(layout.triggerFields.first(where: { $0.id == "trig.loop" }),
                     "trig.loop ma istnieć tylko w layoucie zmierzonym.")
        XCTAssertTrue(layout.globalFields.allSatisfy { !$0.id.hasPrefix("trigset.") },
                      "Ustawienia wejść mają istnieć tylko w layoucie zmierzonym.")
    }

    // MARK: - Wyświetlanie wartości

    /// Edytor ma mówić językiem modułu, nie językiem bajtów: moduł pokazuje
    /// `L15` i `300.0 ms` tam, gdzie w pliku siedzi `0` i `3000`.
    func testFieldDisplayFormatsValuesTheWayModuleDoes() {
        XCTAssertEqual(FieldDisplay.panLeftRight.text(for: -15), "L15")
        XCTAssertEqual(FieldDisplay.panLeftRight.text(for: 0), "CENTER")
        XCTAssertEqual(FieldDisplay.panLeftRight.text(for: 15), "R15")
        XCTAssertEqual(FieldDisplay.panLeftRight.text(for: -3), "L3")

        let ms = FieldDisplay.scaled(divisor: 10, fractionDigits: 1, unit: "ms")
        XCTAssertEqual(ms.text(for: 3000), "300.0 ms")
        XCTAssertEqual(ms.text(for: 1), "0.1 ms")
        XCTAssertEqual(ms.text(for: 0), "0.0 ms")

        XCTAssertEqual(FieldDisplay.plain.text(for: -120), "-120")

        // Dzielnik 0 to błąd w opisie układu, ale widok nie ma od tego padać —
        // ma pokazać surową liczbę, bo to nadal prawda o zawartości pliku.
        let zepsute = FieldDisplay.scaled(divisor: 0, fractionDigits: 1, unit: "ms")
        XCTAssertEqual(zepsute.text(for: 42), "42")
    }

    /// Pola, które mają własny sposób wyświetlania, muszą go realnie mieć
    /// w zmierzonym layoucie — inaczej poprawka widoku nic nie zmienia.
    func testMappedLayoutAssignsDisplayStyles() {
        let layout = BackupLayout.mapped2026_09_02
        let pan = layout.triggerFields.first(where: { $0.id == "trig.pan" })
        let offset = layout.triggerFields.first(where: { $0.id == "trig.offset" })

        XCTAssertEqual(pan?.display, .panLeftRight)
        XCTAssertEqual(offset?.display, .scaled(divisor: 10, fractionDigits: 1, unit: "ms"))
    }

    // MARK: - Oryginał nietknięty

    func testOriginalBytesSurviveEditing() throws {
        var file = BackupFile(bytes: makeBytes(), layout: makeLayout())
        let before = file.originalBytes
        try file.setByte(0xAA, at: 100)
        XCTAssertEqual(file.originalBytes, before)
        XCTAssertNotEqual(file.bytes, before)
        XCTAssertTrue(file.isModified)
    }
}
