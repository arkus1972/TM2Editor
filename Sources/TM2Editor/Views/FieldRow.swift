import AppKit
import SwiftUI

/// Jeden wiersz edycji parametru.
///
/// Wiersz ma trzy stany i wszystkie trzy są normalne:
///  - pole zmapowane        -> pełna edycja
///  - pole niezmapowane     -> nieaktywne, z adnotacją i notatką roboczą
///  - pole zmapowane, ale adres wypada poza plikiem -> ostrzeżenie
struct FieldRow: View {

    let field: FieldSpec
    @ObservedObject var editor: KitEditor
    let kit: Int
    let trigger: Int

    /// Etykieta do pokazania zamiast `field.label`. Sekcja, która już w nagłówku
    /// mówi „TRIG IN 1 · head", nie musi tego powtarzać w każdym wierszu.
    var labelOverride: String?

    /// Wspólna szerokość kolumny z kontrolkami. Dzięki niej pole liczbowe,
    /// lista wyboru, przełącznik i pole tekstowe kończą się w jednej linii —
    /// wcześniej każdy wiersz miał inną szerokość, bo suwak pojawiał się
    /// tylko przy części pól, i całość wyglądała nierówno.
    static let szerokoscKontrolki: CGFloat = 220

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(labelOverride ?? field.label)
                    .font(Styl.etykieta)
                    .foregroundStyle(field.isMapped ? .primary : .secondary)

