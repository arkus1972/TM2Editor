import Foundation

/// Typ pada (Trigger Type) i wartości, które moduł ustawia, gdy ten typ zostaje
/// wybrany.
///
/// Zmierzone 2026-11-22 seriami `typy-1.bin` … `typy-9.bin`: oba gniazda
/// w trybie PADx2, czyli cztery niezależne pady, i w każdym backupie każdy pad
/// przestawiony WYŁĄCZNIE na inny typ. Zmiana typu przestawia resztę rekordu
/// na wartości domyślne, więc jeden backup dawał od razu cztery numery typów
/// i cztery komplety wartości domyślnych. Kontrola krzyżowa: RT-30K zmierzony
/// drugi raz w `noise.bin` dał co do bajtu to samo, a pierwotna baza Arka
/// (RT-30K w trybie HEAD&RIM) — też.
///
/// Dwie rzeczy warte zapamiętania:
///
/// - **Numer w pliku to nie pozycja na liście w module.** Lista zaczyna się od
///   KD-7, a numer 0 ma KT-10. Typy RT-30 mają numery 32–35, na samym końcu,
///   choć moduł pokazuje je wśród innych RT — wygląda to na ślad aktualizacji
///   1.02, która je dopisała.
/// - **Zmiana typu NIE rusza XTLK Cancel ani Input** — tak mówi instrukcja
///   i potwierdziło to wszystkie 36 pomiarów.
///
/// Tablica jest WYGENEROWANA z plików pomiarowych, nie przepisana ręcznie —
/// komentarz przy każdym wierszu mówi, z którego pliku i rekordu pochodzi.
struct TypPada: Equatable {
    let kod: Int
    let nazwa: String
    let czulosc: Int        // +0x02
    let prog: Int           // +0x03
    let krzywa: Int         // +0x04
    let bajt05: Int         // +0x05 — znaczenie nieznane, ustawiane przez typ
    let retrigCancel: Int   // +0x06
    let bajt07: Int         // +0x07 — znaczenie nieznane, ustawiane przez typ
    let hrAdjust: Int       // +0x09
    let rimGain: Int        // +0x0A
    let noiseCancel: Int    // +0x0B

    /// Bajty od +0x01 do +0x0B rekordu po wybraniu tego typu. Pozycja +0x08
    /// (XTLK Cancel) jest przepisywana z obecnej wartości — typ jej nie rusza.
    func bajtyRekordu(zachowujacXTLK xtlk: UInt8) -> [UInt8] {
        [kod, czulosc, prog, krzywa, bajt05, retrigCancel, bajt07]
            .map { UInt8($0) }
            + [xtlk]
            + [hrAdjust, rimGain, noiseCancel].map { UInt8($0) }
    }
}

enum TypyPadow {

