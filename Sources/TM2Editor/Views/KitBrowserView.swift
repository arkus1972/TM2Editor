import SwiftUI

/// Przeglądarka kitów: lista po lewej, edytor po prawej.
///
/// Wzorzec przeniesiony ze sceny padów w PulsoKicie, tylko dużo prostszy —
/// przy dwóch wejściach i czterech triggerach nie ma czego rozbudowywać.
struct KitBrowserView: View {

    @ObservedObject var editor: KitEditor

    /// Zaznaczenie jest tu zwykłym `let`, a NIE `@ObservedObject`. Celowo:
    /// ten widok trzyma splitter i nie ma się przebudowywać przy zmianie
    /// wybranego triggera. Obserwują je dopiero te dzieci, które muszą.
    let selection: EditorSelection

    var body: some View {
        HSplitView {
            KitListPane(
                selection: selection,
                kitCount: max(editor.layout.kitCount, 1),
                names: editor.kitNames,
                changedKits: editor.changedKits
            )
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

            KitDetailView(editor: editor, selection: selection)
                .frame(minWidth: 520)
        }
    }
}

/// Cienkie opakowanie listy kitów.
///
/// Ono jedno obserwuje zaznaczenie, żeby podświetlić właściwy wiersz. Jego
/// ciało jest jednak puste treściowo — składa tylko `KitListView` z gotowych
/// wartości. Dzięki temu zmiana triggera przelatuje tędy bez kosztu:
/// `.equatable()` porównuje wartości, widzi, że lista jest ta sama, i
/// pomija przerysowanie 99 wierszy.
struct KitListPane: View {

    @ObservedObject var selection: EditorSelection
    let kitCount: Int
    let names: [String?]
    let changedKits: Set<Int>

    var body: some View {
        KitListView(
            kitCount: kitCount,
            names: names,
            changedKits: changedKits,
            selected: selection.kit,
            onSelect: { selection.kit = $0 }
        )
        .equatable()
    }
}

// MARK: - Lista kitów

/// Lista 99 kitów.
///
/// Celowo nie obserwuje niczego — ani edytora, ani zaznaczenia. Na macOS
/// `List` z zaznaczeniem to pod spodem `NSTableView`, więc przebudowa widoku
/// oznacza przeładowanie wszystkich wierszy; każdy wiersz dekodował przy tym
/// nazwę kitu z pliku i przeszukiwał liniowo historię zmian.
///
/// Widok dostaje gotowe wartości i jest `Equatable`, więc SwiftUI pomija
/// przerysowanie, dopóki któraś z nich faktycznie się nie zmieni.
struct KitListView: View, Equatable {

    let kitCount: Int
    let names: [String?]
    let changedKits: Set<Int>
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kits")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(kitCount)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(Array(1...kitCount), id: \.self, selection: kitSelection) { kit in
                HStack(spacing: 8) {
                    Text(String(format: "%02d", kit))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)

                    if let name = name(for: kit) {
                        Text(name)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if changedKits.contains(kit) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                }
                .tag(kit)
            }
            .listStyle(.inset)
        }
    }

    /// Nazwa z gotowego bufora. Indeks jest 0-based, numer kitu 1-based.
    private func name(for kit: Int) -> String? {
        let index = kit - 1
        guard names.indices.contains(index) else { return nil }
        return names[index]
    }

    private var kitSelection: Binding<Int?> {
        Binding(
            get: { selected },
            set: { if let value = $0 { onSelect(value) } }
        )
    }

    /// Domknięcie `onSelect` celowo poza porównaniem — SwiftUI tworzy je od
    /// nowa przy każdej przebudowie rodzica, więc porównywanie go (gdyby to
    /// było w ogóle możliwe) zawsze dawałoby „różne" i cały zabieg byłby
    /// bez sensu. Liczy się to, co widać na ekranie.
    static func == (lewa: KitListView, prawa: KitListView) -> Bool {
        lewa.kitCount == prawa.kitCount
            && lewa.selected == prawa.selected
            && lewa.changedKits == prawa.changedKits
            && lewa.names == prawa.names
    }
}

// MARK: - Edytor kitu

struct KitDetailView: View {

