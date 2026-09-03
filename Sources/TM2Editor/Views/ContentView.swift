import SwiftUI

/// Główne okno.
struct ContentView: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.hasOpenFile {
                openFileBody
            } else {
                WelcomeView()
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(
                   get: { model.errorMessage != nil },
                   set: { if !$0 { model.errorMessage = nil } }
               ),
               actions: {
                   Button("OK") { model.errorMessage = nil }
               },
               message: {
                   Text(model.errorMessage ?? "")
               })
    }

    @ViewBuilder
    private var openFileBody: some View {
        VStack(spacing: 0) {
            if let editor = model.editor {
                HeaderBar(editor: editor)
            }
            Divider()

            if !model.validationWarnings.isEmpty {
                WarningBanner(warnings: model.validationWarnings)
                Divider()
            }

            TabSwitcher()
            Divider()

            // Uwaga na obserwowanie: KitEditor i EditorLog to osobne obiekty
            // ObservableObject. Widok, który patrzy tylko na AppModel, nie
            // odświeży się, kiedy zmienią się ich właściwości. Dlatego każdy
            // z tych widoków dostaje swój obiekt jawnie, jako @ObservedObject.
            Group {
                if let editor = model.editor {
                    switch model.selectedTab {
                    case .kits:
                        KitBrowserView(editor: editor)
                    case .hex:
                        HexInspectorView(editor: editor)
                    case .layout:
                        LayoutStatusView(editor: editor)
                    case .log:
                        LogView(log: model.log)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Ekran powitalny

struct WelcomeView: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            Text("TM-2 Editor")
                .font(.largeTitle.weight(.semibold))

            Text(model.profile.modelName)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(model.profile.liveEditingExplanation)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Backup File…") {
                model.presentOpenPanel()
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            SafetyNoteView()
                .frame(maxWidth: 620)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Nota bezpieczeństwa. Zostaje na widoku na stałe, nie chowa się po
/// pierwszym uruchomieniu — to nie jest onboarding, tylko przypomnienie.
struct SafetyNoteView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing is ever sent to the module")
                    .font(.callout.weight(.semibold))
                Text("""
                This editor only reads and writes files. It never transmits \
                anything over MIDI and never overwrites the file you opened — \
                edited backups are always saved under a new name. Keep the \
                original on the SD card until the module has accepted the \
                edited copy.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Pasek nagłówka

struct HeaderBar: View {

    @EnvironmentObject private var model: AppModel
    @ObservedObject var editor: KitEditor

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if editor.hasUnsavedChanges {
                Label("\(editor.changes.count) unsaved change"
                        + (editor.changes.count == 1 ? "" : "s"),
                      systemImage: "pencil.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                editor.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("Undo")
            .disabled(!editor.canUndo)

            Button {
                editor.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .help("Redo")
            .disabled(!editor.canRedo)

            Button("Save As…") {
                model.presentSavePanel()
            }
            .disabled(!editor.hasUnsavedChanges)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var fileName: String {
        editor.file.sourceURL?.lastPathComponent ?? "Untitled"
    }

    private var subtitle: String {
        let size = editor.file.size
        let layout = editor.layout
        if layout.canAddressKits {
            return "\(size) bytes · layout v\(layout.layoutVersion) · "
                + "\(layout.mappedFieldCount)/\(layout.totalFieldCount) fields mapped"
        }
        return "\(size) bytes · layout not mapped yet — view only"
    }
}

// MARK: - Przełącznik zakładek

struct TabSwitcher: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppModel.Tab.allCases) { tab in
                Button {
                    model.selectedTab = tab
                } label: {
                    Label(tab.displayName, systemImage: tab.symbolName)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            model.selectedTab == tab
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Pasek ostrzeżeń

struct WarningBanner: View {

    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
    }
}

// MARK: - O programie

struct AboutView: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TM-2 Editor")
                .font(.title2.weight(.semibold))
            Text("A free, offline editor for Roland TM-2 backup files. "
                + "MIT licensed. No network access, no telemetry, no analytics.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Module").foregroundStyle(.secondary)
                    Text(model.profile.modelName)
                }
                GridRow {
                    Text("Kits").foregroundStyle(.secondary)
                    Text("\(model.profile.kitCount)")
                }
                GridRow {
                    Text("Triggers").foregroundStyle(.secondary)
                    Text("\(model.profile.triggerCount) "
                        + "(\(model.profile.triggerInputCount) dual-trigger inputs)")
                }
                GridRow {
                    Text("USB").foregroundStyle(.secondary)
                    Text(model.profile.hasUSB ? "Yes" : "No")
                }
                GridRow {
                    Text("SysEx map").foregroundStyle(.secondary)
                    Text(model.profile.hasPublishedMIDIImplementation
                         ? "Published by Roland" : "Never published")
                }
            }
            .font(.callout)

            Spacer()
        }
        .padding(24)
        .frame(width: 460, height: 320)
    }
}
