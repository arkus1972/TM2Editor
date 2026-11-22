#!/usr/bin/env python3
"""Strażnik listy pól układu.

Powstał po wpadce: skrypt, którym przepisywałem fragment `BackupLayout.swift`,
wyciął zakres szerszy niż zamierzony i razem z poprawianym komentarzem usunął
pole `file.backupName` oraz przypisanie `currentKitPointerOffset`. Plik dalej
miał poprawne nawiasy, więc kontrola składni niczego nie zauważyła, a łatka
poszła do użytkownika i po cichu zabrała mu dwie działające funkcje.

Ten skrypt porównuje listę identyfikatorów pól i kluczowych przypisań
z migawką zapisaną w repo. Usunięcie czegokolwiek wymaga świadomej zmiany
migawki — przypadkiem się nie zdarzy.

    python3 -I Scripts/sprawdz-pola.py            # sprawdź
    python3 -I Scripts/sprawdz-pola.py --zapisz   # zaktualizuj migawkę
"""
import re
import sys
from pathlib import Path

KORZEN = Path(__file__).resolve().parent.parent
ZRODLO = KORZEN / "Sources/TM2Editor/Model/BackupLayout.swift"
MIGAWKA = KORZEN / "Scripts/pola-oczekiwane.txt"

# Przypisania, których zniknięcie jest zawsze błędem, a nie refaktorem.
WAZNE_PRZYPISANIA = [
    "layout.kitBlockOrigin",
    "layout.kitStride",
    "layout.triggerBlockOrigin",
    "layout.triggerStride",
    "layout.currentKitPointerOffset",
]


def zbierz() -> list[str]:
    tekst = ZRODLO.read_text(encoding="utf-8")
    pozycje = sorted(set(re.findall(r'id:\s*"([^"]+)"', tekst)))
    # Pola generowane w pętli mają identyfikator składany z interpolacji —
    # bierzemy wtedy sam wzorzec, bo i tak chodzi o to, żeby pętla nie znikła.
    for nazwa in WAZNE_PRZYPISANIA:
        if re.search(re.escape(nazwa) + r"\s*=", tekst):
            pozycje.append(f"<przypisanie> {nazwa}")
    return sorted(set(pozycje))


def main() -> int:
    obecne = zbierz()

    if "--zapisz" in sys.argv:
        MIGAWKA.write_text("\n".join(obecne) + "\n", encoding="utf-8")
        print(f"Zapisano migawkę: {len(obecne)} pozycji")
        return 0

    if not MIGAWKA.exists():
        print("Brak migawki. Uruchom z --zapisz, żeby ją utworzyć.")
        return 1

    oczekiwane = [w for w in MIGAWKA.read_text(encoding="utf-8").split("\n") if w]
    zniknely = [w for w in oczekiwane if w not in obecne]
    doszly = [w for w in obecne if w not in oczekiwane]

    for w in zniknely:
        print(f"  ZNIKNELO: {w}")
    for w in doszly:
        print(f"  nowe:     {w}")

    if zniknely:
        print(f"\nBŁĄD: zniknęło {len(zniknely)} pozycji."
              " Jeśli to było zamierzone, uruchom z --zapisz.")
        return 1

    print(f"OK — {len(obecne)} pozycji, nic nie zniknęło"
          + (f", {len(doszly)} nowych" if doszly else "") + ".")
    return 0


if __name__ == "__main__":
    sys.exit(main())
