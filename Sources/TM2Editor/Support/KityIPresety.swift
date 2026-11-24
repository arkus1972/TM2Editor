import Foundation

// Kity jako całość: nowy backup, presety kitów (biblioteka) i ich plik.
//
// Pomysły podpatrzone w cudzym edytorze HTML (porównanie: Projekt, dokument
// 06) — kod napisany od nowa, na naszych pomiarach. Format pliku presetów
// jest WSPÓLNY z wersją na Androida (TM2Editor-Android), więc presety
// zapisane na telefonie da się wczytać na Macu i odwrotnie.

// MARK: - Nowy backup

enum NowyBackup {

    /// Nagłówek 0x00–0x7B z backupu Arka (`baza-2026-11-21.bin`): nazwa
    /// „Backup", wskaźnik kitu 0, ustawienia SYSTEM i wejść jak na jego module.
    static let wzorNaglowka = "VE0tMgAAAABCS0JhY2t1cCAgAAAAAAMBcAAAAAIAAAAAAAAAAAAAAAIAAAAEBwAYAAEACQEBAAAAAAAAAAAAAAAgCA8AJAkMKAAAAgAAAAAaDAcAIAYMKAAKAAAAAAEaDAcAIAYMKAAKAAAAAAAaDAcAIAYMKAAKAAAAAA=="

    /// Kit „New Kit" dokładnie tak, jak trzyma go moduł — kity 52–99 tego
    /// samego backupu są co do bajtu identyczne (efekt REVERB z wartościami
    /// domyślnymi, cztery brzmienia, Level 90, Pan na środku).
    static let wzorKitu = "TgBlAHcAIABLAGkAdAAgACAAIAAgAAEAEwACAB4AAAABAAcACgAKAGQAZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAFoAAAAPAAAAJAAAAAAAAQAAAP//AAAAAAAAAAAAAAAAAAAAAAAAPgABAFoAAAAPAAAAIwAAAAAAAQAAAP//AAAAAAAAAAAAAAAAAAAAAAAAXgABAFoAAAAPAAAAJgAAAAAAAQAAAP//AAAAAAAAAAAAAAAAAAAAAAAAQwABAFoAAAAPAAAAKAAAAAAAAQAAAP//AAAAAAAAAAAAAAAAAAAAAAAA"

    static let rozmiar = 124_748
    static let poczatekKitow = 0x7C
    static let krokKitu = 234
    static let wskaznikKitu = 0x36

    /// 99 × „New Kit", pusta tablica sampli, poprawna suma MD5. Ustawienia
    /// SYSTEM i wejść z `naglowekZ` (np. z otwartego backupu), jeśli podany.
    static func bajty(naglowekZ zrodlo: [UInt8]? = nil) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: rozmiar)
        let naglowek: [UInt8]
        if let zrodlo, zrodlo.count >= poczatekKitow {
            naglowek = Array(zrodlo[0..<poczatekKitow])
        } else {
            naglowek = [UInt8](Data(base64Encoded: wzorNaglowka) ?? Data())
        }
        b.replaceSubrange(0..<naglowek.count, with: naglowek)
        b[wskaznikKitu] = 0
        let kit = [UInt8](Data(base64Encoded: wzorKitu) ?? Data())
        for k in 0..<99 {
            let od = poczatekKitow + k * krokKitu
            b.replaceSubrange(od..<(od + kit.count), with: kit)
        }
        let suma = Checksum.md5(b[0..<(rozmiar - 16)])
        b.replaceSubrange((rozmiar - 16)..<rozmiar, with: suma)
        return b
    }
}

// MARK: - Presety kitów

/// Jeden kit zapisany do biblioteki: blok 234 B (nazwa, efekt, 4 sloty)
/// i cztery ścieżki WAV. Bez ustawień SYSTEM i wejść — te są globalne.
struct PresetKitu: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var saved: String?
    var sourceKit: Int?
    var effect: String?
    var sounds: [String]?
    /// Blok kitu, base64.
    var kit: String
    /// Ścieżki względem ROLAND/TM-2/WAVE (puste, gdy pad nie ma pliku).
    var paths: [String]

    /// Blok kitu, gdy preset jest poprawny.
    var bajtyKitu: [UInt8]? {
        guard let d = Data(base64Encoded: kit), d.count == NowyBackup.krokKitu else { return nil }
        return [UInt8](d)
    }

    var poprawny: Bool {
        bajtyKitu != nil && paths.count == 4 && paths.allSatisfy { sciezka in
            sciezka.utf8.count < KitEditor.dlugoscSciezkiWav
                && sciezka.utf8.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
        }
    }

    /// Pliki WAV, które muszą być na karcie, żeby preset grał.
    var pliki: [String] { paths.filter { !$0.isEmpty } }

    static func noweID() -> String {
        "p" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    }
}

enum BibliotekaPresetow {

    static let format = "TM2Editor-KitPresets"

    private struct Plik: Codable {
        var format: String
        var version: Int
        var exported: String?
        var presets: [PresetKitu]
    }

    /// Biblioteka na tym Macu: ~/Library/Application Support/TM2Editor/.
    static var url: URL {
        let wsparcie = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return wsparcie.appendingPathComponent("TM2Editor/presety.tm2kits.json")
    }

    static func wczytaj() -> [PresetKitu] {
        guard let dane = try? Data(contentsOf: url) else { return [] }
        return (try? czytaj(dane)) ?? []
    }

    static func zapisz(_ lista: [PresetKitu]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try dane(lista).write(to: url, options: .atomic)
    }

    /// Plik biblioteki — ten sam format co na Androidzie.
    static func dane(_ lista: [PresetKitu]) throws -> Data {
        let koder = JSONEncoder()
        koder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try koder.encode(Plik(format: format, version: 1,
                                     exported: ISO8601DateFormatter().string(from: Date()),
                                     presets: lista))
    }

    enum Blad: LocalizedError {
        case toNiePresety
        var errorDescription: String? { "This is not a TM-2 kit preset file." }
    }

    /// Odczyt pliku presetów (z Maca albo z Androida). Zwraca tylko poprawne.
    static func czytaj(_ dane: Data) throws -> [PresetKitu] {
        let dekoder = JSONDecoder()
        let lista: [PresetKitu]
        if let plik = try? dekoder.decode(Plik.self, from: dane) {
            guard plik.format == format else { throw Blad.toNiePresety }
            lista = plik.presets
        } else if let goly = try? dekoder.decode([PresetKitu].self, from: dane) {
            lista = goly
        } else {
            throw Blad.toNiePresety
        }
        return lista.filter(\.poprawny)
    }
}
