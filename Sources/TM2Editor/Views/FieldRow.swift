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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                    .font(.callout)
                    .foregroundStyle(field.isMapped ? .primary : .secondary)

                if let detail = detailText {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 170, alignment: .leading)

            Spacer(minLength: 8)

            if !field.isMapped {
                Text("not mapped yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10),
                                in: Capsule())
            } else if currentValue == nil {
                Label("offset outside file", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                editorControl
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Kontrolka zależna od kodowania

    @ViewBuilder
    private var editorControl: some View {
        switch field.encoding {
        case .ascii(let length):
            TextField("", text: textBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit { commitText() }
                .help("Maximum \(length) ASCII characters.")

        case .utf16LE(let length):
            TextField("", text: textBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit { commitText() }
                .help("Maximum \(length / 2) characters.")

        case .boolean, .bit:
            Toggle("", isOn: boolBinding)
                .labelsHidden()
                .toggleStyle(.switch)

        case .enumeration(let values):
            Picker("", selection: numberBinding) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
            .labelsHidden()
            .frame(width: 180)

        default:
            HStack(spacing: 10) {
                if let range = field.encoding.numericRange, range.count <= 512 {
                    Slider(
                        value: Binding(
                            get: { Double(numberBinding.wrappedValue) },
                            set: { numberBinding.wrappedValue = Int($0.rounded()) }
                        ),
                        in: Double(range.lowerBound)...Double(range.upperBound),
                        step: 1
                    )
                    .frame(width: 160)
                }

                Stepper(
                    value: numberBinding,
                    in: field.encoding.numericRange ?? 0...255
                ) {
                    Text("\(numberBinding.wrappedValue)")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
                .labelsHidden()
            }
        }
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
            }
        )
    }

    private func commitText() {
        guard textLoaded else { return }
        editor.set(.text(textBuffer), for: field, kit: kit, trigger: trigger)
        textLoaded = false
    }

    // MARK: - Opis pod etykietą

    private var detailText: String? {
        if !field.isMapped {
            return field.note
        }
        guard let offset = editor.layout.absoluteOffset(for: field, kit: kit, trigger: trigger) else {
            return nil
        }
        var parts = [String(format: "0x%X", offset)]
        if let range = field.encoding.numericRange, !field.encoding.isTextual {
            parts.append("\(range.lowerBound)…\(range.upperBound)")
        }
        return parts.joined(separator: "  ·  ")
    }
}
