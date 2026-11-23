import AppKit
import SwiftUI

/// Pole liczbowe: duża wartość do wpisania z klawiatury i przyciski −/+ obok.
///
/// Zastępuje suwaki. Te pojawiały się tylko przy części pól (przy dużych
/// zakresach znikały), więc wiersze miały różne szerokości i ekran wyglądał
/// nierówno — a przy zakresach typu 0…3000 i tak nie dało się suwakiem trafić
/// w konkretną wartość. Tutaj każda liczba wygląda tak samo, bez względu na
/// zakres.
///
/// Wpisuje się to, co pokazuje moduł: „R15", „CENTER", „300.0 ms", „OFF".
/// Tekst, którego nie da się odczytać jednoznacznie albo który wypada poza
/// zakresem, jest ODRZUCANY (krótki sygnał dźwiękowy, wraca poprzednia
/// wartość) — nigdy po cichu przycinany ani zaokrąglany.
struct PoleLiczbowe: View {

    let wartosc: Int
    let zakres: ClosedRange<Int>
    let wyswietlanie: FieldDisplay
    let ustaw: (Int) -> Void

    /// Meldunek dla edytora o liczbie wpisanej, a jeszcze niezatwierdzonej —
    /// żeby „Save As…" kliknięte bez Entera zapisało to, co widać na ekranie.
    let zapamietajNiezatwierdzone: (Int) -> Void
    let zapomnijNiezatwierdzone: () -> Void

    @State private var tekst = ""
    @FocusState private var maFokus: Bool

    /// Dokąd zapisać wpisaną wartość. Ustalane w chwili, gdy pole dostaje
    /// fokus, a nie w chwili zatwierdzenia.
    ///
    /// Wiersze pól liczbowych NIE są tworzone od nowa przy zmianie kitu ani
    /// triggera (to kosztowało czas przy przełączaniu). Bez tego zapamiętania
    /// liczba wpisana dla kitu 3 i zatwierdzona dopiero po kliknięciu kitu 7
    /// trafiłaby do kitu 7.
    @State private var celEdycji: ((Int) -> Void)?

    /// Ustawiane na chwilę, gdy to program, a nie użytkownik, zmienia tekst
    /// w polu. Bez tego wpisanie zatwierdzonej wartości z powrotem do pola
    /// meldowałoby ją edytorowi jako „wpisaną, niezatwierdzoną" — i przycisk
    /// zapisu świeciłby się, choć nie ma nic do zapisania.
    @State private var zmianaProgramowa = false

    // Ciało rozbite na części celowo. Na macos-15 (nowszy kompilator) jedno
    // długie wyrażenie — pole tekstowe z siedmioma modyfikatorami, stepper
    // i podpowiedź sklejana pięcioma „+" — kończyło się błędem „unable to
    // type-check this expression in reasonable time". Stary kompilator to
    // przepuszczał. Osobne właściwości z jawnym typem dają mu krótkie kawałki.
    var body: some View {
        HStack(spacing: 8) {
            poleTekstowe
            stepper
        }
    }

    private var poleTekstowe: some View {
        TextField("", text: $tekst)
            .font(Styl.liczba)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .focused($maFokus)
            .onSubmit { zatwierdz() }
            .onChange(of: maFokus) { fokus in zmianaFokusu(fokus) }
            .onChange(of: tekst) { nowy in zmianaTekstu(nowy) }
            .onChange(of: wartosc) { nowa in zmianaWartosci(nowa) }
            .onAppear { pokaz(wyswietlanie.text(for: wartosc)) }
            .help(podpowiedz)
    }

    private var stepper: some View {
        Stepper("", value: wiazanieSteppera, in: zakres)
            .labelsHidden()
            .controlSize(.large)
    }

    private var wiazanieSteppera: Binding<Int> {
        Binding(get: { wartosc }, set: { ustaw($0) })
    }

    private var podpowiedz: String {
        let od: String = wyswietlanie.text(for: zakres.lowerBound)
        let doo: String = wyswietlanie.text(for: zakres.upperBound)
        return "Type a value as the module shows it, e.g. \(przyklad). Range: \(od) … \(doo)."
    }

    private func zmianaFokusu(_ fokus: Bool) {
        if fokus {
            celEdycji = ustaw
        } else {
            zatwierdz()
        }
    }

    private func zmianaTekstu(_ nowy: String) {
        if zmianaProgramowa {
            zmianaProgramowa = false
            return
        }
        guard maFokus else { return }
        if let liczba = wyswietlanie.parse(nowy), zakres.contains(liczba) {
            zapamietajNiezatwierdzone(liczba)
        } else {
            zapomnijNiezatwierdzone()
        }
    }

    /// Zmiana z zewnątrz (−/+, cofnięcie, inny kit) — ale nie w trakcie
    /// pisania, żeby nie wyrywać użytkownikowi tekstu.
    private func zmianaWartosci(_ nowa: Int) {
        if !maFokus { pokaz(wyswietlanie.text(for: nowa)) }
    }

    private var przyklad: String {
        wyswietlanie.text(for: min(max(wartosc, zakres.lowerBound), zakres.upperBound))
    }

    private func zatwierdz() {
        let cel = celEdycji ?? ustaw
        celEdycji = nil
        zapomnijNiezatwierdzone()

        guard let liczba = wyswietlanie.parse(tekst), zakres.contains(liczba) else {
            // Odmowa, nie poprawka. Nietknięty tekst odczytuje się dokładnie
            // jako bieżąca wartość, więc sygnał pada tylko przy prawdziwym
            // błędzie — w tym przy pustym polu.
            NSSound.beep()
            pokaz(wyswietlanie.text(for: wartosc))
            return
        }
        if liczba != wartosc { cel(liczba) }
        pokaz(wyswietlanie.text(for: liczba))
    }

    private func pokaz(_ nowy: String) {
        // Bez zmiany tekstu SwiftUI nie wywoła onChange i flaga zostałaby
        // zapalona do następnego naciśnięcia klawisza.
        guard nowy != tekst else { return }
        zmianaProgramowa = true
        tekst = nowy
    }
}
