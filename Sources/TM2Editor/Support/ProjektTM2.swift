import Foundation

/// Projekt — folder roboczy o strukturze karty TM-2.
///
/// Pomysł Arka: otwarty backup nie jest edytowany „luzem". Edytor zakłada
/// folder z dokładnie taką strukturą, jakiej moduł oczekuje na karcie:
///
///     <projekt>/ROLAND/TM-2/Backup/BKUP-004.TM0
///     <projekt>/ROLAND/TM-2/WAVE/…sample, których backup używa…
///
/// i wszystko — przypisywanie sampli, mini edytor — dzieje się w nim.
/// Oryginał (na karcie albo gdziekolwiek) zostaje nietknięty. Save As
/// zapisuje całość — backup pod kolejnym numerem i używane sample —
/// w strukturze modułu, na kartę albo do dowolnego folderu.
///
/// Gdzie (zmiana 2026-11-23, prośba Arka — „w tej lokalizacji zakładać od razu
/// całą strukturę i tam pracować"):
///  - backup już w `ROLAND/TM-2/Backup` (karta albo jej kopia) — praca NA
///    MIEJSCU, bez kopiowania; nowe sample idą do tamtejszego WAVE;
///  - backup luzem — obok niego folder `<nazwa> TM-2` ze strukturą karty.
/// Wcześniej projekty lądowały w Dokumenty › TM-2 Editor; dodatkowa kopia
/// w innym miejscu okazała się mniej czytelna niż praca tam, gdzie leży plik.
enum ProjektTM2 {

    // MARK: - Geometria tablic w pliku

    /// Adresy, pod którymi backup trzyma informację o samplach (zmierzone
    /// 2026-11-23 — patrz `KitEditor.poczatekSciezekWav`).
    private static let poczatekKitow = 0x7C
    private static let krokKitu = 234
    private static let poczatekSlotow = 0x42
    private static let krokSlotu = 42
    private static let rozmiarPliku = 124_748

    private static func adresSlotu(_ indeks: Int) -> Int {
        poczatekKitow + (indeks / 4) * krokKitu + poczatekSlotow + (indeks % 4) * krokSlotu
    }

    private static func adresSciezki(_ indeks: Int) -> Int {
        KitEditor.poczatekSciezekWav + indeks * KitEditor.dlugoscSciezkiWav
    }

    /// Ścieżki (względem WAVE) wszystkich sampli z karty, których backup
    /// używa — bez powtórzeń, w kolejności padów.
    static func sciezkiSampli(w bajty: [UInt8]) -> [String] {
        var wynik: [String] = []
        for (_, sciezka) in wpisySampli(w: bajty) where !wynik.contains(sciezka) {
            wynik.append(sciezka)
        }
        return wynik
    }

    /// Pady grające sampel z karty: (indeks padu 0…395, ścieżka).
    static func wpisySampli(w bajty: [UInt8]) -> [(Int, String)] {
        guard bajty.count == rozmiarPliku else { return [] }
        var wynik: [(Int, String)] = []
        for indeks in 0..<(99 * 4) {
            let slot = adresSlotu(indeks)
            guard bajty[slot + 2] == 2, bajty[slot + 3] == 0 else { continue }
            let a = adresSciezki(indeks)
            let tekst = bajty[a..<(a + KitEditor.dlugoscSciezkiWav)].prefix { $0 != 0 }
            guard !tekst.isEmpty else { continue }
            wynik.append((indeks, String(decoding: tekst, as: UTF8.self)))
        }
        return wynik
    }

    // MARK: - Zakładanie projektu

    /// Korzeń struktury karty (folder, w którym leży `ROLAND`), gdy backup
    /// leży w `…/ROLAND/TM-2/Backup/`. `nil` dla pliku luzem.
    static func korzenStruktury(dlaBackupu url: URL) -> URL? {
        guard KartaSD.folderWave(dlaBackupu: url) != nil else { return nil }
        let roland = url.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard roland.lastPathComponent.uppercased() == "ROLAND" else { return nil }
        return roland.deletingLastPathComponent()
    }

    struct Zalozony {
        let backup: URL
        let korzen: URL
        let skopiowane: Int
        let brakujace: [String]
    }

