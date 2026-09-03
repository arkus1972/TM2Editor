import SwiftUI

/// Stan rozpoznania formatu pliku.
///
/// Ta zakładka jest tablicą postępu prac: pokazuje, co już wiemy o pliku,
/// czego jeszcze nie, i który krok protokołu mapowania to odblokuje.
/// Dopóki projekt jest na etapie rozpracowywania formatu, to jest zakładka,
/// na którą patrzy się najczęściej.
struct LayoutStatusView: View {

    @ObservedObject var editor: KitEditor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                progressCard(editor: editor)
                structureCard(editor: editor)
                checksumCard(editor: editor)
                fieldsCard(editor: editor)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Postęp

    @ViewBuilder
    private func progressCard(editor: KitEditor) -> some View {
        let layout = editor.layout
        Card(title: "Mapping progress") {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(
                    value: Double(layout.mappedFieldCount),
                    total: Double(max(layout.totalFieldCount, 1))
                )
                Text("\(layout.mappedFieldCount) of \(layout.totalFieldCount) "
                    + "fields have a known offset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                StepRow(done: true,
                        title: "Step 0 — card inventory",
                        detail: "File is open: \(editor.file.size) bytes.")
                StepRow(done: !layout.noiseRanges.isEmpty,
                        title: "Step 1 — noise identified",
                        detail: layout.noiseRanges.isEmpty
                            ? "Compare two backups of the same state to find "
                                + "timestamps and counters."
                            : "\(layout.noiseRanges.count) noise range(s) recorded.")
                StepRow(done: layout.kitBlockOrigin != nil,
                        title: "Step 2 — kit block anchor",
                        detail: layout.kitBlockOrigin.map {
                            "Kit 1 starts at " + String(format: "0x%X", $0) + "."
                        } ?? "Set a kit name to AAAAAAAA and diff against the baseline.")
                StepRow(done: !layout.kitFields.filter { $0.isMapped }.isEmpty
                            || !layout.triggerFields.filter { $0.isMapped }.isEmpty,
                        title: "Steps 3 and 4 — parameter offset and scale",
                        detail: "Change one parameter by +1, then to its minimum "
                            + "and maximum.")
                StepRow(done: layout.kitStride != nil,
                        title: "Step 5 — kit stride",
                        detail: layout.kitStride.map {
                            "\($0) bytes per kit; \(layout.kitCount) kits = "
                                + "\($0 * layout.kitCount) bytes."
                        } ?? "Change the same parameter in kit 2 to unlock the "
                            + "whole layout at once.")
            }
        }
    }

    // MARK: - Struktura

    @ViewBuilder
    private func structureCard(editor: KitEditor) -> some View {
        let layout = editor.layout
        Card(title: "File structure") {
            // Wiersze są budowane funkcją @ViewBuilder, a nie osobnym typem
            // widoku: Grid rozpoznaje wiersze po dosłownych GridRow wśród
            // swoich dzieci, a własny typ opakowujący GridRow potrafi zepsuć
            // wyrównanie kolumn. Dziesięć wierszy mieści się dokładnie
            // w limicie ViewBuildera, więc nie ma potrzeby grupowania —
            // przy dołożeniu jedenastego trzeba będzie owinąć część w Group.
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                infoRow("File size", "\(editor.file.size) bytes")
                infoRow("Expected size", layout.expectedFileSize.map { "\($0) bytes" })
                infoRow("Signature", layout.magic.map { bajty in
                    bajty.map { String(format: "%02X", $0) }.joined(separator: " ")
                })
                infoRow("Module system version", layout.moduleSystemVersion)
                infoRow("Kit 1 offset",
                        layout.kitBlockOrigin.map { String(format: "0x%X", $0) })
                infoRow("Kit stride", layout.kitStride.map { "\($0) bytes" })
                infoRow("Kit count", "\(layout.kitCount)")
                infoRow("Trigger block offset",
                        layout.triggerBlockOrigin.map { String(format: "+0x%X", $0) })
                infoRow("Trigger stride", layout.triggerStride.map { "\($0) bytes" })
                infoRow("Trigger count", "\(layout.triggerCount)")
            }
        }
    }

    /// Jeden wiersz siatki informacyjnej.
    @ViewBuilder
    private func infoRow(_ label: String, _ value: String?) -> some View {
        GridRow {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value ?? "unknown")
                .font(.system(.callout, design: value == nil ? .default : .monospaced))
                .foregroundStyle(value == nil
                                 ? HierarchicalShapeStyle.tertiary
                                 : HierarchicalShapeStyle.primary)
        }
    }

    // MARK: - Suma kontrolna

    @ViewBuilder
    private func checksumCard(editor: KitEditor) -> some View {
        Card(title: "Checksum") {
            if let spec = editor.layout.checksum, spec.algorithm != .none {
                VStack(alignment: .leading, spacing: 8) {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                        infoRow("Algorithm", spec.algorithm.displayName)
                        infoRow("Offset", String(format: "0x%X", spec.offset))
                        infoRow("Length", "\(spec.length) bytes")
                        infoRow("Stored", editor.file.storedChecksum(spec: spec))
                        infoRow("Computed",
                                Checksum.compute(spec: spec, over: editor.file.bytes))
                    }
                    Text("The checksum is recalculated automatically when the "
                        + "edited backup is saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No checksum configured.")
                        .font(.callout)
                    Text("""
                    If the differential mapping shows a group of bytes that \
                    changes on every edit regardless of which parameter was \
                    touched, that group is the checksum. One byte suggests a \
                    plain sum or XOR, two bytes a CRC-16, four bytes a CRC-32 \
                    or a 32-bit sum, sixteen bytes MD5 — which is what the TD0 \
                    files handled by PulsoKit use.
                    """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Lista pól

    @ViewBuilder
    private func fieldsCard(editor: KitEditor) -> some View {
        let all = editor.layout.globalFields
            + editor.layout.kitFields
            + editor.layout.triggerFields

        Card(title: "Fields") {
            VStack(spacing: 0) {
                ForEach(Array(all.enumerated()), id: \.element.id) { index, field in
                    if index > 0 { Divider() }
                    HStack(spacing: 10) {
                        // Obie gałęzie muszą dać ten sam typ ShapeStyle:
                        // .green to Color, .secondary to HierarchicalShapeStyle,
                        // więc bez jawnego Color wyrażenie jest wieloznaczne.
                        Image(systemName: field.isMapped
                              ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(field.isMapped ? Color.green : Color.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.label).font(.callout)
                            Text(field.id)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Text(field.scope.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.10), in: Capsule())

                        Text(field.offset.map { String(format: "0x%X", $0) } ?? "—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(field.isMapped ? .primary : .tertiary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - Drobne elementy

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StepRow: View {
    let done: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
