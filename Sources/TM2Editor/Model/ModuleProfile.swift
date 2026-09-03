import Foundation

/// Wszystko, co zależy od konkretnego modelu modułu, w jednym miejscu.
///
/// Wzorzec przeniesiony z PulsoKita. Powód jest ten sam co tam: prędzej czy
/// później pojawi się drugi model (choćby TM-1 albo TM-6 Pro) i nie chcemy
/// wtedy szukać po całym kodzie miejsc, w których na sztywno wpisano „99".
///
/// Ważne rozróżnienie:
///  - `ModuleProfile` opisuje SPRZĘT — fakty z instrukcji, pewne.
///  - `BackupLayout` opisuje PLIK — hipotezy do potwierdzenia serią mapowania.
struct ModuleProfile: Identifiable, Equatable {

    let id: String

    /// Nazwa modelu tak, jak pisze ją Roland.
    let modelName: String

    /// Liczba kitów.
    let kitCount: Int

    /// Liczba fizycznych wejść TRIG IN.
    let triggerInputCount: Int

    /// Liczba triggerów łącznie (wejścia dual-trigger).
    let triggerCount: Int

    /// Liczba brzmień fabrycznych.
    let presetSoundCount: Int

    /// Maksymalna liczba brzmień użytkownika.
    let userSoundCapacity: Int

    /// Czy moduł ma port USB. Dla TM-2: nie ma, i to jest sedno problemu.
    let hasUSB: Bool

    /// Czy Roland opublikował dla tego modelu dokument MIDI Implementation.
    /// Dla TM-2: nie opublikował, więc droga SysEx jest zamknięta.
    let hasPublishedMIDIImplementation: Bool

    /// Czy moduł przyjmuje Program Change jako wybór kitu.
    let acceptsProgramChange: Bool

    /// Zakres numerów Program Change wybierających kit.
    let programChangeRange: ClosedRange<Int>?

    /// Fragmenty nazwy portu MIDI, po których rozpoznajemy moduł.
    ///
    /// To jest wprost odpowiedź na pułapkę opisaną w dokumencie startowym:
    /// PulsoKit szuka „TD-17"/„TD-27", więc przy podłączonym TM-2 zostaje przy
    /// profilu TD-17 i pozwala na zapis. Tutaj rozpoznanie jest jawne, a przy
    /// braku dopasowania aplikacja NIE zgaduje profilu.
    let portNameHints: [String]

    /// Znane wersje systemu.
    let knownSystemVersions: [String]

    static let tm2 = ModuleProfile(
        id: "roland.tm2",
        modelName: "Roland TM-2",
        kitCount: 99,
        triggerInputCount: 2,
        triggerCount: 4,
        presetSoundCount: 162,
        userSoundCapacity: 90_300,
        hasUSB: false,
        hasPublishedMIDIImplementation: false,
        acceptsProgramChange: true,
        programChangeRange: 1...99,
        portNameHints: ["TM-2", "TM2"],
        knownSystemVersions: ["1.02", "1.03"]
    )

    /// Czy dla tego modelu w ogóle ma sens tryb pracy „na żywym module".
    ///
    /// Dla TM-2 odpowiedź brzmi „nie" i aplikacja ma to mówić wprost, zamiast
    /// udawać, że da się czytać parametry po MIDI. Jedyny tryb to praca na
    /// pliku BACKUP z karty SD.
    var supportsLiveEditing: Bool {
        hasPublishedMIDIImplementation
    }

    /// Zdanie wyświetlane użytkownikowi, kiedy szuka trybu online.
    /// Interfejs jest po angielsku.
    var liveEditingExplanation: String {
        if supportsLiveEditing {
            return "Live editing over MIDI is supported."
        }
        return """
        \(modelName) has no USB port and Roland never published a MIDI \
        Implementation document for it. The only documented incoming message \
        is Program Change \(programChangeRangeText), which selects a kit. \
        There is no way to read or write individual parameters over MIDI, so \
        this editor works on BACKUP files from the SD card instead.
        """
    }

    private var programChangeRangeText: String {
        guard let range = programChangeRange else { return "" }
        return "\(range.lowerBound)–\(range.upperBound)"
    }

    /// Czy nazwa portu MIDI pasuje do tego modelu.
    func matches(portName: String) -> Bool {
        let upper = portName.uppercased()
        return portNameHints.contains { upper.contains($0.uppercased()) }
    }
}
