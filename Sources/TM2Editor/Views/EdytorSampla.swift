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
    /// Który znacznik jest przeciągany na przebiegu: 0 = Start, 1 = End.
    @State private var przeciagany: Int?
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

    /// Przebieg z zaznaczeniem Start/End, obszarami Fade i krzywą głośności.
    /// Start i End da się też przeciągać myszą prosto na przebiegu.
    private var podgladPrzebiegu: some View {
        let calosc = Swift.max(oryginal.sekundy, 0.000_001)
        let w = wynik
        let kolumnWyniku = Swift.max(1, Int(Double(przebiegOryginalu.count)
            * (ustawienia.koniec - ustawienia.poczatek) / calosc))
        return GeometryReader { geo in
            Przebieg(
                oryginal: przebiegOryginalu,
                wynik: w.przebieg(kolumn: kolumnWyniku),
                od: ustawienia.poczatek / calosc,
                doKonca: ustawienia.koniec / calosc,
                narastanie: ustawienia.narastanieMs / 1000 / calosc,
                wygaszanie: ustawienia.wygaszanieMs / 1000 / calosc
            )
            .contentShape(Rectangle())
            .gesture(przeciaganieZnacznikow(szerokosc: geo.size.width, calosc: calosc))
        }
        .frame(height: 150)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Drag the orange markers to set Start and End.")
    }

    /// Przeciąganie: łapiemy znacznik bliższy miejscu kliknięcia i trzymamy
    /// go do puszczenia przycisku.
    private func przeciaganieZnacznikow(szerokosc: CGFloat, calosc: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { ruch in
                guard szerokosc > 0 else { return }
                let pozycja = Swift.min(Swift.max(Double(ruch.location.x / szerokosc), 0), 1) * calosc
                if przeciagany == nil {
                    let klik = Double(ruch.startLocation.x / szerokosc) * calosc
                    przeciagany = abs(klik - ustawienia.poczatek) <= abs(klik - ustawienia.koniec) ? 0 : 1
                }
                if przeciagany == 0 {
                    ustawienia.poczatek = Swift.min(pozycja, ustawienia.koniec)
                } else {
                    ustawienia.koniec = Swift.max(pozycja, ustawienia.poczatek)
                }
            }
            .onEnded { _ in przeciagany = nil }
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

/// Rysunek przebiegu — wszystko, co mini edytor zrobi z dźwiękiem:
///  - poza Start…End: oryginał przygaszony, na ciemnym tle (to odpadnie),
///  - w zaznaczeniu: WYNIK — już z fade, gain i normalizacją, więc widać,
///    jak dźwięk się zgłaśnia i ścisza; przester na czerwono,
///  - obszary Fade podświetlone na żółto, z krzywą głośności,
///  - Start i End jako pomarańczowe znaczniki z uchwytami.
private struct Przebieg: View {
    let oryginal: [(min: Float, max: Float)]
    let wynik: [(min: Float, max: Float)]
    let od: Double
    let doKonca: Double
    let narastanie: Double
    let wygaszanie: Double

    static let kolorZnacznika = Color(red: 1.0, green: 0.55, blue: 0.1)
    static let kolorFade = Color(red: 1.0, green: 0.85, blue: 0.2)
    static let kolorWyniku = Color(red: 0.35, green: 0.8, blue: 1.0)

    var body: some View {
        Canvas { kontekst, rozmiar in
            rysujOdpadajace(kontekst, rozmiar)
            rysujObszaryFade(kontekst, rozmiar)
            rysujWynik(kontekst, rozmiar)
            rysujKrzywaGlosnosci(kontekst, rozmiar)
            rysujZnaczniki(kontekst, rozmiar)
        }
    }

    private func x(_ ulamek: Double, _ r: CGSize) -> CGFloat {
        CGFloat(Swift.min(Swift.max(ulamek, 0), 1)) * r.width
    }

    private func kreska(_ k: GraphicsContext, x: CGFloat, min: Float, max: Float,
                        r: CGSize, szerokosc: CGFloat, kolor: Color) {
        let srodek = r.height / 2
        var linia = Path()
        linia.move(to: CGPoint(x: x, y: srodek - CGFloat(max) * srodek * 0.95))
        linia.addLine(to: CGPoint(x: x, y: srodek - CGFloat(min) * srodek * 0.95 + 1))
        k.stroke(linia, with: .color(kolor), lineWidth: szerokosc)
    }

    /// Oryginał poza zaznaczeniem — przygaszony, to zostanie odcięte.
    private func rysujOdpadajace(_ k: GraphicsContext, _ r: CGSize) {
        let n = oryginal.count
        guard n > 0 else { return }
        let szer = Swift.max(1, r.width / CGFloat(n))
        for (i, s) in oryginal.enumerated() {
            let pozycja = Double(i) / Double(n)
            guard pozycja < od || pozycja > doKonca else { continue }
            kreska(k, x: CGFloat(i) * r.width / CGFloat(n), min: s.min, max: s.max,
                   r: r, szerokosc: szer, kolor: Color.white.opacity(0.18))
        }
    }

    private func rysujObszaryFade(_ k: GraphicsContext, _ r: CGSize) {
        let kolor = Self.kolorFade.opacity(0.16)
        if narastanie > 0 {
            k.fill(Path(CGRect(x: x(od, r), y: 0,
                               width: x(od + narastanie, r) - x(od, r), height: r.height)),
                   with: .color(kolor))
        }
        if wygaszanie > 0 {
            let a = x(doKonca - wygaszanie, r)
            k.fill(Path(CGRect(x: a, y: 0, width: x(doKonca, r) - a, height: r.height)),
                   with: .color(kolor))
        }
    }

    /// Wynik obróbki rozciągnięty na zaznaczenie — dokładnie to, co pójdzie
    /// na kartę. Przester (pełna skala) na czerwono.
    private func rysujWynik(_ k: GraphicsContext, _ r: CGSize) {
        let n = wynik.count
        guard n > 0 else { return }
        let poczatek = x(od, r)
        let szerokoscZaznaczenia = x(doKonca, r) - poczatek
        let szer = Swift.max(1, szerokoscZaznaczenia / CGFloat(n))
        for (i, s) in wynik.enumerated() {
            let przester = s.max >= 0.999 || s.min <= -0.999
            kreska(k, x: poczatek + CGFloat(i) * szerokoscZaznaczenia / CGFloat(n),
                   min: s.min, max: s.max, r: r, szerokosc: szer,
                   kolor: przester ? Color.red : Self.kolorWyniku)
        }
    }

    /// Krzywa głośności: 0 → pełna na długości Fade in, pełna, pełna → 0 na
    /// długości Fade out. Rysowana symetrycznie — u góry i u dołu.
    private func rysujKrzywaGlosnosci(_ k: GraphicsContext, _ r: CGSize) {
        guard narastanie > 0 || wygaszanie > 0 else { return }
        let srodek = r.height / 2
        let punkty: [(Double, CGFloat)] = [
            (od, narastanie > 0 ? 0 : 1),
            (od + narastanie, 1),
            (doKonca - wygaszanie, 1),
            (doKonca, wygaszanie > 0 ? 0 : 1),
        ]
        for znak in [CGFloat(-1), CGFloat(1)] {
            var linia = Path()
            for (j, p) in punkty.enumerated() {
                let punkt = CGPoint(x: x(p.0, r), y: srodek + znak * p.1 * srodek * 0.95)
                if j == 0 { linia.move(to: punkt) } else { linia.addLine(to: punkt) }
            }
            k.stroke(linia, with: .color(Self.kolorFade), lineWidth: 2)
        }
    }

    /// Start i End: grube pomarańczowe linie z trójkątnymi uchwytami.
    private func rysujZnaczniki(_ k: GraphicsContext, _ r: CGSize) {
        for (ulamek, wPrawo) in [(od, true), (doKonca, false)] {
            let px = x(ulamek, r)
            var linia = Path()
            linia.move(to: CGPoint(x: px, y: 0))
            linia.addLine(to: CGPoint(x: px, y: r.height))
            k.stroke(linia, with: .color(Self.kolorZnacznika), lineWidth: 2.5)
            let kierunek: CGFloat = wPrawo ? 1 : -1
            for y in [CGFloat(0), r.height] {
                let pion: CGFloat = y == 0 ? 1 : -1
                var uchwyt = Path()
                uchwyt.move(to: CGPoint(x: px, y: y))
                uchwyt.addLine(to: CGPoint(x: px + 10 * kierunek, y: y))
                uchwyt.addLine(to: CGPoint(x: px, y: y + 12 * pion))
                uchwyt.closeSubpath()
                k.fill(uchwyt, with: .color(Self.kolorZnacznika))
            }
        }
    }
}
