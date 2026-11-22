import Foundation

/// Typ efektu kitu i wartości, które moduł ustawia, gdy ten efekt zostaje
/// wybrany.
///
/// Zmierzone 2026-11-22 jednym backupem (`efekty-1.bin`): kity 70–80 dostały
/// po kolei każdy z jedenastu efektów, BEZ ruszania parametrów — więc każdy kit
/// trzyma wartości domyślne swojego efektu. THRU z serii `min2.bin`.
///
/// Strefa efektu to 44 bajty od +0x16 bloku kitu, pola 16-bitowe LE:
///   +0x16      zawsze 1 — nie zależy od efektu, nie ruszamy
///   +0x18      typ efektu (kod z tej tablicy)
///   +0x1A…     20 pól parametrów; ich ZNACZENIE zależy od typu efektu,
///              a nieużywane pola są wyzerowane
///
/// Numer w pliku to nie pozycja na liście: kody mają dziury (2, 6, 8, 11–13,
/// 17, 18). Wygląda to na wspólną tablicę efektów Rolanda, z której TM-2
/// pokazuje dwanaście.
///
/// Tablica jest WYGENEROWANA z plików pomiarowych — przy każdym wierszu
/// komentarz, skąd pochodzi. Kontrola: REVERB w kicie 80 jest co do bajtu taki
/// sam jak w nietkniętych kitach 69 i 81 (domyślny efekt kitu).
struct TypEfektu: Equatable {
    let kod: Int
    let nazwa: String
    /// 20 wartości dla pól +0x1A, +0x1C, … +0x40.
    let domyslne: [Int]

    /// Bajty od +0x18 (typ) do +0x41 włącznie — 42 bajty, little-endian.
    var bajtyStrefy: [UInt8] {
        ([kod] + domyslne).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    }
}

enum TypyEfektow {

    /// Wszystkie 12 efektów, w kolejności, w jakiej pokazuje je moduł.
    static let wszystkie: [TypEfektu] = [
        TypEfektu(kod:  0, nazwa: "THRU",
                  domyslne: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // min2.bin, kit 40
        TypEfektu(kod:  1, nazwa: "DELAY",
                  domyslne: [0, 100, 100, 50, 1, 9, 50, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 70
        TypEfektu(kod:  3, nazwa: "TAPE ECHO",
                  domyslne: [2, 50, 50, 15, 15, 64, 64, 64, 0, 0, 0, 50, 100, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 71
        TypEfektu(kod:  4, nazwa: "CHORUS",
                  domyslne: [1, 40, 70, 10, 4, 9, 50, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 72
        TypEfektu(kod:  5, nazwa: "FLANGER",
                  domyslne: [0, 30, 0, 90, 100, 80, 50, 10, 50, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 73
        TypEfektu(kod:  7, nazwa: "PHASER",
                  domyslne: [2, 0, 50, 0, 50, 50, 50, 0, 50, 60, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 74
        TypEfektu(kod:  9, nazwa: "EQUALIZER",
                  domyslne: [0, 20, 15, 2, 20, 19, 1, 20, 20, 9, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 75
        TypEfektu(kod: 10, nazwa: "COMP",
                  domyslne: [30, 10, 10, 2, 1, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 76
        TypEfektu(kod: 14, nazwa: "WAH",
                  domyslne: [1, 1, 40, 20, 50, 50, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 77
        TypEfektu(kod: 15, nazwa: "DIST",
                  domyslne: [0, 50, 50, 50, 50, 100, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 78
        TypEfektu(kod: 16, nazwa: "RINGMOD",
                  domyslne: [64, 10, 0, 15, 15, 30, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 79
        TypEfektu(kod: 19, nazwa: "REVERB",
                  domyslne: [2, 30, 0, 1, 7, 10, 10, 100, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),  // efekty-1.bin, kit 80
    ]

    static func typ(kod: Int) -> TypEfektu? {
        wszystkie.first { $0.kod == kod }
    }

    /// Początek zakresu przestawianego przy zmianie efektu, względem bloku kitu.
    static let poczatekWKicie = 0x18
    /// 42 bajty: typ i 20 pól parametrów.
    static let dlugosc = 42
}
