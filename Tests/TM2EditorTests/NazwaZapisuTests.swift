import XCTest
@testable import TM2Editor

/// Nazwa pliku to nie kosmetyka: moduł szuka backupów po wzorcu nazwy
/// (`BKUP-001.TM0` w katalogu `ROLAND/TM-2/Backup` na karcie). Plik nazwany
/// inaczej nie pojawi się na liście przy BACKUP LOAD, więc użytkownik
/// zobaczy, że „nic się nie zapisało", choć plik leży na karcie.
final class NazwaZapisuTests: XCTestCase {

    func testKolejnyNumerDlaPlikuZKarty() {
        XCTAssertEqual(NazwaZapisu.propozycja(dlaPliku: "BKUP-001.TM0"), "BKUP-002.TM0")
        XCTAssertEqual(NazwaZapisu.propozycja(dlaPliku: "BKUP-009.TM0"), "BKUP-010.TM0")
        XCTAssertEqual(NazwaZapisu.propozycja(dlaPliku: "BKUP-099.TM0"), "BKUP-100.TM0")
    }

    /// Karta bywa sformatowana tak, że nazwy pokazują się wersalikami.
    func testWielkoscLiterNieMaZnaczenia() {
        XCTAssertEqual(NazwaZapisu.propozycja(dlaPliku: "bkup-001.tm0"), "BKUP-002.TM0")
        XCTAssertEqual(NazwaZapisu.propozycja(dlaPliku: "BKUP-001.tm0"), "BKUP-002.TM0")
    }

    /// Oryginał nigdy nie może być propozycją — inaczej jedno kliknięcie
    /// „Save" nadpisałoby plik, który moduł zapisał.
    func testPropozycjaNigdyNieJestNazwaOryginalu() {
        for numer in 0...998 {
            let nazwa = String(format: "BKUP-%03d.TM0", numer)
            XCTAssertNotEqual(NazwaZapisu.propozycja(dlaPliku: nazwa), nazwa)
        }
    }

    /// Plik spoza karty zostaje przy starym zachowaniu: dopisek „-edited",
    /// żeby niczego nie nadpisać.
    func testPlikSpozaKartyDostajeDopisek() {
        XCTAssertEqual(NazwaZapisu.propozycja(dlaPliku: "kit40-inst.bin"),
                       "kit40-inst-edited.bin")
        XCTAssertEqual(NazwaZapisu.propozycja(dlaPliku: "backup"), "backup-edited")
        XCTAssertEqual(NazwaZapisu.propozycja(dlaPliku: nil), "TM2-BACKUP-edited")
        XCTAssertEqual(NazwaZapisu.propozycja(dlaPliku: ""), "TM2-BACKUP-edited")
    }

    /// Nazwy tylko podobne do wzorca nie mogą udawać, że nim są —
    /// inaczej edytor zaproponowałby nazwę, której moduł i tak nie przyjmie.
    func testNazwyPodobneDoWzorcaSaOdrzucane() {
        XCTAssertNil(NazwaZapisu.numerBackupu("BKUP-1.TM0"))       // nie trzy cyfry
        XCTAssertNil(NazwaZapisu.numerBackupu("BKUP-0001.TM0"))    // cztery cyfry
        XCTAssertNil(NazwaZapisu.numerBackupu("BKUP-001.TM1"))     // inne rozszerzenie
        XCTAssertNil(NazwaZapisu.numerBackupu("BKUP-001.TM0a"))    // ogon po rozszerzeniu
        XCTAssertNil(NazwaZapisu.numerBackupu("BKUP-00A.TM0"))     // nie liczba
        XCTAssertNil(NazwaZapisu.numerBackupu("KOPIA-001.TM0"))    // inny przedrostek
        XCTAssertNil(NazwaZapisu.numerBackupu("BKUP-001-kopia.TM0"))
        XCTAssertEqual(NazwaZapisu.numerBackupu("BKUP-001.TM0"), 1)
    }

    /// Przy numerze na granicy zakresu lepiej dopisek niż przekręcenie
    /// się na cztery cyfry, których moduł mógłby nie rozpoznać.
    func testNumerNaGranicyNieRosnieDoCzterechCyfr() {
        XCTAssertEqual(NazwaZapisu.propozycja(dlaPliku: "BKUP-999.TM0"),
                       "BKUP-999-edited.TM0")
    }
}
