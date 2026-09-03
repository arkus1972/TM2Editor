import SwiftUI

/// Dziennik zdarzeń.
struct LogView: View {

    @EnvironmentObject private var model: AppModel
    @ObservedObject var log: EditorLog
    @State private var levelFilter: EditorLog.Level?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            entriesList
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $levelFilter) {
                Text("All").tag(EditorLog.Level?.none)
                ForEach(EditorLog.Level.allCases, id: \.self) { level in
                    Text(level.displayName).tag(EditorLog.Level?.some(level))
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Spacer()

            Button("Export…") { model.presentLogExportPanel() }
                .help("Save the log next to your mapping series files.")

            Button("Clear") { log.clear() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var entriesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.formattedTime)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)

                            Image(systemName: entry.level.symbolName)
                                .font(.system(size: 11))
                                .foregroundStyle(color(for: entry.level))
                                .frame(width: 14)

                            Text(entry.message)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 3)
                        .id(entry.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: log.entries.count) { _ in
                if let last = filtered.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var filtered: [EditorLog.Entry] {
        guard let levelFilter else { return log.entries }
        return log.entries.filter { $0.level == levelFilter }
    }

    private func color(for level: EditorLog.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .edit: return .accentColor
        case .undo: return .purple
        case .warning: return .orange
        case .error: return .red
        }
    }
}
