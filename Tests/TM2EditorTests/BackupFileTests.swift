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
            // Retrig Cancel pod +0x06, skala 1:1, zakres 1…16. Wcześniej
            // przypisany do +0x05 i uznany za nieliniowy — obalił to test,
            // w którym zmienił się tylko ten jeden parametr.
            (0x06, "retrigCancel", 1...16),
            // XTLK Cancel pod +0x08, w procentach. Wcześniej był tu H/R Adjust.
            (0x08, "xtlkCancel", 20...80),
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

    /// `Type` NIE jest zwykłym polem i nie może się nim stać: zmiana typu pada
    /// przestawia w module resztę ustawień wejścia, więc zapisanie samego kodu
    /// zostawiłoby w pliku parametry poprzedniego pada. Typ zmienia wyłącznie
    /// `KitEditor.setPadType`, który wpisuje kod razem z wartościami
    /// domyślnymi z tablicy `TypyPadow`. Ten test pilnuje, żeby ogólna ścieżka
    /// zapisu pola nie dostała go przez przypadek.
    func testPadTypeIsDeliberatelyNotEditable() {
        let layout = BackupLayout.mapped2026_09_02
        for numer in 1...4 {
            XCTAssertNil(layout.globalFields.first(where: { $0.id == "trigset.\(numer).type" }),
                "Type nie może być edytowalny, dopóki nie znamy tablicy"
                    + " wartości domyślnych dla każdego typu pada.")
        }
    }

    /// Pola gniazda zmierzone w dwóch krokach, każdy zmieniał dokładnie
    /// jedną rzecz i każdy dał dokładnie jeden bajt:
    ///   Input PADx2 -> HEAD&RIM   +0x00: 1 -> 0
    ///   Rim Gain -> 2.0           +0x0A: 15 -> 20
    func testJackFieldsMeasuredOneParameterAtATime() {
        let layout = BackupLayout.mapped2026_09_02
        func pole(_ id: String) -> FieldSpec? {
            layout.globalFields.first { $0.id == id }
        }

        // Pola gniazda leżą w rekordzie HEAD: 1 dla TRIG IN 1, 3 dla TRIG IN 2.
        XCTAssertEqual(pole("jack.1.input")?.offset, 0x40)
        XCTAssertEqual(pole("jack.2.input")?.offset, 0x40 + 2 * 15)
        XCTAssertEqual(pole("jack.1.input")?.encoding,
                       .enumeration(values: ["HEAD&RIM", "PADx2"]))

        XCTAssertEqual(pole("jack.1.rimGain")?.offset, 0x40 + 0x0A)
        XCTAssertEqual(pole("jack.2.rimGain")?.offset, 0x40 + 2 * 15 + 0x0A)
        XCTAssertEqual(pole("jack.1.rimGain")?.encoding.numericRange, 0...80)
        XCTAssertEqual(pole("jack.1.rimGain")?.display?.text(for: 20), "2.0")
        XCTAssertEqual(pole("jack.1.rimGain")?.display?.text(for: 80), "8.0")

        // Rekordy RIM nie mają tych pól: znaczenie ich bajtów pod tymi
        // offsetami nie zostało zmierzone.
        XCTAssertNil(pole("jack.3.input"))
        XCTAssertNil(pole("trigset.2.rimGain"))
    }

    /// H/R Adjust pod +0x09 — potwierdzony odczytem z wyświetlacza (31 = 31),
    /// a nie wykluczeniem. Noise Cancel dalej bez adresu.
    func testHRAdjustConfirmedByDisplayNoiseCancelStillUnknown() {
        let layout = BackupLayout.mapped2026_09_02
        let pole = layout.globalFields.first { $0.id == "jack.1.hrAdjust" }
        XCTAssertEqual(pole?.offset, 0x40 + 0x09)
        XCTAssertEqual(pole?.encoding.numericRange, 0...80)
        XCTAssertNil(pole?.display, "Skala 1:1, bez przeliczania.")

        XCTAssertEqual(layout.globalFields.first { $0.id == "jack.2.hrAdjust" }?.offset,
                       0x40 + 2 * 15 + 0x09)

        XCTAssertNil(layout.globalFields.first { $0.id.lowercased().contains("noisecancel") },
                     "Noise Cancel nie ma jeszcze adresu.")
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
        let ustawienia = layout.globalFields.filter {
            $0.id.hasPrefix("trigset.") || $0.id.hasPrefix("jack.")
        }
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

    /// Nazwa backupu z nagłówka: osiem znaków ASCII pod 0x0A, dopełnianych
    /// spacjami — tak samo, jak moduł trzyma krótkie nazwy kitów.
    func testBackupNameIsReadAndWrittenWithSpacePadding() throws {
        let layout = BackupLayout.mapped2026_09_02
        guard let pole = layout.globalFields.first(where: { $0.id == "file.backupName" }) else {
            XCTFail("Brak pola file.backupName.")
            return
        }
        XCTAssertEqual(pole.offset, 0x0A)
        XCTAssertEqual(pole.encoding, .ascii(length: 8))

        var bytes = [UInt8](repeating: 0, count: 124_748)
        // „TM-2" + znacznik „BK" + nazwa „Backup  "
        bytes.replaceSubrange(0..<4, with: Array("TM-2".utf8))
        bytes.replaceSubrange(8..<10, with: Array("BK".utf8))
        bytes.replaceSubrange(0x0A..<0x12, with: Array("Backup  ".utf8))

        var plik = BackupFile(bytes: bytes, layout: layout)
        XCTAssertEqual(plik.value(of: pole)?.textValue, "Backup")

        try plik.setValue(.text("Koncert"), for: pole)
        XCTAssertEqual(plik.value(of: pole)?.textValue, "Koncert")
        // Dopełnienie spacją, nie zerem — tak robi moduł.
        XCTAssertEqual(plik.byte(at: 0x11), 0x20)
        // Znacznik „BK" przed nazwą nie może zostać naruszony.
        XCTAssertEqual(plik.byte(at: 0x08), UInt8(ascii: "B"))
        XCTAssertEqual(plik.byte(at: 0x09), UInt8(ascii: "K"))

        // Dziewięć znaków się nie zmieści i ma być odmowa, nie obcięcie.
        XCTAssertThrowsError(try plik.setValue(.text("ZaDlugaNazwa"), for: pole))
    }

    /// Seria max2/min2 (wszystko na maksimum, potem na minimum, przy stałym
    /// typie pada) domknęła trzy rzeczy naraz.
    func testMeasuredSoundSlotExtremes() {
        let layout = BackupLayout.mapped2026_09_02
        func pole(_ id: String) -> FieldSpec? {
            layout.triggerFields.first { $0.id == id }
        }

        // Note# da się WYŁĄCZYĆ, a wyłączone to −1, nie zero. Przy poprzednim
        // opisie (liczba bez znaku 0…127) wyłączona nuta pokazywałaby się
        // jako 255.
        XCTAssertEqual(pole("trig.note")?.encoding, .signed16LE(min: -1, max: 127))
        XCTAssertEqual(pole("trig.note")?.display, .offWhenNegative)
        XCTAssertEqual(FieldDisplay.offWhenNegative.text(for: -1), "OFF")
        XCTAssertEqual(FieldDisplay.offWhenNegative.text(for: 64), "64")

        // Mono/Poly pod +0x12, zmierzone wprost (`poly.bin`): POLY to 1.
        // Polaryzacja jest ODWROTNA niż przy pierwszym, wywnioskowanym
        // przypisaniu — i dlatego tamto zostało wycofane.
        XCTAssertEqual(pole("trig.monoPoly")?.offset, 0x12)
        XCTAssertEqual(pole("trig.monoPoly")?.encoding,
                       .enumeration(values: ["MONO", "POLY"]))

        // Mute Group wyłączona to zero — zmierzone, nie przyjęte.
        XCTAssertEqual(pole("trig.muteGroup")?.encoding.numericRange?.lowerBound, 0)
    }

    /// Typ efektu kitu jest ZNANY (+0x18 bloku kitu, THRU = 0, REVERB = 19),
    /// ale celowo nie wystawiony do edycji: przy THRU cała reszta strefy
    /// zeruje się co do bajtu, czyli znaczenie pól zależy od typu. Ten test
    /// pilnuje, żeby nie trafił tam przez nieuwagę.
    func testKitEffectTypeStaysOutOfEditing() {
        let layout = BackupLayout.mapped2026_09_02
        XCTAssertNil(layout.kitFields.first { $0.id == "kit.effect.type" })
        XCTAssertNil(layout.kitFields.first { $0.id.hasPrefix("kit.effect.") })
    }

    /// Pilnuje tego, co raz już zginęło po cichu: pole nazwy backupu
    /// i offset wskaźnika bieżącego kitu. Skrypt przepisujący sąsiedni
    /// komentarz wyciął oba, nawiasy się zgadzały i nikt tego nie zauważył
    /// aż do następnego pomiaru.
    func testCriticalHeaderFieldsSurviveRefactors() {
        let layout = BackupLayout.mapped2026_09_02
        XCTAssertEqual(layout.currentKitPointerOffset, 0x36,
                       "Bez tego edytor znów stanie na kicie 1 zamiast na tym"
                        + " wybranym w module.")
        XCTAssertNotNil(layout.globalFields.first { $0.id == "file.backupName" },
                        "Nazwa backupu musi zostać polem do edycji.")
    }

    // MARK: - Wpisywanie wartości z klawiatury

    /// Każda wartość pokazana na ekranie musi dać się wpisać z powrotem
    /// i dać tę samą liczbę. Inaczej samo kliknięcie w pole i wyjście z niego
    /// zmieniałoby plik albo kończyło się sygnałem błędu.
    func testParseIsExactInverseOfTextForEveryDisplay() {
        let przypadki: [(FieldDisplay, ClosedRange<Int>)] = [
            (.plain, 0...127),
            (.panLeftRight, -15...15),
            (.offWhenNegative, -1...127),
            (.offWhenZero, 0...5),
            (.scaled(divisor: 10, fractionDigits: 1, unit: "ms"), 0...3000),
            (.scaled(divisor: 10, fractionDigits: 1, unit: ""), 0...80),
        ]
        for (wyswietlanie, zakres) in przypadki {
            for wartosc in zakres {
                let tekst = wyswietlanie.text(for: wartosc)
                XCTAssertEqual(wyswietlanie.parse(tekst), wartosc,
                               "\(wyswietlanie): \"\(tekst)\" nie wraca do \(wartosc)")
            }
        }
    }

    /// Wpisuje się tak, jak pokazuje moduł — i tak, jak się naturalnie pisze.
    func testParseAcceptsHowPeopleActuallyType() {
        let pan = FieldDisplay.panLeftRight
        XCTAssertEqual(pan.parse("c"), 0)
        XCTAssertEqual(pan.parse("center"), 0)
        XCTAssertEqual(pan.parse("l3"), -3)
        XCTAssertEqual(pan.parse(" R15 "), 15)
        XCTAssertEqual(pan.parse("-7"), -7)

        let offset = FieldDisplay.scaled(divisor: 10, fractionDigits: 1, unit: "ms")
        XCTAssertEqual(offset.parse("300"), 3000)
        XCTAssertEqual(offset.parse("12,5"), 125, "Przecinek dziesiętny też.")
        XCTAssertEqual(offset.parse("0.1 ms"), 1)

        XCTAssertEqual(FieldDisplay.offWhenNegative.parse("off"), -1)
    }

    /// Nic nie jest po cichu zaokrąglane ani zgadywane.
    func testParseRejectsWhatItCannotReadExactly() {
        let offset = FieldDisplay.scaled(divisor: 10, fractionDigits: 1, unit: "ms")
        XCTAssertNil(offset.parse("0.15"), "Między krokami 0,1 ms — odmowa, nie zaokrąglenie.")
        XCTAssertNil(offset.parse("1e300"), "Nie może wywrócić programu.")
        XCTAssertNil(offset.parse("abc"))
        XCTAssertNil(FieldDisplay.plain.parse(""))
        XCTAssertNil(FieldDisplay.plain.parse("12.5"))
        XCTAssertNil(FieldDisplay.panLeftRight.parse("X5"))
        XCTAssertNil(FieldDisplay.panLeftRight.parse("L-3"))
    }

    // MARK: - Typy padów

    /// Tablica jest wygenerowana z pomiarów `typy-1` … `typy-9`. Pilnujemy jej
    /// kształtu: 36 typów, numery 0–35 bez dziur i powtórzeń, a kolejność
    /// z modułu to przestawienie tych samych 36 numerów.
    func testPadTypeTableIsComplete() {
        let kody = TypyPadow.wszystkie.map(\.kod)
        XCTAssertEqual(kody, Array(0...35))
        XCTAssertEqual(Set(TypyPadow.wszystkie.map(\.nazwa)).count, 36, "Nazwy bez powtórzeń.")
        XCTAssertEqual(TypyPadow.kolejnoscNaModule.sorted(), Array(0...35))

        // Na liście w module pierwszy jest KD-7, ostatni PAD2 — tak spisał Arek
        // i tak wyszło z serii min/max (1 i 31).
        XCTAssertEqual(TypyPadow.typ(kod: TypyPadow.kolejnoscNaModule.first!)?.nazwa, "KD-7")
        XCTAssertEqual(TypyPadow.typ(kod: TypyPadow.kolejnoscNaModule.last!)?.nazwa, "PAD2")
        // A numer 0 ma KT-10, nie KD-7.
        XCTAssertEqual(TypyPadow.typ(kod: 0)?.nazwa, "KT-10")
    }

    /// Trzy niezależne potwierdzenia jednego wiersza: RT-30K zmierzony w `typy-6`,
    /// drugi raz w `noise.bin` i w pierwotnej bazie Arka (HEAD&RIM).
    func testRT30KDefaultsMatchThreeMeasurements() {
        guard let rt30k = TypyPadow.typ(kod: 32) else { return XCTFail("Brak RT-30K.") }
        XCTAssertEqual(rt30k.nazwa, "RT-30K")
        XCTAssertEqual(rt30k.bajtyRekordu(zachowujacXTLK: 40),
                       [32, 8, 15, 0, 36, 9, 12, 40, 0, 0, 2])
    }

    /// Noise Cancel ma wartość domyślną TYLKO przy dwóch typach, które go
    /// pokazują na module: RT-30K i RT-30HR. To było pierwsze wskazanie, gdzie
    /// leży (+0x0B), zanim potwierdził to pomiar wprost.
    func testOnlyRT30KAndRT30HRHaveNoiseCancel() {
        let zNoise = TypyPadow.wszystkie.filter { $0.noiseCancel != 0 }.map(\.nazwa).sorted()
        XCTAssertEqual(zNoise, ["RT-30HR", "RT-30K"])
    }

    /// Noise Cancel: +0x0B rekordu głównego gniazda, skala 1:1, OFF…5.
    func testNoiseCancelField() {
        let layout = BackupLayout.mapped2026_09_02
        let pole = layout.globalFields.first { $0.id == "jack.1.noiseCancel" }
        XCTAssertEqual(pole?.offset, 0x40 + 0x0B)
        XCTAssertEqual(pole?.encoding.numericRange, 0...5)
        XCTAssertEqual(pole?.display?.text(for: 0), "OFF")
        XCTAssertEqual(pole?.display?.text(for: 2), "2")
        XCTAssertEqual(layout.globalFields.first { $0.id == "jack.2.noiseCancel" }?.offset,
                       0x40 + 2 * 15 + 0x0B)
    }

    // MARK: - Efekty kitu

    /// Dwanaście efektów, kody z dziurami, każdy z kompletem 20 wartości
    /// domyślnych. Kolejność tablicy = kolejność na module.
    func testKitEffectTableIsComplete() {
        let nazwy = TypyEfektow.wszystkie.map(\.nazwa)
        XCTAssertEqual(nazwy, ["THRU", "DELAY", "TAPE ECHO", "CHORUS", "FLANGER", "PHASER",
                               "EQUALIZER", "COMP", "WAH", "DIST", "RINGMOD", "REVERB"])
        XCTAssertEqual(TypyEfektow.wszystkie.map(\.kod), [0, 1, 3, 4, 5, 7, 9, 10, 14, 15, 16, 19])
        for efekt in TypyEfektow.wszystkie {
            XCTAssertEqual(efekt.domyslne.count, 20, efekt.nazwa)
            XCTAssertEqual(efekt.bajtyStrefy.count, TypyEfektow.dlugosc, efekt.nazwa)
        }
        // THRU nie ma parametrów — wszystko wyzerowane.
        XCTAssertTrue(TypyEfektow.typ(kod: 0)?.domyslne.allSatisfy { $0 == 0 } ?? false)
    }

    /// REVERB z serii max2 (zmienione parametry) i z efekty-1 (domyślne) muszą
    /// się zgadzać tam, gdzie Arek parametrów nie ruszał: +0x24, +0x28, +0x2A.
    func testReverbDefaultsAgreeWithEarlierMeasurement() throws {
        let reverb = try XCTUnwrap(TypyEfektow.typ(kod: 19))
        // pola od +0x1A co 2 bajty: indeks 5 = +0x24, 7 = +0x28, 8 = +0x2A
        XCTAssertEqual(reverb.domyslne[5], 10)
        XCTAssertEqual(reverb.domyslne[7], 100)
        XCTAssertEqual(reverb.domyslne[8], 100)
    }

    // MARK: - Parametry efektów

    /// Maksima z backupu `aaa7990` (kity 70–80): kod efektu → [offset: wartość].
    /// Tylko pola, które zmieniły się względem wartości domyślnych.
    private static let zmierzoneMaksima: [Int: [Int: Int]] = [
        1: [0x1C: 350, 0x20: 99, 0x22: 10, 0x26: 100],
        3: [0x1C: 127, 0x1E: 127, 0x20: 30, 0x22: 30, 0x30: 100],
        4: [0x1C: 100, 0x1E: 100, 0x20: 80, 0x22: 10, 0x26: 100],
        5: [0x1C: 100, 0x20: 100, 0x24: 100, 0x2A: 100, 0x2C: 100],
        7: [0x1E: 100, 0x22: 100, 0x24: 100, 0x26: 100, 0x2A: 100, 0x2C: 100],
        9: [0x1E: 27, 0x20: 5, 0x22: 40, 0x24: 27, 0x26: 5, 0x28: 40, 0x2E: 40],
        10: [0x1A: 48, 0x1C: 100, 0x1E: 99, 0x20: 4, 0x24: 24],
        14: [0x1E: 100, 0x20: 100, 0x22: 100, 0x24: 100, 0x26: 100],
        15: [0x1A: 24, 0x1C: 120, 0x1E: 100, 0x20: 100, 0x22: 100, 0x26: 100],
        16: [0x1A: 127, 0x1C: 127, 0x1E: 1, 0x20: 30, 0x22: 30, 0x24: 100],
        19: [0x1A: 4, 0x1C: 99, 0x1E: 100, 0x20: 10, 0x22: 9, 0x26: 100],
    ]

    /// Minima z `BKUP-006`. TAPE ECHO brak — kit 71 przeskoczył przy serii na DELAY.
    private static let zmierzoneMinima: [Int: [Int: Int]] = [
        1: [0x1C: 0, 0x20: 0, 0x22: 0, 0x24: 0, 0x26: 0, 0x28: 0],
        4: [0x1C: 0, 0x1E: 0, 0x20: 0, 0x22: 0, 0x24: 0, 0x26: 0, 0x28: 0],
        5: [0x1C: 0, 0x20: 0, 0x22: 0, 0x24: 0, 0x28: 0, 0x2A: 0, 0x2C: 0],
        7: [0x1E: 0, 0x22: 0, 0x24: 0, 0x26: 0, 0x2A: 0, 0x2C: 0],
        9: [0x1E: 0, 0x20: 0, 0x22: 0, 0x24: 0, 0x26: 0, 0x28: 0, 0x2E: 0],
        10: [0x1A: 0, 0x1C: 0, 0x1E: 0, 0x20: 0, 0x22: 0, 0x24: 0],
        14: [0x1E: 0, 0x20: 0, 0x22: 0, 0x24: 0, 0x26: 0],
        15: [0x1C: 0, 0x1E: 0, 0x20: 0, 0x22: 0, 0x24: 0, 0x26: 0],
        16: [0x1A: 0, 0x1C: 0, 0x20: 0, 0x22: 0, 0x24: 0, 0x26: 0],
        19: [0x1A: 0, 0x1C: 0, 0x20: 0, 0x22: 0, 0x26: 0, 0x28: 0],
    ]

    /// Każde pole, które moduł ruszył w serii max/min, jest parametrem tego
    /// efektu — i odwrotnie: zakres każdego parametru kończy się dokładnie tam,
    /// gdzie moduł się zatrzymał (albo na wartości domyślnej, gdy ta już była
    /// skrajna).
    func testEffectParametersMatchMeasuredExtremes() throws {
        for efekt in TypyEfektow.wszystkie {
            let parametry = ParametryEfektow.parametry(kodEfektu: efekt.kod)
            if efekt.kod == 0 {
                XCTAssertTrue(parametry.isEmpty, "THRU nie ma parametrów.")
                continue
            }
            XCTAssertFalse(parametry.isEmpty, efekt.nazwa)
            let poOffsecie = Dictionary(uniqueKeysWithValues: parametry.map { ($0.offset!, $0) })
            XCTAssertEqual(poOffsecie.count, parametry.count, "\(efekt.nazwa): powtórzony offset")

            let maksima = Self.zmierzoneMaksima[efekt.kod] ?? [:]
            let minima = Self.zmierzoneMinima[efekt.kod]
            for offset in Set(maksima.keys).union(minima.map { Array($0.keys) } ?? []) {
                XCTAssertNotNil(poOffsecie[offset],
                                "\(efekt.nazwa) +0x\(String(offset, radix: 16)): moduł ruszył pole, którego nie ma na liście")
            }

            for p in parametry {
                let offset = try XCTUnwrap(p.offset)
                XCTAssertTrue((0x1A...0x40).contains(offset) && offset % 2 == 0,
                              "\(p.id) poza strefą parametrów")
                XCTAssertEqual(p.scope, .kit)
                XCTAssertEqual(p.encoding.byteLength, 2)
                XCTAssertEqual(ParametryEfektow.kodEfektu(zID: p.id), efekt.kod)
                let zakres = try XCTUnwrap(p.encoding.numericRange)
                let domyslna = efekt.domyslne[(offset - 0x1A) / 2]
                XCTAssertTrue(zakres.contains(domyslna), "\(p.id): wartość domyślna poza zakresem")
                XCTAssertEqual(maksima[offset] ?? domyslna, zakres.upperBound, "\(p.id): maksimum")
                if let minima {
                    XCTAssertEqual(minima[offset] ?? domyslna, zakres.lowerBound, "\(p.id): minimum")
                }
            }
        }
    }

    /// Odczyty Arka z wyświetlacza przy maksimach (23.11) i listy z modułu.
    func testEffectParametersShowValuesLikeTheModule() throws {
        func tekst(_ kod: Int, _ klucz: String, _ wartosc: Int) throws -> String {
            let p = try XCTUnwrap(ParametryEfektow.parametry(kodEfektu: kod)
                .first { $0.id == "fx.\(kod).\(klucz)" }, "fx.\(kod).\(klucz)")
            return (p.display ?? .plain).text(for: wartosc)
        }
        XCTAssertEqual(try tekst(1, "dlyTime", 350), "350 ms")
        XCTAssertEqual(try tekst(1, "dlyTime", 100), "100 ms")
        XCTAssertEqual(try tekst(1, "loCut", 10), "800 Hz")
        XCTAssertEqual(try tekst(1, "loCut", 0), "FLAT")
        XCTAssertEqual(try tekst(1, "hiCut", 9), "FLAT")
        XCTAssertEqual(try tekst(1, "hiCut", 7), "8.0 kHz")
        XCTAssertEqual(try tekst(1, "dryWet", 50), "50:50")
        XCTAssertEqual(try tekst(1, "dryWet", 100), "0:100")
        XCTAssertEqual(try tekst(3, "repeatRate", 127), "127")
        XCTAssertEqual(try tekst(3, "bass", 30), "+15 dB")
        XCTAssertEqual(try tekst(3, "bass", 15), "0 dB")
        XCTAssertEqual(try tekst(3, "bass", 0), "-15 dB")
        XCTAssertEqual(try tekst(4, "preDelay", 80), "40.0 ms")
        XCTAssertEqual(try tekst(9, "eq1Freq", 27), "10.0 kHz")
        XCTAssertEqual(try tekst(9, "eq1Freq", 15), "630 Hz")
        XCTAssertEqual(try tekst(9, "eq2Freq", 19), "1.60 kHz")
        XCTAssertEqual(try tekst(9, "eq1Freq", 0), "20.0 Hz")
        XCTAssertEqual(try tekst(9, "eq1Q", 5), "16")
        XCTAssertEqual(try tekst(9, "eq1Gain", 40), "+20 dB")
        XCTAssertEqual(try tekst(9, "level", 40), "+20 dB")
        XCTAssertEqual(try tekst(10, "threshold", 0), "-48 dB")
        XCTAssertEqual(try tekst(10, "threshold", 48), "0 dB")
        XCTAssertEqual(try tekst(10, "ratio", 4), "100:1")
        XCTAssertEqual(try tekst(10, "ratio", 2), "4:1")
        XCTAssertEqual(try tekst(10, "knee", 1), "HARD")
        XCTAssertEqual(try tekst(10, "makeUp", 24), "+24 dB")
        XCTAssertEqual(try tekst(15, "type", 0), "MID BST")
        XCTAssertEqual(try tekst(15, "type", 24), "MUFF FUZZ")
        XCTAssertEqual(try tekst(15, "bottom", 0), "-50")
        XCTAssertEqual(try tekst(16, "polarity", 1), "DOWN")
        XCTAssertEqual(try tekst(19, "type", 4), "PLATE")
        XCTAssertEqual(try tekst(19, "type", 1), "ROOM")
        XCTAssertEqual(try tekst(19, "time", 99), "99")
        // Wartość spoza listy — pokazana uczciwie, nie jako ostatnia pozycja.
        XCTAssertEqual(try tekst(19, "type", 7), "#7")
    }

    /// Każda wartość każdego parametru: tekst z wyświetlacza czyta się z powrotem
    /// dokładnie jako ta sama wartość. Inaczej wpisanie z klawiatury tego,
    /// co widać, zapisałoby coś innego.
    func testEffectParameterDisplayRoundTrips() throws {
        for efekt in TypyEfektow.wszystkie {
            for p in ParametryEfektow.parametry(kodEfektu: efekt.kod) {
                let wyswietlanie = p.display ?? .plain
                for v in try XCTUnwrap(p.encoding.numericRange) {
                    XCTAssertEqual(wyswietlanie.parse(wyswietlanie.text(for: v)), v,
                                   "\(p.id): \(wyswietlanie.text(for: v))")
                }
            }
        }
        let dw = FieldDisplay.dryWet
        XCTAssertEqual(dw.parse("70:30"), 30)
        XCTAssertNil(dw.parse("70:40"), "Proporcja musi się sumować do 100.")
        XCTAssertEqual(FieldDisplay.przesuniecie(bias: 15, unit: "dB").parse("+3dB"), 18)
        XCTAssertEqual(FieldDisplay.lista(ParametryEfektow.typPoglosu).parse("hall 1"), 2)
        XCTAssertNil(FieldDisplay.lista(ParametryEfektow.dobrocQ).parse("3"))
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
