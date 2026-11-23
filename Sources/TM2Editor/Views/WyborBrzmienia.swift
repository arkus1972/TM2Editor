import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Wybór brzmienia padu: jedno ze 162 wewnętrznych albo plik z karty.
///
/// Lista pokazuje brzmienia wewnętrzne; gdy pad gra sampel z karty, na górze
/// listy stoi jego nazwa z ikoną karty. Obok dwa przyciski:
///  - plik z Maca (WAV, AIFF, MP3, M4A, FLAC, OGG) → mini edytor → karta,
///  - edycja sampla, który pad już gra (nowy plik, oryginał zostaje).
/// Przypisanie to jedna zmiana — jedno Cmd+Z. Pliki skopiowane na kartę
/// zostają (edytor z karty nic nie kasuje).
struct WyborBrzmienia: View {

    @ObservedObject var editor: KitEditor
    let kit: Int
    let trigger: Int

    /// Plik otwarty w mini edytorze, razem z miejscem, do którego ma trafić.
    struct Edycja: Identifiable {
        let id = UUID()
        let probka: ProbkaAudio
        let nazwa: String
        /// Ścieżka w WAVE, gdy źródło już tam leży w formacie modułu —
        /// wtedy bez zmian w edytorze nic nie kopiujemy.
        let gotowaSciezka: String?
        let kit: Int
        let trigger: Int
    }

    @State private var edycja: Edycja?

    /// Znacznik wyboru oznaczający „plik z karty" — nie jest numerem brzmienia.
    private static let tagSampla = -1

    var body: some View {
        HStack(spacing: 6) {
            lista
            przyciskPliku
            if editor.sciezkaSampla(kit: kit, trigger: trigger) != nil {
                przyciskEdycji
            }
        }
        .sheet(item: $edycja) { e in
            EdytorSampla(
                oryginal: e.probka,
                nazwaZrodla: e.nazwa,
                zatwierdz: { wynik, nazwa, bezZmian in
                    edycja = nil
                    zapisz(wynik, nazwa: nazwa, bezZmian: bezZmian, edycja: e)
                },
                anuluj: { edycja = nil }
            )
        }
    }

    private var lista: some View {
        Picker("", selection: wybor) {
            if let sciezka = editor.sciezkaSampla(kit: kit, trigger: trigger) {
                Label(sciezka, systemImage: "sdcard").tag(Self.tagSampla)
                Divider()
            }
            ForEach(Array(Instrumenty.nazwy.enumerated()), id: \.offset) { numer, nazwa in
                Text(nazwa).tag(numer)
            }
        }
        .labelsHidden()
        .controlSize(.large)
        .font(Styl.wartosc)
    }

    private var przyciskPliku: some View {
        Button(action: wybierzPlik) {
            Image(systemName: "waveform.badge.plus")
        }
        .controlSize(.large)
        .help("Assign an audio file from your Mac (WAV, AIFF, MP3, M4A, FLAC, OGG). "
              + "You can trim and adjust it before it is copied to the SD card.")
    }

    private var przyciskEdycji: some View {
        Button(action: edytujBiezacy) {
            Image(systemName: "scissors")
        }
        .controlSize(.large)
        .help("Edit the sample this pad plays. The result is saved as a new file; "
              + "the original on the card is not changed.")
    }

    private var wybor: Binding<Int> {
        Binding(
            get: {
                editor.sciezkaSampla(kit: kit, trigger: trigger) != nil
                    ? Self.tagSampla
                    : editor.numerBrzmienia(kit: kit, trigger: trigger)
            },
            set: { numer in
                guard numer >= 0 else { return }
                editor.ustawBrzmienieWewnetrzne(numer: numer, kit: kit, trigger: trigger)
            }
        )
    }

    // MARK: - Akcje

    /// Folder WAVE: znany z położenia backupu albo zapamiętany; jeśli żadnego
    /// nie ma, pytamy raz o kartę (lub jej kopię) i zapamiętujemy odpowiedź.
    private func ustalFolderWave() -> URL? {
        if let wave = editor.folderWave { return wave }
        let panel = NSOpenPanel()
        panel.title = "Where Is Your SD Card?"
        panel.message = "This backup is not inside a ROLAND/TM-2 folder, so the editor does not know "
            + "where to put the WAV files. Choose the SD card, or a copy of its ROLAND folder. "
            + "The editor remembers your choice."
        panel.prompt = "Use This Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let wybrany = panel.url else { return nil }
        guard let wave = KartaSD.folderWave(zWybranego: wybrany) else {
            pokazKomunikat("There is no ROLAND/TM-2 folder in \(wybrany.lastPathComponent). "
                + KartaSD.Blad.nieNaKarcie.localizedDescription)
            return nil
        }
        KartaSD.zapamietanyFolderWave = wave
        editor.log.append(.info, "Sample będą zapisywane do \(wave.path)")
        return wave
    }

