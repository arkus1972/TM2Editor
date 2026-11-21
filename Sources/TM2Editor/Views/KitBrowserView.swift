import SwiftUI

/// Przeglądarka kitów: lista po lewej, edytor po prawej.
///
/// Wzorzec przeniesiony ze sceny padów w PulsoKicie, tylko dużo prostszy —
/// przy dwóch wejściach i czterech triggerach nie ma czego rozbudowywać.
struct KitBrowserView: View {

    @ObservedObject var editor: KitEditor

    var body: some View {
        HSplitView {
            KitListView(editor: editor)
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

            KitDetailView(editor: editor)
                .frame(minWidth: 520)
        }
    }
}

// MARK: - Lista kitów

struct KitListView: View {

    @ObservedObject var editor: KitEditor

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kits")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(editor.layout.kitCount)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(Array(1...max(editor.layout.kitCount, 1)),
                 id: \.self, selection: kitSelection) { kit in
                HStack(spacing: 8) {
                    Text(String(format: "%02d", kit))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)

                    if let name = editor.kitName(kit) {
                        Text(name)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if hasChanges(in: kit) {
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

    private var kitSelection: Binding<Int?> {
        Binding(
            get: { editor.selectedKit },
            set: { if let value = $0 { editor.selectedKit = value } }
        )
    }

    private func hasChanges(in kit: Int) -> Bool {
        editor.changes.contains { $0.scope != .global && $0.kit == kit }
    }
}

// MARK: - Edytor kitu

struct KitDetailView: View {

    @ObservedObject var editor: KitEditor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                if !editor.layout.canAddressKits {
                    NotMappedNotice()
                }

                // Pola kitu
                FieldSection(
                    title: "Kit \(editor.selectedKit)",
                    fields: editor.layout.kitFields,
                    editor: editor,
                    kit: editor.selectedKit,
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
                                kit: editor.selectedKit,
                                trigger: editor.selectedTrigger
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
                        kit: editor.selectedKit,
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
            get: { editor.selectedTrigger },
            set: { editor.selectedTrigger = $0 }
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
                    // Tożsamość wiersza obejmuje adres, nie tylko pole.
                    // Bez tego bufor edycji tekstu przeżyłby zmianę kitu i
                    // niezatwierdzona nazwa z kitu 3 trafiłaby do kitu 7.
                    FieldRow(field: field, editor: editor, kit: kit, trigger: trigger)
                        .id("\(field.id)#\(kit)#\(trigger)")
                }
            }
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
