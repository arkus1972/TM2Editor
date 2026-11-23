import SwiftUI

/// Jedne czcionki dla wszystkich wierszy parametrów (prośba Arka:
/// „ujednolicić czcionki"). Wcześniej każdy rodzaj wiersza miał swoje:
/// liczby `title2` o stałej szerokości, opisy `caption`, listy domyślną
/// czcionkę systemu — obok siebie wyglądało to jak trzy różne programy.
enum Styl {
    /// Nazwa parametru.
    static let etykieta: Font = .title3
    /// Opis pod nazwą: zakres, lista pozycji, wyjaśnienie.
    static let opis: Font = .callout
    /// Wartość w kontrolce — lista, pole tekstowe.
    static let wartosc: Font = .title3
    /// Wartość liczbowa — ta sama wielkość, cyfry równej szerokości, żeby
    /// liczby w kolejnych wierszach stały równo.
    static let liczba: Font = .title3.monospacedDigit()
}
