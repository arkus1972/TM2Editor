import Foundation

/// Parametry każdego efektu kitu — nazwy, adresy, zakresy i sposób pokazania.
///
/// Skąd to wiadomo (2026-11-23):
///  - nazwy, kolejność i zakresy z wyświetlacza: Roland „TM-2 Sound List"
///    (TM-2_SoundList_e01_W.pdf, strony 5–6, „Effect List");
///  - adresy i skale z trzech backupów na kitach 70–80: wartości domyślne
///    (`efekty-1.bin` przed 23.11), maksima (commit `aaa7990`) i minima
///    (`BKUP-006`), plus odczyty Arka z wyświetlacza.
///
/// Zasada przypisania: kolejność pól w pliku = kolejność parametrów na
/// wyświetlaczu. Potwierdzona pomiarem w DELAY, TAPE ECHO, CHORUS, EQUALIZER,
/// COMP (Attack do 100, Release do 99), DIST, RINGMOD i REVERB. W FLANGER,
/// PHASER i WAH wszystkie parametry mają ten sam zakres 0–100, więc seria
/// max/min ich nie rozróżniała — rozstrzygnął osobny backup z 23.11
/// (`efekty-kolejnosc.bin`): każdy parametr inna wartość, 1, 2, 3, 4, i w pliku
/// ułożyły się dokładnie po kolei.
///
/// Pola, których moduł nie pokazuje (np. +0x1E w DELAY, stałe 100), nie są
/// tu wystawione — trzymają wartości domyślne i edytor ich nie rusza.
///
/// Nazwy parametrów jak na WYŚWIETLACZU, nie jak w PDF: Sound List pisze
/// „Feedbak", moduł pokazuje „FeedBack" (odczyt Arka 23.11).
///
/// Rozbieżność z PDF: lista typów DIST w Sound List ma „METAL LEAD" jako
/// jedną pozycję. Plik (maksimum 24, czyli 25 pozycji) i przeklikanie listy
/// na module mówią: METAL i LEAD osobno. Obowiązuje moduł.
enum ParametryEfektow {

    // MARK: - Listy wartości

    /// Potwierdzone na module: 55 Hz (1), 200 Hz (4), 800 Hz (10) pomiarem,
    /// reszta przeklikana przez Arka 23.11.
    static let loCut = ["FLAT", "55 Hz", "110 Hz", "165 Hz", "200 Hz", "280 Hz",
                        "340 Hz", "400 Hz", "500 Hz", "630 Hz", "800 Hz"]

    /// 8.0 kHz (7) i FLAT (9) pomiarem, reszta przeklikana 23.11.
    static let hiCut = ["700 Hz", "1.0 kHz", "1.4 kHz", "2.0 kHz", "3.0 kHz",
                        "4.0 kHz", "6.0 kHz", "8.0 kHz", "11 kHz", "FLAT"]

    /// Szereg tercjowy 20 Hz…10 kHz, 28 pozycji. Zmierzone: 630 Hz (15),
    /// 1.60 kHz (19), 10.0 kHz (27) i minimum 0; krańce zgodne z Sound List.
    static let czestotliwoscEQ = [
        "20.0 Hz", "25.0 Hz", "31.5 Hz", "40.0 Hz", "50.0 Hz", "63.0 Hz",
        "80.0 Hz", "100 Hz", "125 Hz", "160 Hz", "200 Hz", "250 Hz", "315 Hz",
        "400 Hz", "500 Hz", "630 Hz", "800 Hz", "1.00 kHz", "1.25 kHz",
        "1.60 kHz", "2.00 kHz", "2.50 kHz", "3.15 kHz", "4.00 kHz", "5.00 kHz",
        "6.30 kHz", "8.00 kHz", "10.0 kHz",
    ]

    /// Sound List: „0.5, 1, 2, 4, 8, 16"; maksimum 5 = 16 na wyświetlaczu.
    static let dobrocQ = ["0.5", "1", "2", "4", "8", "16"]

    /// 2:1 i 100:1 z Sound List, 4:1 i 100:1 pomiarem, 3:1 i 8:1 odczytane
    /// przez Arka 23.11.
    static let ratio = ["2:1", "3:1", "4:1", "8:1", "100:1"]

    static let knee = ["SOFT", "HARD"]

    static let polarity = ["UP", "DOWN"]

    /// Kolejność przeklikana na module. Sound List pisze „HALL 1", moduł
    /// „HALL1" — sprawdzone na wyświetlaczu 23.11.
    static let typPoglosu = ["AMB", "ROOM", "HALL1", "HALL2", "PLATE"]

    /// 25 pozycji, przeklikane na module od MID BST do MUFF FUZZ.
    static let typPrzesteru = [
        "MID BST", "CLN BST", "TRBL BST", "BLUES", "CRUNCH", "NATURAL", "OD-1",
        "T-SCREAM", "TURBO OD", "WARM OD", "DIST", "MILD DS", "MID DS", "RAT",
        "GUV DS", "DST+", "MODERN DS", "SOLID DS", "STACK", "LOUD", "METAL",
        "LEAD", "'60S FUZZ", "OCT FUZZ", "MUFF FUZZ",
    ]

