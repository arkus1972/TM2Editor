import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Własny obrazek w tle — trzymany WYŁĄCZNIE na komputerze użytkownika.
///
/// Program nie ma w sobie żadnej grafiki modułu i mieć nie może: zdjęcia
/// produktowe Rolanda należą do Rolanda, więc nie da się ich rozpowszechniać
/// w publicznym repo na licencji MIT ani w każdej kopii aplikacji. Do tego
/// nieoficjalne narzędzie ubrane w oficjalne zdjęcie wyglądałoby jak program
/// producenta.
///
/// Rozwiązanie: użytkownik sam wskazuje obrazek, a edytor kopiuje go do swojego
/// katalogu w Application Support (tego samego, w którym leży opis układu).
/// Obrazek zostaje na tym jednym komputerze — nie trafia do projektu, do repo
/// ani do zbudowanej aplikacji.
@MainActor
final class WlasneTlo: ObservableObject {

    @Published private(set) var obraz: NSImage?

    /// Rdzeń nazwy pliku w katalogu edytora: `tlo.png`, `tlo.jpg` itd.
    private static let rdzen = "tlo"
    private static let rozszerzenia = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]

    init() {
        wczytaj()
    }

    private static var katalog: URL? { LayoutStore.directory }

    private static func istniejacePliki() -> [URL] {
        guard let katalog else { return [] }
        return rozszerzenia
            .map { katalog.appendingPathComponent("\(rdzen).\($0)") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func wczytaj() {
        obraz = Self.istniejacePliki().first.flatMap { NSImage(contentsOf: $0) }
    }

    func wybierz(log: EditorLog) {
        let panel = NSOpenPanel()
        panel.title = "Choose Background Image"
        panel.message = "The image stays on this Mac only. It is copied to the "
            + "editor's own folder and is never added to the project or the app."
        panel.prompt = "Use as Background"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]

        guard panel.runModal() == .OK, let zrodlo = panel.url else { return }

        // Najpierw sprawdzamy, czy to w ogóle da się otworzyć jako obraz —
        // dopiero potem ruszamy cokolwiek na dysku. Inaczej zły plik
        // skasowałby dotychczasowe tło i nic by nie wstawił.
        guard NSImage(contentsOf: zrodlo) != nil else {
            log.append(.error, "Nie da się otworzyć \(zrodlo.lastPathComponent) jako obrazu")
            return
        }
        let rozszerzenie = zrodlo.pathExtension.lowercased()
        guard Self.rozszerzenia.contains(rozszerzenie), let katalog = Self.katalog else {
            log.append(.error, "Nieobsługiwany format obrazu: .\(rozszerzenie)")
            return
        }

        do {
            try FileManager.default.createDirectory(at: katalog,
                                                    withIntermediateDirectories: true)
            for stary in Self.istniejacePliki() {
                try FileManager.default.removeItem(at: stary)
            }
            let cel = katalog.appendingPathComponent("\(Self.rdzen).\(rozszerzenie)")
            try FileManager.default.copyItem(at: zrodlo, to: cel)
            wczytaj()
            log.append(.info, "Ustawiono tło: \(zrodlo.lastPathComponent)"
                + " (kopia tylko na tym komputerze)")
        } catch {
            log.append(.error, "Nie udało się ustawić tła: \(error.localizedDescription)")
            wczytaj()
        }
    }

    func usun(log: EditorLog) {
        let pliki = Self.istniejacePliki()
        guard !pliki.isEmpty else {
            log.append(.info, "Nie było ustawionego tła")
            return
        }
        do {
            for plik in pliki {
                try FileManager.default.removeItem(at: plik)
            }
            log.append(.info, "Usunięto tło")
        } catch {
            log.append(.error, "Nie udało się usunąć tła: \(error.localizedDescription)")
        }
        wczytaj()
    }
}

/// Tło edytora kitu: obrazek przyciszony tak, żeby nie przeszkadzał w czytaniu.
/// Sekcje z parametrami mają własne, nieprzezroczyste tło, więc obrazek widać
/// tylko w marginesach i odstępach między nimi.
struct TloEdytora: View {

    @ObservedObject var tlo: WlasneTlo

    var body: some View {
        if let obraz = tlo.obraz {
            Image(nsImage: obraz)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 460)
                .opacity(0.16)
                .padding(24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Obrazek na ekranie powitalnym — w pełnej krasie, bo tam nie ma czego
/// przysłaniać. Bez ustawionego tła pokazuje dotychczasową ikonę.
struct ObrazPowitalny: View {

    @ObservedObject var tlo: WlasneTlo

    var body: some View {
        if let obraz = tlo.obraz {
            Image(nsImage: obraz)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 360, maxHeight: 300)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        } else {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
        }
    }
}
