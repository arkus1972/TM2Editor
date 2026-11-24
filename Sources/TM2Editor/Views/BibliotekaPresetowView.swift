import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Przyciski pod nazwą kitu: kopiowanie, zamiana i presety.
struct NarzedziaKitu: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Button { model.kopiujKitDo() } label: { Label("Copy To…", systemImage: "doc.on.doc") }
                .help("Copy this kit (effect, sounds, WAV file names) onto another kit.")
            Button { model.zamienKitZ() } label: { Label("Swap With…", systemImage: "arrow.left.arrow.right") }
                .help("Exchange this kit with another one.")
            Button { model.zapiszPresetKitu() } label: { Label("Save as Preset…", systemImage: "square.and.arrow.down") }
                .help("Keep this kit in your preset library to use it in any backup.")
            Button { model.pokazPresety = true } label: { Label("Presets…", systemImage: "books.vertical") }
                .help("Open the kit preset library.")
            Spacer(minLength: 0)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Biblioteka presetów kitów: lista, zastosowanie na bieżącym kicie,
/// zmiana nazwy, usuwanie, import i eksport pliku (ten sam format co na
/// Androidzie).
struct BibliotekaPresetowView: View {

    @ObservedObject var editor: KitEditor
    @ObservedObject var selection: EditorSelection
    let zamknij: () -> Void

    @State private var lista: [PresetKitu] = BibliotekaPresetow.wczytaj()
    @State private var blad: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kit Presets")
                .font(.title2.weight(.semibold))
            Text("A preset is one kit with its effect, four sounds and WAV file names. System and "
                 + "trigger settings are never included. Presets can be exchanged with the Android editor.")
                .font(Styl.opis)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if lista.isEmpty {
                Text("No presets yet. Choose a kit and click “Save as Preset…”, or import a preset file.")
                    .font(Styl.opis)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List {
                    ForEach(lista) { preset in
                        wiersz(preset)
                    }
                }
                .frame(minHeight: 260)
            }

            if let blad {
                Label(blad, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(Styl.opis)
            }

            HStack {
                Button("Import…", action: importuj)
                Button("Export…", action: eksportuj).disabled(lista.isEmpty)
                Spacer()
                Button("Close", action: zamknij).keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 440)
    }

    private func wiersz(_ preset: PresetKitu) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name).font(Styl.etykieta)
                Text(opis(preset))
                    .font(Styl.opis)
                    .foregroundStyle(.secondary)
                if !preset.pliki.isEmpty {
                    Text("Needs on the card: " + preset.pliki.joined(separator: ", "))
                        .font(Styl.opis)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Apply to Kit \(String(format: "%02d", selection.kit))") { zastosuj(preset) }
                .buttonStyle(.borderedProminent)
            Button("Rename…") { zmienNazwe(preset) }
            Button(role: .destructive) { usun(preset) } label: { Text("Delete") }
        }
        .padding(.vertical, 6)
    }

    /// „DELAY · 001 Acous K · SD: Kick.wav · …"
    private func opis(_ preset: PresetKitu) -> String {
        var czesci: [String] = []
        if let efekt = preset.effect { czesci.append(efekt) }
        czesci += preset.sounds ?? []
        return czesci.joined(separator: " · ")
    }

    // MARK: - Akcje

    private func zachowaj(_ nowa: [PresetKitu]) {
        do {
            try BibliotekaPresetow.zapisz(nowa)
            lista = nowa
            blad = nil
        } catch {
            blad = "Could not save the preset library: \(error.localizedDescription)"
        }
    }

    private func zastosuj(_ preset: PresetKitu) {
        let kit = selection.kit
        let alert = NSAlert()
        alert.messageText = "Apply “\(preset.name)” to kit \(kit)?"
        alert.informativeText = "Kit \(kit) (\(editor.kitName(kit) ?? "—")) will be replaced. You can undo it."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if editor.zastosujPreset(preset, kit: kit) {
            zamknij()
        } else {
            blad = editor.lastError
        }
    }

    private func zmienNazwe(_ preset: PresetKitu) {
        let pole = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        pole.stringValue = preset.name
        let alert = NSAlert()
        alert.messageText = "Rename Preset"
        alert.accessoryView = pole
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = pole
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let nazwa = pole.stringValue.trimmingCharacters(in: .whitespaces)
        guard !nazwa.isEmpty else { return }
        zachowaj(lista.map { p in
            guard p.id == preset.id else { return p }
            var nowy = p
            nowy.name = String(nazwa.prefix(60))
            return nowy
        })
    }

    private func usun(_ preset: PresetKitu) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(preset.name)”?"
        alert.informativeText = "The preset is removed from the library on this Mac."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        zachowaj(lista.filter { $0.id != preset.id })
    }

    private func importuj() {
        let panel = NSOpenPanel()
        panel.title = "Import Kit Presets"
        panel.message = "Choose a preset file saved by the TM-2 editor on a Mac or on Android."
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var nowe = try BibliotekaPresetow.czytaj(Data(contentsOf: url))
            guard !nowe.isEmpty else {
                blad = "No TM-2 kit presets in \(url.lastPathComponent)."
                return
            }
            let zajete = Set(lista.map(\.id))
            for i in nowe.indices where zajete.contains(nowe[i].id) {
                nowe[i].id = PresetKitu.noweID()
            }
            zachowaj(lista + nowe)
        } catch {
            blad = error.localizedDescription
        }
    }

    private func eksportuj() {
        let panel = NSSavePanel()
        panel.title = "Export Kit Presets"
        panel.nameFieldStringValue = "TM2-Kit-Presets.tm2kits.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BibliotekaPresetow.dane(lista).write(to: url, options: .atomic)
            blad = nil
        } catch {
            blad = "Could not export: \(error.localizedDescription)"
        }
    }
}
