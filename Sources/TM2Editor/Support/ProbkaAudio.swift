import AVFoundation
import CStbVorbis
import Foundation

/// Dźwięk wczytany do pamięci, już w częstotliwości modułu (44,1 kHz),
/// gotowy do obróbki w mini edytorze i zapisu na kartę.
///
/// Próbki trzymamy jako `Float` w zakresie −1…1, osobno dla każdego kanału
/// (1 albo 2). Wszystkie operacje zwracają NOWĄ próbkę — oryginał zostaje,
/// więc suwaki w edytorze zawsze liczą od czystego źródła, a nie od wyniku
/// poprzedniego ruchu.
struct ProbkaAudio: Equatable {

    static let czestotliwosc: Double = 44_100

    /// Kanały: `[lewy]` albo `[lewy, prawy]`, równej długości.
    var kanaly: [[Float]]

    var dlugosc: Int { kanaly.first?.count ?? 0 }
    var liczbaKanalow: Int { kanaly.count }
    var sekundy: Double { Double(dlugosc) / Self.czestotliwosc }

    /// Rozmiar pliku WAV po zapisie: 44 B nagłówka + 2 B na próbkę na kanał.
    var rozmiarPliku: Int { 44 + dlugosc * liczbaKanalow * 2 }

    /// Największa wartość bezwzględna — do normalizacji i wskaźnika przesteru.
    var szczyt: Float {
        kanaly.reduce(0) { wynik, kanal in
            kanal.reduce(wynik) { Swift.max($0, abs($1)) }
        }
    }

    enum Blad: LocalizedError {
        case nieCzytelny(String)
        case zaDuzoKanalow(Int)
        case pusty

        var errorDescription: String? {
            switch self {
            case .nieCzytelny(let nazwa):
                return "Cannot read \(nazwa). Supported: WAV, AIFF, MP3, M4A, FLAC, OGG."
            case .zaDuzoKanalow(let ile):
                return "The file has \(ile) channels. The TM-2 plays mono or stereo only."
            case .pusty:
                return "The file contains no audio."
            }
        }
    }

    // MARK: - Wczytywanie