    // MARK: - Parametry według kodu efektu

    /// Parametry efektu o danym kodzie, w kolejności z wyświetlacza.
    /// THRU i nieznane kody — pusta lista.
    static func parametry(kodEfektu kod: Int) -> [FieldSpec] {
        tablica[kod] ?? []
    }

    private static let tablica: [Int: [FieldSpec]] = {
        var t: [Int: [FieldSpec]] = [:]

        // DELAY — wszystkie skrajności zmierzone.
        t[1] = [
            pole(1, "dlyTime", "DlyTime", 0x1C, 0...350, .scaled(divisor: 1, fractionDigits: 0, unit: "ms")),
            pole(1, "feedback", "FeedBack", 0x20, 0...99, .scaled(divisor: 1, fractionDigits: 0, unit: "%")),
            pole(1, "loCut", "LoCut", 0x22, lista: loCut),
            pole(1, "hiCut", "HiCut", 0x24, lista: hiCut),
            dryWet(1, 0x26),
            poziom(1, 0x28),
        ]

        // TAPE ECHO — maksima zmierzone; minima odczytane z wyświetlacza 23.11
        // (RepeatRate 0, Intensity 0, Bass/Treble −15 dB, Dry-Wet 100:0, Level 0),
        // bez backupu: przy serii min kit 71 przeskoczył na DELAY.
        t[3] = [
            pole(3, "repeatRate", "RepeatRate", 0x1C, 0...127, .plain),
            pole(3, "intensity", "Intensity", 0x1E, 0...127, .plain),
            pole(3, "bass", "Bass", 0x20, 0...30, .przesuniecie(bias: 15, unit: "dB")),
            pole(3, "treble", "Treble", 0x22, 0...30, .przesuniecie(bias: 15, unit: "dB")),
            dryWet(3, 0x30),
            poziom(3, 0x32),
        ]

        // CHORUS — wszystkie skrajności zmierzone; PreDly co 0,5 ms.
        t[4] = [
            pole(4, "rate", "Rate", 0x1C, 0...100, .plain),
            pole(4, "depth", "Depth", 0x1E, 0...100, .plain),
            pole(4, "preDelay", "PreDly", 0x20, 0...80, .scaled(divisor: 2, fractionDigits: 1, unit: "ms")),
            pole(4, "loCut", "LoCut", 0x22, lista: loCut),
            pole(4, "hiCut", "HiCut", 0x24, lista: hiCut),
            dryWet(4, 0x26),
            poziom(4, 0x28),
        ]

        // FLANGER — Rate/Depth/Manual/Resonance = 1/2/3/4 w efekty-kolejnosc.bin.
        // LoCut zmierzony (0…10).
        t[5] = [
            pole(5, "rate", "Rate", 0x1C, 0...100, .plain),
            pole(5, "depth", "Depth", 0x20, 0...100, .plain),
            pole(5, "manual", "Manual", 0x22, 0...100, .plain),
            pole(5, "resonance", "Resonance", 0x24, 0...100, .plain),
            pole(5, "loCut", "LoCut", 0x28, lista: loCut),
            dryWet(5, 0x2A),
            poziom(5, 0x2C),
        ]

        // PHASER — Rate/Depth/Manual/Resonance = 1/2/3/4 w efekty-kolejnosc.bin.
        t[7] = [
            pole(7, "rate", "Rate", 0x1E, 0...100, .plain),
            pole(7, "depth", "Depth", 0x22, 0...100, .plain),
            pole(7, "manual", "Manual", 0x24, 0...100, .plain),
            pole(7, "resonance", "Resonance", 0x26, 0...100, .plain),
            dryWet(7, 0x2A),
            poziom(7, 0x2C),
        ]

        // EQUALIZER — maksima odczytane z wyświetlacza (10.0 kHz, 16, +20 dB).
        t[9] = [
            pole(9, "eq1Freq", "Eq1Frq", 0x1E, lista: czestotliwoscEQ),
            pole(9, "eq1Q", "Eq1 Q", 0x20, lista: dobrocQ),
            pole(9, "eq1Gain", "Eq1 Gain", 0x22, 0...40, .przesuniecie(bias: 20, unit: "dB")),
            pole(9, "eq2Freq", "Eq2Frq", 0x24, lista: czestotliwoscEQ),
            pole(9, "eq2Q", "Eq2 Q", 0x26, lista: dobrocQ),
            pole(9, "eq2Gain", "Eq2 Gain", 0x28, 0...40, .przesuniecie(bias: 20, unit: "dB")),
            pole(9, "level", "Level", 0x2E, 0...40, .przesuniecie(bias: 20, unit: "dB")),
        ]

        // COMP — Ratio 100:1 i Make Up +24 dB odczytane z wyświetlacza.
        t[10] = [
            pole(10, "threshold", "Thrshd", 0x1A, 0...48, .przesuniecie(bias: 48, unit: "dB")),
            pole(10, "attack", "Attack", 0x1C, 0...100, .plain),
            pole(10, "release", "Release", 0x1E, 0...99, .plain),
            pole(10, "ratio", "Ratio", 0x20, lista: ratio),
            pole(10, "knee", "Knee", 0x22, lista: knee),
            pole(10, "makeUp", "Make Up", 0x24, 0...24, .przesuniecie(bias: 0, unit: "dB")),
        ]

        // WAH — Sens/Frequency/Peak = 1/2/3 w efekty-kolejnosc.bin.
        t[14] = [
            pole(14, "sens", "Sens", 0x1E, 0...100, .plain),
            pole(14, "frequency", "Frequency", 0x20, 0...100, .plain),
            pole(14, "peak", "Peak", 0x22, 0...100, .plain),
            dryWet(14, 0x24),
            poziom(14, 0x26),
        ]

        // DIST — typ MUFF FUZZ (24) i Drive 120 zmierzone.
        t[15] = [
            pole(15, "type", "Type", 0x1A, lista: typPrzesteru),
            pole(15, "drive", "Drive", 0x1C, 0...120, .plain),
            pole(15, "bottom", "Bottom", 0x1E, 0...100, .przesuniecie(bias: 50, unit: "")),
            pole(15, "tone", "Tone", 0x20, 0...100, .przesuniecie(bias: 50, unit: "")),
            pole(15, "wetLevel", "Wet Level", 0x22, 0...100, .plain),
            dryWet(15, 0x24),
            poziom(15, 0x26),
        ]

        // RINGMOD — Frequency 127, Sens 127, Polarity DOWN odczytane.
        t[16] = [
            pole(16, "frequency", "Frequency", 0x1A, 0...127, .plain),
            pole(16, "sens", "Sens", 0x1C, 0...127, .plain),
            pole(16, "polarity", "Polarity", 0x1E, lista: polarity),
            pole(16, "loGain", "Lo Gain", 0x20, 0...30, .przesuniecie(bias: 15, unit: "dB")),
            pole(16, "hiGain", "Hi Gain", 0x22, 0...30, .przesuniecie(bias: 15, unit: "dB")),
            dryWet(16, 0x24),
            poziom(16, 0x26),
        ]

        // REVERB — Level pod +0x28 rozstrzygnięty serią minimów (100 → 0).
        t[19] = [
            pole(19, "type", "Rev Type", 0x1A, lista: typPoglosu),
            pole(19, "time", "RevTime", 0x1C, 0...99, .plain),
            pole(19, "preDelay", "PreDly", 0x1E, 0...100, .plain),
            pole(19, "loCut", "LoCut", 0x20, lista: loCut),
            pole(19, "hiCut", "HiCut", 0x22, lista: hiCut),
            dryWet(19, 0x26),
            poziom(19, 0x28),
        ]
        return t
    }()