                if let detail = detailText {
                    Text(detail)
                        .font(Styl.opis)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            Group {
                if !field.isMapped {
                    Text("not mapped yet")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.10),
                                    in: Capsule())
                } else if currentValue == nil {
                    Label("offset outside file", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else {
                    editorControl
                }
            }
            .frame(width: Self.szerokoscKontrolki, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Kontrolka zależna od kodowania

    /// Pozycje listy, gdy pole pokazuje nazwę zamiast liczby (LoCut, typ
    /// pogłosu…). Wtedy wybór z listy, jak na module — niezależnie od tego,
    /// czy w pliku siedzi jeden bajt, czy dwa.
    private var pozycjeListy: [String]? {
        if case .lista(let pozycje) = wyswietlanie { return pozycje }
        return nil
    }

    /// Sposób pokazania wartości. Zwykle ten z opisu pola; wyjątek to numer
    /// instrumentu w slocie, który nie wygląda na brzmienie wewnętrzne —
    /// wtedy goła liczba zamiast nazwy z listy fabrycznej (plik WAV z karty
    /// dostałby inaczej nazwę zupełnie innego brzmienia).
    private var wyswietlanie: FieldDisplay {
        if field.id == "trig.instrument",
           !editor.brzmienieWewnetrzne(kit: kit, trigger: trigger) {
            return .plain
        }
        return field.display ?? .plain
    }

    @ViewBuilder
    private var editorControl: some View {
        if field.id == "trig.instrument", editor.obslugujeBrzmienia {
            // Brzmienie wewnętrzne z listy albo plik WAV z karty — osobny
            // widok, bo jedna zmiana rusza tu dwa miejsca pliku.
            WyborBrzmienia(editor: editor, kit: kit, trigger: trigger)
        } else if let pozycje = pozycjeListy {
            Picker("", selection: numberBinding) {
                ForEach(Array(pozycje.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
            .labelsHidden()
            .controlSize(.large)
            .font(Styl.wartosc)
        } else {
            kontrolkaWedlugKodowania
        }
    }

    @ViewBuilder
    private var kontrolkaWedlugKodowania: some View {
        switch field.encoding {
        case .ascii(let length):
            TextField("", text: textBinding)
                .font(Styl.wartosc)
                .textFieldStyle(.roundedBorder)
                .focused($maTekstFokus)
                .onSubmit { commitText() }
                .onChange(of: maTekstFokus) { zatwierdzPoUtracieFokusu($0) }
                .help("Maximum \(length) ASCII characters.")

        case .utf16LE(let length):
            TextField("", text: textBinding)
                .font(Styl.wartosc)
                .textFieldStyle(.roundedBorder)
                .focused($maTekstFokus)
                .onSubmit { commitText() }
                .onChange(of: maTekstFokus) { zatwierdzPoUtracieFokusu($0) }
                .help("Maximum \(length / 2) characters.")

        case .boolean, .bit:
            Toggle("", isOn: boolBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.large)

        case .enumeration(let values):
            Picker("", selection: numberBinding) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
            .labelsHidden()
            .controlSize(.large)
            .font(Styl.wartosc)

        default:
            // Jeden wzór dla KAŻDEJ liczby: duża wartość do wpisania
            // z klawiatury i przyciski −/+ obok, jak na samym module.
            // Suwaki zniknęły — pojawiały się tylko przy części pól, więc
            // wiersze miały różne szerokości, a przy zakresach typu 0…3000
            // i tak nie dało się nimi trafić w konkretną wartość.
            PoleLiczbowe(
                wartosc: numberBinding.wrappedValue,
                zakres: field.encoding.numericRange ?? 0...255,
                wyswietlanie: wyswietlanie,
                ustaw: { nowa in
                    editor.set(.number(nowa), for: field, kit: kit, trigger: trigger)
                },
                zapamietajNiezatwierdzone: { liczba in
                    editor.rememberPendingNumber(liczba, for: field,
                                                 kit: kit, trigger: trigger)
                },
                zapomnijNiezatwierdzone: {
                    editor.forgetPendingText(for: field, kit: kit, trigger: trigger)
                }
            )
        }
    }

    /// Wartość tak, jak pokazałby ją moduł: `L15`, `300.0 ms`, albo po prostu
    /// liczba, jeśli pole nie ma własnego sposobu wyświetlania.
    private var displayedValue: String {
        wyswietlanie.text(for: numberBinding.wrappedValue)
    }

    /// Surowa liczba dziesiętna spod spodu — pokazywana drobnym drukiem tylko
    /// wtedy, gdy różni się od tego, co widać wyżej. Przy mapowaniu trzeba
    /// wiedzieć, co naprawdę siedzi w pliku, a nie tylko jak to wygląda.
    private var rawValueText: String? {
        let raw = numberBinding.wrappedValue
        let shown = displayedValue
        return shown == String(raw) ? nil : String(raw)
    }

    // MARK: - Powiązania

    private var currentValue: FieldValue? {
        editor.value(of: field, kit: kit, trigger: trigger)
    }

    private var numberBinding: Binding<Int> {
        Binding(
            get: { currentValue?.numberValue ?? 0 },
            set: { editor.set(.number($0), for: field, kit: kit, trigger: trigger) }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { (currentValue?.numberValue ?? 0) != 0 },
            set: { editor.set(.number($0 ? 1 : 0), for: field, kit: kit, trigger: trigger) }
        )
    }

    /// Tekst edytujemy w buforze i zatwierdzamy dopiero na Enter albo przy
    /// utracie fokusu — inaczej każda wpisana litera trafiałaby na listę zmian
    /// jako osobna pozycja.
    @State private var textBuffer: String = ""
    @State private var textLoaded = false
    @FocusState private var maTekstFokus: Bool

    private var textBinding: Binding<String> {
        Binding(
            get: {
                if !textLoaded {
                    return currentValue?.textValue ?? ""
                }
                return textBuffer
            },
            set: { newValue in
                textBuffer = newValue
                textLoaded = true
                // Meldunek dla edytora: gdyby użytkownik zapisał plik bez
                // naciśnięcia Entera, zapis i tak ma wziąć to, co widzi
                // na ekranie. Bez tego nazwa kitu zostawała stara, choć
                // parametry liczbowe zapisywały się poprawnie.
                editor.rememberPendingText(newValue, for: field,
                                           kit: kit, trigger: trigger)
            }
        )
    }

    private func commitText() {
        guard textLoaded else { return }
        editor.set(.text(textBuffer), for: field, kit: kit, trigger: trigger)
        editor.forgetPendingText(for: field, kit: kit, trigger: trigger)
        textLoaded = false
    }

    /// Wyjście z pola myszą albo tabulatorem zatwierdza tak samo jak Enter.
    /// Dzięki temu nazwa kitu pojawia się na liście po lewej od razu, a nie
    /// dopiero po Enterze — czego nikt nie ma obowiązku się domyślać.
    private func zatwierdzPoUtracieFokusu(_ maFokus: Bool) {
        guard !maFokus else { return }
        commitText()
    }

    // MARK: - Opis pod etykietą

    /// Narzędzia mapowania włączone (View › Show Mapping Tools) — tylko wtedy
    /// pod parametrem pokazujemy adres w pliku i surową wartość.
    @AppStorage("TM2Editor.narzedziaMapowania") private var narzedziaMapowania = false

    /// Opis pod nazwą parametru: zakres albo dostępne pozycje, tak jak
    /// pokazuje je moduł. Adres w pliku (heks) tylko w trybie narzędzi
    /// mapowania — dla grania jest bez znaczenia.
    private var detailText: String? {
        if !field.isMapped {
            return field.note
        }
        var parts: [String] = []
        if let opis = opisZakresu { parts.append(opis) }
        if narzedziaMapowania,
           let offset = editor.layout.absoluteOffset(for: field, kit: kit, trigger: trigger) {
            parts.append(String(format: "0x%X (%d)", offset, offset))
            if let raw = rawValueText { parts.append("raw \(raw)") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    /// Zakres liczby albo lista pozycji po przecinkach. Długie listy skrócone.
    private var opisZakresu: String? {
        if field.id == "trig.instrument" {
            // 162 nazw nie zmieści się pod parametrem — pełna lista jest
            // w menu obok.
            return "162 internal sounds or a WAV file from the SD card"
        }
        switch field.encoding {
        case .ascii(let length):
            return "Up to \(length) characters"
        case .utf16LE(let length):
            return "Up to \(length / 2) characters"
        case .boolean, .bit:
            return nil
        case .enumeration(let values):
            return Self.lista(values)
        default:
            break
        }
        if let pozycje = pozycjeListy {
            return Self.lista(pozycje)
        }
        guard let zakres = field.encoding.numericRange else { return nil }
        return wyswietlanie.text(for: zakres.lowerBound) + " … " + wyswietlanie.text(for: zakres.upperBound)
    }

    /// Opis listy pozycji, jak prosił Arek: liczby rosnące równo — zakres
    /// („1 … 10", „-24 dB … -1 dB, OFF"); teksty i liczby rosnące
    /// nieregularnie (LoCut, Q, Ratio, częstotliwości EQ) — wszystkie
    /// pozycje po przecinkach.
    static func lista(_ pozycje: [String]) -> String {
        // Pozycje tekstowe na końcu (np. „OFF" za liczbami) zostają osobno.
        var liczbowe = pozycje
        var dopisek: [String] = []
        while let ostatnia = liczbowe.last, liczbaZJednostka(ostatnia) == nil {
            dopisek.insert(ostatnia, at: 0)
            liczbowe.removeLast()
        }
        let wartosci = liczbowe.compactMap(liczbaZJednostka)
        guard liczbowe.count >= 3, wartosci.count == liczbowe.count,
              Set(wartosci.map(\.jednostka)).count == 1 else {
            return pozycje.joined(separator: ", ")
        }
        let krok = wartosci[1].liczba - wartosci[0].liczba
        let rowno = krok != 0 && zip(wartosci, wartosci.dropFirst())
            .allSatisfy { abs(($1.liczba - $0.liczba) - krok) < 1e-9 }
        guard rowno, let pierwsza = liczbowe.first, let ostatnia = liczbowe.last else {
            return pozycje.joined(separator: ", ")
        }
        return ([pierwsza + " … " + ostatnia] + dopisek).joined(separator: ", ")
    }

    /// „-24 dB" → (-24, " dB"), „16" → (16, ""), „2:1" → (2, ":1"),
    /// „FLAT" → nil.
    private static func liczbaZJednostka(_ tekst: String) -> (liczba: Double, jednostka: String)? {
        var cyfry = ""
        var reszta = Substring(tekst)
        if let pierwszy = reszta.first, pierwszy == "-" || pierwszy == "+" {
            cyfry.append(pierwszy)
            reszta = reszta.dropFirst()
        }
        while let znak = reszta.first, znak.isNumber || znak == "." {
            cyfry.append(znak)
            reszta = reszta.dropFirst()
        }
        guard let liczba = Double(cyfry) else { return nil }
        return (liczba, String(reszta))
    }


}
