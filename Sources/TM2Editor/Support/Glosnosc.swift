import Foundation

/// Głośność „tak, jak się słyszy" — do wyrównywania sampli między sobą.
///
/// Normalizacja do szczytu tego nie załatwia: krótki klap i długi bas mogą
/// mieć ten sam szczyt, a brzmieć zupełnie inaczej. Tu mierzymy metodą
/// ITU-R BS.1770 (ta sama, której używa radio i mastering — LUFS):
///  1. filtr „K" udający czułość ucha (półka w górze + odcięcie basu),
///  2. średnia moc w oknie 400 ms, przesuwanym co 100 ms,
///  3. wynik = NAJGŁOŚNIEJSZE okno („momentary max").
/// Dla sampli perkusyjnych to najlepsza miara: liczy się uderzenie, a nie
/// cisza po nim. Sampel krótszy niż 400 ms mierzony jest w całości.
enum Glosnosc {

    /// Współczynniki biquada (już podzielone przez a0).
    private struct Filtr {
        let b0, b1, b2, a1, a2: Double

        func zastosuj(_ x: [Double]) -> [Double] {
            var y = [Double](repeating: 0, count: x.count)
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for i in x.indices {
                let x0 = x[i]
                let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                y[i] = y0
                x2 = x1; x1 = x0
                y2 = y1; y1 = y0
            }
            return y
        }
    }

    /// Filtr K dla danej częstotliwości próbkowania — parametry z BS.1770,
    /// przeliczane wzorami z biblioteki libebur128. Przy 48 kHz dają
    /// dokładnie współczynniki z normy (1.53512486, −2.69169619, …), a przy
    /// 44,1 kHz sinus 997 Hz w pełnej skali mierzy −3,01 LUFS, jak powinien.
    /// (Zwykła „półka" z książki kucharskiej RBJ dawała tu −3,27 — błąd 0,26 dB.)
    private static func filtryK(czestotliwosc fs: Double) -> (Filtr, Filtr) {
        // 1. Półka w górze: ok. +4 dB powyżej ok. 1,7 kHz.
        var f0 = 1681.974450955533
        let g = 3.999843853973347
        var q = 0.7071752369554196
        var k = tan(Double.pi * f0 / fs)
        let vh = pow(10, g / 20)
        let vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        let polka = Filtr(
            b0: (vh + vb * k / q + k * k) / a0,
            b1: 2 * (k * k - vh) / a0,
            b2: (vh - vb * k / q + k * k) / a0,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / q + k * k) / a0)

        // 2. Odcięcie basu poniżej ok. 38 Hz.
        f0 = 38.13547087602444
        q = 0.5003270373238773
        k = tan(Double.pi * f0 / fs)
        a0 = 1 + k / q + k * k
        let gornoprzepustowy = Filtr(
            b0: 1, b1: -2, b2: 1,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / q + k * k) / a0)
        return (polka, gornoprzepustowy)
    }

    /// Głośność najgłośniejszego okna 400 ms w LUFS. `nil` dla ciszy.
    static func zmierz(_ probka: ProbkaAudio) -> Double? {
        let n = probka.dlugosc
        guard n > 0 else { return nil }
        let fs = ProbkaAudio.czestotliwosc
        let (polka, gornoprzepustowy) = filtryK(czestotliwosc: fs)
        // Kwadraty po filtrze K, zsumowane po kanałach (wagi 1 dla L i P).
        var moc = [Double](repeating: 0, count: n)
        for kanal in probka.kanaly {
            let k = gornoprzepustowy.zastosuj(polka.zastosuj(kanal.map { Double($0) }))
            for i in 0..<n { moc[i] += k[i] * k[i] }
        }
        // Sumy narastające — każde okno liczone w stałym czasie.
        var suma = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { suma[i + 1] = suma[i] + moc[i] }

        let okno = Swift.min(n, Int(0.4 * fs))
        let krok = Swift.max(1, Int(0.1 * fs))
        var najwieksza = 0.0
        var start = 0
        while start + okno <= n {
            najwieksza = Swift.max(najwieksza, (suma[start + okno] - suma[start]) / Double(okno))
            start += krok
        }
        // Ostatnie okno do samego końca, żeby nic nie umknęło.
        najwieksza = Swift.max(najwieksza, (suma[n] - suma[n - okno]) / Double(okno))
        guard najwieksza > 1e-12 else { return nil }
        return -0.691 + 10 * log10(najwieksza)
    }

    /// Ile dB dodać, żeby sampel miał docelową głośność — ale nie więcej,
    /// niż pozwala zapas do przesteru (szczyt najwyżej −0,3 dBFS).
    /// Zwraca (wzmocnienie, czy ograniczone przez przester).
    static func wzmocnienie(odGlosnosci zmierzona: Double, szczyt: Float,
                            doCelu cel: Double) -> (dB: Double, ograniczone: Bool) {
        let potrzebne = cel - zmierzona
        guard szczyt > 0 else { return (0, false) }
        let zapas = -0.3 - 20 * log10(Double(szczyt))
        return potrzebne > zapas ? (zapas, true) : (potrzebne, false)
    }
}
