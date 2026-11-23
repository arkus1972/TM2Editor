import AVFoundation
import XCTest
@testable import TM2Editor

/// Mini edytor sampli: obróbka, zapis WAV „na czysto" i wczytywanie formatów.
final class ProbkaAudioTests: XCTestCase {

    private func narastajaca(_ n: Int, kanalow: Int = 1) -> ProbkaAudio {
        let k = (0..<n).map { Float($0) / Float(n) * 0.5 }
        return ProbkaAudio(kanaly: Array(repeating: k, count: kanalow))
    }

    func testPrzycieciePilnujeGranic() {
        let p = narastajaca(1000)
        XCTAssertEqual(p.przyciete(od: 100, do: 300).dlugosc, 200)
        XCTAssertEqual(p.przyciete(od: 100, do: 300).kanaly[0].first, p.kanaly[0][100])
        XCTAssertEqual(p.przyciete(od: -5, do: 5000).dlugosc, 1000)
        XCTAssertEqual(p.przyciete(od: 800, do: 200).dlugosc, 0, "Koniec przed początkiem — pusto, bez wywrotki.")
    }

    func testNormalizacjaIWzmocnienie() {
        let p = narastajaca(1000)
        let n = p.znormalizowane()
        XCTAssertEqual(Double(n.szczyt), pow(10, -0.3 / 20), accuracy: 1e-4)
        XCTAssertEqual(Double(p.zeWzmocnieniem(dB: 6).szczyt) / Double(p.szczyt), 1.995, accuracy: 0.01)
        XCTAssertEqual(ProbkaAudio(kanaly: [[0, 0, 0]]).znormalizowane().szczyt, 0, "Cisza zostaje ciszą.")
    }

    func testObwiednieKonczaSieWZerze() {
        let p = ProbkaAudio(kanaly: [[Float](repeating: 1, count: 1000)])
        let w = p.zWygaszaniem(probek: 100)
        XCTAssertEqual(w.kanaly[0].last, 0, "Koniec pliku w zerze — bez trzasku.")
        XCTAssertEqual(w.kanaly[0][899], 1)
        let n = p.zNarastaniem(probek: 100)
        XCTAssertEqual(n.kanaly[0][0], 0)
        XCTAssertEqual(n.kanaly[0][100], 1)
    }

    func testMonoToSredniaKanalow() {
        let p = ProbkaAudio(kanaly: [[1, 0.5], [0, -0.5]])
        XCTAssertEqual(p.mono().kanaly, [[0.5, 0]])
        XCTAssertEqual(p.mono().mono(), p.mono())
    }

    /// Nagłówek dokładnie 44 B, nic poza „fmt " i „data" — bez metadanych,
    /// których TM-2 nie znosi.
    func testPlikWavBezMetadanych() throws {
        let p = narastajaca(441, kanalow: 2)
        let d = p.danePliku()
        XCTAssertEqual(d.count, 44 + 441 * 2 * 2)
        XCTAssertEqual(d.count, p.rozmiarPliku)
        let b = [UInt8](d)
        XCTAssertEqual(Array(b[0..<4]), Array("RIFF".utf8))
        XCTAssertEqual(Array(b[8..<16]), Array("WAVEfmt ".utf8))
        XCTAssertEqual(Array(b[36..<40]), Array("data".utf8))
        XCTAssertEqual(UInt16(b[22]) | UInt16(b[23]) << 8, 2, "kanały")
        XCTAssertEqual(UInt32(b[24]) | UInt32(b[25]) << 8 | UInt32(b[26]) << 16, 44_100)
        XCTAssertEqual(UInt16(b[34]) | UInt16(b[35]) << 8, 16, "bity")

        // macOS czyta to jako format modułu.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("czysty-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try d.write(to: url)
        XCTAssertTrue(KartaSD.czyFormatModulu(url))
        let z = try ProbkaAudio.wczytaj(url)
        XCTAssertEqual(z.dlugosc, 441)
        XCTAssertEqual(z.liczbaKanalow, 2)
        XCTAssertEqual(Double(z.kanaly[1][440]), Double(p.kanaly[1][440]), accuracy: 1.0 / 32768 + 1e-6)
    }

    /// OGG przez wbudowany dekoder: 0,5 s, 48 kHz, stereo → 44,1 kHz.
    func testOggDekodowanyIPrzeprobkowany() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "test-48k-stereo", withExtension: "ogg",
                                                  subdirectory: "Zasoby"))
        let p = try ProbkaAudio.wczytaj(url)
        XCTAssertEqual(p.liczbaKanalow, 2)
        XCTAssertEqual(p.sekundy, 0.5, accuracy: 0.01)
        XCTAssertGreaterThan(p.szczyt, 0.05, "Sinus z ffmpeg ma amplitudę 1/8 — ma być słychać, nie cisza.")
    }

    func testUstawieniaLiczoneOdOryginalu() {
        let p = ProbkaAudio(kanaly: [[Float](repeating: 0.25, count: 44_100)])
        var u = UstawieniaSampla(dlaDlugosci: p.sekundy)
        XCTAssertTrue(u.czyBezZmian(dlugoscZrodla: p.sekundy))
        XCTAssertEqual(u.zastosuj(do: p), p)
        u.poczatek = 0.5
        u.normalizuj = true
        u.wygaszanieMs = 100
        let w = u.zastosuj(do: p)
        XCTAssertEqual(w.dlugosc, 22_050)
        XCTAssertEqual(w.kanaly[0].last, 0)
        XCTAssertFalse(u.czyBezZmian(dlugoscZrodla: p.sekundy))
    }

    func testCzytaWiecejNizWav() {
        XCTAssertThrowsError(try ProbkaAudio.wczytaj(URL(fileURLWithPath: "/nie/ma/takiego.mp3")))
    }
}