    /// Wczytuje plik w dowolnym formacie, który zna macOS (WAV, AIFF, MP3,
    /// M4A, FLAC…), a OGG — wbudowanym dekoderem stb_vorbis. Wynik jest już
    /// w 44,1 kHz, z zachowaną liczbą kanałów.
    static func wczytaj(_ url: URL) throws -> ProbkaAudio {
        if ["ogg", "oga"].contains(url.pathExtension.lowercased()) {
            return try wczytajOgg(url)
        }
        let plik: AVAudioFile
        do {
            plik = try AVAudioFile(forReading: url)
        } catch {
            throw Blad.nieCzytelny(url.lastPathComponent)
        }
        let format = plik.processingFormat
        guard (1...2).contains(format.channelCount) else {
            throw Blad.zaDuzoKanalow(Int(format.channelCount))
        }
        let ramki = AVAudioFrameCount(plik.length)
        guard ramki > 0, let bufor = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: ramki) else {
            throw Blad.pusty
        }
        do {
            try plik.read(into: bufor)
        } catch {
            throw Blad.nieCzytelny(url.lastPathComponent)
        }
        return try zBufora(bufor)
    }

    private static func wczytajOgg(_ url: URL) throws -> ProbkaAudio {
        var kanaly: Int32 = 0
        var czestotliwosc: Int32 = 0
        var dekodowane: UnsafeMutablePointer<Int16>?
        let ramki = url.withUnsafeFileSystemRepresentation { sciezka -> Int32 in
            guard let sciezka else { return -1 }
            return stb_vorbis_decode_filename(sciezka, &kanaly, &czestotliwosc, &dekodowane)
        }
        guard ramki > 0, let wynik = dekodowane else { throw Blad.nieCzytelny(url.lastPathComponent) }
        defer { free(wynik) }
        guard (1...2).contains(kanaly) else { throw Blad.zaDuzoKanalow(Int(kanaly)) }

        let n = Int(ramki), k = Int(kanaly)
        var dane = [[Float]](repeating: [Float](repeating: 0, count: n), count: k)
        for i in 0..<n {
            for kanal in 0..<k {
                dane[kanal][i] = Float(wynik[i * k + kanal]) / 32768
            }
        }
        return try przeprobkuj(dane, z: Double(czestotliwosc))
    }

    /// Bufor w dowolnym formacie → próbka 44,1 kHz (przez AVAudioConverter).
    private static func zBufora(_ wejscie: AVAudioPCMBuffer) throws -> ProbkaAudio {
        let formatWe = wejscie.format
        guard let formatWy = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                           sampleRate: czestotliwosc,
                                           channels: formatWe.channelCount,
                                           interleaved: false),
              let konwerter = AVAudioConverter(from: formatWe, to: formatWy) else {
            throw Blad.pusty
        }
        let proporcja = czestotliwosc / formatWe.sampleRate
        let pojemnosc = AVAudioFrameCount(Double(wejscie.frameLength) * proporcja) + 4096
        guard let wyjscie = AVAudioPCMBuffer(pcmFormat: formatWy, frameCapacity: pojemnosc) else {
            throw Blad.pusty
        }
        var podane = false
        var blad: NSError?
        let stan = konwerter.convert(to: wyjscie, error: &blad) { _, status in
            if podane {
                status.pointee = .endOfStream
                return nil
            }
            podane = true
            status.pointee = .haveData
            return wejscie
        }
        if stan == .error || blad != nil {
            throw Blad.nieCzytelny(blad?.localizedDescription ?? "audio")
        }
        guard let dane = wyjscie.floatChannelData, wyjscie.frameLength > 0 else {
            throw Blad.pusty
        }
        let n = Int(wyjscie.frameLength)
        let kanaly = (0..<Int(formatWy.channelCount)).map { kanal in
            Array(UnsafeBufferPointer(start: dane[kanal], count: n))
        }
        return ProbkaAudio(kanaly: kanaly)
    }

    /// Kanały w innej częstotliwości → 44,1 kHz.
    static func przeprobkuj(_ dane: [[Float]], z czestotliwoscZrodla: Double) throws -> ProbkaAudio {
        guard let n = dane.first?.count, n > 0 else { throw Blad.pusty }
        if czestotliwoscZrodla == czestotliwosc { return ProbkaAudio(kanaly: dane) }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: czestotliwoscZrodla,
                                         channels: AVAudioChannelCount(dane.count),
                                         interleaved: false),
              let bufor = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let cel = bufor.floatChannelData else {
            throw Blad.pusty
        }
        bufor.frameLength = AVAudioFrameCount(n)
        for (kanal, probki) in dane.enumerated() {
            for i in 0..<n { cel[kanal][i] = probki[i] }
        }
        return try zBufora(bufor)
    }

    // MARK: - Obróbka

    /// Fragment od próbki `od` (włącznie) do `do` (wyłącznie).
    func przyciete(od: Int, do koniec: Int) -> ProbkaAudio {
        let a = Swift.max(0, Swift.min(od, dlugosc))
        let b = Swift.max(a, Swift.min(koniec, dlugosc))
        return ProbkaAudio(kanaly: kanaly.map { Array($0[a..<b]) })
    }

    /// Stereo → mono (średnia kanałów). Mono zostaje bez zmian.
    func mono() -> ProbkaAudio {
        guard liczbaKanalow == 2 else { return self }
        let l = kanaly[0], p = kanaly[1]
        return ProbkaAudio(kanaly: [zip(l, p).map { ($0 + $1) * 0.5 }])
    }

    func zeWzmocnieniem(dB: Double) -> ProbkaAudio {
        guard dB != 0 else { return self }
        let mnoznik = Float(pow(10, dB / 20))
        return ProbkaAudio(kanaly: kanaly.map { $0.map { $0 * mnoznik } })
    }

    /// Najgłośniejsza próbka na `szczytDB` dBFS (domyślnie −0,3 dB — zapas,
    /// żeby zaokrąglenie do 16 bitów nie dało przesteru).
    func znormalizowane(szczytDB: Double = -0.3) -> ProbkaAudio {
        let teraz = szczyt
        guard teraz > 0 else { return self }
        let cel = Float(pow(10, szczytDB / 20))
        let mnoznik = cel / teraz
        return ProbkaAudio(kanaly: kanaly.map { $0.map { $0 * mnoznik } })
    }

    /// Liniowe narastanie na pierwszych `probek` próbkach.
    func zNarastaniem(probek: Int) -> ProbkaAudio {
        let n = Swift.min(probek, dlugosc)
        guard n > 0 else { return self }
        var wynik = kanaly
        for k in wynik.indices {
            for i in 0..<n { wynik[k][i] *= Float(i) / Float(n) }
        }
        return ProbkaAudio(kanaly: wynik)
    }

    /// Liniowe wygaszenie na ostatnich `probek` próbkach — koniec dokładnie
    /// w zerze, bez trzasku.
    func zWygaszaniem(probek: Int) -> ProbkaAudio {
        let n = Swift.min(probek, dlugosc)
        guard n > 0 else { return self }
        var wynik = kanaly
        let start = dlugosc - n
        for k in wynik.indices {
            for i in 0..<n { wynik[k][start + i] *= Float(n - 1 - i) / Float(n) }
        }
        return ProbkaAudio(kanaly: wynik)
    }

    // MARK: - Zapis

    /// Plik WAV dokładnie w formacie modułu: RIFF, 16 bit, 44,1 kHz,
    /// 44-bajtowy nagłówek i NIC więcej.
    ///
    /// Bez metadanych celowo: Roland pisze, że TM-2 odrzuca WAV-y z tagami
    /// komunikatem „Unsupported Format", nawet przy poprawnym formacie.
    /// Dlatego nawet plik, który już był w dobrym formacie, idzie na kartę
    /// przepisany na czysto.
    func danePliku() -> Data {
        let k = liczbaKanalow, n = dlugosc
        let bajtyDanych = n * k * 2
        var d = Data(capacity: 44 + bajtyDanych)
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bajtyDanych)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1)                                   // PCM
        u16(k)
        u32(Int(Self.czestotliwosc))
        u32(Int(Self.czestotliwosc) * k * 2)     // bajtów na sekundę
        u16(k * 2)                               // bajtów na ramkę
        u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bajtyDanych)
        var probki = [Int16](repeating: 0, count: n * k)
        for i in 0..<n {
            for kanal in 0..<k {
                let v = Swift.max(-1, Swift.min(1, kanaly[kanal][i]))
                probki[i * k + kanal] = Int16((v * 32767).rounded()).littleEndian
            }
        }
        probki.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }

    // MARK: - Podgląd

    /// Najmniejsza i największa wartość (ze wszystkich kanałów) w każdej
    /// z `kolumn` równych części — do narysowania przebiegu.
    func przebieg(kolumn: Int) -> [(min: Float, max: Float)] {
        guard kolumn > 0, dlugosc > 0 else { return [] }
        return (0..<kolumn).map { c in
            let a = c * dlugosc / kolumn
            let b = Swift.max(a + 1, (c + 1) * dlugosc / kolumn)
            var lo: Float = 0, hi: Float = 0
            for kanal in kanaly {
                for i in a..<Swift.min(b, dlugosc) {
                    lo = Swift.min(lo, kanal[i]); hi = Swift.max(hi, kanal[i])
                }
            }
            return (lo, hi)
        }
    }
}

