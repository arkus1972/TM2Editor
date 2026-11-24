import AppKit
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
        // Własny obrazek NAD całym oknem, jako przezroczysty znak wodny.
        // Pod spodem zawsze coś go zasłaniało: lista kitów i panele rysują
        // własne tło. Na wierzchu nic go nie przykryje, a kliknięcia przez
        // niego przechodzą (allowsHitTesting(false) w TloOkna).
        .overlay { TloOkna(tlo: model.tlo) }
        .sheet(isPresented: $model.pokazWyrownanie) {
            if let editor = model.editor {
                WyrownanieGlosnosci(editor: editor, zamknij: { model.pokazWyrownanie = false })
            }
        }
        .sheet(isPresented: $model.pokazPresety) {
            if let editor = model.editor {
                BibliotekaPresetowView(editor: editor, selection: model.selection,
                                       zamknij: { model.pokazPresety = false })
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
                        KitBrowserView(editor: editor, selection: model.selection)
                    case .hex:
                        HexInspectorView(editor: editor, selection: model.selection)
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

            HStack(spacing: 12) {
                Button("Open Backup File…") {
                    model.presentOpenPanel()
                }
                .keyboardShortcut(.defaultAction)
                Button("New Backup…") {
                    model.nowyBackup()
                }
                .help("Start a backup with 99 empty kits, in a new folder with the SD card structure.")
            }
            .controlSize(.large)

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

            if editor.hasUnsavedChanges || editor.hasPendingText {
                Label(opisNiezapisanych, systemImage: "pencil.circle.fill")
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
            // Tekst wpisany, a jeszcze niezatwierdzony Enterem, też jest
            // powodem do zapisu. Bez tego po samej zmianie nazwy kitu
            // przycisk zostawał wyszarzony i nazwy nie dało się zapisać.
            .disabled(!editor.hasUnsavedChanges && !editor.hasPendingText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Plakietka ma mówić prawdę także wtedy, gdy jedyną zmianą jest tekst
    /// wpisany w pole i jeszcze niezatwierdzony — wtedy licznik zmian stoi
    /// na zerze, a zapisać i tak jest co.
    private var opisNiezapisanych: String {
        let liczba = editor.changes.count
        guard liczba > 0 else { return "unsaved text edit" }
        let tekst = "\(liczba) unsaved change" + (liczba == 1 ? "" : "s")
        return editor.hasPendingText ? tekst + " + text being typed" : tekst
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
            // Przy schowanych narzędziach mapowania zostaje sama zakładka Kits —
            // wtedy nie pokazujemy jej wcale, pasek służy tylko przyciskom.
            ForEach(model.widoczneZakladki.count > 1 ? model.widoczneZakladki : []) { tab in
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
            PasekNarzedzi()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Pasek narzędzi

/// Najczęstsze polecenia z menu File i Tools pod ręką, na pasku zakładek
/// (prośba Arka). Menu zostają — to tylko skróty do tych samych funkcji.
/// Undo, Redo i Save As są w pasku nagłówka nad zakładkami.
struct PasekNarzedzi: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        // Przy wąskim oknie same ikony (z podpowiedzią po najechaniu),
        // przy szerszym — ikony z napisami.
        ViewThatFits(in: .horizontal) {
            przyciski(zNapisami: true)
            przyciski(zNapisami: false)
        }
    }

    private func przyciski(zNapisami: Bool) -> some View {
        HStack(spacing: 2) {
            przycisk("Open", ikona: "folder", pomoc: "Open a backup file (⌘O)",
                     zNapisem: zNapisami) {
                model.presentOpenPanel()
            }
            Divider().frame(height: 18).padding(.horizontal, 4)
            przycisk("Copy to Card", ikona: "sdcard",
                     pomoc: "Copy this backup and its samples to the SD card in one go",
                     zNapisem: zNapisami) {
                model.kopiujNaKarte()
            }
            .disabled(model.projekt == nil)
            przycisk("Missing Samples", ikona: "questionmark.folder",
                     pomoc: "Find sample files this backup uses but the project does not have",
                     zNapisem: zNapisami) {
                model.znajdzBrakujaceSample()
            }
            .disabled(model.projekt == nil)
            przycisk("Even Out Levels", ikona: "slider.horizontal.3",
                     pomoc: "Measure all card samples of this backup and bring them to one loudness",
                     zNapisem: zNapisami) {
                model.pokazWyrownanie = true
            }
            .disabled(model.projekt == nil || model.editor == nil)
            przycisk("Show in Finder", ikona: "arrow.up.forward.app",
                     pomoc: "Show the folder with ROLAND/TM-2 in Finder",
                     zNapisem: zNapisami) {
                if let projekt = model.projekt {
                    NSWorkspace.shared.activateFileViewerSelecting([projekt])
                }
            }
            .disabled(model.projekt == nil)
        }
    }

    @ViewBuilder
    private func przycisk(_ tytul: String, ikona: String, pomoc: String, zNapisem: Bool,
                          akcja: @escaping () -> Void) -> some View {
        Button(action: akcja) {
            Group {
                if zNapisem {
                    Label(tytul, systemImage: ikona)
                } else {
                    Image(systemName: ikona)
                }
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(zNapisem ? pomoc : tytul + " — " + pomoc)
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
