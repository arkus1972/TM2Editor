import SwiftUI

/// Wyświetlacz w stylu podświetlanego ekranu LCD: numer i nazwa kitu oraz
/// wybrana strefa triggera.
///
/// Nawiązuje do charakteru sprzętu — pomarańczowe podświetlenie, ciemne znaki
/// stałej szerokości — ale go nie kopiuje: to zwykły, ogólny styl ekranu
/// znakowego, a nie odwzorowanie panelu konkretnego urządzenia.
///
/// Pełni też praktyczną funkcję: przy przewijaniu długiej listy parametrów
/// od razu widać, NA CZYM się pracuje. Wczorajsza pomyłka „Level się nie
/// zgadza" wzięła się właśnie z tego, że edytor stał na innym kicie, niż się
/// wydawało.
struct WyswietlaczLCD: View {

    let kit: Int
    let nazwa: String?
    let strefa: String

    private let podswietlenie = Color(red: 0.99, green: 0.56, blue: 0.18)
    private let podswietlenieCien = Color(red: 0.93, green: 0.45, blue: 0.10)
    private let znaki = Color(red: 0.16, green: 0.07, blue: 0.02)

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Text("KIT")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                Text(String(format: "%02d", kit))
                    .font(.system(size: 44, weight: .heavy, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(nazwa ?? "—")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(strefa.uppercased())
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .opacity(0.7)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(znaki)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [podswietlenie, podswietlenieCien],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            // Wpuszczona ramka, jak szyba osadzona w obudowie.
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.black.opacity(0.55), lineWidth: 3)
        )
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kit \(kit), \(nazwa ?? "unnamed"), \(strefa)")
    }
}
