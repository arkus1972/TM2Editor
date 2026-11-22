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

    /// Dwa bajty, little-endian, ZE ZNAKIEM (uzupełnienia do dwóch).
    ///
    /// Tak zapisany jest Pitch w prawdziwym pliku BACKUP — zmierzone
    /// 2026-09-04 na obu skrajnościach: +120 to bajty `78 00`, −120 to
    /// `88 FF`. Niezależne potwierdzenie przyszło z samego pliku bazowego:
    /// kit 1, trigger 2 ma fabrycznie `FE FF`, czyli −2, więc wartości
    /// ujemne naprawdę występują w danych z modułu, a nie tylko w teorii.
    ///
    /// Osobny wariant, a nie `biased`, bo przesunięcie zapisuje wartość
    /// w jednym bajcie i nie udźwignęłoby zakresu ±120 wokół zera razem
    /// z drugim bajtem, który tu realnie się rusza.
    case signed16LE(min: Int, max: Int)

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
        case .unsigned16LE, .unsigned16BE, .signed16LE:
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
        case .unsigned16LE(let min, let max), .unsigned16BE(let min, let max),
             .signed16LE(let min, let max):
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

/// Jak pokazać wartość użytkownikowi.
///
/// Sposób zapisu w pliku i sposób pokazania to dwie różne rzeczy. Moduł na
/// wyświetlaczu pokazuje `L15` i `300 ms`, a w pliku siedzi `0` i `3000` —
/// i dobrze, żeby edytor mówił językiem modułu, a nie językiem bajtów.
/// Surowa wartość zostaje dostępna w dymku, bo przy mapowaniu bywa potrzebna.
enum FieldDisplay: Codable, Equatable {

    /// Liczba wprost, bez upiększeń.
    case plain

    /// Panorama: ujemne jako `L…`, dodatnie jako `R…`, zero jako `CENTER`.
    case panLeftRight

    /// Wartość ujemna to „wyłączone". Moduł tak zapisuje `Note# = OFF`:
    /// −1 zamiast liczby nuty. Bez tego edytor pokazywałby „−1", a przy
    /// odczycie jednobajtowym nawet „255".
    case offWhenNegative

    /// Wartość przeskalowana w dół, z jednostką: 3000 przy dzielniku 10
    /// i jednym miejscu po przecinku daje `300.0 ms`.
    case scaled(divisor: Int, fractionDigits: Int, unit: String)

    func text(for value: Int) -> String {
        switch self {
        case .plain:
            return String(value)

        case .panLeftRight:
            if value == 0 { return "CENTER" }
            return value < 0 ? "L\(-value)" : "R\(value)"

        case .offWhenNegative:
            return value < 0 ? "OFF" : String(value)

        case .scaled(let divisor, let fractionDigits, let unit):
            // Dzielnik 0 byłby błędem w opisie układu, ale widok nie jest od
            // zgłaszania błędów — pokazuje wtedy surową liczbę, co i tak jest
            // prawdą o zawartości pliku.
            guard divisor > 0 else { return String(value) }
            let scaled = Double(value) / Double(divisor)
            let liczba = String(format: "%.\(fractionDigits)f", scaled)
            // Pusta jednostka to normalny przypadek: Rim Gain pokazuje samo
            // „8.0", bez niczego dalej. Bez tego warunku zostawałaby wisząca
            // spacja na końcu wartości.
            return unit.isEmpty ? liczba : "\(liczba) \(unit)"
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

    /// Jak pokazać wartość. `nil` = liczba wprost.
    /// Opcjonalne celowo: stary `tm2-layout.json` bez tego klucza ma się
    /// nadal wczytywać bez błędu.
    var display: FieldDisplay? = nil

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
