import AVFoundation
import Foundation

/// Przygotowanie pliku dźwiękowego z Maca do zagrania na module: format,
/// nazwa, miejsce na karcie.
///
/// Wymagania modułu (instrukcja TM-2, s. 10): WAV, 44,1 kHz, 16 bit, mono
/// albo stereo, w `ROLAND/TM-2/WAVE` lub jednym poziomie podfolderów, do 300
/// plików w folderze, nazwy bez znaków dwubajtowych. Moduł szuka pliku po
/// ścieżce zapisanej w backupie (zmierzone 2026-11-23), więc wystarczy, że
/// plik leży tam, gdzie wskazuje backup.
///
/// Zasady:
///  - oryginał na Macu nigdy nie jest ruszany — na kartę idzie kopia;
///  - plik w innym formacie (48 kHz, 24 bit, AIFF, MP3…) jest PRZEROBIONY
///    wbudowanymi narzędziami macOS, offline — tak chciał Arek: „to ma
///    ułatwiać życie";
///  - z karty niczego nie kasujemy; istniejący plik o tej samej nazwie, ale
///    innej zawartości, nie jest nadpisywany — nowy dostaje dopisek `_2`, `_3`.
enum KartaSD {

    static let czestotliwosc: Double = 44_100
    static let limitPlikowWFolderze = 300

    enum Blad: LocalizedError {
        case nieNaKarcie
        case brakFolderuWave(URL)
        case zaDuzoKanalow(Int)
        case pelnyFolder
        case konwersja(String)

        var errorDescription: String? {
            switch self {
            case .nieNaKarcie:
                return "Open the backup straight from the SD card (ROLAND/TM-2/Backup) "
                    + "to assign WAV files — the editor copies them to ROLAND/TM-2/WAVE next to it."
            case .brakFolderuWave(let url):
                return "Could not create the WAVE folder: \(url.path)"
            case .zaDuzoKanalow(let ile):
                return "The file has \(ile) channels. The TM-2 plays mono or stereo only."
            case .pelnyFolder:
                return "The WAVE folder already holds \(KartaSD.limitPlikowWFolderze) files — the TM-2 limit."
            case .konwersja(let opis):
                return "Could not convert the audio file: \(opis)"
            }
        }
    }

    /// Folder WAVE karty, na której leży backup.
    /// `…/ROLAND/TM-2/Backup/BKUP-001.TM0` → `…/ROLAND/TM-2/WAVE`.
    /// `nil`, gdy plik nie leży w takiej strukturze (np. kopia w Pobranych).
    static func folderWave(dlaBackupu url: URL) -> URL? {
        let backup = url.deletingLastPathComponent()
        guard backup.lastPathComponent.lowercased() == "backup" else { return nil }
        let tm2 = backup.deletingLastPathComponent()
        guard tm2.lastPathComponent.uppercased() == "TM-2" else { return nil }
        return tm2.appendingPathComponent("WAVE", isDirectory: true)
    }

