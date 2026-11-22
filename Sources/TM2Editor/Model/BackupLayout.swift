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

    /// Offset bajtu, w którym moduł zapisuje, który kit był wybrany
    /// w chwili BACKUP SAVE. Numeracja w pliku jest od zera.
    ///
    /// To nie jest pole do edycji, więc nie ma go na liście `globalFields` —
    /// służy wyłącznie do tego, żeby po otwarciu pliku stanąć na tym kicie,
    /// nad którym użytkownik ostatnio pracował na sprzęcie.
    var currentKitPointerOffset: Int?

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

        // USTAWIENIA WEJŚĆ TRIGGEROWYCH — globalne, nie kitowe.
        //
        // Strefa 0x40…0x7B to cztery rekordy po 15 B, po jednym na trigger
        // (1 head, 1 rim, 2 head, 2 rim). Że są globalne, wyszło dwojako:
        // nie jadą razem z kitem przy przestawianiu kitów, a zmiana zrobiona
        // na kicie 40 wylądowała w rekordzie pierwszym. To jest spójne z tym,
        // jak działa sprzęt: czułość zależy od pada wpiętego w gniazdo,
        // a nie od tego, jakie brzmienie akurat gra.
        //
        // Kolejność pól w rekordzie zgadza się z kolejnością w menu modułu.
        // Para plików `trigger_max.bin` / `trigger_min.bin` (2026-11-21):
        // wszystkie parametry wejścia TRIG IN 1 head wykręcone na maksimum,
        // a potem na minimum. Zmieniły się WYŁĄCZNIE bajty +0x01…+0x0A
        // pierwszego rekordu — pozostałe trzy rekordy nie drgnęły, co
        // potwierdza i granice rekordu, i to, że ustawienia są per trigger.
        //
        // Mapa rekordu po TRZECH seriach pomiarów. Trzecia (plik
        // `trzy-drobiazgi.bin`: zmieniony jeden parametr naraz) obaliła dwa
        // przypisania z serii drugiej — i to jest tu najważniejsza lekcja.
        //
        // Pułapka była taka: przy maksimum wyświetlacz pokazywał
        // „Retrig Cancel 16" i „Rim Gain 8.0", a w pliku stały obok siebie
        // bajty 40 i 16. Przypisanie 16 do Rim Gain (skala ÷2) i 40 do Retrig
        // Cancel wyglądało spójnie i było BŁĘDNE. Test, w którym zmienił się
        // JEDEN parametr, pokazał co innego: ustawienie Retrig Cancel na 8
        // zmieniło bajt +0x06 z 16 na 8, czyli to Retrig Cancel, skala 1:1,
        // zakres 1…16 — dokładnie taki, jaki ten parametr ma u Rolanda.
        //
        //   +0x00  Input (HEAD&RIM / PADx2)   nietknięte we wszystkich testach
        //   +0x01  Type            raw 1…31   <- NIE do edycji, patrz niżej
        //   +0x02  Sensitivity     raw 1…32   1:1
        //   +0x03  Threshold       raw 0…31   1:1 (wyświetlacz 31 = raw 31)
        //   +0x04  Curve           raw 0…6    raw 6 = LOUD2, ostatnia na liście
        //   +0x05  ?               zmienia się RAZEM Z TYPE, nie ustawiany ręcznie
        //   +0x06  Retrig Cancel   raw 1…16   1:1, dwa zgodne punkty (16 i 8)
        //   +0x07  ?               zmienia się RAZEM Z TYPE, nie ustawiany ręcznie
        //   +0x08  XTLK Cancel     raw 20…80  1:1, w procentach (80% i 40%)
        //   +0x09  +0x0A           raw 0…80   Rim Gain i H/R Adjust,
        //                                     kolejność nierozstrzygnięta
        //   +0x0B  ?               w bazie 2, we wszystkich testach 0
        //
        // Rim Gain i H/R Adjust zostają NIEZMAPOWANE. Przy maksimum oba
        // pokazywały wartości dające raw 80 (8.0 przy dzielniku 10 oraz 80
        // wprost), więc z samych skrajności nie da się ich rozróżnić —
        // a zgadywanie przy tym rekordzie zdążyło się już raz zemścić.
        //
        // `Type` zostaje poza edycją: instrukcja mówi, a Arek potwierdził
        // z praktyki, że zmiana typu pada przestawia wartości pozostałych
        // parametrów. Widać to zresztą wprost w pliku — bajty +0x05 i +0x07
        // ruszają się wyłącznie razem z Type i nikt ich ręcznie nie ustawia.
        // Edytor pliku nie zna tablicy wartości domyślnych dla każdego typu,
        // więc zapisanie samego `Type` zostawiłoby komplet parametrów od
        // poprzedniego pada.
        // Nazwa backupu — ta, którą moduł pokazuje na liście przy BACKUP LOAD.
        //
        // Wyszła z oglądania nagłówka, nie z pomiaru różnicowego. Po magicznym
        // „TM-2" stoi znacznik „BK", a od 0x0A idzie osiem znaków ASCII
        // dopełnionych spacjami. Potwierdzenie przyszło z dwóch stron: bajt
        // 0x0A był jednym z dwóch nierozpoznanych w całym pliku (0x42 „B"
        // w jednym backupie, 0x43 „C" w innym — jedno naciśnięcie [+] przy
        // zmianie nazwy), a Arek potwierdził, że nazwę backupu zmieniał.
        //
        // Dopełnienie spacją zgadza się z tym, jak moduł trzyma krótkie nazwy
        // kitów (sprawdzone: „Cowbells   " ma 0x20 na końcu, nie zera), więc
        // nasz zapis pól ASCII robi dokładnie to samo co sprzęt.
        //
        // DŁUGOŚĆ 8 JEST HIPOTEZĄ. Po ósmym znaku stoją dwa bajty 0x20,
        // a potem zera — czyli pole może być dłuższe, a te spacje to już
        // dopełnienie czegoś innego. Dlatego trzymamy ostrożniejszą wartość:
        // za krótkie pole odmówi dłuższej nazwy (błąd widoczny, odwracalny),
        // za długie wpisałoby znaki w sąsiednie, nieznane bajty nagłówka.
        layout.globalFields.append(
            FieldSpec(
                id: "file.backupName",
                label: "Backup Name",
                scope: .global,
                group: .system,
                offset: 0x0A,
                encoding: .ascii(length: 8),
                note: "Nazwa, pod którą moduł pokazuje ten backup na liście"
                    + " BACKUP LOAD. Osiem znaków ASCII, dopełnianych spacjami."
                    + " Długość przyjęta ostrożnie — patrz komentarz w kodzie."
            )
        )

        // Wskaźnik bieżącego kitu. Zmierzony 2026-09-04: w teście zrobionym
        // na kicie 40 ten bajt pokazał 0x27, czyli 39 — numer kitu liczony
        // od zera. Wcześniejsze próbki (0 i 1) nie pozwalały tego odróżnić
        // od flagi albo bitmapy.
        layout.currentKitPointerOffset = 0x36

        // Typ efektu kitu siedzi pod +0x18 bloku kitu. Zmierzone serią
        // max2/min2: REVERB to 19, THRU to 0, a przy THRU cała reszta strefy
        // efektu zeruje się co do bajtu. Czyli parametry efektu nie są
        // stałymi polami — ich znaczenie zależy od typu, dokładnie tak jak
        // przy typie pada.
        //
        // Dlatego tego pola tu NIE MA. Zapisanie samego typu zostawiłoby
        // w pliku komplet parametrów poprzedniego efektu, a edytor nie zna
        // tablic wartości domyślnych. Adres jest w `pola.json` i widać go
        // w inspektorze heks.

        let trigUstawieniaOd = 0x40
        let trigUstawieniaKrok = 15
        let nazwyTrigerow = ["TRIG IN 1 head", "TRIG IN 1 rim",
                             "TRIG IN 2 head", "TRIG IN 2 rim"]

        /// Pola rekordu ustawień wejścia: offset w rekordzie, etykieta,
        /// identyfikator, etykietę, zakres, sposób wyświetlania i notatkę.
        /// Pola rekordu ustawień wejścia: offset w rekordzie, identyfikator,
        /// etykietę, zakres, sposób wyświetlania i notatkę.
        let polaWejscia: [(Int, String, String, Int, Int, FieldDisplay?, String)] = [
            (0x02, "sensitivity", "Sensitivity", 1, 32, nil,
             "Skala 1:1 — wyświetlacz 32 przy surowym 32. Minimum"
                + " potwierdzone pomiarem `trigger_min.bin`: 1."),
            (0x03, "threshold", "Threshold", 0, 31, nil,
             "Skala 1:1 — wyświetlacz 31 przy surowym 31. Zakres 0…31"
                + " z pary max/min."),
            (0x04, "curve", "Curve", 0, 6, nil,
             "Siedem krzywych, raw 0…6. Zmierzone: raw 6 to LOUD2, czyli"
                + " ostatnia pozycja listy. Stara instrukcja wymienia tylko"
                + " pięć krzywych (LINEAR, LOG1, LOG2, LOUD1, LOUD2) —"
                + " firmware ma ich więcej, a nazw dwóch środkowych nie"
                + " znamy. Dlatego pole jest liczbą, a nie listą wyboru:"
                + " lista z dziurami kłamałaby bardziej niż goły numer."),
            (0x06, "retrigCancel", "Retrig Cancel", 1, 16, nil,
             "Skala 1:1, dwa zgodne punkty: wyświetlacz 16 przy surowym 16"
                + " i wyświetlacz 8 przy surowym 8. Zakres 1…16 — typowy dla"
                + " tego parametru u Rolanda. KOREKTA: wcześniej pole było"
                + " przypisane do +0x05 i uznane za nieliniowe; to był błąd"
                + " wzięty z serii, w której zmieniało się wszystko naraz."),
            (0x08, "xtlkCancel", "XTLK Cancel", 20, 80, nil,
             "Tłumienie przesłuchu, w procentach. Skala 1:1, dwa zgodne"
                + " punkty: 80% przy surowym 80 i 40% przy surowym 40."
                + " Minimum surowe 20. KOREKTA: wcześniej ten bajt był"
                + " przypisany do H/R Adjust — obaliło to ustawienie samego"
                + " XTLK Cancel, które zmieniło dokładnie ten bajt."),
        ]

        for (numer, nazwa) in nazwyTrigerow.enumerated() {
            let baza = trigUstawieniaOd + numer * trigUstawieniaKrok
            // Nazwy `dolny`/`gorny`, a nie `min`/`max` — te drugie zasłoniłyby
            // globalne funkcje `min`/`max` Swifta w całym ciele pętli.
            for (wRekordzie, nazwaPola, etykieta, dolny, gorny, pokazJako, notatka) in polaWejscia {
                layout.globalFields.append(
                    FieldSpec(
                        id: "trigset.\(numer + 1).\(nazwaPola)",
                        label: "\(etykieta) — \(nazwa)",
                        scope: .global,
                        group: .triggerInput,
                        offset: baza + wRekordzie,
                        encoding: .unsigned(min: dolny, max: gorny),
                        note: notatka
                            + " Ustawienie globalne modułu, nie kitu: zmiana"
                            + " zrobiona przy wybranym kicie 40 trafiła"
                            + " w ten sam bajt.",
                        display: pokazJako
                    )
                )
            }
        }

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
        // UKŁAD PRZEBUDOWANY 2026-11-21 — patrz dziennik, wpis (s).
        //
        // Wcześniej przyjmowaliśmy, że blok kitu zaczyna się pod 0x40, a nazwa
        // leży w nim pod +0x3C. Adresy wychodziły poprawne (0x40 + 0x3C = 0x7C),
        // ale granice bloku były przesunięte: te 60 bajtów przed nazwą NIE
        // należy do kitu. Dowód z dwóch stron:
        //   1. Przy przestawianiu kitów miejscami na module ta strefa NIE
        //      jechała razem z kitem (nazwa i rekordy triggerów jechały).
        //   2. Zmiana Sensitivity zrobiona na kicie 40 wylądowała właśnie tam,
        //      pod 0x42 — czyli to ustawienie globalne modułu, nie kitu.
        //
        // Blok kitu zaczyna się więc od nazwy, pod 0x7C, i domyka się co do
        // bajtu: 66 B (nazwa + ustawienia kitu) + 4 × 42 B = 234 = krok kitu.
        layout.kitBlockOrigin = 0x7C     // 124 -- początek bloku kitu = pole nazwy
        layout.kitStride = 234           // 0xEA
        layout.kitCount = 99

        // CZTERY sloty brzmień na kit, po 42 B, jeden za drugim.
        //
        // To zastępuje poprzedni model (2 rekordy po 84 B). Okazało się, że
        // rekord 84-bajtowy to po prostu DWA sloty po 42: head i rim tego
        // samego gniazda. Potwierdzone odczytem pliku przy tym założeniu —
        // fabryczny kit 1 pokazuje wtedy we wszystkich czterech slotach
        // poziom 90, pitch 0 i pan dokładnie na środku, a w kicie 40 każdy
        // zmierzony dotąd parametr siedzi tam, gdzie powinien.
        //
        // Kolejność slotów: 1 = TRIG IN 1 head, 2 = TRIG IN 1 rim,
        //                   3 = TRIG IN 2 head, 4 = TRIG IN 2 rim.
        //
        // Dawna obawa, która kazała trzymać triggerCount = 2, jest tym samym
        // rozwiązana: cztery sloty mieszczą się w kicie bez wchodzenia
        // w sąsiada, bo mają po 42 B, a nie po 84.
        //   0x42 + 4 × 42 = 0xEA = 234 = dokładnie krok kitu.
        layout.triggerBlockOrigin = 0x42   // 66 -- względem początku bloku kitu
        layout.triggerStride = 42          // 0x2A
        layout.triggerCount = 4

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
            // Nazwa leży teraz na SAMYM POCZĄTKU bloku kitu, bo blok zaczyna
            // się właśnie od niej (0x7C). Wcześniej było tu 0x3C względem
            // błędnie przyjętego początku pod 0x40 — adres bezwzględny wychodził
            // ten sam, zmieniła się tylko granica bloku.
            layout.kitFields[index].offset = 0
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

            case "trig.pitch":
                // UWAGA: nadpisujemy TAKŻE kodowanie. W `unmappedTM2` pitch był
                // zgadnięty jako bajt z przesunięciem 64 i zakresem ±48 — pomiar
                // pokazał co innego: dwa bajty ze znakiem, zakres ±120, 1:1
                // z wyświetlaczem. Zgadywanka z pustego layoutu zostaje tam
                // nietknięta (zależą od niej testy), ale tu musi ustąpić faktom.
                layout.triggerFields[index].offset = 6
                layout.triggerFields[index].encoding = .signed16LE(min: -120, max: 120)
                layout.triggerFields[index].note = "Zmierzone 2026-09-04 na obu"
                    + " skrajnościach: +120 to bajty 78 00, −120 to 88 FF."
                    + " Skala 1:1 z wyświetlaczem modułu. Wartości ujemne"
                    + " potwierdzone niezależnie w samym pliku bazowym:"
                    + " kit 1, trigger 2 ma fabrycznie FE FF, czyli −2."

            case "trig.pan":
                // Tu również kodowanie było zgadnięte (przesunięcie 64, ±32).
                // Pomiar: przesunięcie 15, zakres ±15 (L15..CENTER..R15),
                // czyli w pliku bajt 0..30.
                layout.triggerFields[index].offset = 8
                layout.triggerFields[index].encoding = .biased(bias: 15, min: -15, max: 15)
                layout.triggerFields[index].display = .panLeftRight
                layout.triggerFields[index].note = "Zmierzone 2026-09-04 na obu"
                    + " skrajnościach: L15 to bajt 0, R15 to bajt 30."
                    + " Środek (CENTER) wypada na 15 — zgodne z tym, że kit 1"
                    + " ma fabrycznie 15 w obu triggerach, czyli wszystko"
                    + " wyśrodkowane. Hipoteza kroku 2 odpadła policzalnie:"
                    + " dawałaby dla fabrycznego 15 wartość R7,5."

            default:
                break   // trig.decay, trig.type, trig.sensitivity itd. — jeszcze niezmapowane
            }
        }

        // Pięć pól, które `unmappedTM2` zgadywał jako parametry brzmienia,
        // a które pomiary umieściły w globalnym rekordzie ustawień wejścia:
        // Type, Sensitivity, Threshold, Retrig Cancel i Mask Time. W slocie
        // brzmienia nie mają czego szukać — pokazywanie ich tam jako
        // „not mapped yet" sugerowałoby, że kiedyś się tam znajdą, a wiemy,
        // że nie. `unmappedTM2` zostaje nietknięty, bo zależą od niego
        // pozostałe testy i tryb „jeszcze nic nie wiem o formacie".
        let przeniesioneDoGlobalnych: Set<String> = [
            "trig.type", "trig.sensitivity", "trig.threshold",
            "trig.retrigCancel", "trig.maskTime",
        ]
        layout.triggerFields.removeAll { przeniesioneDoGlobalnych.contains($0.id) }

        // Pola, których `unmappedTM2` w ogóle nie przewidywał — wyszły dopiero
        // z mapowania różnicowego. Dopisujemy je tutaj, a nie do pustego
        // layoutu, żeby nie ruszać jego wartości domyślnych (zależą od nich
        // istniejące testy).
        layout.triggerFields.append(
            FieldSpec(
                id: "trig.loop",
                label: "Loop",
                scope: .trigger,
                group: .sound,
                offset: 14,                 // +0x0E względem początku rekordu
                encoding: .boolean,
                note: "Zmierzone 2026-11-21. Rozróżnione od Offsetu dopiero"
                    + " testem na skrajnej wartości: przy Loop ON i Offsetcie"
                    + " wykręconym na maksimum to pole zostało na 1, a drugie"
                    + " skoczyło na 3000. Przełącznik nie ma jak wyjść poza 1,"
                    + " więc to jest Loop."
            )
        )

        layout.triggerFields.append(
            FieldSpec(
                id: "trig.offset",
                label: "Offset",
                scope: .trigger,
                group: .sound,
                offset: 26,                 // +0x1A względem początku rekordu
                encoding: .unsigned16LE(min: 0, max: 3000),
                note: "Opóźnienie startu próbki, zapisane w DZIESIĄTYCH"
                    + " CZĘŚCIACH MILISEKUNDY: 0.1 ms na wyświetlaczu to 1"
                    + " w pliku, 300 ms to 3000 (0x0BB8). Dwa zgodne pomiary."
                    + " UWAGA: górna granica 3000 jest przyjęta z pliku"
                    + " nazwanego \"offset300ms\", zapisanego na prośbę"
                    + " o wykręcenie na maksimum — ale sam fakt, że to jest"
                    + " maksimum, nie został potwierdzony wprost. Lepiej, żeby"
                    + " edytor odmówił wartości legalnej, niż żeby wpisał"
                    + " do pliku wartość, której moduł nigdy by nie wystawił.",
                display: .scaled(divisor: 10, fractionDigits: 1, unit: "ms")
            )
        )

        // Pomiar `kit40-inst.bin` (2026-11-21). Arek ustawił na kicie 40,
        // TRIG IN 1 head, cały komplet parametrów brzmienia na skrajne
        // i ROZPOZNAWALNE wartości: Level 100, Dynmcs MAX, Pitch 120,
        // Pan R15, Loop ON, Mono/Poly MONO, Offset 300 ms, MuteGroup GRP2,
        // Note# 127, EffectSend ON. Każda inna, więc nic nie mogło się
        // pomylić — to ta sama sztuczka, której brakowało przy pierwszym
        // teście Loop/Offset, gdzie oba parametry przyjęły 1.
        //
        // Slot okazał się siatką 21 pól 16-bitowych LE na parzystych
        // offsetach. Po tym pomiarze wygląda tak:
        //
        //   +0x00 Instrument   +0x02 ?            +0x04 Level
        //   +0x06 Pitch        +0x08 Pan          +0x0A MuteGroup
        //   +0x0C Note#        +0x0E Loop         +0x10 Dynmcs
        //   +0x12 ?            +0x14 ?            +0x16 = 0xFFFF
        //   +0x18 ?            +0x1A Offset       +0x1C…+0x28 zera
        //
        // Mono/Poly i EffectSend nie drgnęły, bo oba były już ustawione
        // na docelową wartość — siedzą pod +0x12 i +0x14 (obie mają 1),
        // ale którym jest które, tego ten pomiar nie rozstrzyga.
        layout.triggerFields.append(
            FieldSpec(
                id: "trig.muteGroup",
                label: "Mute Group",
                scope: .trigger,
                group: .sound,
                offset: 10,                 // +0x0A
                encoding: .unsigned(min: 0, max: 8),
                note: "Zmierzone: GRP2 na wyświetlaczu to 2 w pliku, a stan"
                    + " wyjściowy (bez grupy) to 0. Skala 1:1, 0 = brak grupy."
                    + " GÓRNA GRANICA NIEZMIERZONA — przyjęte 8, bo tyle grup"
                    + " ma zwykle sprzęt Rolanda. Hipoteza, że grupa siedzi"
                    + " pod +0x16 (gdzie stoi 0xFFFF, czyli −1 jako „OFF”),"
                    + " okazała się nietrafiona: tamten bajt nie drgnął."
            )
        )

        layout.triggerFields.append(
            FieldSpec(
                id: "trig.note",
                label: "Note Number",
                scope: .trigger,
                group: .sound,
                offset: 12,                 // +0x0C
                encoding: .signed16LE(min: -1, max: 127),
                note: "Numer nuty MIDI wysyłanej przy uderzeniu. Górna granica"
                    + " ZMIERZONA: 127 na wyświetlaczu to 127 w pliku."
                    + " Hipoteza postawiona wcześniej z samych wartości"
                    + " fabrycznych — kit 1 ma w czterech slotach 36, 35, 38"
                    + " i 40, czyli standardowe numery nut perkusyjnych"
                    + " w kolejności padów — i pomiar ją potwierdził."
                    + " KOREKTA z serii max2/min2: `Note# = OFF` to w pliku"
                    + " −1 (0xFFFF), a nie zero. Pole jest więc dwubajtowe"
                    + " ze znakiem, a nie liczbą bez znaku 0…127 —"
                    + " przy poprzednim opisie wyłączona nuta pokazywałaby"
                    + " się jako 255.",
                display: .offWhenNegative
            )
        )

        layout.triggerFields.append(
            FieldSpec(
                id: "trig.dynamics",
                label: "Dynamics",
                scope: .trigger,
                group: .sound,
                offset: 16,                 // +0x10
                encoding: .enumeration(values: ["LINEAR", "LOUD 1", "LOUD 2",
                                                "LOUD 3", "MAX"]),
                note: "Zmierzone: MAX na wyświetlaczu to 4 w pliku, a to"
                    + " ostatnia z pięciu pozycji wymienionych w instrukcji"
                    + " (LINEAR, LOUD 1, LOUD 2, LOUD 3, MAX) — więc indeks"
                    + " idzie wprost, od zera. Pierwsze pole w tym projekcie"
                    + " z prawdziwą listą nazw, a nie samym numerem."
                    + " Wyjaśnia też starą zagadkę: wartość 1 pod tym"
                    + " offsetem w archiwalnym `b1.bin` to po prostu LOUD 1,"
                    + " a nie ślad nieznanego parametru."
            )
        )

        // Mono/Poly — CELOWO BEZ ADRESU. Przez chwilę było tu pole pod +0x12,
        // wywnioskowane z wykluczenia: bajt zmienił się z 1 na 0 w serii
        // max2/min2, a Mono/Poly było ostatnim parametrem instrumentu bez
        // adresu. Obaliło to jedno spojrzenie na wyświetlacz: moduł pokazuje
        // MONO zarówno przy 1, jak i przy 0. Do tego fabryczny kit 1 ma pod
        // +0x12 jedynkę na wszystkich padach przy wyłączonym Loop.
        // Czyli +0x12 to coś innego, a wniosek z wykluczenia był fałszywy —
        // zakładał, że lista parametrów z instrukcji jest kompletna.

        layout.triggerFields.append(
            FieldSpec(
                id: "trig.effectSend",
                label: "Effect Send",
                scope: .trigger,
                group: .sound,
                offset: 20,                 // +0x14
                encoding: .boolean,
                note: "Czy ten pad idzie przez efekt kitu. Zmierzone"
                    + " `trzy-drobiazgi.bin`: przestawienie na OFF zmieniło"
                    + " ten bajt z 1 na 0, a sąsiedni +0x12 został na 1."
                    + " Pod +0x12 siedzi najpewniej Mono/Poly (w chwili"
                    + " pomiaru ustawione na MONO), ale to wniosek"
                    + " z wykluczenia, nie pomiar — dlatego tamto pole"
                    + " zostaje niezmapowane."
            )
        )

        return layout
    }
}
