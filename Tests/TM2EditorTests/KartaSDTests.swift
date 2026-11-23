import AVFoundation
import XCTest
@testable import TM2Editor

/// Przygotowanie sampli dla modułu: nazwy, położenie na karcie, przeróbka
/// formatu. Testy pracują w katalogu tymczasowym udającym kartę.
final class KartaSDTests: XCTestCase {

    private var karta: URL!

    override func setUpWithError() throws {
        karta = FileManager.default.temporaryDirectory
            .appendingPathComponent("karta-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: karta.appendingPathComponent("ROLAND/TM-2/Backup"),
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: karta)
    }

    func testFolderWaveObokBackupu() {
        let backup = karta.appendingPathComponent("ROLAND/TM-2/Backup/BKUP-001.TM0")
        XCTAssertEqual(KartaSD.folderWave(dlaBackupu: backup)?.path,
                       karta.appendingPathComponent("ROLAND/TM-2/WAVE").path)
        XCTAssertNil(KartaSD.folderWave(dlaBackupu: karta.appendingPathComponent("BKUP-001.TM0")),
                     "Kopia poza kartą — nie wiadomo, gdzie jest WAVE.")
    }

    /// Wskazać można kartę, folder ROLAND, TM-2 albo WAVE — za każdym razem
    /// wychodzi ten sam folder WAVE. Folder bez ROLAND/TM-2 — odmowa.
    func testFolderWaveZWybranegoFolderu() throws {
        let oczekiwany = karta.appendingPathComponent("ROLAND/TM-2/WAVE").standardizedFileURL.path
        for wskazany in ["", "ROLAND", "ROLAND/TM-2"] {
            let url = wskazany.isEmpty ? karta! : karta.appendingPathComponent(wskazany)
            XCTAssertEqual(KartaSD.folderWave(zWybranego: url)?.standardizedFileURL.path, oczekiwany, wskazany)
        }
        let wave = karta.appendingPathComponent("ROLAND/TM-2/WAVE")
        try FileManager.default.createDirectory(at: wave, withIntermediateDirectories: true)
        XCTAssertEqual(KartaSD.folderWave(zWybranego: wave)?.standardizedFileURL.path, oczekiwany)
        XCTAssertNil(KartaSD.folderWave(zWybranego: karta.appendingPathComponent("ROLAND/TM-2/Backup")))
        XCTAssertNil(KartaSD.folderWave(zWybranego: FileManager.default.temporaryDirectory
            .appendingPathComponent("nie-karta-\(UUID().uuidString)")))
    }

    func testBezpiecznaNazwa() {
        XCTAssertEqual(KartaSD.bezpiecznaNazwa("Werbel ąę.aiff"), "Werbel ae.wav")
        XCTAssertEqual(KartaSD.bezpiecznaNazwa("Kick #1 (dry).WAV"), "Kick _1 _dry_.wav")
        XCTAssertEqual(KartaSD.bezpiecznaNazwa("żółw.mp3"), "zolw.wav")
        XCTAssertTrue(KartaSD.bezpiecznaNazwa(String(repeating: "x", count: 200) + ".wav").count <= 64)
    }

    func testSciezkaWzglednaTylkoJedenPoziom() {
        let wave = karta.appendingPathComponent("ROLAND/TM-2/WAVE")
        XCTAssertEqual(KartaSD.sciezkaWzgledna(wave.appendingPathComponent("A.wav"), wave: wave), "A.wav")
        XCTAssertEqual(KartaSD.sciezkaWzgledna(wave.appendingPathComponent("TESTY/C.wav"), wave: wave),
                       "TESTY/C.wav")
        XCTAssertNil(KartaSD.sciezkaWzgledna(wave.appendingPathComponent("a/b/C.wav"), wave: wave),
                     "Moduł nie widzi drugiego poziomu podfolderów.")
        XCTAssertNil(KartaSD.sciezkaWzgledna(karta.appendingPathComponent("X.wav"), wave: wave))
    }

    /// Plik 48 kHz / 32 bit float stereo — typowy z DAW — wychodzi jako
    /// WAV 44,1 kHz / 16 bit stereo, o długości zgodnej z oryginałem.
    func testPrzerobkaNaFormatModulu() throws {
        let zrodlo = karta.appendingPathComponent("Moj sampel 48k.wav")
        let ustawienia: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ]
        do {
            let plik = try AVAudioFile(forWriting: zrodlo, settings: ustawienia,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            let ramki: AVAudioFrameCount = 48_000 / 2       // 0,5 s
            let bufor = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: plik.processingFormat,
                                                       frameCapacity: ramki))
            bufor.frameLength = ramki
            for kanal in 0..<2 {
                let dane = try XCTUnwrap(bufor.floatChannelData?[kanal])
                for i in 0..<Int(ramki) {
                    dane[i] = 0.5 * sin(2 * .pi * 440 * Float(i) / 48_000)
                }
            }
            try plik.write(from: bufor)
        }
        XCTAssertFalse(KartaSD.czyFormatModulu(zrodlo))

        let wave = karta.appendingPathComponent("ROLAND/TM-2/WAVE")
        let wynik = try KartaSD.przygotuj(zrodlo: zrodlo, wave: wave)
        XCTAssertTrue(wynik.przerobiony)
        XCTAssertEqual(wynik.sciezka, "Moj sampel 48k.wav")
        let cel = wave.appendingPathComponent(wynik.sciezka)
        XCTAssertTrue(KartaSD.czyFormatModulu(cel))
        let gotowy = try AVAudioFile(forReading: cel)
        XCTAssertEqual(gotowy.fileFormat.channelCount, 2)
        XCTAssertEqual(Double(gotowy.length), 22_050, accuracy: 300, "0,5 s przy 44,1 kHz")

        // Drugie przypisanie tego samego pliku nie nadpisuje istniejącego —
        // dostaje nową nazwę (przy przeróbce nie da się porównać zawartości).
        let drugi = try KartaSD.przygotuj(zrodlo: zrodlo, wave: wave)
        XCTAssertEqual(drugi.sciezka, "Moj sampel 48k_2.wav")

        // Plik już w WAVE, w dobrym formacie — tylko wskazany, bez kopii.
        let trzeci = try KartaSD.przygotuj(zrodlo: cel, wave: wave)
        XCTAssertEqual(trzeci.sciezka, "Moj sampel 48k.wav")
        XCTAssertFalse(trzeci.przerobiony)
    }
}