    /// Kopiuje plik i wszystkie sample, których używa, ze `zrodloWave`
    /// (WAVE karty, z której pochodzi backup — jeśli wiadomo).
    /// Zakłada strukturę karty OBOK backupu leżącego luzem:
    /// `<folder pliku>/<nazwa> TM-2/ROLAND/TM-2/{Backup,WAVE}`.
    static func zaloz(dla oryginal: URL, zrodloWave: URL?) throws -> Zalozony {
        let fm = FileManager.default
        let bajty = [UInt8](try Data(contentsOf: oryginal))

        let katalog = oryginal.deletingLastPathComponent()
        let rdzen = (oryginal.lastPathComponent as NSString).deletingPathExtension
        var korzen = katalog.appendingPathComponent("\(rdzen) TM-2", isDirectory: true)
        var numer = 2
        while fm.fileExists(atPath: korzen.path) {
            korzen = katalog.appendingPathComponent("\(rdzen) TM-2 (\(numer))", isDirectory: true)
            numer += 1
        }
        let tm2 = korzen.appendingPathComponent("ROLAND/TM-2", isDirectory: true)
        let backupy = tm2.appendingPathComponent("Backup", isDirectory: true)
        let wave = tm2.appendingPathComponent("WAVE", isDirectory: true)
        try fm.createDirectory(at: backupy, withIntermediateDirectories: true)
        try fm.createDirectory(at: wave, withIntermediateDirectories: true)

        let kopia = backupy.appendingPathComponent(oryginal.lastPathComponent)
        try fm.copyItem(at: oryginal, to: kopia)

        var skopiowane = 0
        var brakujace: [String] = []
        for sciezka in sciezkiSampli(w: bajty) {
            let mozliweZrodlo = zrodloWave?.appendingPathComponent(sciezka)
            guard let zrodlo = mozliweZrodlo, fm.fileExists(atPath: zrodlo.path) else {
                brakujace.append(sciezka)
                continue
            }
            let cel = wave.appendingPathComponent(sciezka)
            try fm.createDirectory(at: cel.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: zrodlo, to: cel)
            skopiowane += 1
        }
        return Zalozony(backup: kopia, korzen: korzen, skopiowane: skopiowane, brakujace: brakujace)
    }

    /// Sample, których backup używa, a których nie ma w folderze WAVE.
    static func brakujaceSample(w bajty: [UInt8], wave: URL) -> [String] {
        sciezkiSampli(w: bajty).filter {
            !FileManager.default.fileExists(atPath: wave.appendingPathComponent($0).path)
        }
    }

