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

/// Obrazek pod CAŁYM oknem — ta sama zasada na każdym ekranie.
///
/// Historia tej decyzji: pierwsza wersja kładła obrazek tylko pod panelem
/// parametrów, z założeniem, że będzie go widać „w marginesach". Wystawał
/// strzępami w szczelinach między sekcjami i wyglądał jak błąd wyświetlania.
/// Druga wersja zrobiła z niego miniaturę obok wyświetlacza LCD. Arek: „albo
/// wszędzie, albo nigdzie". Słusznie — tło to tło.
///
/// Teraz obrazek wypełnia całe okno, a panele z parametrami i lista kitów są
/// półprzezroczyste (matowe szkło), więc widać go równo pod wszystkim.
/// Bez ustawionego obrazka nic tu się nie rysuje i program wygląda jak dawniej.
struct TloOkna: View {

    @ObservedObject var tlo: WlasneTlo

    var body: some View {
        GeometryReader { geometria in
            if let obraz = tlo.obraz {
                Image(nsImage: obraz)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometria.size.width, height: geometria.size.height)
                    .clipped()
                    .opacity(0.22)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
