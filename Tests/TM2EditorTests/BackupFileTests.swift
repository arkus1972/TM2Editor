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

    /// Dokumentuje i pilnuje decyzji `triggerCount = 2` w `mapped2026_09_02`.
    /// Fakty sprzętowe mówią o do 4 triggerach (2× TRIG IN, dual-trigger), ale
    /// przy zmierzonym origin/stride trzeci rekord nałożyłby się na nazwę
    /// następnego kitu. Jeśli ktoś kiedyś podniesie `triggerCount` do 4 bez
    /// ponownego zmierzenia stride'u, ten test ma to złapać, zanim złapie to
    /// użytkownik nadpisując cudzy kit.
    func testHypotheticalThirdTriggerWouldOverrunNextKitName() {
        var layout = BackupLayout.mapped2026_09_02
        layout.triggerCount = 4   // celowo błędne, tylko na potrzeby tego testu

        guard let thirdTriggerOrigin = layout.triggerOrigin(kit: 1, trigger: 3),
              let kit2Origin = layout.kitOrigin(kit: 2),
              let nameOffset = layout.kitFields.first(where: { $0.id == "kit.name" })?.offset
        else {
            return XCTFail("Brakuje danych w mapped2026_09_02 -- sprawdź, czy"
                + " kitBlockOrigin/kitStride/triggerBlockOrigin/triggerStride"
                + " i offset kit.name są nadal ustawione.")
        }

        XCTAssertEqual(thirdTriggerOrigin, kit2Origin + nameOffset,
            "Trzeci rekord triggera (stride 84 B od origin 0x7E) wypada dokładnie"
            + " na polu nazwy następnego kitu -- to jest POWÓD, dla którego"
            + " mapped2026_09_02 trzyma triggerCount=2. Nie podnoś tej liczby"
            + " bez ponownego zmierzenia stride'u na module.")
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
