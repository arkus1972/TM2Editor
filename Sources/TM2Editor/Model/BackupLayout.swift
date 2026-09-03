import Foundation

/// Opis układu pliku BACKUP.
///
/// Ten typ jest sercem całego projektu i jednocześnie jego największą
/// niewiadomą. Dopóki seria mapowania różnicowego nie jest zrobiona, wszystkie
/// offsety są `nil` — i tak ma być. Aplikacja ma działać w stanie "jeszcze nie
/// wiem, gdzie co leży": pokazuje plik, pozwala go obejrzeć w inspektorze
/// heks, ale edycję udostępnia tylko dla pól, które faktycznie zostały
/// zmapowane.
///
/// Zasada projektowa: układ jest DANYMI, nie kodem. Kiedy z analizatora
/// `tools/tm2diff.py` wyjdą offsety, wypełniamy je tutaj (albo wczytujemy z
/// pliku JSON) i nie ruszamy niczego innego. Nie chcemy sytuacji, w której
/// każdy nowy odkryty parametr wymaga przepisywania widoków.
struct BackupLayout: Codable, Equatable {

    /// Wersja opisu układu. Rośnie, kiedy zmieniamy znaczenie offsetów, żeby
    /// dało się odróżnić plik zapisany starym rozpoznaniem od nowego.
    var layoutVersion: Int = 1

    /// Wersja systemu modułu, na której ten układ został rozpoznany.
    /// Instrukcja wymienia 1.02 i 1.03 — dopóki nie sprawdzimy, czy format
    /// jest ten sam, trzymamy to jawnie przy układzie.
    var moduleSystemVersion: String?

    /// Oczekiwany rozmiar pliku w bajtach. `nil` = jeszcze nie wiemy.
    /// Kiedy już będzie znany, służy jako pierwszy, najtańszy test sanity:
    /// plik innego rozmiaru to plik innego formatu.
    var expectedFileSize: Int?

    /// Bajty rozpoznawcze na początku pliku, jeśli takie są.
    var magic: [UInt8]?

    /// Offset pierwszego bloku kitu (kit 1) od początku pliku.
    var kitBlockOrigin: Int?

    /// Odległość między początkami kolejnych bloków kitów.
    /// To jest wynik kroku 5 z protokołu mapowania.
    var kitStride: Int?

    /// Liczba kitów. Dla TM-2 to fakt sprzętowy, nie niewiadoma.
    var kitCount: Int = 99

    /// Offset pierwszego bloku triggera WEWNĄTRZ bloku kitu.
    var triggerBlockOrigin: Int?

    /// Odległość między blokami triggerów wewnątrz kitu.
    var triggerStride: Int?

    /// Liczba triggerów w kicie. TM-2 ma 2 wejścia TRIG IN, każde
    /// dual-trigger, czyli do 4 triggerów.
    var triggerCount: Int = 4

    /// Opis sumy kontrolnej, jeśli plik ją nosi.
    var checksum: ChecksumSpec?

    /// Offsety uznane za szum (znacznik czasu, licznik zapisów). Wychodzą z
    /// porównania pliku 0 z plikiem 1. Przy porównywaniu dwóch backupów
    /// aplikacja je pomija, żeby nie pokazywać fałszywych różnic.
    var noiseRanges: [ByteRange] = []

    /// Pola przypisane do całego modułu (ustawienia globalne).
    var globalFields: [FieldSpec] = []

    /// Pola przypisane do kitu jako całości (np. nazwa kitu).
    /// Offsety liczone WZGLĘDEM początku bloku kitu.
    var kitFields: [FieldSpec] = []

    /// Pola przypisane do pojedynczego triggera.
    /// Offsety liczone WZGLĘDEM początku bloku triggera.
    var triggerFields: [FieldSpec] = []

    // MARK: - Stan rozpoznania

    /// Czy da się w ogóle adresować kity. Bez tego edytor pracuje wyłącznie
    /// w trybie podglądu.
    var canAddressKits: Bool {
        kitBlockOrigin != nil && kitStride != nil
    }

