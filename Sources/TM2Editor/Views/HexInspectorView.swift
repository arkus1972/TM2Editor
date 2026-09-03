import SwiftUI

/// Inspektor heks.
///
/// To jest narzędzie robocze na czas rozpracowywania formatu, a nie ozdoba.
/// Dopóki układ nie jest zmapowany, jest jedynym sposobem, żeby cokolwiek
/// w pliku zobaczyć. Podświetla bajty zmienione przez użytkownika i bajty
/// uznane za szum, więc od razu widać, co jest czym.
struct HexInspectorView: View {

    @ObservedObject var editor: KitEditor
    @State private var gotoText: String = ""
    @State private var scrollTarget: Int?

    private let bytesPerRow = 16

    var body: some View {
        VStack(spacing: 0) {
            toolbar(editor: editor)
            Divider()
            hexTable(editor: editor)
        }
    }

    // MARK: - Pasek narzędzi

    @ViewBuilder
    private func toolbar(editor: KitEditor) -> some View {
        HStack(spacing: 12) {
            TextField("Go to offset (hex or decimal)", text: $gotoText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { jump(editor: editor) }

            Button("Go") { jump(editor: editor) }

            Divider().frame(height: 16)

            if let origin = editor.layout.kitBlockOrigin {
                Button("Kit \(editor.selectedKit)") {
                    scrollTarget = editor.layout.kitOrigin(kit: editor.selectedKit) ?? origin
                }
                .help("Jump to the start of the selected kit block.")
            }

            if let spec = editor.layout.checksum, spec.algorithm != .none {
                Button("Checksum") { scrollTarget = spec.offset }
            }

            Spacer()

            LegendSwatch(color: .orange, label: "edited")
            LegendSwatch(color: .purple, label: "noise")
            LegendSwatch(color: .blue, label: "kit start")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Tabela

    @ViewBuilder
    private func hexTable(editor: KitEditor) -> some View {
        let bytes = editor.file.bytes
        let rowCount = (bytes.count + bytesPerRow - 1) / bytesPerRow
        let modified = editor.modifiedOffsets
        let kitOrigins = Set(
            (1...max(editor.layout.kitCount, 1))
                .compactMap { editor.layout.kitOrigin(kit: $0) }
        )

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        HexRow(
                            row: row,
                            bytes: bytes,
                            bytesPerRow: bytesPerRow,
                            modified: modified,
                            layout: editor.layout,
                            kitOrigins: kitOrigins
                        )
                        .id(row)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                withAnimation {
                    proxy.scrollTo(target / bytesPerRow, anchor: .center)
                }
                // Zerujemy cel, żeby dwa skoki pod ten sam offset z rzędu
                // faktycznie zadziałały — inaczej wartość się nie zmienia
                // i onChange w ogóle nie odpala.
                scrollTarget = nil
            }
        }
    }

    private func jump(editor: KitEditor) {
        let trimmed = gotoText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }
        let parsed: Int?
        if trimmed.hasPrefix("0x") {
            parsed = Int(trimmed.dropFirst(2), radix: 16)
        } else if trimmed.contains(where: { "abcdef".contains($0) }) {
            parsed = Int(trimmed, radix: 16)
        } else {
            parsed = Int(trimmed)
        }
        guard let offset = parsed, offset >= 0, offset < editor.file.size else { return }
        scrollTarget = offset
    }
}

/// Jeden wiersz szesnastu bajtów.
struct HexRow: View {

    let row: Int
    let bytes: [UInt8]
    let bytesPerRow: Int
    let modified: Set<Int>
    let layout: BackupLayout
    let kitOrigins: Set<Int>

    var body: some View {
        let start = row * bytesPerRow
        let end = min(start + bytesPerRow, bytes.count)

        HStack(spacing: 12) {
            Text(String(format: "%08X", start))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 3) {
                ForEach(start..<(start + bytesPerRow), id: \.self) { offset in
                    if offset < end {
                        Text(String(format: "%02X", bytes[offset]))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(color(for: offset))
                            .fontWeight(weight(for: offset))
                            .frame(width: 18)
                            .background(background(for: offset))
                    } else {
                        Text("  ")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 18)
                    }
                }
            }

            Text(asciiColumn(start: start, end: end))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 1)
    }

    private func color(for offset: Int) -> Color {
        if modified.contains(offset) { return .orange }
        if layout.isNoise(offset: offset) { return .purple }
        if kitOrigins.contains(offset) { return .blue }
        return .primary
    }

    private func weight(for offset: Int) -> Font.Weight {
        modified.contains(offset) || kitOrigins.contains(offset) ? .bold : .regular
    }

    @ViewBuilder
    private func background(for offset: Int) -> some View {
        if modified.contains(offset) {
            Color.orange.opacity(0.15)
        } else if kitOrigins.contains(offset) {
            Color.blue.opacity(0.12)
        } else {
            Color.clear
        }
    }

    private func asciiColumn(start: Int, end: Int) -> String {
        var text = ""
        for offset in start..<end {
            let byte = bytes[offset]
            text.append((byte >= 32 && byte < 127)
                        ? Character(UnicodeScalar(byte))
                        : ".")
        }
        return text
    }
}

struct LegendSwatch: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.6))
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
