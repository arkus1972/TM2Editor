import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Wybór brzmienia padu: jedno ze 162 wewnętrznych albo plik WAV z karty.
///
/// Lista pokazuje brzmienia wewnętrzne; gdy pad gra sampel z karty, na górze
/// listy stoi jego nazwa z ikoną karty. Przycisk obok wybiera plik z Maca —
/// edytor przerabia go w razie potrzeby na format modułu (44,1 kHz / 16 bit),
/// kopiuje do `ROLAND/TM-2/WAVE` na karcie i wpisuje ścieżkę do backupu.
/// Wszystko jako jedna zmiana: jedno Cmd+Z cofa przypisanie (skopiowany plik
/// zostaje na karcie — edytor z karty nic nie kasuje).
struct WyborBrzmienia: View {

    @ObservedObject var editor: KitEditor
    let kit: Int
    let trigger: Int

    /// Znacznik wyboru oznaczający „plik z karty" — nie jest numerem brzmienia.
    private static let tagSampla = -1

    var body: some View {
        HStack(spacing: 6) {
            lista
            przyciskPliku
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
    }

    private var przyciskPliku: some View {
        Button(action: wybierzPlik) {
            Image(systemName: "waveform.badge.plus")
        }
        .controlSize(.large)
        .help("Assign an audio file from your Mac. It is converted to 44.1 kHz / 16-bit WAV "
              + "if needed and copied to ROLAND/TM-2/WAVE on the SD card.")
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

    private func wybierzPlik() {
        guard let wave = editor.folderWave else {
            pokazBlad(KartaSD.Blad.nieNaKarcie)
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose an Audio File"
        panel.message = "WAV, AIFF, MP3 and other formats are converted to what the TM-2 plays. "
            + "Your original file is not changed."
        panel.prompt = "Assign to Pad"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let zrodlo = panel.url else { return }

        // Wybór kitu/triggera zapamiętany teraz — panel jest modalny, ale
        // przypisanie ma trafić tam, gdzie użytkownik kliknął przycisk.
        let cel = (kit: kit, trigger: trigger)
        do {
            let wynik = try KartaSD.przygotuj(zrodlo: zrodlo, wave: wave)
            if wynik.przerobiony {
                editor.log.append(.info, "Przerobiono \(zrodlo.lastPathComponent) na WAV"
                    + " 44,1 kHz / 16 bit → WAVE/\(wynik.sciezka)")
            } else {
                editor.log.append(.info, "Sampel na karcie: WAVE/\(wynik.sciezka)")
            }
            if !editor.przypiszSampel(sciezka: wynik.sciezka, kit: cel.kit, trigger: cel.trigger),
               let komunikat = editor.lastError {
                pokazKomunikat(komunikat)
            }
        } catch {
            editor.log.append(.error, "Nie udało się przygotować sampla:"
                + " \(error.localizedDescription)")
            pokazBlad(error)
        }
    }

    private func pokazBlad(_ blad: Error) {
        pokazKomunikat(blad.localizedDescription)
    }

    private func pokazKomunikat(_ tekst: String) {
        let alert = NSAlert()
        alert.messageText = "Cannot assign the file"
        alert.informativeText = tekst
        alert.alertStyle = .warning
        alert.runModal()
    }
}
