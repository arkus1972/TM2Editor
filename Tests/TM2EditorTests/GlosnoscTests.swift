import XCTest
@testable import TM2Editor

/// Pomiar głośności (BS.1770) i wyrównywanie sampli.
final class GlosnoscTests: XCTestCase {

    private func sinus(_ amplituda: Float, sekund: Double = 1, kanalow: Int = 1) -> ProbkaAudio {
        let n = Int(sekund * ProbkaAudio.czestotliwosc)
        let k = (0..<n).map { amplituda * sin(2 * .pi * 997 * Float($0) / 44_100) }
        return ProbkaAudio(kanaly: Array(repeating: k, count: kanalow))
    }

    /// Punkt odniesienia z normy: sinus 997 Hz w pełnej skali, jeden kanał
    /// = −3,01 LUFS. Sprawdzone też obliczeniem tych samych filtrów w Pythonie.
    func testSinusOdniesieniaZNormy() throws {
        XCTAssertEqual(try XCTUnwrap(Glosnosc.zmierz(sinus(1))), -3.01, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(Glosnosc.zmierz(sinus(0.1))), -23.01, accuracy: 0.05)
        // Dwa jednakowe kanały = +3 dB.
        XCTAssertEqual(try XCTUnwrap(Glosnosc.zmierz(sinus(1, kanalow: 2))), 0.0, accuracy: 0.05)
    }

    func testKrotkiSampelICisza() throws {
        // 0,2 s — krócej niż okno 400 ms: mierzony w całości.
        XCTAssertEqual(try XCTUnwrap(Glosnosc.zmierz(sinus(1, sekund: 0.2))), -3.01, accuracy: 0.15)
        XCTAssertNil(Glosnosc.zmierz(ProbkaAudio(kanaly: [[Float](repeating: 0, count: 1000)])))
    }

    /// Wzmocnienie nigdy nie wchodzi w przester (szczyt najwyżej −0,3 dBFS).
    func testWzmocnienieOgraniczonePrzesterem() {
        let w = Glosnosc.wzmocnienie(odGlosnosci: -20, szczyt: 0.5, doCelu: -10)
        XCTAssertTrue(w.ograniczone)
        XCTAssertEqual(w.dB, -0.3 - 20 * log10(0.5), accuracy: 1e-9)   // ok. +5,72 dB
        let ok = Glosnosc.wzmocnienie(odGlosnosci: -20, szczyt: 0.1, doCelu: -14)
        XCTAssertFalse(ok.ograniczone)
        XCTAssertEqual(ok.dB, 6, accuracy: 1e-9)
        XCTAssertEqual(Glosnosc.wzmocnienie(odGlosnosci: -8, szczyt: 0.9, doCelu: -14).dB, -6, accuracy: 1e-9)
    }
}
