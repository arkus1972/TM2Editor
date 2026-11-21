import SwiftUI

/// Co jest w tej chwili wybrane w interfejsie: kit i trigger.
///
/// Zaznaczenie jest celowo OSOBNYM obiektem, a nie częścią `KitEditor`.
/// Dopóki siedziało w edytorze, kliknięcie w trigger ogłaszało zmianę
/// *dokumentu*. A `AppModel` przekazuje zmiany edytora dalej do siebie
/// (żeby Undo/Redo w menu nie było wyszarzone), więc jedno kliknięcie
/// przebudowywało całe okno: pasek nagłówka, zakładki, splitter, listę
/// 99 kitów i prawy panel — mimo że ani jeden bajt pliku się nie ruszył.
///
/// Teraz zmiana zaznaczenia dociera tylko do tych widoków, które od niego
/// faktycznie zależą. Edytor zajmuje się plikiem, ten obiekt — zaznaczeniem.
@MainActor
final class EditorSelection: ObservableObject {

    /// Wybrany kit, numerowany od 1 — tak jak w module.
    @Published var kit: Int = 1

    /// Wybrany trigger, numerowany od 1.
    @Published var trigger: Int = 1

    /// Nowy plik zaczyna się od pierwszego kitu i pierwszego triggera.
    func reset() {
        kit = 1
        trigger = 1
    }
}
