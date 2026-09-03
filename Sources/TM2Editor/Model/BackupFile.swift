import Foundation

/// Błędy pracy z plikiem BACKUP.
enum BackupFileError: LocalizedError {
    case empty
    case unexpectedSize(actual: Int, expected: Int)
    case badMagic(actual: [UInt8], expected: [UInt8])
    case offsetOutOfBounds(offset: Int, length: Int, fileSize: Int)
    case fieldNotMapped(fieldID: String)
    case valueOutOfRange(fieldID: String, value: Int, allowed: ClosedRange<Int>)
    case textTooLong(fieldID: String, limit: Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "The file is empty."
        case .unexpectedSize(let actual, let expected):
            return "Unexpected file size: \(actual) bytes, expected \(expected)."
        case .badMagic(let actual, let expected):
            let a = actual.map { String(format: "%02X", $0) }.joined(separator: " ")
            let e = expected.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "Unrecognised file header: \(a), expected \(e)."
        case .offsetOutOfBounds(let offset, let length, let fileSize):
            return "Offset \(offset)+\(length) is outside the file (\(fileSize) bytes)."
        case .fieldNotMapped(let fieldID):
            return "Field \"\(fieldID)\" has no known offset yet."
        case .valueOutOfRange(let fieldID, let value, let allowed):
            return "Value \(value) is outside the allowed range "
                + "\(allowed.lowerBound)…\(allowed.upperBound) for \"\(fieldID)\"."
        case .textTooLong(let fieldID, let limit):
            return "Text is too long for \"\(fieldID)\" (limit \(limit) characters)."
        }
    }
}

/// Plik BACKUP wczytany do pamięci, razem z opisem układu.
///
/// Zasada bezpieczeństwa całego projektu: pracujemy na kopii bajtów w pamięci.
/// Plik źródłowy nie jest nigdy nadpisywany w miejscu — zapis idzie zawsze do
/// nowego pliku, a oryginał zostaje na karcie nietknięty.
struct BackupFile {

    /// Surowa zawartość pliku.
    private(set) var bytes: [UInt8]

    /// Zawartość w chwili wczytania — punkt odniesienia dla listy zmian
    /// i dla cofania.
    let originalBytes: [UInt8]

    /// Skąd plik pochodzi.
    let sourceURL: URL?

    /// Opis układu. Może być całkowicie pusty (nic jeszcze nie zmapowane).
    var layout: BackupLayout

    var size: Int { bytes.count }

    var isModified: Bool { bytes != originalBytes }

    // MARK: - Tworzenie

    init(bytes: [UInt8], layout: BackupLayout, sourceURL: URL? = nil) {
        self.bytes = bytes
        self.originalBytes = bytes
        self.layout = layout
        self.sourceURL = sourceURL
    }

