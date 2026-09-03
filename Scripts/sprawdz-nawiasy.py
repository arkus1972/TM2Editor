#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sprawdza balans nawiasów w plikach .swift.

Po co: w sesji roboczej nie ma kompilatora Swift, a najczęstszy błąd przy
edycji kodu przez czytanie to zgubiony albo nadmiarowy nawias klamrowy.
Ten skrypt tego nie zastąpi kompilatora, ale wyłapuje właśnie tę klasę
pomyłek, i to natychmiast.

Co uwzględnia:
  - komentarze // do końca linii
  - komentarze blokowe /* */ razem z ich zagnieżdżaniem (Swift na to pozwala)
  - napisy "..." z sekwencjami \\" oraz interpolacją \\( ... )
  - napisy wielolinijkowe \"\"\" ... \"\"\"
  - surowe napisy #"..."# i ##"..."##

Użycie:
  python3 Scripts/sprawdz-nawiasy.py Sources Tests
  python3 Scripts/sprawdz-nawiasy.py plik.swift
"""

from __future__ import annotations

import os
import sys

PARY = {")": "(", "]": "[", "}": "{"}
OTWIERAJACE = set(PARY.values())


class Wynik:
    def __init__(self, sciezka: str) -> None:
        self.sciezka = sciezka
        self.problemy: list[str] = []

    @property
    def ok(self) -> bool:
        return not self.problemy


def sprawdz_plik(sciezka: str) -> Wynik:
    wynik = Wynik(sciezka)
    with open(sciezka, "r", encoding="utf-8") as fh:
        tekst = fh.read()

    stos: list[tuple[str, int, int]] = []   # (znak, linia, kolumna)
    i = 0
    linia = 1
    kolumna = 1
    dlugosc = len(tekst)

    glebokosc_komentarza = 0
    w_komentarzu_liniowym = False

    # Stan napisów. Dla surowych napisów pamiętamy liczbę krzyżyków.
    w_napisie = False
    napis_wielolinijkowy = False
    krzyzyki_napisu = 0

    # Stos poziomów interpolacji: ile nawiasów wewnątrz \( ... )
    stos_interpolacji: list[int] = []

    def dalej(n: int = 1) -> None:
        nonlocal i, linia, kolumna
        for _ in range(n):
            if i < dlugosc and tekst[i] == "\n":
                linia += 1
                kolumna = 1
            else:
                kolumna += 1
            i += 1

    while i < dlugosc:
        znak = tekst[i]

        # --- komentarz liniowy ---
        if w_komentarzu_liniowym:
            if znak == "\n":
                w_komentarzu_liniowym = False
            dalej()
            continue

        # --- komentarz blokowy ---
        if glebokosc_komentarza > 0:
            if tekst.startswith("/*", i):
                glebokosc_komentarza += 1
                dalej(2)
                continue
            if tekst.startswith("*/", i):
                glebokosc_komentarza -= 1
                dalej(2)
                continue
            dalej()
            continue

        # --- wnętrze napisu ---
        if w_napisie:
            if krzyzyki_napisu > 0:
                # Surowy napis: ucieczka to \ z tyloma krzyżykami.
                ucieczka = "\\" + "#" * krzyzyki_napisu
                if tekst.startswith(ucieczka + "(", i):
                    stos_interpolacji.append(0)
                    w_napisie = False
                    stos.append(("(", linia, kolumna))
                    dalej(len(ucieczka) + 1)
                    continue
                if tekst.startswith(ucieczka, i):
                    dalej(len(ucieczka) + 1)
                    continue
                zamkniecie = ('"""' if napis_wielolinijkowy else '"') + "#" * krzyzyki_napisu
                if tekst.startswith(zamkniecie, i):
                    w_napisie = False
                    dalej(len(zamkniecie))
                    continue
                dalej()
                continue

            if znak == "\\":
                if tekst.startswith("\\(", i):
                    stos_interpolacji.append(0)
                    w_napisie = False
                    stos.append(("(", linia, kolumna))
                    dalej(2)
                    continue
                dalej(2)      # zwykła sekwencja ucieczki
                continue

            if napis_wielolinijkowy:
                if tekst.startswith('"""', i):
                    w_napisie = False
                    napis_wielolinijkowy = False
                    dalej(3)
                    continue
            else:
                if znak == '"':
                    w_napisie = False
                    dalej()
                    continue
                if znak == "\n":
                    wynik.problemy.append(
                        f"linia {linia}: napis w cudzysłowie nie został zamknięty"
                    )
                    w_napisie = False
                    dalej()
                    continue
            dalej()
            continue

        # --- poza napisem i komentarzem ---

        if tekst.startswith("//", i):
            w_komentarzu_liniowym = True
            dalej(2)
            continue

        if tekst.startswith("/*", i):
            glebokosc_komentarza = 1
            dalej(2)
            continue

        # Surowy napis: jeden lub więcej # przed cudzysłowem.
        if znak == "#":
            j = i
            while j < dlugosc and tekst[j] == "#":
                j += 1
            if tekst.startswith('"""', j):
                krzyzyki_napisu = j - i
                w_napisie = True
                napis_wielolinijkowy = True
                dalej((j - i) + 3)
                continue
            if j < dlugosc and tekst[j] == '"':
                krzyzyki_napisu = j - i
                w_napisie = True
                napis_wielolinijkowy = False
                dalej((j - i) + 1)
                continue
            dalej()
            continue

        if tekst.startswith('"""', i):
            w_napisie = True
            napis_wielolinijkowy = True
            krzyzyki_napisu = 0
            dalej(3)
            continue

        if znak == '"':
            w_napisie = True
            napis_wielolinijkowy = False
            krzyzyki_napisu = 0
            dalej()
            continue

        # Znak w apostrofach w Swiftcie nie istnieje jako literał znakowy,
        # więc apostrof traktujemy jak zwykły znak.

        if znak in OTWIERAJACE:
            stos.append((znak, linia, kolumna))
            if stos_interpolacji:
                stos_interpolacji[-1] += 1
            dalej()
            continue

        if znak in PARY:
            oczekiwany = PARY[znak]
            if not stos:
                wynik.problemy.append(
                    f"linia {linia}, kolumna {kolumna}: nadmiarowe '{znak}'"
                )
            else:
                otwarty, linia_otwarcia, kolumna_otwarcia = stos.pop()
                if otwarty != oczekiwany:
                    wynik.problemy.append(
                        f"linia {linia}, kolumna {kolumna}: '{znak}' zamyka"
                        f" '{otwarty}' otwarty w linii {linia_otwarcia},"
                        f" kolumnie {kolumna_otwarcia}"
                    )
                if stos_interpolacji:
                    # Licznik trzyma liczbę nawiasów otwartych WEWNĄTRZ
                    # interpolacji. Nawias samego \( nie jest w nim liczony,
                    # więc zero oznacza, że właśnie zamykamy interpolację
                    # i wracamy do wnętrza napisu.
                    if znak == ")" and stos_interpolacji[-1] == 0:
                        stos_interpolacji.pop()
                        w_napisie = True
                        dalej()
                        continue
                    stos_interpolacji[-1] -= 1
            dalej()
            continue

        dalej()

    # --- co zostało otwarte ---
    for otwarty, linia_otwarcia, kolumna_otwarcia in stos:
        wynik.problemy.append(
            f"linia {linia_otwarcia}, kolumna {kolumna_otwarcia}:"
            f" '{otwarty}' nigdy nie został zamknięty"
        )
    if glebokosc_komentarza > 0:
        wynik.problemy.append("komentarz blokowy /* nie został zamknięty")
    if w_napisie:
        wynik.problemy.append("napis nie został zamknięty do końca pliku")

    return wynik


def zbierz_pliki(sciezki: list[str]) -> list[str]:
    pliki: list[str] = []
    for sciezka in sciezki:
        if os.path.isfile(sciezka):
            if sciezka.endswith(".swift"):
                pliki.append(sciezka)
        else:
            for katalog, _, nazwy in os.walk(sciezka):
                if ".build" in katalog:
                    continue
                for nazwa in sorted(nazwy):
                    if nazwa.endswith(".swift"):
                        pliki.append(os.path.join(katalog, nazwa))
    return sorted(pliki)


def main(argv: list[str]) -> int:
    sciezki = argv[1:] or ["Sources", "Tests"]
    pliki = zbierz_pliki(sciezki)

    if not pliki:
        print("Nie znalazłem żadnego pliku .swift.", file=sys.stderr)
        return 1

    bledne = 0
    for sciezka in pliki:
        wynik = sprawdz_plik(sciezka)
        if wynik.ok:
            print(f"  OK    {sciezka}")
        else:
            bledne += 1
            print(f"  BŁĄD  {sciezka}")
            for problem in wynik.problemy:
                print(f"          {problem}")

    print()
    print(f"Sprawdzono plików: {len(pliki)}, z problemami: {bledne}")
    return 1 if bledne else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
