import CryptoKit
import XCTest
@testable import TM2Editor

/// Kity jako całość: kopiowanie, zamiana, presety, szukanie, nowy backup.
@MainActor
final class KityTests: XCTestCase {

    /// Prawdziwa geometria (124 748 B): kity 1–99 „New Kit", kit 1 nazwany
    /// „CIECHOCINEK", kit 70 z trzema samplami z karty.
    private func bajty() -> [UInt8] {
        var b = NowyBackup.bajty()
        func nazwa(_ kit: Int, _ tekst: String) {
            let od = 0x7C + (kit - 1) * 234
            let znaki = Array(tekst.utf16) + Array(repeating: 0x20, count: 11 - tekst.count)
            for (i, z) in znaki.enumerated() { b[od + 2 * i] = UInt8(z & 0xFF); b[od + 2 * i + 1] = UInt8(z >> 8) }
        }
        func sampel(_ kit: Int, _ pad: Int, _ sciezka: String) {
            let slot = 0x7C + (kit - 1) * 234 + 0x42 + (pad - 1) * 42
            b[slot] = 0; b[slot + 1] = 0; b[slot + 2] = 2; b[slot + 3] = 0
            let wpis = 0x5AFA + ((kit - 1) * 4 + (pad - 1)) * 256
            let t = Array(sciezka.utf8)
            b.replaceSubrange(wpis..<(wpis + t.count), with: t)
        }
        nazwa(1, "CIECHOCINEK")
        nazwa(70, "Samples")
        sampel(70, 1, "TEST_A.wav")
        sampel(70, 2, "TEST_B.wav")
        sampel(70, 3, "TESTY/TEST_C.wav")
        return b
    }

    private func edytor() -> KitEditor {
        KitEditor(file: BackupFile(bytes: bajty(), layout: .mapped2026_09_02), log: EditorLog())
    }

    func testNowyBackupJakNaModule() {
        let b = NowyBackup.bajty()
        XCTAssertEqual(b.count, 124_748)
        XCTAssertEqual(Array(b.suffix(16)), Array(Insecure.MD5.hash(data: Data(b.dropLast(16)))))
        XCTAssertEqual(b[0x36], 0)
        let e = KitEditor(file: BackupFile(bytes: b, layout: .mapped2026_09_02), log: EditorLog())
        XCTAssertEqual(e.kitNames.compactMap { $0 }.count, 99)
        XCTAssertTrue(e.kitNames.allSatisfy { $0 == "New Kit" })
        XCTAssertEqual(e.kitEffect(kit: 50)?.nazwa, "REVERB")
        XCTAssertTrue(ProjektTM2.sciezkiSampli(w: b).isEmpty)

        // Ustawienia SYSTEM i wejść z podanego backupu, wskaźnik kitu wyzerowany.
        var zrodlo = b
        zrodlo[0x2C] = 7; zrodlo[0x36] = 40; zrodlo[0x40] = 1
        let z = NowyBackup.bajty(naglowekZ: zrodlo)
        XCTAssertEqual(z[0x2C], 7)
        XCTAssertEqual(z[0x40], 1)
        XCTAssertEqual(z[0x36], 0)
    }

    /// Backup fabryczny co do bajtu jak plik zrobiony na module po FACTORY RESET.
    func testBackupFabrycznyJakZModulu() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "fabryczny", withExtension: "bin",
                                                  subdirectory: "Zasoby"))
        let zModulu = [UInt8](try Data(contentsOf: url))
        XCTAssertEqual(NowyBackup.fabryczny(), zModulu)
        XCTAssertEqual(Array(NowyBackup.bajty()[0..<0x7C]), Array(zModulu[0..<0x7C]),
                       "Pusty backup bez otwartego pliku ma fabryczny nagłówek.")
        let e = KitEditor(file: BackupFile(bytes: zModulu, layout: .mapped2026_09_02), log: EditorLog())
        XCTAssertEqual(e.kitName(1), "Claps!")
        XCTAssertEqual(e.kitName(50), "Acoustic")
        XCTAssertEqual(e.kitName(51), "New Kit")
    }

    func testKopiowanieKituRazemZSamplamiIJednoCofniecie() {
        let e = edytor()
        let przed = e.file.bytes
        XCTAssertTrue(e.kopiujKit(z: 70, do: 5))
        XCTAssertEqual(e.kitName(5), "Samples")
        XCTAssertEqual(e.sciezkaSampla(kit: 5, trigger: 3), "TESTY/TEST_C.wav")
        XCTAssertEqual(e.changes.count, 1)
        XCTAssertEqual(Array(e.file.bytes[0..<0x7C]), Array(przed[0..<0x7C]), "Globalne nietknięte.")
        e.undo()
        XCTAssertEqual(e.file.bytes, przed)
    }

    func testZamianaKitowDwaRazyWracaDoStanuWyjscia() {
        let e = edytor()
        let przed = e.file.bytes
        XCTAssertTrue(e.zamienKity(1, 70))
        XCTAssertEqual(e.kitName(1), "Samples")
        XCTAssertEqual(e.kitName(70), "CIECHOCINEK")
        XCTAssertEqual(e.sciezkaSampla(kit: 1, trigger: 2), "TEST_B.wav")
        XCTAssertNil(e.sciezkaSampla(kit: 70, trigger: 1))
        XCTAssertTrue(e.zamienKity(1, 70))
        XCTAssertEqual(e.file.bytes, przed)
        XCTAssertEqual(e.changes.count, 2)
    }

    func testPresetZapisOdczytIZastosowanie() throws {
        let e = edytor()
        let preset = try XCTUnwrap(e.presetKitu(70, nazwa: "Moj Kit"))
        XCTAssertEqual(preset.paths, ["TEST_A.wav", "TEST_B.wav", "TESTY/TEST_C.wav", ""])
        let wczytane = try BibliotekaPresetow.czytaj(BibliotekaPresetow.dane([preset]))
        XCTAssertEqual(wczytane, [preset])
        XCTAssertTrue(e.zastosujPreset(wczytane[0], kit: 12))
        XCTAssertEqual(e.kitName(12), "Samples")
        XCTAssertEqual(e.sciezkaSampla(kit: 12, trigger: 1), "TEST_A.wav")
        XCTAssertThrowsError(try BibliotekaPresetow.czytaj(Data("{\"x\":1}".utf8)))
    }

    /// Plik presetów zapisany przez wersję na Androida — ten sam format.
    func testPresetyZAndroida() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "presety-android.tm2kits", withExtension: "json",
                                                  subdirectory: "Zasoby"))
        let lista = try BibliotekaPresetow.czytaj(Data(contentsOf: url))
        XCTAssertEqual(lista.count, 1)
        XCTAssertEqual(lista[0].name, "Moj Kit")
        XCTAssertEqual(lista[0].pliki, ["TEST_A.wav", "TEST_B.wav", "TESTY/TEST_C.wav"])
        let e = edytor()
        XCTAssertTrue(e.zastosujPreset(lista[0], kit: 3))
        XCTAssertEqual(e.sciezkaSampla(kit: 3, trigger: 1), "TEST_A.wav")
        XCTAssertEqual(e.kitEffect(kit: 3)?.nazwa, "DELAY")
    }

    func testTekstyDoSzukania() {
        let e = edytor()
        XCTAssertTrue(e.tekstyKitow[69].contains("testy/test_c.wav"))
        XCTAssertTrue(e.tekstyKitow[0].contains("ciechocinek"))
        XCTAssertFalse(e.tekstyKitow[1].contains(".wav"))
    }
}