    // MARK: - Pomocnicze

    /// Identyfikator zawiera kod efektu: `fx.19.time`. Po nim edytor sprawdza
    /// przed zapisem, czy kit nadal ma TEN efekt — inaczej liczba wpisana dla
    /// REVERB i zatwierdzona po zmianie efektu trafiłaby w pole innego
    /// parametru.
    static let prefiksID = "fx."

    static func kodEfektu(zID id: String) -> Int? {
        guard id.hasPrefix(prefiksID) else { return nil }
        let reszta = id.dropFirst(prefiksID.count)
        guard let kropka = reszta.firstIndex(of: ".") else { return nil }
        return Int(reszta[..<kropka])
    }

    private static func pole(_ kod: Int, _ klucz: String, _ etykieta: String,
                             _ offset: Int, _ zakres: ClosedRange<Int>,
                             _ wyswietlanie: FieldDisplay) -> FieldSpec {
        FieldSpec(
            id: "\(prefiksID)\(kod).\(klucz)",
            label: etykieta,
            scope: .kit,
            group: .kit,
            offset: offset,
            encoding: .unsigned16LE(min: zakres.lowerBound, max: zakres.upperBound),
            note: nil,
            display: wyswietlanie
        )
    }

    private static func pole(_ kod: Int, _ klucz: String, _ etykieta: String,
                             _ offset: Int, lista: [String]) -> FieldSpec {
        pole(kod, klucz, etykieta, offset, 0...(lista.count - 1), .lista(lista))
    }

    /// Dry-Wet: w pliku udział efektu 0–100, na wyświetlaczu „100:0"…„0:100".
    private static func dryWet(_ kod: Int, _ offset: Int) -> FieldSpec {
        pole(kod, "dryWet", "Dry-Wet", offset, 0...100, .dryWet)
    }

    private static func poziom(_ kod: Int, _ offset: Int) -> FieldSpec {
        pole(kod, "level", "Level", offset, 0...100, .plain)
    }
}
