import Combine
import Foundation

/// Dziennik zdarzeń.
///
/// W PulsoKicie zakładka Log okazała się najważniejszym narzędziem
/// diagnostycznym — i tu będzie tak samo, tylko z innego powodu. Tam log
/// pokazywał, co poszło po kablu MIDI. Tu pokazuje, co dokładnie zmieniliśmy
/// w pliku i pod jakimi adresami, czyli jest materiałem dowodowym przy
/// rozpracowywaniu formatu.
///
/// Log zostaje w pamięci. Nic nie idzie do sieci — aplikacja z założenia nie
/// łączy się z internetem i niczego nie zbiera.
@MainActor
final class EditorLog: ObservableObject {

    enum Level: String, CaseIterable {
        case info
        case edit
        case undo
        case warning
        case error

        /// Etykieta w interfejsie (po angielsku).
        var displayName: String {
            switch self {
            case .info: return "Info"
            case .edit: return "Edit"
            case .undo: return "Undo"
            case .warning: return "Warning"
            case .error: return "Error"
            }
        }

        var symbolName: String {
            switch self {
            case .info: return "info.circle"
            case .edit: return "pencil"
            case .undo: return "arrow.uturn.backward"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String

        var formattedTime: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: timestamp)
        }
    }

    @Published private(set) var entries: [Entry] = []

    /// Górny limit, żeby długa sesja nie zjadła pamięci.
    private let limit = 5000

    func append(_ level: Level, _ message: String) {
        entries.append(Entry(timestamp: Date(), level: level, message: message))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// Cały log jako tekst — do skopiowania albo zapisania obok plików serii
    /// mapowania. Notatka „co dokładnie zmienione, z jakiej wartości na jaką"
    /// jest wymagana przez protokół, a ręczne przepisywanie jej z ekranu to
    /// prosta droga do pomyłki.
    func plainText() -> String {
        entries
            .map { "\($0.formattedTime)  [\($0.level.rawValue.uppercased())]  \($0.message)" }
            .joined(separator: "\n")
    }
}