/// Ustawienia mini edytora — wszystko, co da się zrobić z sampelkiem przed
/// wysłaniem na kartę. Zawsze liczone od oryginału, w stałej kolejności.
struct UstawieniaSampla: Equatable {
    var poczatek: Double = 0              // sekundy
    var koniec: Double                    // sekundy
    var mono = false
    var normalizuj = false
    var wzmocnienieDB: Double = 0
    var narastanieMs: Double = 0
    var wygaszanieMs: Double = 0

    init(dlaDlugosci sekundy: Double) {
        koniec = sekundy
    }

    /// Kolejność: przycięcie → mono → normalizacja → wzmocnienie → narastanie
    /// i wygaszenie. Normalizacja przed wzmocnieniem, żeby suwak „Gain" działał
    /// względem znormalizowanego poziomu, a obwiednie na końcu, żeby koniec
    /// pliku zawsze był w zerze, bez względu na wzmocnienie.
    func zastosuj(do zrodlo: ProbkaAudio) -> ProbkaAudio {
        let f = ProbkaAudio.czestotliwosc
        var p = zrodlo.przyciete(od: Int((poczatek * f).rounded()), do: Int((koniec * f).rounded()))
        if mono { p = p.mono() }
        if normalizuj { p = p.znormalizowane() }
        p = p.zeWzmocnieniem(dB: wzmocnienieDB)
        p = p.zNarastaniem(probek: Int(narastanieMs / 1000 * f))
        p = p.zWygaszaniem(probek: Int(wygaszanieMs / 1000 * f))
        return p
    }

    /// Czy cokolwiek zmieniono względem pełnego, nietkniętego pliku.
    func czyBezZmian(dlugoscZrodla sekundy: Double) -> Bool {
        self == UstawieniaSampla(dlaDlugosci: sekundy)
    }
}