    /// Wszystkie 36 typów, w kolejności numerów z pliku.
    static let wszystkie: [TypPada] = [
        TypPada(kod:  0, nazwa: "KT-10", czulosc: 10, prog: 10, krzywa: 0, bajt05: 28, retrigCancel:  6, bajt07: 16, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-9.bin, rekord 3
        TypPada(kod:  1, nazwa: "KD-7", czulosc:  7, prog: 10, krzywa: 0, bajt05: 16, retrigCancel:  5, bajt07: 16, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-8.bin, rekord 1
        TypPada(kod:  2, nazwa: "KD-8", czulosc:  7, prog:  8, krzywa: 0, bajt05: 16, retrigCancel:  3, bajt07: 16, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-8.bin, rekord 2
        TypPada(kod:  3, nazwa: "KD-9", czulosc:  8, prog: 14, krzywa: 0, bajt05: 20, retrigCancel:  3, bajt07: 16, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-8.bin, rekord 3
        TypPada(kod:  4, nazwa: "KD-85", czulosc: 10, prog: 14, krzywa: 0, bajt05: 24, retrigCancel:  5, bajt07: 16, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-8.bin, rekord 4
        TypPada(kod:  5, nazwa: "KD-120", czulosc: 10, prog: 12, krzywa: 0, bajt05: 28, retrigCancel:  6, bajt07: 16, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-9.bin, rekord 1
        TypPada(kod:  6, nazwa: "KD-140", czulosc: 10, prog: 12, krzywa: 0, bajt05: 28, retrigCancel:  6, bajt07: 16, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-9.bin, rekord 2
        TypPada(kod:  7, nazwa: "PD-8", czulosc:  8, prog: 14, krzywa: 0, bajt05: 12, retrigCancel:  1, bajt07:  9, hrAdjust:  0, rimGain: 13, noiseCancel: 0),  // typy-9.bin, rekord 4
        TypPada(kod:  8, nazwa: "PDX-6", czulosc:  7, prog:  8, krzywa: 0, bajt05: 20, retrigCancel:  1, bajt07:  9, hrAdjust: 30, rimGain: 10, noiseCancel: 0),  // typy-1.bin, rekord 1
        TypPada(kod:  9, nazwa: "PDX-8", czulosc:  7, prog:  8, krzywa: 0, bajt05: 20, retrigCancel:  1, bajt07:  9, hrAdjust: 30, rimGain: 10, noiseCancel: 0),  // typy-1.bin, rekord 2
        TypPada(kod: 10, nazwa: "PDX-100", czulosc:  6, prog: 16, krzywa: 0, bajt05: 20, retrigCancel:  1, bajt07:  9, hrAdjust: 26, rimGain: 10, noiseCancel: 0),  // typy-1.bin, rekord 3
        TypPada(kod: 11, nazwa: "PD-85", czulosc:  5, prog: 10, krzywa: 0, bajt05: 20, retrigCancel:  1, bajt07:  9, hrAdjust: 24, rimGain: 10, noiseCancel: 0),  // typy-1.bin, rekord 4
        TypPada(kod: 12, nazwa: "PD-105", czulosc:  7, prog: 18, krzywa: 0, bajt05: 20, retrigCancel:  1, bajt07:  9, hrAdjust: 23, rimGain: 10, noiseCancel: 0),  // typy-2.bin, rekord 1
        TypPada(kod: 13, nazwa: "PD-105X", czulosc:  7, prog: 18, krzywa: 0, bajt05: 20, retrigCancel:  1, bajt07:  9, hrAdjust: 20, rimGain: 10, noiseCancel: 0),  // typy-2.bin, rekord 2
        TypPada(kod: 14, nazwa: "PD-108", czulosc:  7, prog: 16, krzywa: 0, bajt05: 20, retrigCancel:  1, bajt07:  9, hrAdjust: 20, rimGain: 10, noiseCancel: 0),  // typy-2.bin, rekord 3
        TypPada(kod: 15, nazwa: "PD-125", czulosc:  7, prog: 18, krzywa: 0, bajt05: 20, retrigCancel:  1, bajt07:  9, hrAdjust: 15, rimGain: 10, noiseCancel: 0),  // typy-2.bin, rekord 4
        TypPada(kod: 16, nazwa: "PD-125X", czulosc:  7, prog: 18, krzywa: 0, bajt05: 20, retrigCancel:  1, bajt07:  9, hrAdjust: 14, rimGain: 10, noiseCancel: 0),  // typy-3.bin, rekord 1
        TypPada(kod: 17, nazwa: "PD-128", czulosc:  7, prog: 16, krzywa: 0, bajt05: 20, retrigCancel:  1, bajt07:  9, hrAdjust: 11, rimGain: 10, noiseCancel: 0),  // typy-3.bin, rekord 2
        TypPada(kod: 18, nazwa: "CY-5", czulosc:  8, prog: 16, krzywa: 0, bajt05: 20, retrigCancel:  8, bajt07: 10, hrAdjust:  0, rimGain: 11, noiseCancel: 0),  // typy-3.bin, rekord 3
        TypPada(kod: 19, nazwa: "CY-8", czulosc:  7, prog: 20, krzywa: 0, bajt05: 20, retrigCancel:  8, bajt07: 10, hrAdjust:  0, rimGain:  8, noiseCancel: 0),  // typy-3.bin, rekord 4
        TypPada(kod: 20, nazwa: "CY-12C", czulosc:  7, prog: 17, krzywa: 0, bajt05: 20, retrigCancel:  8, bajt07: 10, hrAdjust:  0, rimGain:  8, noiseCancel: 0),  // typy-4.bin, rekord 1
        TypPada(kod: 21, nazwa: "CY-13R", czulosc:  7, prog: 18, krzywa: 0, bajt05: 20, retrigCancel:  8, bajt07: 10, hrAdjust:  0, rimGain:  8, noiseCancel: 0),  // typy-4.bin, rekord 2
        TypPada(kod: 22, nazwa: "CY-12RC", czulosc:  7, prog: 14, krzywa: 0, bajt05: 20, retrigCancel:  8, bajt07: 10, hrAdjust:  0, rimGain:  8, noiseCancel: 0),  // typy-4.bin, rekord 3
        TypPada(kod: 23, nazwa: "CY-14C", czulosc:  7, prog: 14, krzywa: 0, bajt05: 20, retrigCancel:  8, bajt07: 10, hrAdjust:  0, rimGain:  8, noiseCancel: 0),  // typy-4.bin, rekord 4
        TypPada(kod: 24, nazwa: "CY-15R", czulosc:  8, prog: 16, krzywa: 0, bajt05: 20, retrigCancel:  8, bajt07: 10, hrAdjust:  0, rimGain:  8, noiseCancel: 0),  // typy-5.bin, rekord 1
        TypPada(kod: 25, nazwa: "BT-1", czulosc: 12, prog:  8, krzywa: 0, bajt05: 16, retrigCancel:  6, bajt07: 12, hrAdjust:  0, rimGain: 10, noiseCancel: 0),  // typy-5.bin, rekord 2
        TypPada(kod: 26, nazwa: "BT-1 SENS", czulosc: 12, prog:  7, krzywa: 0, bajt05: 32, retrigCancel:  6, bajt07: 12, hrAdjust:  0, rimGain: 10, noiseCancel: 0),  // typy-5.bin, rekord 3
        TypPada(kod: 27, nazwa: "RT-10K", czulosc:  8, prog: 20, krzywa: 0, bajt05: 36, retrigCancel:  8, bajt07: 12, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-5.bin, rekord 4
        TypPada(kod: 28, nazwa: "RT-10S", czulosc: 10, prog: 18, krzywa: 0, bajt05: 28, retrigCancel:  8, bajt07: 10, hrAdjust: 20, rimGain:  9, noiseCancel: 0),  // typy-6.bin, rekord 2
        TypPada(kod: 29, nazwa: "RT-10T", czulosc:  6, prog: 20, krzywa: 0, bajt05: 32, retrigCancel: 11, bajt07: 10, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-6.bin, rekord 4
        TypPada(kod: 30, nazwa: "PAD1", czulosc: 17, prog: 16, krzywa: 0, bajt05: 40, retrigCancel: 10, bajt07: 12, hrAdjust:  0, rimGain: 11, noiseCancel: 0),  // typy-7.bin, rekord 3
        TypPada(kod: 31, nazwa: "PAD2", czulosc: 17, prog: 16, krzywa: 0, bajt05: 40, retrigCancel: 10, bajt07: 12, hrAdjust: 20, rimGain: 15, noiseCancel: 0),  // typy-7.bin, rekord 4
        TypPada(kod: 32, nazwa: "RT-30K", czulosc:  8, prog: 15, krzywa: 0, bajt05: 36, retrigCancel:  9, bajt07: 12, hrAdjust:  0, rimGain:  0, noiseCancel: 2),  // typy-6.bin, rekord 1
        TypPada(kod: 33, nazwa: "RT-30HR", czulosc:  8, prog: 14, krzywa: 0, bajt05: 28, retrigCancel:  8, bajt07: 10, hrAdjust: 20, rimGain:  9, noiseCancel: 3),  // typy-6.bin, rekord 3
        TypPada(kod: 34, nazwa: "RT30H_SNR", czulosc:  8, prog: 18, krzywa: 0, bajt05: 28, retrigCancel:  8, bajt07: 10, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-7.bin, rekord 1
        TypPada(kod: 35, nazwa: "RT30H_TOM", czulosc:  8, prog: 21, krzywa: 0, bajt05: 32, retrigCancel: 11, bajt07: 24, hrAdjust:  0, rimGain:  0, noiseCancel: 0),  // typy-7.bin, rekord 2
    ]

    /// Kolejność, w jakiej moduł pokazuje typy na liście — spisana przez Arka
    /// z wyświetlacza. Edytor pokazuje je tak samo, żeby nie trzeba było szukać.
    static let kolejnoscNaModule: [Int] = [1, 2, 3, 4, 5, 6, 0, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 32, 28, 33, 29, 34, 35, 30, 31]

    static func typ(kod: Int) -> TypPada? {
        wszystkie.first { $0.kod == kod }
    }

    /// Pozycja w rekordzie, od której zaczyna się to, co przestawia typ.
    static let poczatekWRekordzie = 0x01
    /// Ile bajtów od tego miejsca: +0x01 … +0x0B.
    static let dlugosc = 11
    /// Pozycja XTLK Cancel w rekordzie — jedyny bajt w tym zakresie,
    /// którego zmiana typu nie rusza.
    static let pozycjaXTLK = 0x08
}
