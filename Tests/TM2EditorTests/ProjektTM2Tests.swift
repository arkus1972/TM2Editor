import CryptoKit
import XCTest
@testable import TM2Editor

/// Projekt ze strukturą karty: zakładanie (kopia backupu i sampli) i zapis
/// całości na kartę, z pilnowaniem, żeby niczego tam nie nadpisać.
final class ProjektTM2Tests: XCTestCase {

    private var baza: URL!

    override func setUpWithError() throws {
        baza = FileManager.default.temporaryDirectory
            .appendingPathComponent("projekt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baza, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: baza)
    }

    /// Backup z samplami: kit 1 head = TEST_A.wav, kit 1 rim = TESTY/TEST_C.wav,
    /// kit 2 head = BRAK.wav, kit 2 rim = TEST_A.wav (ten sam plik drugi raz).
    private func bajtyZSamplami() -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 124_748)
        func ustaw(kit: Int, pad: Int, _ sciezka: String) {
            let slot = 0x7C + (kit - 1) * 234 + 0x42 + (pad - 1) * 42
            b[slot + 2] = 2
            let wpis = 0x5AFA + ((kit - 1) * 4 + (pad - 1)) * 256
            let t = Array(sciezka.utf8)
            b.replaceSubrange(wpis..<(wpis + t.count), with: t)
        }
        ustaw(kit: 1, pad: 1, "TEST_A.wav")
        ustaw(kit: 1, pad: 2, "TESTY/TEST_C.wav")
        ustaw(kit: 2, pad: 1, "BRAK.wav")
        ustaw(kit: 2, pad: 2, "TEST_A.wav")
        // Pad z „bankiem" 1 i śmieciami w tablicy — nie jest samplem.
        let wpis = 0x5AFA + 2 * 256
        b.replaceSubrange(wpis..<(wpis + 5), with: Array("STARY".utf8))
        return b
    }

    private func zapiszPlik(_ dane: Data, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try dane.write(to: url)
    }

    func testSciezkiSampliBezPowtorzen() {
        XCTAssertEqual(ProjektTM2.sciezkiSampli(w: bajtyZSamplami()),
                       ["TEST_A.wav", "TESTY/TEST_C.wav", "BRAK.wav"])
        XCTAssertEqual(ProjektTM2.wpisySampli(w: bajtyZSamplami()).count, 4)
        XCTAssertTrue(ProjektTM2.sciezkiSampli(w: [1, 2, 3]).isEmpty)
    }

    /// Backup luzem (np. w Pobranych) — obok niego powstaje `<nazwa> TM-2`
    /// ze strukturą karty, kopią backupu i samplami z karty, które się znalazły.
    func testStrukturaObokBackupuLuzem() throws {
        let karta = baza.appendingPathComponent("KARTA/ROLAND/TM-2")
        try zapiszPlik(Data("A".utf8), karta.appendingPathComponent("WAVE/TEST_A.wav"))
        try zapiszPlik(Data("C".utf8), karta.appendingPathComponent("WAVE/TESTY/TEST_C.wav"))
        let luzem = baza.appendingPathComponent("Pobrane/BKUP-004.TM0")
        try zapiszPlik(Data(bajtyZSamplami()), luzem)

        let p = try ProjektTM2.zaloz(dla: luzem, zrodloWave: karta.appendingPathComponent("WAVE"))
        XCTAssertEqual(p.korzen.lastPathComponent, "BKUP-004 TM-2")
        XCTAssertEqual(p.korzen.deletingLastPathComponent().lastPathComponent, "Pobrane")
        XCTAssertEqual(p.skopiowane, 2)
        XCTAssertEqual(p.brakujace, ["BRAK.wav"])
        XCTAssertEqual(p.backup.path,
                       p.korzen.appendingPathComponent("ROLAND/TM-2/Backup/BKUP-004.TM0").path)
        XCTAssertEqual(try Data(contentsOf: p.backup), Data(bajtyZSamplami()))
        let wave = p.korzen.appendingPathComponent("ROLAND/TM-2/WAVE")
        XCTAssertEqual(try Data(contentsOf: wave.appendingPathComponent("TESTY/TEST_C.wav")), Data("C".utf8))
        XCTAssertEqual(try Data(contentsOf: luzem), Data(bajtyZSamplami()), "Oryginał nietknięty.")

        // Kopia w strukturze jest już „na miejscu" — drugi raz nic nie zakładamy.
        XCTAssertEqual(ProjektTM2.korzenStruktury(dlaBackupu: p.backup)?.path, p.korzen.path)
        XCTAssertNil(ProjektTM2.korzenStruktury(dlaBackupu: luzem))

        // Drugie otwarcie tego samego pliku luzem nie nadpisuje pierwszej struktury.
        let drugi = try ProjektTM2.zaloz(dla: luzem, zrodloWave: nil)
        XCTAssertEqual(drugi.korzen.lastPathComponent, "BKUP-004 TM-2 (2)")
        XCTAssertEqual(drugi.brakujace.count, 3)
    }

    /// Backup na karcie (albo w jej kopii) — praca na miejscu.
    func testKorzenStrukturyKarty() throws {
        let naKarcie = baza.appendingPathComponent("KARTA/ROLAND/TM-2/Backup/BKUP-008.TM0")
        try zapiszPlik(Data(bajtyZSamplami()), naKarcie)
        XCTAssertEqual(ProjektTM2.korzenStruktury(dlaBackupu: naKarcie)?.lastPathComponent, "KARTA")
    }

    /// Backup otwarty bez karty: brakujące sample dociągane z karty (po
    /// ścieżce) albo ze zwykłego folderu (po samej nazwie pliku).
    func testDociaganieBrakujacychSampli() throws {
        let wave = baza.appendingPathComponent("P/ROLAND/TM-2/WAVE")
        try FileManager.default.createDirectory(at: wave, withIntermediateDirectories: true)
        let bajty = bajtyZSamplami()
        XCTAssertEqual(ProjektTM2.brakujaceSample(w: bajty, wave: wave),
                       ["TEST_A.wav", "TESTY/TEST_C.wav", "BRAK.wav"])

        // Karta z TEST_A i TESTY/TEST_C.
        let karta = baza.appendingPathComponent("KARTA")
        try zapiszPlik(Data("A".utf8), karta.appendingPathComponent("ROLAND/TM-2/WAVE/TEST_A.wav"))
        try zapiszPlik(Data("C".utf8), karta.appendingPathComponent("ROLAND/TM-2/WAVE/TESTY/TEST_C.wav"))
        var wynik = ProjektTM2.dociagnij(["TEST_A.wav", "TESTY/TEST_C.wav", "BRAK.wav"],
                                         zWybranego: karta, doWave: wave)
        XCTAssertEqual(wynik.skopiowane, 2)
        XCTAssertEqual(wynik.nadal, ["BRAK.wav"])
        XCTAssertEqual(try Data(contentsOf: wave.appendingPathComponent("TESTY/TEST_C.wav")), Data("C".utf8))

        // Zwykły folder z plikiem — po samej nazwie.
        let luzem = baza.appendingPathComponent("Pobrane")
        try zapiszPlik(Data("B".utf8), luzem.appendingPathComponent("BRAK.wav"))
        wynik = ProjektTM2.dociagnij(["BRAK.wav"], zWybranego: luzem, doWave: wave)
        XCTAssertEqual(wynik.skopiowane, 1)
        XCTAssertTrue(ProjektTM2.brakujaceSample(w: bajty, wave: wave).isEmpty)
    }

    func testTM2DoceloweZRoznychWskazan() {
        let karta = baza.appendingPathComponent("KARTA")
        let tm2 = karta.appendingPathComponent("ROLAND/TM-2").path
        XCTAssertEqual(ProjektTM2.tm2Docelowe(zWybranego: karta).path, tm2)
        XCTAssertEqual(ProjektTM2.tm2Docelowe(zWybranego: karta.appendingPathComponent("ROLAND")).path, tm2)
        XCTAssertEqual(ProjektTM2.tm2Docelowe(zWybranego: karta.appendingPathComponent("ROLAND/TM-2")).path, tm2)
        XCTAssertEqual(ProjektTM2.tm2Docelowe(zWybranego: karta.appendingPathComponent("ROLAND/TM-2/Backup")).path, tm2)
    }

    /// Zapis na „kartę", na której już coś jest: backup dostaje kolejny numer,
    /// identyczny sampel jest pomijany, inny o tej samej nazwie — kopiowany
    /// pod nową nazwą, a ścieżka w zapisanym backupie poprawiona. Niczego na
    /// karcie nie nadpisano. Suma MD5 zapisanego pliku poprawna.
    func testZapisNaKarteBezNadpisywania() throws {
        let projektWave = baza.appendingPathComponent("P/ROLAND/TM-2/WAVE")
        try zapiszPlik(Data("A-nowy".utf8), projektWave.appendingPathComponent("TEST_A.wav"))
        try zapiszPlik(Data("C".utf8), projektWave.appendingPathComponent("TESTY/TEST_C.wav"))

        let karta = baza.appendingPathComponent("KARTA/ROLAND/TM-2")
        try zapiszPlik(Data("stary backup".utf8), karta.appendingPathComponent("Backup/BKUP-003.TM0"))
        try zapiszPlik(Data("A-inny".utf8), karta.appendingPathComponent("WAVE/TEST_A.wav"))
        try zapiszPlik(Data("C".utf8), karta.appendingPathComponent("WAVE/TESTY/TEST_C.wav"))

        let plik = BackupFile(bytes: bajtyZSamplami(), layout: .mapped2026_09_02)
        let raport = try ProjektTM2.zapisz(plik, waveProjektu: projektWave, doTM2: karta)

        XCTAssertEqual(raport.backup.lastPathComponent, "BKUP-004.TM0")
        XCTAssertEqual(raport.skopiowane, 1)
        XCTAssertEqual(raport.pominiete, 1)
        XCTAssertEqual(raport.przemianowane.map { $0.1 }, ["TEST_A_2.wav"])
        XCTAssertEqual(raport.brakujace, ["BRAK.wav"])

        // Na karcie nic nie nadpisane.
        XCTAssertEqual(try Data(contentsOf: karta.appendingPathComponent("WAVE/TEST_A.wav")), Data("A-inny".utf8))
        XCTAssertEqual(try Data(contentsOf: karta.appendingPathComponent("Backup/BKUP-003.TM0")),
                       Data("stary backup".utf8))
        XCTAssertEqual(try Data(contentsOf: karta.appendingPathComponent("WAVE/TEST_A_2.wav")), Data("A-nowy".utf8))

        // Oba pady z TEST_A grają teraz TEST_A_2 — w zapisanym pliku.
        let zapisany = [UInt8](try Data(contentsOf: raport.backup))
        let sciezki = ProjektTM2.wpisySampli(w: zapisany).map { $0.1 }
        XCTAssertEqual(sciezki, ["TEST_A_2.wav", "TESTY/TEST_C.wav", "BRAK.wav", "TEST_A_2.wav"])
        XCTAssertEqual(Array(zapisany.suffix(16)), Array(Insecure.MD5.hash(data: Data(zapisany.dropLast(16)))))
    }
}
