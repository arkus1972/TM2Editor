import Foundation

/// Do czego pole się odnosi.
enum FieldScope: String, Codable, CaseIterable {
    /// Ustawienie całego modułu.
    case global
    /// Ustawienie kitu jako całości.
    case kit
    /// Ustawienie pojedynczego triggera w kicie.
    case trigger
}

/// Grupa tematyczna — służy tylko do porządkowania widoku.
enum FieldGroup: String, Codable, CaseIterable {
    case kit
    case sound
    case triggerInput
    case system

    /// Etykieta w interfejsie. Interfejs aplikacji jest po angielsku.
    var displayName: String {
        switch self {
        case .kit: return "Kit"
        case .sound: return "Sound"
        case .triggerInput: return "Trigger Input"
        case .system: return "System"
        }
    }
}

/// Sposób zakodowania wartości w pliku.
///
/// Dopóki nie znamy formatu, każdy wariant jest hipotezą. Wszystkie są proste
/// i odwracalne — żaden nie robi nic sprytnego, bo w module z 2013 roku nie ma
/// powodu spodziewać się niczego sprytnego.
enum FieldEncoding: Codable, Equatable {

    /// Jeden bajt, wartość wprost.
    case unsigned(min: Int, max: Int)

    /// Jeden bajt z przesunięciem: wartość = bajt - bias.
    /// Tak zwykle koduje się zakresy symetryczne (Pan L32..R32, Pitch -48..+48).
    case biased(bias: Int, min: Int, max: Int)

    /// Dwa bajty, little-endian.
    case unsigned16LE(min: Int, max: Int)

    /// Dwa bajty, big-endian. Roland historycznie lubi big-endian.
    case unsigned16BE(min: Int, max: Int)

    /// Pojedynczy bit w bajcie.
    case bit(index: Int)

    /// Bajt jako indeks na liście nazw.
    case enumeration(values: [String])

    /// Bajt jako 0/1.
    case boolean

    /// Ciąg znaków ASCII o stałej długości, dopełniany spacjami.
    case ascii(length: Int)

    /// Ciąg znaków UTF-16, little-endian, o stałej długości W BAJTACH,
    /// dopełniany spacjami. Tak koduje nazwę kitu prawdziwy plik BACKUP —
    /// znalezione na mapowaniu różnicowym 2026-09-02, nie zgadnięte: bez tego
    /// przeszukiwanie ASCII widziało tylko nagłówek pliku, bo każdy znak
    /// nazwy jest przeplatany zerowym bajtem.
    case utf16LE(length: Int)

    /// Ile bajtów zajmuje pole.
    var byteLength: Int {
        switch self {
        case .unsigned, .biased, .bit, .enumeration, .boolean:
            return 1
        case .unsigned16LE, .unsigned16BE:
            return 2
        case .ascii(let length), .utf16LE(let length):
            return length
        }
    }

    /// Dopuszczalny zakres wartości liczbowej. Dla pól tekstowych `nil`.
    var numericRange: ClosedRange<Int>? {
        switch self {
        case .unsigned(let min, let max):
            return min...max
        case .biased(_, let min, let max):
            return min...max
        case .unsigned16LE(let min, let max), .unsigned16BE(let min, let max):
            return min...max
        case .bit:
            return 0...1
        case .boolean:
            return 0...1
        case .enumeration(let values):
            return values.isEmpty ? nil : 0...(values.count - 1)
        case .ascii, .utf16LE:
            return nil
        }
    }

    var isTextual: Bool {
        switch self {
        case .ascii, .utf16LE: return true
        default: return false
        }
    }
}

/// Opis jednego edytowalnego parametru.
///
/// `offset` jest opcjonalny i to jest celowe: pole opisane, ale jeszcze
/// niezmapowane, ma pełne prawo istnieć. Widok pokazuje je wtedy jako
/// nieaktywne, z adnotacją "not mapped yet" — dzięki temu lista pól jest
/// jednocześnie listą zadań do zrobienia w protokole mapowania.
struct FieldSpec: Codable, Equatable, Identifiable, Hashable {

    /// Stabilny identyfikator, np. "trig.level". Po nim odwołuje się do pola
    /// lista zmian i testy — nigdy po etykiecie, bo etykieta może się zmienić.
    let id: String

    /// Etykieta w interfejsie (po angielsku).
    let label: String

    let scope: FieldScope

    let group: FieldGroup

    /// Offset względem początku bloku właściwego dla `scope`.
    /// `nil` = jeszcze nie zmapowane.
    var offset: Int?

    var encoding: FieldEncoding

    /// Notatka robocza (po polsku) — co wiemy, czego nie wiemy, co sprawdzić.
    var note: String?

    var isMapped: Bool { offset != nil }

    static func == (lhs: FieldSpec, rhs: FieldSpec) -> Bool {
        lhs.id == rhs.id && lhs.offset == rhs.offset && lhs.encoding == rhs.encoding
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Wartość pola — liczba albo tekst.
enum FieldValue: Equatable, CustomStringConvertible {
    case number(Int)
    case text(String)

    var description: String {
        switch self {
        case .number(let value): return String(value)
        case .text(let value): return value
        }
    }

    var numberValue: Int? {
        if case .number(let value) = self { return value }
        return nil
    }

    var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}
