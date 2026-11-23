import AVFoundation
import SwiftUI

/// Mini edytor sampla — okno, które pokazuje się po wybraniu pliku z Maca
/// (albo przy „Edit sample" na padzie, który już gra plik z karty).
///
/// Wszystko liczone od oryginału przy każdej zmianie suwaka (`UstawieniaSampla`),
/// więc nie ma kumulowania się błędów ani „cofnij" w środku edytora — wystarczy
/// przesunąć suwak z powrotem. Na kartę idzie wynik zapisany na czysto: WAV
/// 44,1 kHz / 16 bit, bez metadanych.
///
/// Ostrzeżenie o długości i rozmiarze to prośba Arka: za długie i za duże
/// pliki sprawiają na module kłopot. Progi są ostrożne i nie blokują zapisu.
struct EdytorSampla: View {

    let oryginal: ProbkaAudio
    let zatwierdz: (ProbkaAudio, String, Bool) -> Void
    let anuluj: () -> Void

    @State private var ustawienia: UstawieniaSampla
    @State private var nazwa: String
    @State private var odtwarzacz: AVAudioPlayer?
    private let przebiegOryginalu: [(min: Float, max: Float)]

    static let progDlugosci: Double = 30          // sekundy
    static let progRozmiaru = 10 * 1024 * 1024     // bajty

    init(oryginal: ProbkaAudio, nazwaZrodla: String,
         zatwierdz: @escaping (ProbkaAudio, String, Bool) -> Void,
         anuluj: @escaping () -> Void) {
        self.oryginal = oryginal
        self.zatwierdz = zatwierdz
        self.anuluj = anuluj
        _ustawienia = State(initialValue: UstawieniaSampla(dlaDlugosci: oryginal.sekundy))
        _nazwa = State(initialValue: KartaSD.bezpiecznaNazwa(nazwaZrodla))
        przebiegOryginalu = oryginal.przebieg(kolumn: 600)
    }

    private var wynik: ProbkaAudio { ustawienia.zastosuj(do: oryginal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Sample")
                .font(.title2.weight(.semibold))
            podgladPrzebiegu
            suwakiPrzyciecia
            Divider()
            obrobka
            Divider()
            informacje
            poleNazwy
            przyciski
        }
        .padding(20)
        .frame(width: 640)
        .onDisappear { odtwarzacz?.stop() }
    }

    // MARK: - Przebieg