    /// Wczytanie z dysku. Nie waliduje formatu — walidacja jest osobno, żeby
    /// dało się otworzyć i obejrzeć plik, którego jeszcze nie rozumiemy.
    init(contentsOf url: URL, layout: BackupLayout) throws {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw BackupFileError.empty }
        self.init(bytes: [UInt8](data), layout: layout, sourceURL: url)
    }

    // MARK: - Walidacja

    /// Sprawdza plik na tyle, na ile pozwala aktualna wiedza o formacie.
    /// Zwraca listę ostrzeżeń — pusta lista znaczy "nic podejrzanego".
    func validate() -> [String] {
        var warnings: [String] = []

        if let expected = layout.expectedFileSize, expected != bytes.count {
            warnings.append("File size is \(bytes.count) bytes, "
                + "but the mapped layout expects \(expected).")
        }

        if let magic = layout.magic {
            let head = Array(bytes.prefix(magic.count))
            if head != magic {
                let shown = head.map { String(format: "%02X", $0) }.joined(separator: " ")
                warnings.append("File header is \(shown), which does not match "
                    + "the expected signature.")
            }
        }

        if let spec = layout.checksum, spec.algorithm != .none {
            if let expected = Checksum.computeBytes(spec: spec, over: bytes),
               expected.count != spec.length {
                warnings.append("Layout mismatch: algorithm "
                    + "\(spec.algorithm.displayName) produces \(expected.count) bytes, "
                    + "but the layout declares \(spec.length). Fix tm2-layout.json "
                    + "before saving — the checksum will not be written.")
            } else if let stored = storedChecksum(spec: spec),
                      let computed = Checksum.compute(spec: spec, over: bytes),
                      stored != computed {
                warnings.append("Checksum mismatch: stored \(stored), computed \(computed).")
            }
        }

        if let last = layout.kitOrigin(kit: layout.kitCount),
           let stride = layout.kitStride,
           last + stride > bytes.count {
            warnings.append("The mapped kit layout runs past the end of the file: "
                + "kit \(layout.kitCount) would end at \(last + stride), "
                + "file is \(bytes.count) bytes.")
        }

        return warnings
    }

    // MARK: - Dostęp do surowych bajtów

    func byte(at offset: Int) -> UInt8? {
        guard offset >= 0 && offset < bytes.count else { return nil }
        return bytes[offset]
    }

    func slice(at offset: Int, length: Int) -> [UInt8]? {
        // Odejmowanie zamiast dodawania: offset i length pochodzą z pliku
        // układu wypełnianego ręcznie, a `offset + length` przy patologicznych
        // wartościach przepełniłoby się i wywaliło program zamiast zwrócić nil.
        guard offset >= 0, length >= 0,
              length <= bytes.count, offset <= bytes.count - length else { return nil }
        return Array(bytes[offset..<(offset + length)])
    }

    mutating func setByte(_ value: UInt8, at offset: Int) throws {
        guard offset >= 0 && offset < bytes.count else {
            throw BackupFileError.offsetOutOfBounds(offset: offset, length: 1, fileSize: bytes.count)
        }
        bytes[offset] = value
    }

    mutating func setSlice(_ value: [UInt8], at offset: Int) throws {
        guard offset >= 0, value.count <= bytes.count,
              offset <= bytes.count - value.count else {
            throw BackupFileError.offsetOutOfBounds(offset: offset,
                                                    length: value.count,
                                                    fileSize: bytes.count)
        }
        for (index, byte) in value.enumerated() {
            bytes[offset + index] = byte
        }
    }

    // MARK: - Odczyt pól

    /// Odczyt wartości pola. `nil`, jeżeli pole nie jest zmapowane albo adres
    /// wypada poza plikiem.
    func value(of field: FieldSpec, kit: Int = 1, trigger: Int = 1) -> FieldValue? {
        guard let offset = layout.absoluteOffset(for: field, kit: kit, trigger: trigger) else {
            return nil
        }
        return decode(field.encoding, at: offset)
    }

    func decode(_ encoding: FieldEncoding, at offset: Int) -> FieldValue? {
        switch encoding {
        case .unsigned:
            guard let raw = byte(at: offset) else { return nil }
            return .number(Int(raw))

        case .biased(let bias, _, _):
            guard let raw = byte(at: offset) else { return nil }
            return .number(Int(raw) - bias)

        case .unsigned16LE:
            guard let raw = slice(at: offset, length: 2) else { return nil }
            return .number(Int(raw[0]) | (Int(raw[1]) << 8))

        case .unsigned16BE:
            guard let raw = slice(at: offset, length: 2) else { return nil }
            return .number((Int(raw[0]) << 8) | Int(raw[1]))

        case .bit(let index):
            guard let raw = byte(at: offset), index >= 0, index < 8 else { return nil }
            return .number((Int(raw) >> index) & 1)

        case .enumeration:
            guard let raw = byte(at: offset) else { return nil }
            return .number(Int(raw))

        case .boolean:
            guard let raw = byte(at: offset) else { return nil }
            return .number(raw == 0 ? 0 : 1)

        case .ascii(let length):
            guard let raw = slice(at: offset, length: length) else { return nil }
            let characters = raw.map { byte -> Character in
                (byte >= 32 && byte < 127) ? Character(UnicodeScalar(byte)) : " "
            }
            // Obcinamy dopełnienie tylko z prawej. Trimming z obu stron
            // zjadałby wiodące spacje, przez co cofnięcie edycji nie
            // przywracałoby dokładnie oryginalnej nazwy.
            var text = String(characters)
            while text.hasSuffix(" ") { text.removeLast() }
            return .text(text)

        case .utf16LE(let length):
            guard let raw = slice(at: offset, length: length), length % 2 == 0 else { return nil }
            var units: [UInt16] = []
            units.reserveCapacity(length / 2)
            var index = 0
            while index + 1 < raw.count {
                units.append(UInt16(raw[index]) | (UInt16(raw[index + 1]) << 8))
                index += 2
            }
            // Tak samo jak przy ASCII: przycinamy dopełnienie tylko z prawej,
            // żeby cofnięcie edycji odtwarzało dokładnie oryginalny napis.
            var text = String(decoding: units, as: UTF16.self)
            while text.hasSuffix(" ") { text.removeLast() }
            return .text(text)
        }
    }

    // MARK: - Zapis pól

    /// Zapisuje wartość pola. Waliduje zakres, zanim ruszy bajty — nie chcemy
    /// wpisać do pliku wartości, której moduł nigdy by nie wystawił.
    mutating func setValue(_ value: FieldValue,
                           for field: FieldSpec,
                           kit: Int = 1,
                           trigger: Int = 1) throws {
        guard let offset = layout.absoluteOffset(for: field, kit: kit, trigger: trigger) else {
            throw BackupFileError.fieldNotMapped(fieldID: field.id)
        }
        try encode(value, encoding: field.encoding, at: offset, fieldID: field.id)
    }

    mutating func encode(_ value: FieldValue,
                         encoding: FieldEncoding,
                         at offset: Int,
                         fieldID: String) throws {
        switch encoding {
        // UWAGA: żadnego UInt8(clamping:). Ciche przycięcie 260 do 255
        // wyglądałoby jak udana zmiana, a zapisałoby coś innego, niż widzi
        // użytkownik — najgorszy możliwy wariant w edytorze plików dla sprzętu.
        // Zakres niemieszczący się w bajcie to błąd w opisie układu i ma
        // zostać zgłoszony, a nie zamaskowany.
        case .unsigned(let min, let max):
            let number = try requireNumber(value, fieldID: fieldID, range: min...max)
            guard let raw = UInt8(exactly: number) else {
                throw BackupFileError.valueOutOfRange(fieldID: fieldID,
                                                      value: number, allowed: 0...255)
            }
            try setByte(raw, at: offset)

        case .biased(let bias, let min, let max):
            let number = try requireNumber(value, fieldID: fieldID, range: min...max)
            guard let raw = UInt8(exactly: number + bias) else {
                throw BackupFileError.valueOutOfRange(fieldID: fieldID,
                                                      value: number + bias,
                                                      allowed: 0...255)
            }
            try setByte(raw, at: offset)

        case .unsigned16LE(let min, let max):
            let number = try requireNumber(value, fieldID: fieldID, range: min...max)
            let word = try requireWord(number, fieldID: fieldID)
            try setSlice([UInt8(word & 0xFF), UInt8(word >> 8)], at: offset)

        case .unsigned16BE(let min, let max):
            let number = try requireNumber(value, fieldID: fieldID, range: min...max)
            let word = try requireWord(number, fieldID: fieldID)
            try setSlice([UInt8(word >> 8), UInt8(word & 0xFF)], at: offset)

        case .bit(let index):
            let number = try requireNumber(value, fieldID: fieldID, range: 0...1)
            guard var raw = byte(at: offset), index >= 0, index < 8 else {
                throw BackupFileError.offsetOutOfBounds(offset: offset, length: 1, fileSize: bytes.count)
            }
            if number == 1 {
                raw |= UInt8(1 << index)
            } else {
                raw &= ~UInt8(1 << index)
            }
            try setByte(raw, at: offset)

        case .enumeration(let values):
            let upper = Swift.min(Swift.max(values.count - 1, 0), 255)
            let number = try requireNumber(value, fieldID: fieldID, range: 0...upper)
            guard let raw = UInt8(exactly: number) else {
                throw BackupFileError.valueOutOfRange(fieldID: fieldID,
                                                      value: number, allowed: 0...255)
            }
            try setByte(raw, at: offset)

        case .boolean:
            let number = try requireNumber(value, fieldID: fieldID, range: 0...1)
            try setByte(UInt8(number), at: offset)

        case .ascii(let length):
            guard let text = value.textValue else {
                throw BackupFileError.valueOutOfRange(fieldID: fieldID, value: 0, allowed: 0...0)
            }
            let ascii = text.unicodeScalars.compactMap { scalar -> UInt8? in
                (scalar.value >= 32 && scalar.value < 127) ? UInt8(scalar.value) : nil
            }
            guard ascii.count <= length else {
                throw BackupFileError.textTooLong(fieldID: fieldID, limit: length)
            }
            var padded = ascii
            while padded.count < length { padded.append(0x20) }   // dopełnienie spacją
            try setSlice(padded, at: offset)

        case .utf16LE(let length):
            guard let text = value.textValue else {
                throw BackupFileError.valueOutOfRange(fieldID: fieldID, value: 0, allowed: 0...0)
            }
            // Długość musi być parzysta -- tak samo jak w decode(). Bez tej
            // straży `length / 2` po prostu obcina resztę, a zapis kończyłby
            // się po cichu bajt krótszy niż zadeklarowane pole: ostatni bajt
            // zostałby nietknięty (nie odziedziczony po staréj wartości, tylko
            // przypadkowy), a pole stałoby się trwale nieczytelne (decode()
            // odmawia dla nieparzystej długości). Błąd w tm2-layout.json ma
            // zostać zgłoszony, nie zamaskowany.
            guard length % 2 == 0 else {
                throw BackupFileError.valueOutOfRange(fieldID: fieldID, value: length, allowed: 0...0)
            }
            let maxCharacters = length / 2
            let units = Array(text.utf16)
            guard units.count <= maxCharacters else {
                throw BackupFileError.textTooLong(fieldID: fieldID, limit: maxCharacters)
            }
            var padded = units
            while padded.count < maxCharacters { padded.append(0x0020) }   // dopełnienie spacją
            var raw: [UInt8] = []
            raw.reserveCapacity(length)
            for unit in padded {
                raw.append(UInt8(unit & 0xFF))
                raw.append(UInt8(unit >> 8))
            }
            try setSlice(raw, at: offset)
        }
    }

    /// Sprawdza, że liczba mieści się w dwóch bajtach. Tak samo jak przy
    /// `UInt8(exactly:)` — żadnego cichego maskowania `& 0xFFFF`.
    private func requireWord(_ number: Int, fieldID: String) throws -> UInt16 {
        guard let word = UInt16(exactly: number) else {
            throw BackupFileError.valueOutOfRange(fieldID: fieldID,
                                                  value: number, allowed: 0...65535)
        }
        return word
    }

    private func requireNumber(_ value: FieldValue,
                               fieldID: String,
                               range: ClosedRange<Int>) throws -> Int {
        guard let number = value.numberValue else {
            throw BackupFileError.valueOutOfRange(fieldID: fieldID, value: 0, allowed: range)
        }
        guard range.contains(number) else {
            throw BackupFileError.valueOutOfRange(fieldID: fieldID, value: number, allowed: range)
        }
        return number
    }

    // MARK: - Suma kontrolna

    func storedChecksum(spec: ChecksumSpec) -> String? {
        guard let raw = slice(at: spec.offset, length: spec.length) else { return nil }
        return raw.map { String(format: "%02X", $0) }.joined()
    }

    /// Przelicza sumę kontrolną i wpisuje ją do pliku. Wywoływane tuż przed
    /// zapisem — nie po każdej zmianie pojedynczego pola.
    mutating func refreshChecksum() {
        guard let spec = layout.checksum, spec.algorithm != .none else { return }
        guard let value = Checksum.computeBytes(spec: spec, over: bytes) else { return }
        // Długość wyniku zależy od algorytmu, a nie od tego, co ktoś wpisał
        // w tm2-layout.json. Rozjazd (np. md5 zadeklarowane jako 2 bajty)
        // nadpisałby 14 bajtów za sumą — cicho, bo błąd połyka `try?`.
        // Bez assertionFailure: rozjazd bierze się z danych (ręcznie pisany
        // tm2-layout.json), a nie z błędu programisty, a przerwanie procesu
        // w buildzie debug zabiłoby aplikację przy zwykłym „Save As…".
        // Ostrzeżenie o tym wystawia już validate().
        guard value.count == spec.length else { return }
        try? setSlice(value, at: spec.offset)
    }

    // MARK: - Różnice

    /// Offsety, na których bieżąca zawartość różni się od wczytanej,
    /// z pominięciem zakresów uznanych za szum.
    func modifiedOffsets() -> [Int] {
        var result: [Int] = []
        for index in 0..<min(bytes.count, originalBytes.count)
        where bytes[index] != originalBytes[index] && !layout.isNoise(offset: index) {
            result.append(index)
        }
        return result
    }

    /// Porównanie z innym plikiem. Używane, żeby zobaczyć, co się zmieniło
    /// między dwoma zrzutami z modułu.
    static func compare(_ lhs: BackupFile, _ rhs: BackupFile) -> [Int] {
        var result: [Int] = []
        let shared = min(lhs.bytes.count, rhs.bytes.count)
        for index in 0..<shared
        where lhs.bytes[index] != rhs.bytes[index] && !lhs.layout.isNoise(offset: index) {
            result.append(index)
        }
        return result
    }

    // MARK: - Zapis na dysk

    /// Zapisuje do NOWEGO pliku. Celowo nie ma metody zapisującej w miejsce
    /// oryginału — kopia na karcie ma zostać nietknięta.
    func write(to url: URL) throws {
        var copy = self
        copy.refreshChecksum()
        try Data(copy.bytes).write(to: url, options: .atomic)
    }
}