    /// Czy da się adresować triggery wewnątrz kitu.
    var canAddressTriggers: Bool {
        canAddressKits && triggerBlockOrigin != nil && triggerStride != nil
    }

    /// Ile pól ma już znany offset — do pokazania postępu prac.
    var mappedFieldCount: Int {
        (globalFields + kitFields + triggerFields).filter { $0.offset != nil }.count
    }

    var totalFieldCount: Int {
        globalFields.count + kitFields.count + triggerFields.count
    }

    // MARK: - Wyliczanie adresów bezwzględnych

    /// Adres początku bloku danego kitu. Kity numerujemy od 1, tak jak moduł.
    func kitOrigin(kit: Int) -> Int? {
        guard let origin = kitBlockOrigin, let stride = kitStride else { return nil }
        guard kit >= 1 && kit <= kitCount else { return nil }
        return origin + (kit - 1) * stride
    }

    /// Adres początku bloku danego triggera w danym kicie.
    /// Triggery numerujemy od 1.
    func triggerOrigin(kit: Int, trigger: Int) -> Int? {
        guard let kitStart = kitOrigin(kit: kit),
              let triggerStart = triggerBlockOrigin,
              let stride = triggerStride else { return nil }
        guard trigger >= 1 && trigger <= triggerCount else { return nil }
        return kitStart + triggerStart + (trigger - 1) * stride
    }

    /// Bezwzględny adres konkretnego pola.
    func absoluteOffset(for field: FieldSpec, kit: Int, trigger: Int) -> Int? {
        guard let relative = field.offset else { return nil }
        switch field.scope {
        case .global:
            return relative
        case .kit:
            guard let base = kitOrigin(kit: kit) else { return nil }
            return base + relative
        case .trigger:
            guard let base = triggerOrigin(kit: kit, trigger: trigger) else { return nil }
            return base + relative
        }
    }

    /// Czy offset wpada w zakres uznany za szum.
    func isNoise(offset: Int) -> Bool {
        noiseRanges.contains { $0.contains(offset) }
    }
}

/// Zakres bajtów, oba końce włącznie.
struct ByteRange: Codable, Equatable, Hashable {
    var start: Int
    var end: Int

    func contains(_ offset: Int) -> Bool {
        offset >= start && offset <= end
    }

    var length: Int { end - start + 1 }
}

/// Opis sumy kontrolnej pliku.
struct ChecksumSpec: Codable, Equatable {
    /// Gdzie w pliku leży suma.
    var offset: Int
    /// Ile zajmuje bajtów.
    var length: Int
    /// Jak jest liczona.
    var algorithm: ChecksumAlgorithm
    /// Zakres bajtów objętych sumą. `nil` = cały plik poza samą sumą.
    var coverage: ByteRange?
}

enum ChecksumAlgorithm: String, Codable, CaseIterable {
    /// Plik nie nosi sumy — najlepszy możliwy wynik.
    case none
    /// Suma bajtów obcięta do 8 bitów.
    case sum8
    /// Suma bajtów, 32 bity, little-endian.
    case sum32LE
    /// XOR wszystkich bajtów.
    case xor8
    /// CRC-16/MODBUS — częsty u Rolanda w plikach kart.
    case crc16Modbus
    /// CRC-32 (wielomian jak w zip).
    case crc32
    /// MD5 — tak działają pliki TD0 obsługiwane przez PulsoKit.
    case md5

    var displayName: String {
        switch self {
        case .none: return "None"
        case .sum8: return "Sum (8-bit)"
        case .sum32LE: return "Sum (32-bit LE)"
        case .xor8: return "XOR (8-bit)"
        case .crc16Modbus: return "CRC-16/MODBUS"
        case .crc32: return "CRC-32"
        case .md5: return "MD5"
        }
    }
}

// MARK: - Profil startowy, jeszcze niezmapowany

extension BackupLayout {