    private var podgladPrzebiegu: some View {
        Przebieg(szczyty: przebiegOryginalu,
                 od: oryginal.sekundy > 0 ? ustawienia.poczatek / oryginal.sekundy : 0,
                 doKonca: oryginal.sekundy > 0 ? ustawienia.koniec / oryginal.sekundy : 1)
            .frame(height: 110)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private var suwakiPrzyciecia: some View {
        VStack(alignment: .leading, spacing: 6) {
            wierszSuwaka("Start", wartosc: $ustawienia.poczatek, zakres: 0...oryginal.sekundy,
                         tekst: String(format: "%.3f s", ustawienia.poczatek))
            wierszSuwaka("End", wartosc: $ustawienia.koniec, zakres: 0...oryginal.sekundy,
                         tekst: String(format: "%.3f s", ustawienia.koniec))
        }
        .onChange(of: ustawienia.poczatek) { nowy in
            if nowy > ustawienia.koniec { ustawienia.koniec = nowy }
        }
        .onChange(of: ustawienia.koniec) { nowy in
            if nowy < ustawienia.poczatek { ustawienia.poczatek = nowy }
        }
    }

    // MARK: - Obróbka

    private var obrobka: some View {
        VStack(alignment: .leading, spacing: 6) {
            wierszSuwaka("Fade in", wartosc: $ustawienia.narastanieMs, zakres: 0...500,
                         tekst: String(format: "%.0f ms", ustawienia.narastanieMs))
            wierszSuwaka("Fade out", wartosc: $ustawienia.wygaszanieMs, zakres: 0...2000,
                         tekst: String(format: "%.0f ms", ustawienia.wygaszanieMs))
            wierszSuwaka("Gain", wartosc: $ustawienia.wzmocnienieDB, zakres: -24...12,
                         tekst: String(format: "%+.1f dB", ustawienia.wzmocnienieDB))
            HStack(spacing: 24) {
                Toggle("Normalize", isOn: $ustawienia.normalizuj)
                    .help("Raise the level so the loudest peak sits just below full scale.")
                if oryginal.liczbaKanalow == 2 {
                    Toggle("Make mono", isOn: $ustawienia.mono)
                        .help("Mix both channels into one — half the size on the card.")
                }
            }
        }
    }

    private func wierszSuwaka(_ etykieta: String, wartosc: Binding<Double>,
                              zakres: ClosedRange<Double>, tekst: String) -> some View {
        HStack(spacing: 12) {
            Text(etykieta)
                .frame(width: 70, alignment: .leading)
            Slider(value: wartosc, in: zakres)
            Text(tekst)
                .font(.system(.body, design: .monospaced))
                .frame(width: 90, alignment: .trailing)
        }
    }

    // MARK: - Informacje i zapis

    private var informacje: some View {
        let w = wynik
        let kanaly = w.liczbaKanalow == 2 ? "stereo" : "mono"
        let mb = Double(w.rozmiarPliku) / (1024 * 1024)
        let przester = w.szczyt >= 0.999
        let zaDuzy = w.sekundy > Self.progDlugosci || w.rozmiarPliku > Self.progRozmiaru
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "%.2f s · %@ · %.2f MB · 44.1 kHz / 16-bit WAV", w.sekundy, kanaly, mb))
                .font(.callout)
            if zaDuzy {
                Label("Long or large files can cause trouble on the TM-2. Consider trimming "
                      + "it or making it mono.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if przester {
                Label("Clipping — lower the gain.", systemImage: "waveform.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var poleNazwy: some View {
        HStack(spacing: 12) {
            Text("File name")
                .frame(width: 70, alignment: .leading)
            TextField("", text: $nazwa)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var przyciski: some View {
        HStack {
            Button(action: odtworz) {
                Label("Play", systemImage: "play.fill")
            }
            Spacer()
            Button("Cancel", role: .cancel, action: anuluj)
                .keyboardShortcut(.cancelAction)
            Button("Copy to Card & Assign") {
                odtwarzacz?.stop()
                let bezZmian = ustawienia.czyBezZmian(dlugoscZrodla: oryginal.sekundy)
                zatwierdz(wynik, nazwa, bezZmian)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(wynik.dlugosc == 0)
        }
    }

    /// Odsłuch na Macu tego, co pójdzie na kartę — z pamięci, bez plików.
    private func odtworz() {
        odtwarzacz?.stop()
        guard let gracz = try? AVAudioPlayer(data: wynik.danePliku()) else { return }
        odtwarzacz = gracz
        gracz.play()
    }
}

/// Rysunek przebiegu: pionowa kreska min–max na kolumnę, części poza
/// zaznaczeniem (Start…End) przyciemnione.
private struct Przebieg: View {
    let szczyty: [(min: Float, max: Float)]
    let od: Double
    let doKonca: Double

    var body: some View {
        Canvas { kontekst, rozmiar in
            let n = szczyty.count
            guard n > 0 else { return }
            let srodek = rozmiar.height / 2
            let szerokosc = rozmiar.width / CGFloat(n)
            for (i, s) in szczyty.enumerated() {
                let x = CGFloat(i) * szerokosc
                let pozycja = Double(i) / Double(n)
                let wZaznaczeniu = pozycja >= od && pozycja <= doKonca
                var linia = Path()
                linia.move(to: CGPoint(x: x, y: srodek - CGFloat(s.max) * srodek))
                linia.addLine(to: CGPoint(x: x, y: srodek - CGFloat(s.min) * srodek + 1))
                kontekst.stroke(linia,
                                with: .color(wZaznaczeniu ? Color.accentColor : Color.secondary.opacity(0.35)),
                                lineWidth: Swift.max(1, szerokosc))
            }
        }
    }
}