    @ObservedObject var editor: KitEditor
    @ObservedObject var selection: EditorSelection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                if !editor.layout.canAddressKits {
                    NotMappedNotice()
                }

                // Pola kitu
                FieldSection(
                    title: "Kit \(selection.kit)",
                    fields: editor.layout.kitFields,
                    editor: editor,
                    kit: selection.kit,
                    trigger: 1
                )

                // Wybór triggera
                if !editor.layout.triggerFields.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trigger")
                            .font(.headline)

                        Picker("", selection: triggerSelection) {
                            ForEach(Array(1...max(editor.layout.triggerCount, 1)),
                                    id: \.self) { index in
                                Text(triggerLabel(index)).tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(triggerHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(FieldGroup.allCases, id: \.self) { group in
                        let fields = editor.layout.triggerFields.filter { $0.group == group }
                        if !fields.isEmpty {
                            FieldSection(
                                title: group.displayName,
                                fields: fields,
                                editor: editor,
                                kit: selection.kit,
                                trigger: selection.trigger
                            )
                        }
                    }
                }

                // Ustawienia globalne
                if !editor.layout.globalFields.isEmpty {
                    FieldSection(
                        title: "System",
                        fields: editor.layout.globalFields,
                        editor: editor,
                        kit: selection.kit,
                        trigger: 1
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var triggerSelection: Binding<Int> {
        Binding(
            get: { selection.trigger },
            set: { selection.trigger = $0 }
        )
    }

    /// Cztery sloty brzmień na kit: head i rim obu gniazd TRIG IN.
    ///
    /// Historia tych etykiet to dobra ilustracja, po co jest mapowanie
    /// różnicowe. Najpierw było `1A`/`1B` — zgadnięte, przy założeniu dwóch
    /// slotów będących dwiema stronami jednego gniazda. Pomiar to obalił:
    /// parametr ustawiony na TRIG IN 2 wylądował w slocie drugim, więc sloty
    /// odpowiadały gniazdom. Potem okazało się, że slotów jest cztery, nie
    /// dwa — 84-bajtowy rekord to dwa sloty po 42 B. Dopiero teraz etykiety
    /// mówią to, co jest naprawdę w pliku.
    private func triggerLabel(_ index: Int) -> String {
        let jack = (index - 1) / 2 + 1
        let side = (index - 1) % 2 == 0 ? "head" : "rim"
        return "TRIG IN \(jack) · \(side)"
    }

    private var triggerHint: String {
        "Each TRIG IN jack is dual-trigger: head is the tip signal, rim is "
            + "the ring signal. Each of the four gets its own sound settings. "
            + "Trigger input settings (sensitivity and so on) are global, not "
            + "per kit — they follow the pad, not the sound."
    }
}

/// Komunikat pokazywany, dopóki format pliku nie jest rozpracowany.
struct NotMappedNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text("The backup layout is not mapped yet")
                    .font(.callout.weight(.semibold))
                Text("""
                The file opens and can be inspected byte by byte, but no field \
                offsets are known, so editing is disabled. Run the differential \
                mapping series described in the project documentation \
                (tools/tm2diff.py), then drop the resulting layout description \
                into Application Support › TM2Editor › tm2-layout.json.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Sekcja pól

struct FieldSection: View {

    let title: String
    let fields: [FieldSpec]
    @ObservedObject var editor: KitEditor
    let kit: Int
    let trigger: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                    if index > 0 { Divider() }
                    // Tożsamość zależna od adresu TYLKO dla pól tekstowych.
                    // One jedne mają bufor edycji, który bez tego przeżyłby
                    // zmianę kitu i niezatwierdzona nazwa z kitu 3 trafiłaby
                    // do kitu 7. Dla pól liczbowych taka tożsamość była czystą
                    // stratą: zmiana numeru kitu albo triggera kasowała wiersz
                    // i budowała go od zera, a pod spodem suwak i stepper to
                    // widoki AppKit — ich tworzenie nie jest darmowe.
                    FieldRow(field: field, editor: editor, kit: kit, trigger: trigger)
                        .id(field.encoding.isTextual
                            ? "\(field.id)#\(kit)#\(trigger)"
                            : field.id)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