    /// Układ, z którym aplikacja startuje, zanim ktokolwiek zrobi serię
    /// mapowania. Wszystkie offsety puste, ale lista pól już opisana — dzięki
    /// temu widać, czego szukamy, i można odhaczać postęp.
    ///
    /// Nazwy pól są po angielsku, bo to nazwy z interfejsu modułu i z
    /// instrukcji Rolanda. Interfejs aplikacji też jest po angielsku.
    static var unmappedTM2: BackupLayout {
        var layout = BackupLayout()
        layout.moduleSystemVersion = nil
        layout.kitCount = 99
        layout.triggerCount = 4

        layout.kitFields = [
            FieldSpec(
                id: "kit.name",
                label: "Kit Name",
                scope: .kit,
                group: .kit,
                offset: nil,
                encoding: .ascii(length: 8),
                note: "Kotwica z kroku 2 protokołu — ustaw na AAAAAAAA."
            ),
            FieldSpec(
                id: "kit.volume",
                label: "Kit Volume",
                scope: .kit,
                group: .kit,
                offset: nil,
                encoding: .unsigned(min: 0, max: 100),
                note: nil
            ),
            FieldSpec(
                id: "kit.tempo",
                label: "Kit Tempo",
                scope: .kit,
                group: .kit,
                offset: nil,
                // Zakres 20…260 nie mieści się w jednym bajcie, więc już na
                // starcie zakładamy dwa. Kolejność bajtów do potwierdzenia
                // przy mapowaniu — Roland historycznie lubi big-endian.
                encoding: .unsigned16LE(min: 20, max: 260),
                note: "Dwa bajty; kolejność (LE/BE) do potwierdzenia przy mapowaniu."
            )
        ]

        layout.triggerFields = [
            FieldSpec(
                id: "trig.instrument",
                label: "Instrument",
                scope: .trigger,
                group: .sound,
                offset: nil,
                // 162 brzmienia fabryczne zmieszczą się w bajcie, ale do 90 300
                // brzmień użytkownika już nie — więc dwa bajty od początku.
                encoding: .unsigned16LE(min: 0, max: 65535),
                note: "162 brzmienia fabryczne, do 90 300 użytkownika — samo"
                    + " 90 300 nie mieści się w dwóch bajtach, więc pewnie jest"
                    + " osobny bajt banku. Do ustalenia przy mapowaniu."
            ),
            FieldSpec(
                id: "trig.level",
                label: "Level",
                scope: .trigger,
                group: .sound,
                offset: nil,
                encoding: .unsigned(min: 0, max: 100),
                note: "To jest parametr z kroków 3, 4 i 5 protokołu."
            ),
            FieldSpec(
                id: "trig.pan",
                label: "Pan",
                scope: .trigger,
                group: .sound,
                offset: nil,
                encoding: .biased(bias: 64, min: -32, max: 32),
                note: "Zakres L32..CTR..R32 — spodziewamy się przesunięcia."
            ),
            FieldSpec(
                id: "trig.pitch",
                label: "Pitch",
                scope: .trigger,
                group: .sound,
                offset: nil,
                encoding: .biased(bias: 64, min: -48, max: 48),
                note: nil
            ),
            FieldSpec(
                id: "trig.decay",
                label: "Decay",
                scope: .trigger,
                group: .sound,
                offset: nil,
                encoding: .biased(bias: 64, min: -31, max: 31),
                note: nil
            ),
            FieldSpec(
                id: "trig.type",
                label: "Trigger Type",
                scope: .trigger,
                group: .triggerInput,
                offset: nil,
                encoding: .enumeration(values: [
                    "KD-7", "KD-9", "PD-8", "PDX-8", "PDX-100", "RT-10K",
                    "RT-10S", "RT-10T", "RT-30K", "RT-30H", "RT-30HR", "Other"
                ]),
                note: "Typy RT-30 doszły w systemie 1.02 — lista może się"
                    + " różnić między wersjami systemu."
            ),
            FieldSpec(
                id: "trig.sensitivity",
                label: "Sensitivity",
                scope: .trigger,
                group: .triggerInput,
                offset: nil,
                encoding: .unsigned(min: 1, max: 16),
                note: nil
            ),
            FieldSpec(
                id: "trig.threshold",
                label: "Threshold",
                scope: .trigger,
                group: .triggerInput,
                offset: nil,
                encoding: .unsigned(min: 0, max: 15),
                note: nil
            ),
            FieldSpec(
                id: "trig.retrigCancel",
                label: "Retrig Cancel",
                scope: .trigger,
                group: .triggerInput,
                offset: nil,
                encoding: .unsigned(min: 1, max: 16),
                note: nil
            ),
            FieldSpec(
                id: "trig.maskTime",
                label: "Mask Time",
                scope: .trigger,
                group: .triggerInput,
                offset: nil,
                encoding: .unsigned(min: 0, max: 64),
                note: "W milisekundach; skala do potwierdzenia."
            )
        ]

        layout.globalFields = [
            FieldSpec(
                id: "sys.midiChannel",
                label: "MIDI Channel",
                scope: .global,
                group: .system,
                offset: nil,
                encoding: .unsigned(min: 1, max: 16),
                note: "Musi się zgadzać, żeby Program Change wybierał kity."
            ),
            FieldSpec(
                id: "sys.programChangeRx",
                label: "Program Change Rx",
                scope: .global,
                group: .system,
                offset: nil,
                encoding: .boolean,
                note: "Jedyny udokumentowany sposób sterowania TM-2 po MIDI."
            ),
            FieldSpec(
                id: "sys.masterVolume",
                label: "Master Volume",
                scope: .global,
                group: .system,
                offset: nil,
                encoding: .unsigned(min: 0, max: 100),
                note: nil
            )
        ]

        return layout
    }

