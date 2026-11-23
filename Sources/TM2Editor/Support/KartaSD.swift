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
    /// (względem WAVE) oraz to, czy na kartę poszła nowa kopia.
    ///
    /// Plik, który już leży w WAVE i ma format modułu, jest tylko wskazany.
    /// Każdy inny — wczytany (z przeróbką do 44,1 kHz) i zapisany na kartę
    /// na czysto, bez metadanych (patrz `ProbkaAudio.danePliku`).
    static func przygotuj(zrodlo: URL, wave: URL) throws -> (sciezka: String, przerobiony: Bool) {
        if czyFormatModulu(zrodlo), let wzgledna = sciezkaWzgledna(zrodlo, wave: wave),
           wzgledna.allSatisfy({ $0.isASCII }) {
            return (wzgledna, false)
        }
        let probka = try ProbkaAudio.wczytaj(zrodlo)
        let sciezka = try zapiszNaKarte(probka, nazwa: zrodlo.lastPathComponent, wave: wave)
        return (sciezka, true)
    }

    /// Zapisuje próbkę jako nowy plik w WAVE i zwraca jego ścieżkę względną.
    /// Nigdy nie nadpisuje: zajęta nazwa dostaje dopisek `_2`, `_3`…
    static func zapiszNaKarte(_ probka: ProbkaAudio, nazwa: String, wave: URL) throws -> String {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: wave, withIntermediateDirectories: true)
        } catch {
            throw Blad.brakFolderuWave(wave)
        }
        let ileWFolderze = (try? fm.contentsOfDirectory(atPath: wave.path))?
            .filter { $0.lowercased().hasSuffix(".wav") }.count ?? 0
        guard ileWFolderze < limitPlikowWFolderze else { throw Blad.pelnyFolder }

        let czysta = bezpiecznaNazwa(nazwa)
        let rdzen = (czysta as NSString).deletingPathExtension
        var wolny: URL?
        for numer in 1...99 {
            let kandydat = wave.appendingPathComponent(numer == 1 ? czysta : "\(rdzen)_\(numer).wav")
            if !fm.fileExists(atPath: kandydat.path) {
                wolny = kandydat
                break
            }
        }
        guard let cel = wolny else { throw Blad.konwersja("too many files named \(czysta)") }
        do {
            // .withoutOverwriting: gdyby plik pojawił się w międzyczasie,
            // zapis się nie uda, zamiast go nadpisać.
            try probka.danePliku().write(to: cel, options: .withoutOverwriting)
        } catch {
            throw Blad.konwersja(error.localizedDescription)
        }
        return cel.lastPathComponent
    }
}