    /// Dociąga brakujące sample ze wskazanego miejsca do WAVE projektu.
    ///
    /// Wskazać można kartę (albo jej kopię, ROLAND, TM-2, WAVE) — wtedy
    /// ścieżki są szukane względem jej WAVE — albo dowolny folder z plikami:
    /// wtedy najpierw pełna ścieżka, a gdy jej nie ma, sama nazwa pliku.
    /// Zwraca, czego dalej brakuje.
    static func dociagnij(_ brakujace: [String], zWybranego wybrany: URL,
                          doWave wave: URL) -> (skopiowane: Int, nadal: [String]) {
        let fm = FileManager.default
        let zrodloWave = KartaSD.folderWave(zWybranego: wybrany) ?? wybrany
        var skopiowane = 0
        var nadal: [String] = []
        for sciezka in brakujace {
            let kandydaci = [zrodloWave.appendingPathComponent(sciezka),
                             wybrany.appendingPathComponent(sciezka),
                             wybrany.appendingPathComponent((sciezka as NSString).lastPathComponent)]
            guard let zrodlo = kandydaci.first(where: { fm.fileExists(atPath: $0.path) }) else {
                nadal.append(sciezka)
                continue
            }
            let cel = wave.appendingPathComponent(sciezka)
            do {
                try fm.createDirectory(at: cel.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                try fm.copyItem(at: zrodlo, to: cel)
                skopiowane += 1
            } catch {
                nadal.append(sciezka)
            }
        }
        return (skopiowane, nadal)
    }

    // MARK: - Zapis całości (Save As)

    struct Raport {
        let backup: URL
        var skopiowane = 0
        var pominiete = 0
        var przemianowane: [(String, String)] = []
        var brakujace: [String] = []

        var opis: String {
            var linie = ["Saved \(backup.lastPathComponent) to \(backup.deletingLastPathComponent().path)."]
            linie.append("WAV files: \(skopiowane) copied, \(pominiete) already there.")
            if !przemianowane.isEmpty {
                linie.append("Renamed because a different file had the same name: "
                    + przemianowane.map { "\($0.0) → \($0.1)" }.joined(separator: ", "))
            }
            if !brakujace.isEmpty {
                linie.append("Not found in the project, so not copied: "
                    + brakujace.joined(separator: ", "))
            }
            return linie.joined(separator: "\n")
        }
    }

    /// Folder `ROLAND/TM-2` w miejscu wskazanym przy zapisie. Można wskazać
    /// kartę (albo dowolny folder), ROLAND, TM-2, albo Backup/WAVE wewnątrz TM-2.
    static func tm2Docelowe(zWybranego url: URL) -> URL {
        let nazwa = url.lastPathComponent.uppercased()
        let rodzic = url.deletingLastPathComponent()
        if nazwa == "TM-2" { return url }
        if nazwa == "ROLAND" { return url.appendingPathComponent("TM-2", isDirectory: true) }
        if (nazwa == "BACKUP" || nazwa == "WAVE"), rodzic.lastPathComponent.uppercased() == "TM-2" {
            return rodzic
        }
        return url.appendingPathComponent("ROLAND/TM-2", isDirectory: true)
    }

    /// Kolejny wolny numer `BKUP-NNN.TM0` w folderze Backup.
    static func wolnaNazwaBackupu(w folder: URL) -> String? {
        let istniejace = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let numery = istniejace.compactMap { NazwaZapisu.numerBackupu($0) }
        let nastepny = (numery.max() ?? 0) + 1
        guard nastepny <= 999 else { return nil }
        return String(format: "BKUP-%03d.TM0", nastepny)
    }

    /// Zapisuje backup i używane sample w strukturze modułu.
    ///
    /// Na miejscu docelowym niczego nie kasujemy ani nie nadpisujemy: sampel
    /// o tej samej nazwie i zawartości jest pomijany, o tej samej nazwie
    /// i INNEJ zawartości — kopiowany pod nową nazwą, a ścieżka w zapisanym
    /// backupie poprawiana, żeby pad grał właściwy plik.
    static func zapisz(_ plik: BackupFile, waveProjektu: URL, doTM2 tm2: URL) throws -> Raport {
        let fm = FileManager.default
        let backupy = tm2.appendingPathComponent("Backup", isDirectory: true)
        let wave = tm2.appendingPathComponent("WAVE", isDirectory: true)
        try fm.createDirectory(at: backupy, withIntermediateDirectories: true)
        try fm.createDirectory(at: wave, withIntermediateDirectories: true)
        guard let nazwa = wolnaNazwaBackupu(w: backupy) else {
            throw KartaSD.Blad.konwersja("no free backup number (BKUP-001…999) in \(backupy.path)")
        }

        var kopia = plik
        var raport = Raport(backup: backupy.appendingPathComponent(nazwa))
        var zmianyNazw: [String: String] = [:]

        for sciezka in sciezkiSampli(w: plik.bytes) {
            let zrodlo = waveProjektu.appendingPathComponent(sciezka)
            guard fm.fileExists(atPath: zrodlo.path) else {
                raport.brakujace.append(sciezka)
                continue
            }
            var docelowa = sciezka
            var cel = wave.appendingPathComponent(sciezka)
            if fm.fileExists(atPath: cel.path) {
                if fm.contentsEqual(atPath: zrodlo.path, andPath: cel.path) {
                    raport.pominiete += 1
                    continue
                }
                // Inny plik pod tą nazwą — szukamy wolnej.
                let folder = (sciezka as NSString).deletingLastPathComponent
                let rdzen = ((sciezka as NSString).lastPathComponent as NSString).deletingPathExtension
                var numer = 2
                repeat {
                    let nowa = "\(rdzen)_\(numer).wav"
                    docelowa = folder.isEmpty ? nowa : "\(folder)/\(nowa)"
                    cel = wave.appendingPathComponent(docelowa)
                    numer += 1
                } while fm.fileExists(atPath: cel.path) && numer < 1000
                guard docelowa.utf8.count < KitEditor.dlugoscSciezkiWav else {
                    raport.brakujace.append(sciezka)
                    continue
                }
                zmianyNazw[sciezka] = docelowa
                raport.przemianowane.append((sciezka, docelowa))
            }
            try fm.createDirectory(at: cel.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: zrodlo, to: cel)
            raport.skopiowane += 1
        }

        // Poprawione ścieżki w zapisywanej kopii — tylko w niej; projekt
        // zostaje ze swoimi nazwami.
        for (indeks, sciezka) in wpisySampli(w: plik.bytes) {
            guard let nowa = zmianyNazw[sciezka] else { continue }
            var wpis = [UInt8](repeating: 0, count: KitEditor.dlugoscSciezkiWav)
            let b = Array(nowa.utf8)
            wpis.replaceSubrange(0..<b.count, with: b)
            try kopia.setSlice(wpis, at: adresSciezki(indeks))
        }
        try kopia.write(to: raport.backup)
        return raport
    }
}