    /// Układ po pierwszej rundzie mapowania różnicowego na prawdziwym sprzęcie
    /// Arka, 2026-09-02 — szczegóły i dowody w projekcie „ROLAND TM-2 EDYTOR”,
    /// `03-stan-prac.md`, wpisy (c)–(g), i w `DOKUMENTACJA/02-format-pliku-backup.md`.
    ///
    /// Startuje z `unmappedTM2` (żeby nie duplikować listy pól i etykiet) i
    /// wypełnia wyłącznie to, co jest POTWIERDZONE testami na module — żadnej
    /// wartości tu nie ma, która by nie wyszła wprost z `tm2diff.py diff` na
    /// parze prawdziwych plików BACKUP. Reszta pól zostaje `nil`, tak jak
    /// w `unmappedTM2` — to nadal jest lista rzeczy do zrobienia, tylko krótsza.
    ///
    /// UWAGA: `unmappedTM2` samo w sobie zostaje NIETKNIĘTE — testy
    /// (`BackupFileTests`, `KitEditorTests`) zakładają jego dotychczasowe,
    /// puste wartości domyślne. Ten układ jest osobnym, nowym punktem startu.
    static var mapped2026_09_02: BackupLayout {
        var layout = unmappedTM2
        layout.layoutVersion = 2
        layout.moduleSystemVersion = nil   // niesprawdzone, na jakiej wersji systemu jest moduł Arka

        // Rozmiar i nagłówek — z pierwszego prawdziwego pliku BACKUP (124 748 B).
        // Zakładamy, że rozmiar jest stały dla tej wersji formatu (żadnych pól
        // o zmiennej długości nie znaleziono) — jeśli kiedyś pojawi się plik
        // o innym rozmiarze, `validate()` to zgłosi zamiast cicho się mylić.
        layout.expectedFileSize = 124_748
        layout.magic = Array("TM-2".utf8)   // + 4 bajty zera po (niesprawdzane osobno)

        // Blok kitów — origin i stride potwierdzone dwukrotnie: na polu nazwy
        // (100 kolejnych nazw kitów) i na prawdziwym parametrze (poziom,
        // kity 1 i 2).
        layout.kitBlockOrigin = 0x40     // 64
        layout.kitStride = 234           // 0xEA
        layout.kitCount = 99

        // Rekord triggera — origin i stride potwierdzone na polach Instrument
        // i Level, na dwóch triggerach.
        layout.triggerBlockOrigin = 0x7E   // 126 -- początek rekordu = pole Instrument
        layout.triggerStride = 84          // 0x54

        // UWAGA BEZPIECZEŃSTWA — dlaczego triggerCount = 2, a nie 4:
        // fakty sprzętowe (2 × TRIG IN, każde dual-trigger) sugerują do 4
        // triggerów na kit, ale przy origin=0x7E i stride=84 trzeci rekord,
        // liczony tym samym wzorem, wypadłby pod 0x7E + 2×84 = 0x126 (294) —
        // czyli 234 (kitStride) + 60 (0x3C, offset nazwy kitu) w głąb
        // NASTĘPNEGO kitu, dokładnie na jego polu nazwy. Pole "Instrument"
        // tego rzekomego trzeciego triggera nałożyłoby się więc na nazwę
        // kitu sąsiada. Zmierzone bezpośrednio, nie zgadnięte — patrz
        // `testHypotheticalThirdTriggerWouldOverrunNextKitName` w BackupFileTests.
        // Najpewniejsza hipoteza: head/rim tego samego wejścia TRIG IN siedzi
        // jako pole WEWNĄTRZ jednego rekordu (zdjęcie panelu: RIM = SHIFT +
        // ten sam przycisk TRIG IN, nie osobny przycisk), a nie jako osobny
        // rekord. Dopóki różnicowo nie znajdziemy inaczej, triggerCount ZOSTAJE
        // na 2 — podniesienie tej liczby bez ponownego zmierzenia stride'u
        // pisałoby w dane cudzego kitu.
        layout.triggerCount = 2

        // Suma kontrolna — potwierdzona bezpośrednio: ostatnie 16 B pliku to
        // MD5 wszystkich poprzedzających bajtów (coverage: nil = domyślnie
        // "cały plik poza samą sumą", co jest dokładnie tym, co zmierzono).
        layout.checksum = ChecksumSpec(
            offset: 124_748 - 16,
            length: 16,
            algorithm: .md5,
            coverage: nil
        )

        for index in layout.kitFields.indices {
            guard layout.kitFields[index].id == "kit.name" else { continue }
            layout.kitFields[index].offset = 0x3C   // 60, względem początku kitu
            // Nazwa jest UTF-16LE, nie ASCII — bez tego przeszukiwanie stringów
            // widziało tylko nagłówek pliku, bo każdy znak jest przeplatany
            // zerowym bajtem. 11 znaków × 2 B = 22 B.
            layout.kitFields[index].encoding = .utf16LE(length: 22)
            layout.kitFields[index].note = "Znalezione bezpośrednio przeszukiwaniem UTF-16LE"
                + " (100 nazw kitów, stride 234 B) — krok „ustaw na AAAAAAAA” z"
                + " protokołu okazał się niepotrzebny."
        }

        for index in layout.triggerFields.indices {
            switch layout.triggerFields[index].id {
            case "trig.instrument":
                layout.triggerFields[index].offset = 0   // początek rekordu triggera
                layout.triggerFields[index].note = "Potwierdzone: zmiana brzmienia na padzie"
                    + " rusza dokładnie ten bajt (+1 na kolejną pozycję na liście)."
                    + " Moduł Arka ma maksymalnie 162 brzmienia (fabryczne), więc"
                    + " starszy bajt pola nigdy nie był wymuszony powyżej zera —"
                    + " szerokość 16-bit jest strukturalnie prawdopodobna"
                    + " (spójna z innymi polami wielobajtowymi w pliku), ale"
                    + " nie zmierzona bezpośrednio na wartości > 255."
            case "trig.level":
                layout.triggerFields[index].offset = 4   // względem początku rekordu triggera
                layout.triggerFields[index].note = "Potwierdzone na dwóch triggerach, dwóch"
                    + " kitach, obu skrajnościach: 0-100 wprost, bez odwrócenia."
            default:
                break   // trig.pan, trig.pitch, trig.type itd. — jeszcze niezmapowane
            }
        }

        return layout
    }
}