    /// Nazwa bezpieczna dla wyświetlacza modułu: polskie i inne znaki
    /// zamienione na łacińskie bez ogonków, reszta spoza [A-Za-z0-9 _-.] na
    /// „_", rozszerzenie `.wav`. „Werbel ąę.aiff" → „Werbel ae.wav".
    static func bezpiecznaNazwa(_ nazwa: String) -> String {
        let rdzen = (nazwa as NSString).deletingPathExtension
        // „Latin-ASCII" radzi sobie też z literami, których nie da się rozłożyć
        // na literę i znak diakrytyczny — „ł" → „l", „ß" → „ss".
        let bezOgonkow = rdzen.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"),
                                                 reverse: false) ?? rdzen
        let dozwolone = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _-.")
        var wynik = String(bezOgonkow.map { dozwolone.contains($0) ? $0 : "_" })
            .trimmingCharacters(in: .whitespaces)
        if wynik.isEmpty { wynik = "sample" }
        // Krótko: wyświetlacz i tak pokaże tylko początek.
        if wynik.count > 60 { wynik = String(wynik.prefix(60)) }
        return wynik + ".wav"
    }

    /// Czy plik już jest w formacie, który moduł gra bez przeróbki.
    static func czyFormatModulu(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "wav",
              let plik = try? AVAudioFile(forReading: url) else { return false }
        let format = plik.fileFormat
        let bity = format.settings[AVLinearPCMBitDepthKey] as? Int
        let zmiennoprzecinkowy = format.settings[AVLinearPCMIsFloatKey] as? Bool ?? false
        return format.sampleRate == czestotliwosc
            && (1...2).contains(format.channelCount)
            && bity == 16 && !zmiennoprzecinkowy
    }

    /// Ścieżka pliku względem folderu WAVE, jeśli plik już w nim leży
    /// (w korzeniu albo jeden poziom niżej) — wtedy nic nie kopiujemy.
    static func sciezkaWzgledna(_ plik: URL, wave: URL) -> String? {
        let p = plik.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let w = wave.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard p.count > w.count, Array(p.prefix(w.count)) == w else { return nil }
        let reszta = Array(p.dropFirst(w.count))
        guard (1...2).contains(reszta.count) else { return nil }
        return reszta.joined(separator: "/")
    }

    /// Przygotowuje plik dla modułu i zwraca ścieżkę do wpisania w backup
    /// (względem WAVE) oraz to, czy był przerabiany.
    static func przygotuj(zrodlo: URL, wave: URL) throws -> (sciezka: String, przerobiony: Bool) {
        let fm = FileManager.default
        let gotowy = czyFormatModulu(zrodlo)

        // Plik już leży w WAVE i ma dobry format — tylko go wskazujemy.
        if gotowy, let wzgledna = sciezkaWzgledna(zrodlo, wave: wave),
           wzgledna.allSatisfy({ $0.isASCII }) {
            return (wzgledna, false)
        }

        do {
            try fm.createDirectory(at: wave, withIntermediateDirectories: true)
        } catch {
            throw Blad.brakFolderuWave(wave)
        }

        let nazwa = bezpiecznaNazwa(zrodlo.lastPathComponent)
        let cel = try wolneMiejsce(na: nazwa, w: wave, zrodlo: gotowy ? zrodlo : nil)
        if fm.fileExists(atPath: cel.path) {
            // Ta sama zawartość już jest na karcie — używamy jej.
            return (cel.lastPathComponent, false)
        }
        let ileWFolderze = (try? fm.contentsOfDirectory(atPath: wave.path))?
            .filter { $0.lowercased().hasSuffix(".wav") }.count ?? 0
        guard ileWFolderze < limitPlikowWFolderze else { throw Blad.pelnyFolder }

        do {
            if gotowy {
                try fm.copyItem(at: zrodlo, to: cel)
            } else {
                try przerob(zrodlo, na: cel)
            }
        } catch {
            // Usuwamy wyłącznie to, co sami przed chwilą zaczęliśmy zapisywać —
            // niedokończony plik na karcie grałby śmieci.
            try? fm.removeItem(at: cel)
            throw error
        }
        return (cel.lastPathComponent, !gotowy)
    }

    /// Wolna nazwa w folderze. Gdy plik o tej nazwie istnieje i jest TAKI SAM
    /// jak źródło (tylko przy kopiowaniu bez przeróbki da się to porównać),
    /// zwraca istniejący — bez dublowania.
    private static func wolneMiejsce(na nazwa: String, w folder: URL, zrodlo: URL?) throws -> URL {
        let fm = FileManager.default
        let rdzen = (nazwa as NSString).deletingPathExtension
        for numer in 1...99 {
            let kandydat = folder.appendingPathComponent(numer == 1 ? nazwa : "\(rdzen)_\(numer).wav")
            guard fm.fileExists(atPath: kandydat.path) else { return kandydat }
            if let zrodlo, fm.contentsEqual(atPath: zrodlo.path, andPath: kandydat.path) {
                return kandydat
            }
        }
        throw Blad.konwersja("too many files named \(nazwa)")
    }

    /// Przeróbka na WAV 44,1 kHz / 16 bit, z zachowaniem mono/stereo.
    static func przerob(_ zrodlo: URL, na cel: URL) throws {
        let wejscie: AVAudioFile
        do {
            wejscie = try AVAudioFile(forReading: zrodlo)
        } catch {
            throw Blad.konwersja("cannot read \(zrodlo.lastPathComponent): \(error.localizedDescription)")
        }
        let formatWe = wejscie.processingFormat
        let kanaly = formatWe.channelCount
        guard (1...2).contains(kanaly) else { throw Blad.zaDuzoKanalow(Int(kanaly)) }

        let ustawienia: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: czestotliwosc,
            AVNumberOfChannelsKey: kanaly,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let wyjscie = try AVAudioFile(forWriting: cel, settings: ustawienia,
                                      commonFormat: .pcmFormatFloat32, interleaved: false)
        let formatWy = wyjscie.processingFormat
        guard let konwerter = AVAudioConverter(from: formatWe, to: formatWy) else {
            throw Blad.konwersja("no converter from \(formatWe) to \(formatWy)")
        }

        let porcja: AVAudioFrameCount = 8192
        var koniec = false
        while true {
            guard let bufor = AVAudioPCMBuffer(pcmFormat: formatWy, frameCapacity: porcja) else {
                throw Blad.konwersja("out of memory")
            }
            var blad: NSError?
            let stan = konwerter.convert(to: bufor, error: &blad) { ile, status in
                if koniec {
                    status.pointee = .endOfStream
                    return nil
                }
                guard let we = AVAudioPCMBuffer(pcmFormat: formatWe, frameCapacity: ile) else {
                    status.pointee = .endOfStream
                    return nil
                }
                do {
                    try wejscie.read(into: we, frameCount: ile)
                } catch {
                    koniec = true
                }
                if we.frameLength == 0 {
                    koniec = true
                    status.pointee = .endOfStream
                    return nil
                }
                status.pointee = .haveData
                return we
            }
            if let blad {
                throw Blad.konwersja(blad.localizedDescription)
            }
            if bufor.frameLength > 0 {
                try wyjscie.write(from: bufor)
            }
            if stan == .endOfStream || stan == .error {
                break
            }
        }
    }
}