    private func wybierzPlik() {
        guard let wave = ustalFolderWave() else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an Audio File"
        panel.message = "WAV, AIFF, MP3, M4A, FLAC and OGG are converted to what the TM-2 plays. "
            + "Your original file is not changed."
        panel.prompt = "Open"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var typy: [UTType] = [.audio]
        if let ogg = UTType(filenameExtension: "ogg") { typy.append(ogg) }
        panel.allowedContentTypes = typy
        guard panel.runModal() == .OK, let zrodlo = panel.url else { return }

        // Plik spoza WAVE projektu — najpierw zgoda (prośba Arka). Na kartę
        // i tak idzie kopia zapisana na czysto; oryginał zostaje na miejscu.
        if KartaSD.sciezkaWzgledna(zrodlo, wave: wave) == nil {
            let alert = NSAlert()
            alert.messageText = "Copy \(zrodlo.lastPathComponent) into the project?"
            alert.informativeText = "The file is outside the project's WAVE folder. The editor will "
                + "save a copy there as 44.1 kHz / 16-bit WAV (after you edit it, if you like). "
                + "Your original file stays where it is."
            alert.addButton(withTitle: "Copy and Edit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        otworzWEdytorze(zrodlo, wave: wave)
    }

    private func edytujBiezacy() {
        guard let sciezka = editor.sciezkaSampla(kit: kit, trigger: trigger),
              let wave = ustalFolderWave() else { return }
        let plik = wave.appendingPathComponent(sciezka)
        guard FileManager.default.fileExists(atPath: plik.path) else {
            pokazKomunikat("The file WAVE/\(sciezka) is not on this card.")
            return
        }
        otworzWEdytorze(plik, wave: wave)
    }

    private func otworzWEdytorze(_ zrodlo: URL, wave: URL) {
        do {
            let probka = try ProbkaAudio.wczytaj(zrodlo)
            var gotowa: String?
            if KartaSD.czyFormatModulu(zrodlo),
               let wzgledna = KartaSD.sciezkaWzgledna(zrodlo, wave: wave),
               wzgledna.allSatisfy({ $0.isASCII }) {
                gotowa = wzgledna
            }
            // Kit i trigger zapamiętane teraz: przypisanie ma trafić tam,
            // gdzie kliknięto, nawet gdyby w tle zmieniło się zaznaczenie.
            edycja = Edycja(probka: probka, nazwa: zrodlo.lastPathComponent,
                            gotowaSciezka: gotowa, kit: kit, trigger: trigger)
        } catch {
            editor.log.append(.error, "Nie udało się wczytać \(zrodlo.lastPathComponent):"
                + " \(error.localizedDescription)")
            pokazKomunikat(error.localizedDescription)
        }
    }

    private func zapisz(_ probka: ProbkaAudio, nazwa: String, bezZmian: Bool, edycja e: Edycja) {
        guard let wave = editor.folderWave else {
            pokazKomunikat(KartaSD.Blad.nieNaKarcie.localizedDescription)
            return
        }
        do {
            let sciezka: String
            if bezZmian, let gotowa = e.gotowaSciezka {
                sciezka = gotowa
            } else {
                sciezka = try KartaSD.zapiszNaKarte(probka, nazwa: nazwa, wave: wave)
                editor.log.append(.info, "Zapisano na kartę WAVE/\(sciezka)"
                    + String(format: " (%.2f s, %ld kB)", probka.sekundy, probka.rozmiarPliku / 1024))
            }
            if !editor.przypiszSampel(sciezka: sciezka, kit: e.kit, trigger: e.trigger),
               let komunikat = editor.lastError {
                pokazKomunikat(komunikat)
            }
        } catch {
            editor.log.append(.error, "Nie udało się zapisać sampla: \(error.localizedDescription)")
            pokazKomunikat(error.localizedDescription)
        }
    }

    private func pokazKomunikat(_ tekst: String) {
        let alert = NSAlert()
        alert.messageText = "Cannot assign the file"
        alert.informativeText = tekst
        alert.alertStyle = .warning
        alert.runModal()
    }
}
