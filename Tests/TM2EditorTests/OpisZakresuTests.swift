import XCTest
@testable import TM2Editor

/// Opis pod parametrem: liczby rosnące równo — zakres, reszta — pełna lista.
final class OpisZakresuTests: XCTestCase {

    func testRownoRosnaceLiczbyToZakres() {
        XCTAssertEqual(FieldRow.lista((1...10).map(String.init)), "1 … 10")       // Contrast
        XCTAssertEqual(FieldRow.lista((1...16).map(String.init)), "1 … 16")       // MIDI Ch
        XCTAssertEqual(FieldRow.lista((-24 ... -1).map { "\($0) dB" } + ["OFF"]),
                       "-24 dB … -1 dB, OFF")                                     // Limiter
    }

    func testTekstyINieregularneLiczbyToLista() {
        XCTAssertEqual(FieldRow.lista(ParametryEfektow.dobrocQ), "0.5, 1, 2, 4, 8, 16")
        XCTAssertEqual(FieldRow.lista(ParametryEfektow.ratio), "2:1, 3:1, 4:1, 8:1, 100:1")
        XCTAssertEqual(FieldRow.lista(ParametryEfektow.loCut), ParametryEfektow.loCut.joined(separator: ", "))
        XCTAssertEqual(FieldRow.lista(ParametryEfektow.hiCut), ParametryEfektow.hiCut.joined(separator: ", "))
        XCTAssertEqual(FieldRow.lista(["LINEAR", "EXP1", "EXP2"]), "LINEAR, EXP1, EXP2")
        XCTAssertEqual(FieldRow.lista(["1", "2"]), "1, 2", "Dwie pozycje — po prostu obie.")
    }
}
