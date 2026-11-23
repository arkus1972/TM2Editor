import SwiftUI

/// Tools › Even Out Sample Levels… — wyrównanie głośności wszystkich sampli
/// z karty, których używa otwarty backup.
///
/// Prośba Arka: „niektóre sample są głośniejsze i jak się zmienia kit,
/// okazuje się, że jest źle". Mierzymy głośność tak, jak się słyszy
/// (`Glosnosc`, LUFS, najgłośniejsze 400 ms), a nie szczyt — po zwykłym
/// Normalize krótki klap i długi bas dalej brzmią różnie.
///
/// Nic nie jest nadpisywane: każdy zmieniany plik dostaje kopię
/// `<nazwa>_lvl.wav` obok siebie, a pady tego backupu przełączają się na
/// kopie jedną zmianą (jedno Cmd+Z). Wzmocnienie nigdy nie wchodzi
/// w przester — gdy zabraknie zapasu, sampel jest podniesiony tyle, ile się
/// da, i oznaczony.
struct WyrownanieGlosnosci: View {

    @ObservedObject var editor: KitEditor
    let zamknij: () -> Void

    struct Wiersz: Identifiable {
        var id: String { sciezka }
        let sciezka: String
        let pady: Int
        let glosnosc: Double?
        let szczyt: Float
        let probka: ProbkaAudio?
        var wlaczony = true
    }

    @State private var wiersze: [Wiersz] = []
    @State private var cel: Double = -14
    @State private var wczytywanie = true
    @State private var raport: String?

    /// Zmiany poniżej tego progu pomijamy — niesłyszalne, a dałyby nowy plik.
    static let progZmianyDB = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Even Out Sample Levels")
                .font(.title2.weight(.semibold))
            Text("Every card sample used by this backup is measured the way you hear it "
                 + "(loudness of the loudest 0.4 s, in LUFS) and brought to one level. "
                 + "Changed samples are saved as new \"…_lvl.wav\" files next to the originals, "
                 + "and the pads switch to them — one Cmd+Z undoes it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if wczytywanie {
                ProgressView("Measuring samples…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if wiersze.isEmpty {
                Text("This backup uses no samples from the SD card.")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                suwakCelu
                lista
            }

            if let raport {
                Text(raport)
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            przyciski
        }
        .padding(20)
        .frame(width: 680)
        .task { await zmierzWszystko() }
    }

    private var suwakCelu: some View {
        HStack(spacing: 12) {
            Text("Target level")
            Slider(value: $cel, in: -36 ... -3, step: 0.5)
            Text(String(format: "%.1f LUFS", cel))
                .font(.system(.body, design: .monospaced))
                .frame(width: 100, alignment: .trailing)
        }
    }

    private var lista: some View {
        List {
            ForEach($wiersze) { $w in
                wiersz(w, wlaczony: $w.wlaczony)
            }
        }
        .frame(minHeight: 240, maxHeight: 360)
    }

    private func wiersz(_ w: Wiersz, wlaczony: Binding<Bool>) -> some View {
        let plan = planowanaZmiana(w)
        return HStack(spacing: 10) {
            Toggle("", isOn: wlaczony)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(w.sciezka)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(w.pady) pad\(w.pady == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(w.glosnosc.map { String(format: "%.1f LUFS", $0) } ?? "silent / unreadable")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)
            Text(plan.map { String(format: "%+.1f dB", $0.dB) } ?? "—")
                .font(.system(.callout, design: .monospaced))
                .frame(width: 80, alignment: .trailing)
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .opacity(plan?.ograniczone == true ? 1 : 0)
                .help("Cannot be raised that far without clipping — raised as much as possible.")
        }
    }

    private var przyciski: some View {
        HStack {
            Spacer()
            Button("Close", action: zamknij)
                .keyboardShortcut(.cancelAction)
            Button("Even Out") { wyrownaj() }
                .keyboardShortcut(.defaultAction)
                .disabled(wczytywanie || wiersze.allSatisfy { !$0.wlaczony })
        }
    }

    // MARK: - Pomiar i zapis

    private func planowanaZmiana(_ w: Wiersz) -> (dB: Double, ograniczone: Bool)? {
        guard let g = w.glosnosc else { return nil }
        return Glosnosc.wzmocnienie(odGlosnosci: g, szczyt: w.szczyt, doCelu: cel)
    }

    private func zmierzWszystko() async {
        guard let wave = editor.folderWave else {
            wczytywanie = false
            return
        }
        let wpisy = ProjektTM2.wpisySampli(w: editor.file.bytes)
        var pady: [String: Int] = [:]
        for (_, sciezka) in wpisy { pady[sciezka, default: 0] += 1 }
        let sciezki = ProjektTM2.sciezkiSampli(w: editor.file.bytes)

        let wyniki: [Wiersz] = await Task.detached(priority: .userInitiated) {
            sciezki.map { sciezka -> Wiersz in
                let probka = try? ProbkaAudio.wczytaj(wave.appendingPathComponent(sciezka))
                return Wiersz(sciezka: sciezka, pady: pady[sciezka] ?? 0,
                              glosnosc: probka.flatMap { Glosnosc.zmierz($0) },
                              szczyt: probka?.szczyt ?? 0, probka: probka)
            }
        }.value

        wiersze = wyniki
        // Domyślny cel: mediana — głośne w dół, ciche w górę, najmniej zmian.
        let zmierzone = wyniki.compactMap(\.glosnosc).sorted()
        if !zmierzone.isEmpty {
            cel = (zmierzone[zmierzone.count / 2] * 2).rounded() / 2
        }
        wczytywanie = false
    }

    private func wyrownaj() {
        guard let wave = editor.folderWave else { return }
        var mapa: [String: String] = [:]
        var bledy: [String] = []
        var ograniczone = 0
        for w in wiersze where w.wlaczony {
            guard let probka = w.probka, let plan = planowanaZmiana(w),
                  abs(plan.dB) >= Self.progZmianyDB else { continue }
            if plan.ograniczone { ograniczone += 1 }
            let folder = (w.sciezka as NSString).deletingLastPathComponent
            let rdzen = ((w.sciezka as NSString).lastPathComponent as NSString).deletingPathExtension
            let docelowy = folder.isEmpty ? wave : wave.appendingPathComponent(folder)
            do {
                let nazwa = try KartaSD.zapiszNaKarte(probka.zeWzmocnieniem(dB: plan.dB),
                                                      nazwa: rdzen + "_lvl.wav", wave: docelowy)
                mapa[w.sciezka] = folder.isEmpty ? nazwa : "\(folder)/\(nazwa)"
            } catch {
                bledy.append("\(w.sciezka): \(error.localizedDescription)")
            }
        }
        let pady = editor.zamienSciezkiSampli(mapa, opis: "Even Out Sample Levels")
        editor.log.append(.info, "Wyrównano głośność \(mapa.count) sampli (cel "
            + String(format: "%.1f", cel) + " LUFS), \(pady) padów przełączonych")
        var tekst = "\(mapa.count) sample(s) evened out, \(pady) pad(s) switched to the new files."
        if ograniczone > 0 { tekst += " \(ograniczone) raised only as far as clipping allows." }
        if !bledy.isEmpty { tekst += " Errors: " + bledy.joined(separator: "; ") }
        if mapa.isEmpty && bledy.isEmpty { tekst = "Nothing to change — all samples are within 0.5 dB." }
        raport = tekst
    }
}
