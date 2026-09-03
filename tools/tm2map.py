#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tm2map.py — asystent mapowania różnicowego plików BACKUP z Roland TM-2.

Po co ten program, skoro jest już tm2diff.py?
-----------------------------------------------
tm2diff.py to narzędzie ogólne: pokazuje SUROWĄ różnicę bajtów między dwoma
plikami i nic więcej. Przy realnym mapowaniu to oznacza, że przy KAŻDYM
kolejnym pliku trzeba było ręcznie rozpoznawać, które zmienione bajty to już
znane pola (np. poziom triggera 1 zostawiony na innej wartości z
poprzedniego testu), a które to coś naprawdę nowego — i to rozpoznawanie
zajmowało większość czasu i wiadomości w rozmowie.

tm2map.py wie, co już wiemy (patrz `default_pola()` niżej — to jest wprost
przepisany stan wiedzy z dziennika projektu na dzień utworzenia tego
narzędzia) i automatycznie opisuje każdą zmianę: "Kit 3, Trigger 1, pole
Level" zamiast gołego "offset 0x1AC: 5F -> 64". Bajty, których nie da się
opisać, są wypisywane osobno i wyraźnie oznaczone jako NOWE / NIEZNANE — to
jedyne, na czym trzeba się realnie skupić przy każdym kolejnym pliku.

Do tego program prowadzi dziennik (plik `dziennik.md` w katalogu sesji) —
każda analiza dopisuje się do niego, więc nie trzeba już kopiować wklejać
wyników do rozmowy z Claude ani samemu nic zapamiętywać. Kiedy pole zostanie
rozpoznane, `ustal` dopisuje je do `pola.json` i od tego momentu każdy
kolejny plik automatycznie je etykietuje.

Tylko biblioteka standardowa Pythona (3.8+). Nic nie wysyła nigdzie —
wszystko lokalnie, na plikach, zgodnie z zasadami bezpieczeństwa projektu.

Użycie — najprościej: uruchom bez żadnych argumentów, program zapyta co
zrobić:

    python3 tm2map.py

Dla wygodniejszego użycia z linii poleceń (albo w skrypcie) są też
podkomendy:

    python3 tm2map.py init stan_wyjsciowy.bin
    python3 tm2map.py analizuj 01max.bin --opis "poziom pada 1, kit 1, na max"
    python3 tm2map.py ustal --offset 3145 --nazwa "trig.pan" --opis "panorama" \
                       --dlugosc 2 --zakres trigger --kit 1 --trigger 1
    python3 tm2map.py raport
    python3 tm2map.py pokaz
    python3 tm2map.py rebazuj 05_stan_po_rundzie.bin

Katalog sesji domyślnie to ./sesja-tm2 (obok pliku, z którego uruchamiasz
program) — można zmienić flagą --sesja.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Stan wiedzy o formacie na dzień utworzenia tego narzędzia (2026-09-03).
# To jest DOKŁADNIE to, co jest już wpisane w BackupLayout.mapped2026_09_02
# w kodzie Swift i w DOKUMENTACJA/02-format-pliku-backup.md — trzy miejsca,
# jeden stan wiedzy. Jeśli mapowanie pójdzie dalej i te trzy miejsca się
# rozjadą, to ten plik (i `pola.json` z niego wygenerowany) jest tym, który
# powinien się zmienić jako pierwszy, bo to na nim pracuje się najczęściej.
# ---------------------------------------------------------------------------

WERSJA_SCHEMATU = 1


def domyslne_pola() -> dict:
    return {
        "_wersja": WERSJA_SCHEMATU,
        "_uwaga": (
            "Ten plik opisuje, co już wiemy o pliku BACKUP. Powstał jako kopia "
            "stanu wiedzy z dziennika projektu (03-stan-prac.md) na dzień "
            "2026-09-03. 'ustal' dopisuje tu nowe znaleziska; edycja ręczna też "
            "jest w porządku, to zwykły JSON."
        ),
        "rozmiar_pliku_oczekiwany": 124748,
        "geometria": {
            "blokKitowOd": 64,          # 0x40 -- początek pierwszego bloku kitu
            "krokKitu": 234,            # 0xEA -- odstęp między kolejnymi kitami
            "liczbaKitow": 99,          # fakt sprzętowy; w pliku widziano 100 nazw (patrz otwarte pytania)
            "trigerBlokOd": 126,        # 0x7E -- początek rekordu triggera 1, WZGLĘDEM początku kitu
            "krokTrigera": 84,          # 0x54 -- odstęp między rekordami triggerów
            "liczbaTrigerow": 2,        # UWAGA BEZPIECZEŃSTWA: sprzęt sugeruje do 4, ale przy tym
                                        # kroku/origin trzeci rekord nakłada się na nazwę następnego
                                        # kitu -- patrz testHypotheticalThirdTriggerWouldOverrunNextKitName
                                        # w kodzie Swift. Nie podnosić bez ponownego zmierzenia.
        },
        "polaKitu": [
            {
                "nazwa": "kit.name",
                "offset": 60,           # 0x3C, względem początku kitu
                "dlugosc": 22,
                "kodowanie": "utf16le",
                "opis": "Nazwa kitu, UTF-16LE, dopełniana spacjami, 11 znaków / 22 B",
            }
        ],
        "polaTrigera": [
            {
                "nazwa": "trig.instrument",
                "offset": 0,            # względem początku rekordu triggera
                "dlugosc": 2,
                "kodowanie": "uint16le",
                "opis": (
                    "Numer brzmienia (Instrument), indeks wprost. Kierunek "
                    "potwierdzony, szerokość 16-bit NIE potwierdzona na wartości "
                    ">255 -- na module z 162 brzmieniami fabrycznymi nie da się "
                    "tego eksperymentalnie sprawdzić."
                ),
            },
            {
                "nazwa": "trig.level",
                "offset": 4,
                "dlugosc": 1,
                "kodowanie": "uint8_wprost_0_100",
                "opis": "Poziom pada. 0 = minimum, 100 = maksimum, wprost, bez odwrócenia.",
            },
        ],
        "polaGlobalne": [
            {
                "nazwa": "checksum",
                "offsetOdKonca": 16,
                "dlugosc": 16,
                "kodowanie": "md5_reszty_pliku",
                "opis": "Ostatnie 16 B pliku = MD5 wszystkich poprzedzających bajtów.",
            },
            {
                "nazwa": "current_kit_pointer",
                "offset": 54,           # 0x36, bezwzględny offset w pliku
                "dlugosc": 1,
                "kodowanie": "uint8",
                "opis": (
                    "Hipoteza (4 zgodne próbki): który kit jest aktualnie "
                    "wyświetlany/wybrany na module w chwili BACKUP SAVE, "
                    "0-based. Nie jest bitmapą zmienionych kitów."
                ),
            },
        ],
        # Bajty zaobserwowane, o których wiadomo, że NIE są jeszcze wyjaśnione,
        # ale zgłaszanie ich za każdym razem jako "nowe odkrycie" byłoby
        # mylące, skoro już wiemy, że są tajemnicze. Tu tylko dla pamięci —
        # klasyfikator i tak pokaże je jako nieznane, to jest osobna lista
        # czysto informacyjna do 'pokaz'.
        "otwartePytania": [
            "Pola +0x02 (stałe '01 00'?) i +0x06 (pan/tune?) w rekordzie triggera.",
            "Ok. 60 nieznanych bajtów na początku bloku kitu, przed nazwą.",
            "Ok. 20 nieznanych bajtów po drugim triggerze, do końca 234-bajtowego bloku.",
            "Nagłówek pliku: pola pod 0x14, 0x18, 0x1C, 0x28.",
            "Strefa ~101 KB zer po bloku kitów -- zarezerwowane miejsce na co?",
            "W pliku jest 100 nazw kitów, nie 99 -- dlaczego jedna więcej?",
        ],
    }


# ---------------------------------------------------------------------------
# Pomocnicze
# ---------------------------------------------------------------------------


def sciezka_sesji(katalog: Path, nazwa: str) -> Path:
    return katalog / nazwa


def wczytaj_json(sciezka: Path) -> dict:
    with open(sciezka, "r", encoding="utf-8") as f:
        return json.load(f)


def zapisz_json(sciezka: Path, dane: dict) -> None:
    with open(sciezka, "w", encoding="utf-8") as f:
        json.dump(dane, f, ensure_ascii=False, indent=2)
        f.write("\n")


def wczytaj_bajty(sciezka: Path) -> bytes:
    with open(sciezka, "rb") as f:
        return f.read()


def md5_hex(dane: bytes) -> str:
    return hashlib.md5(dane).hexdigest()


def teraz() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M")


def upewnij_sesje(katalog: Path) -> None:
    if not (katalog / "pola.json").exists():
        print(f"BŁĄD: nie widzę sesji w '{katalog}'.")
        print("Najpierw: python3 tm2map.py init <plik_wyjsciowy.bin>")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Klasyfikacja pojedynczego zmienionego bajtu
# ---------------------------------------------------------------------------


class Opis:
    """Wynik rozpoznania jednego offsetu: co to za pole, w jakim kontekście."""

    def __init__(self, tekst: str, znany: bool, klucz_grupy: str):
        self.tekst = tekst
        self.znany = znany          # True = już wiemy, co to jest
        self.klucz_grupy = klucz_grupy  # do grupowania sąsiednich bajtów tego samego pola


def rozpoznaj_offset(offset: int, rozmiar_pliku: int, pola: dict) -> Opis:
    geo = pola["geometria"]

    # 1. Suma kontrolna na końcu pliku.
    for pg in pola["polaGlobalne"]:
        if "offsetOdKonca" in pg:
            start = rozmiar_pliku - pg["offsetOdKonca"]
            if start <= offset < start + pg["dlugosc"]:
                return Opis(f"suma kontrolna ({pg['opis']})", True, "suma_kontrolna")

    # 2. Inne pola globalne, adresowane wprost od początku pliku.
    for pg in pola["polaGlobalne"]:
        if "offset" in pg:
            if pg["offset"] <= offset < pg["offset"] + pg["dlugosc"]:
                return Opis(f"{pg['nazwa']} ({pg['opis']})", True, f"global:{pg['nazwa']}")

    # 3. Czy offset leży w bloku kitów w ogóle?
    if offset >= geo["blokKitowOd"]:
        wzgledem_bloku = offset - geo["blokKitowOd"]
        nr_kitu0 = wzgledem_bloku // geo["krokKitu"]
        w_kicie = wzgledem_bloku % geo["krokKitu"]
        nr_kitu = nr_kitu0 + 1

        poza_zakresem = nr_kitu0 >= geo["liczbaKitow"]
        prefiks_kitu = f"Kit {nr_kitu}" + (" [POZA liczbaKitow z geometrii]" if poza_zakresem else "")

        # 3a. Pole kitu (np. nazwa).
        for pk in pola["polaKitu"]:
            if pk["offset"] <= w_kicie < pk["offset"] + pk["dlugosc"]:
                return Opis(
                    f"{prefiks_kitu}, pole {pk['nazwa']} ({pk['opis']})",
                    True,
                    f"kit:{pk['nazwa']}:{nr_kitu}",
                )

        # 3b. Czy to obszar rekordów triggerów?
        if w_kicie >= geo["trigerBlokOd"]:
            wzgledem_trigerow = w_kicie - geo["trigerBlokOd"]
            nr_trigera0 = wzgledem_trigerow // geo["krokTrigera"]
            w_trigerze = wzgledem_trigerow % geo["krokTrigera"]
            nr_trigera = nr_trigera0 + 1

            for pt in pola["polaTrigera"]:
                if pt["offset"] <= w_trigerze < pt["offset"] + pt["dlugosc"]:
                    return Opis(
                        f"{prefiks_kitu}, Trigger {nr_trigera}, pole {pt['nazwa']} ({pt['opis']})",
                        True,
                        f"trig:{pt['nazwa']}:{nr_kitu}:{nr_trigera}",
                    )

            return Opis(
                f"{prefiks_kitu}, Trigger {nr_trigera}, offset +0x{w_trigerze:X} w rekordzie "
                f"-- NIEZNANE POLE",
                False,
                f"nieznane_trigger:{w_trigerze:X}",
            )

        return Opis(
            f"{prefiks_kitu}, offset +0x{w_kicie:X} w bloku kitu (poza rekordami triggerów) "
            f"-- NIEZNANE POLE",
            False,
            f"nieznane_kit:{w_kicie:X}",
        )

    # 4. Nagłówek pliku, przed blokiem kitów.
    return Opis(f"nagłówek pliku, offset 0x{offset:X} -- NIEZNANE POLE", False, f"nieznany_naglowek:{offset:X}")


def znajdz_rozniace_sie_offsety(a: bytes, b: bytes) -> list[int]:
    dlugosc = min(len(a), len(b))
    return [i for i in range(dlugosc) if a[i] != b[i]]


def grupuj_sasiednie(offsety: list[int]) -> list[tuple[int, int]]:
    """Zwraca listę (start, koniec_wlacznie) dla ciągłych przebiegów offsetów."""
    if not offsety:
        return []
    grupy = []
    start = poprzedni = offsety[0]
    for o in offsety[1:]:
        if o == poprzedni + 1:
            poprzedni = o
            continue
        grupy.append((start, poprzedni))
        start = poprzedni = o
    grupy.append((start, poprzedni))
    return grupy


# ---------------------------------------------------------------------------
# Podkomendy
# ---------------------------------------------------------------------------


def cmd_init(katalog: Path, plik_bazowy: Path) -> None:
    if not plik_bazowy.exists():
        print(f"BŁĄD: nie ma pliku '{plik_bazowy}'.")
        sys.exit(1)

    katalog.mkdir(parents=True, exist_ok=True)
    baza_docelowa = katalog / "baza.bin"
    shutil.copyfile(plik_bazowy, baza_docelowa)

    pola_sciezka = katalog / "pola.json"
    if pola_sciezka.exists():
        print(f"Uwaga: '{pola_sciezka}' już istnieje, zostawiam bez zmian (Twoje wcześniejsze ustalenia).")
    else:
        zapisz_json(pola_sciezka, domyslne_pola())
        print(f"Utworzono '{pola_sciezka}' ze znanym stanem wiedzy na 2026-09-03.")

    dziennik = katalog / "dziennik.md"
    if not dziennik.exists():
        dane = wczytaj_bajty(baza_docelowa)
        with open(dziennik, "w", encoding="utf-8") as f:
            f.write("# Dziennik mapowania TM-2\n\n")
            f.write(f"## Sesja rozpoczęta {teraz()}\n\n")
            f.write(f"- Plik bazowy: `{plik_bazowy.name}`\n")
            f.write(f"- Rozmiar: {len(dane)} B\n")
            f.write(f"- MD5 całości: `{md5_hex(dane)}`\n\n")
            f.write("---\n\n")
        print(f"Utworzono '{dziennik}'.")

    print()
    print(f"Sesja gotowa w '{katalog}'.")
    print("Następny krok: zmień JEDEN parametr na module, zrób BACKUP SAVE, wgraj plik tutaj,")
    print("i uruchom:  python3 tm2map.py analizuj <nowy_plik.bin> --opis \"co dokładnie zmieniłeś\"")


def cmd_analizuj(katalog: Path, plik: Path, opis_zmiany: str | None) -> None:
    upewnij_sesje(katalog)
    if not plik.exists():
        print(f"BŁĄD: nie ma pliku '{plik}'.")
        sys.exit(1)

    baza = wczytaj_bajty(katalog / "baza.bin")
    nowy = wczytaj_bajty(plik)
    pola = wczytaj_json(katalog / "pola.json")

    if len(baza) != len(nowy):
        print(f"UWAGA: rozmiar się różni ({len(baza)} B -> {len(nowy)} B) -- rzadkie, sprawdź czy to")
        print("na pewno plik z tego samego modułu / tej samej wersji systemu.")

    rozmiar = len(nowy)
    offsety = znajdz_rozniace_sie_offsety(baza, nowy)

    if not offsety:
        print("Brak jakiejkolwiek różnicy względem pliku bazowego. Nic się nie zmieniło (albo to ten sam plik).")
        return

    grupy = grupuj_sasiednie(offsety)

    znane: list[str] = []
    nowe: list[str] = []

    for start, koniec in grupy:
        opis = rozpoznaj_offset(start, rozmiar, pola)
        stare_bajty = baza[start:koniec + 1].hex(" ")
        nowe_bajty = nowy[start:koniec + 1].hex(" ")
        linia = f"offset 0x{start:06X} ({start})  {stare_bajty} -> {nowe_bajty}   [{opis.tekst}]"
        if opis.znany:
            znane.append(linia)
        else:
            nowe.append(linia)

    print()
    print(f"Plik: {plik.name}   ({len(grupy)} grup zmienionych bajtów)")
    print()
    if znane:
        print(f"Już znane pola ({len(znane)}) -- zostałości poprzednich testów albo spodziewane zmiany:")
        for l in znane:
            print("  " + l)
        print()
    if nowe:
        print(f"### NOWE / NIEZNANE ({len(nowe)}) -- na tym warto się skupić:")
        for l in nowe:
            print("  " + l)
        print()
    else:
        print("Brak nierozpoznanych zmian -- wszystko, co się zmieniło, jest już opisane w pola.json.")
        print("(Jeśli to nieoczekiwane -- czy na pewno zmieniłeś dokładnie jeden nowy parametr?)")
        print()

    with open(katalog / "dziennik.md", "a", encoding="utf-8") as f:
        f.write(f"## {teraz()} — `{plik.name}`\n\n")
        if opis_zmiany:
            f.write(f"**Co zmieniono na module:** {opis_zmiany}\n\n")
        if znane:
            f.write(f"Już znane ({len(znane)}):\n\n")
            for l in znane:
                f.write(f"- {l}\n")
            f.write("\n")
        if nowe:
            f.write(f"**NOWE / NIEZNANE ({len(nowe)}):**\n\n")
            for l in nowe:
                f.write(f"- {l}\n")
            f.write("\n")
        else:
            f.write("Brak nierozpoznanych zmian.\n\n")
        f.write("---\n\n")

    print(f"Dopisano do '{katalog / 'dziennik.md'}'.")


def cmd_ustal(
    katalog: Path,
    offset: int,
    nazwa: str,
    opis: str,
    dlugosc: int,
    zakres: str,
    kit: int | None,
    trigger: int | None,
    kodowanie: str,
) -> None:
    upewnij_sesje(katalog)
    pola = wczytaj_json(katalog / "pola.json")
    geo = pola["geometria"]

    if zakres == "global":
        wpis = {"nazwa": nazwa, "offset": offset, "dlugosc": dlugosc, "kodowanie": kodowanie, "opis": opis}
        pola["polaGlobalne"].append(wpis)

    elif zakres == "kit":
        if kit is None:
            print("BŁĄD: --zakres kit wymaga --kit <numer>, żeby policzyć offset względny.")
            sys.exit(1)
        poczatek_kitu = geo["blokKitowOd"] + (kit - 1) * geo["krokKitu"]
        wzgledny = offset - poczatek_kitu
        if not (0 <= wzgledny < geo["krokKitu"]):
            print(
                f"BŁĄD: offset {offset} nie leży w kicie {kit} "
                f"(kit {kit} zajmuje 0x{poczatek_kitu:X}..0x{poczatek_kitu + geo['krokKitu'] - 1:X})."
            )
            sys.exit(1)
        wpis = {"nazwa": nazwa, "offset": wzgledny, "dlugosc": dlugosc, "kodowanie": kodowanie, "opis": opis}
        pola["polaKitu"].append(wpis)
        print(f"Offset względny w kicie: +0x{wzgledny:X} ({wzgledny})")

    elif zakres == "trigger":
        if kit is None or trigger is None:
            print("BŁĄD: --zakres trigger wymaga --kit <numer> i --trigger <numer>.")
            sys.exit(1)
        poczatek_kitu = geo["blokKitowOd"] + (kit - 1) * geo["krokKitu"]
        poczatek_trigera = poczatek_kitu + geo["trigerBlokOd"] + (trigger - 1) * geo["krokTrigera"]
        wzgledny = offset - poczatek_trigera
        if not (0 <= wzgledny < geo["krokTrigera"]):
            print(
                f"BŁĄD: offset {offset} nie leży w rekordzie Trigger {trigger} kitu {kit} "
                f"(zajmuje 0x{poczatek_trigera:X}..0x{poczatek_trigera + geo['krokTrigera'] - 1:X})."
            )
            sys.exit(1)
        wpis = {"nazwa": nazwa, "offset": wzgledny, "dlugosc": dlugosc, "kodowanie": kodowanie, "opis": opis}
        pola["polaTrigera"].append(wpis)
        print(f"Offset względny w rekordzie triggera: +0x{wzgledny:X} ({wzgledny})")

    else:
        print(f"BŁĄD: nieznany zakres '{zakres}' (oczekiwano: global, kit, trigger).")
        sys.exit(1)

    zapisz_json(katalog / "pola.json", pola)
    print(f"Zapisano pole '{nazwa}' do pola.json. Od teraz kolejne 'analizuj' będą je rozpoznawać.")

    with open(katalog / "dziennik.md", "a", encoding="utf-8") as f:
        f.write(f"## {teraz()} — ustalono nowe pole: `{nazwa}`\n\n")
        f.write(f"- Zakres: {zakres}" + (f", kit {kit}" if kit else "") + (f", trigger {trigger}" if trigger else "") + "\n")
        f.write(f"- Opis: {opis}\n")
        f.write(f"- Długość: {dlugosc} B, kodowanie: {kodowanie}\n\n")
        f.write("---\n\n")


def cmd_pokaz(katalog: Path) -> None:
    upewnij_sesje(katalog)
    pola = wczytaj_json(katalog / "pola.json")
    print(json.dumps(pola, ensure_ascii=False, indent=2))


def cmd_raport(katalog: Path) -> None:
    upewnij_sesje(katalog)
    pola = wczytaj_json(katalog / "pola.json")
    geo = pola["geometria"]

    linie = []
    linie.append(f"# Raport mapowania TM-2 — {teraz()}")
    linie.append("")
    linie.append("## Geometria")
    linie.append("")
    for k, v in geo.items():
        linie.append(f"- `{k}`: {v}")
    linie.append("")
    linie.append("## Pola kitu")
    linie.append("")
    for pk in pola["polaKitu"]:
        linie.append(f"- `{pk['nazwa']}` @ +0x{pk['offset']:X} ({pk['dlugosc']} B, {pk['kodowanie']}) — {pk['opis']}")
    linie.append("")
    linie.append("## Pola rekordu triggera")
    linie.append("")
    for pt in pola["polaTrigera"]:
        linie.append(f"- `{pt['nazwa']}` @ +0x{pt['offset']:X} ({pt['dlugosc']} B, {pt['kodowanie']}) — {pt['opis']}")
    linie.append("")
    linie.append("## Pola globalne")
    linie.append("")
    for pg in pola["polaGlobalne"]:
        if "offsetOdKonca" in pg:
            linie.append(f"- `{pg['nazwa']}`: ostatnie {pg['dlugosc']} B pliku — {pg['opis']}")
        else:
            linie.append(f"- `{pg['nazwa']}` @ 0x{pg['offset']:X} ({pg['dlugosc']} B, {pg['kodowanie']}) — {pg['opis']}")
    linie.append("")
    linie.append("## Otwarte pytania")
    linie.append("")
    for pytanie in pola.get("otwartePytania", []):
        linie.append(f"- {pytanie}")
    linie.append("")

    tekst = "\n".join(linie)
    sciezka = katalog / "raport.md"
    with open(sciezka, "w", encoding="utf-8") as f:
        f.write(tekst)
    print(tekst)
    print()
    print(f"Zapisano też do '{sciezka}' — ten plik możesz wkleić do rozmowy.")


def cmd_rebazuj(katalog: Path, plik: Path) -> None:
    upewnij_sesje(katalog)
    if not plik.exists():
        print(f"BŁĄD: nie ma pliku '{plik}'.")
        sys.exit(1)
    shutil.copyfile(plik, katalog / "baza.bin")
    print(f"Nowy plik bazowy: '{plik.name}'. Kolejne 'analizuj' będą liczone względem niego.")
    with open(katalog / "dziennik.md", "a", encoding="utf-8") as f:
        f.write(f"## {teraz()} — zmiana pliku bazowego na `{plik.name}`\n\n---\n\n")


# ---------------------------------------------------------------------------
# Tryb interaktywny (menu) -- domyślny, gdy program uruchomiono bez argumentów
# ---------------------------------------------------------------------------


def zapytaj(pytanie: str, domyslna: str | None = None) -> str:
    podpowiedz = f" [{domyslna}]" if domyslna else ""
    odpowiedz = input(f"{pytanie}{podpowiedz}: ").strip()
    return odpowiedz or (domyslna or "")


def tryb_interaktywny(katalog: Path) -> None:
    print("=" * 70)
    print("tm2map.py — asystent mapowania TM-2 (tryb interaktywny)")
    print(f"Katalog sesji: {katalog}")
    print("=" * 70)

    while True:
        print()
        print("Co robimy?")
        print("  1) Zacznij nową sesję (init) -- pierwszy plik BACKUP")
        print("  2) Przeanalizuj nowy plik BACKUP")
        print("  3) Ustal nowe pole (zapisz odkrycie na stałe)")
        print("  4) Pokaż, co już wiemy (raport)")
        print("  5) Zmień plik bazowy (rebazuj)")
        print("  0) Wyjście")
        wybor = input("> ").strip()

        if wybor == "0" or wybor.lower() in ("q", "wyjdz", "exit"):
            print("Do zobaczenia.")
            return

        if wybor == "1":
            plik = zapytaj("Ścieżka do pliku BACKUP (stanu wyjściowego)")
            if plik:
                cmd_init(katalog, Path(plik))

        elif wybor == "2":
            if not (katalog / "pola.json").exists():
                print("Nie ma jeszcze sesji -- najpierw opcja 1.")
                continue
            plik = zapytaj("Ścieżka do nowego pliku BACKUP")
            if not plik:
                continue
            opis = zapytaj("Co dokładnie zmieniłeś na module przed tym zapisem? (opcjonalne)")
            cmd_analizuj(katalog, Path(plik), opis or None)

        elif wybor == "3":
            if not (katalog / "pola.json").exists():
                print("Nie ma jeszcze sesji -- najpierw opcja 1.")
                continue
            print("Jaki to zakres?")
            print("  kit     -- pole w bloku kitu (np. coś obok nazwy)")
            print("  trigger -- pole w rekordzie triggera (najczęstszy przypadek)")
            print("  global  -- pole w nagłówku pliku, poza kitami")
            zakres = zapytaj("Zakres (kit/trigger/global)", "trigger").lower()
            try:
                offset = int(zapytaj("Bezwzględny offset z raportu 'analizuj' (liczba dziesiętna)"))
                dlugosc = int(zapytaj("Długość pola w bajtach", "1"))
            except ValueError:
                print("To musi być liczba. Przerywam.")
                continue
            nazwa = zapytaj("Krótka nazwa pola (np. trig.pan)")
            opis = zapytaj("Opis / hipoteza")
            kodowanie = zapytaj("Kodowanie (np. uint8, uint16le, uint8_wprost_0_100)", "uint8")
            kit = trigger = None
            if zakres in ("kit", "trigger"):
                kit = int(zapytaj("Numer kitu (1-99)", "1"))
            if zakres == "trigger":
                trigger = int(zapytaj("Numer triggera (1-2)", "1"))
            cmd_ustal(katalog, offset, nazwa, opis, dlugosc, zakres, kit, trigger, kodowanie)

        elif wybor == "4":
            if not (katalog / "pola.json").exists():
                print("Nie ma jeszcze sesji -- najpierw opcja 1.")
                continue
            cmd_raport(katalog)

        elif wybor == "5":
            if not (katalog / "pola.json").exists():
                print("Nie ma jeszcze sesji -- najpierw opcja 1.")
                continue
            plik = zapytaj("Ścieżka do pliku, który ma być nową bazą")
            if plik:
                cmd_rebazuj(katalog, Path(plik))

        else:
            print("Nie rozumiem tej opcji, wybierz numer z listy.")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def zbuduj_parser() -> argparse.ArgumentParser:
    # --sesja jest zdefiniowane na WSPÓLNYM rodzicu i doklejone też do każdej
    # podkomendy (parents=[wspolny]) -- inaczej argparse przyjmuje --sesja
    # tylko PRZED nazwą podkomendy ("tm2map.py --sesja X analizuj plik.bin"),
    # a nie po niej ("tm2map.py analizuj plik.bin --sesja X"), co jest mylące
    # i akurat tej drugiej kolejności używa CI. Z tą definicją działają obie.
    wspolny = argparse.ArgumentParser(add_help=False)
    wspolny.add_argument(
        "--sesja",
        default="sesja-tm2",
        help="Katalog sesji mapowania (domyślnie ./sesja-tm2).",
    )

    parser = argparse.ArgumentParser(
        description="Asystent mapowania różnicowego plików BACKUP Roland TM-2.",
        parents=[wspolny],
    )
    sub = parser.add_subparsers(dest="polecenie")

    p_init = sub.add_parser(
        "init", parents=[wspolny], help="Rozpocznij sesję od pliku bazowego (stanu wyjściowego)."
    )
    p_init.add_argument("plik", type=Path)

    p_analizuj = sub.add_parser(
        "analizuj", parents=[wspolny], help="Porównaj nowy plik z bazą i opisz różnice."
    )
    p_analizuj.add_argument("plik", type=Path)
    p_analizuj.add_argument("--opis", default=None, help="Co dokładnie zmieniono na module.")

    p_ustal = sub.add_parser(
        "ustal", parents=[wspolny], help="Zapisz nowo rozpoznane pole do pola.json."
    )
    p_ustal.add_argument("--offset", type=int, required=True, help="Bezwzględny offset w pliku (dziesiętnie).")
    p_ustal.add_argument("--nazwa", required=True)
    p_ustal.add_argument("--opis", required=True)
    p_ustal.add_argument("--dlugosc", type=int, default=1)
    p_ustal.add_argument("--zakres", choices=["global", "kit", "trigger"], default="trigger")
    p_ustal.add_argument("--kit", type=int, default=None)
    p_ustal.add_argument("--trigger", type=int, default=None)
    p_ustal.add_argument("--kodowanie", default="uint8")

    sub.add_parser("pokaz", parents=[wspolny], help="Wypisz całą zawartość pola.json.")
    sub.add_parser("raport", parents=[wspolny], help="Zbuduj czytelne podsumowanie stanu wiedzy (raport.md).")

    p_rebazuj = sub.add_parser(
        "rebazuj", parents=[wspolny], help="Ustaw nowy plik bazowy dla kolejnych porównań."
    )
    p_rebazuj.add_argument("plik", type=Path)

    return parser


def main() -> None:
    parser = zbuduj_parser()
    args = parser.parse_args()
    katalog = Path(args.sesja)

    if args.polecenie is None:
        tryb_interaktywny(katalog)
        return

    if args.polecenie == "init":
        cmd_init(katalog, args.plik)
    elif args.polecenie == "analizuj":
        cmd_analizuj(katalog, args.plik, args.opis)
    elif args.polecenie == "ustal":
        cmd_ustal(
            katalog, args.offset, args.nazwa, args.opis, args.dlugosc,
            args.zakres, args.kit, args.trigger, args.kodowanie,
        )
    elif args.polecenie == "pokaz":
        cmd_pokaz(katalog)
    elif args.polecenie == "raport":
        cmd_raport(katalog)
    elif args.polecenie == "rebazuj":
        cmd_rebazuj(katalog, args.plik)


if __name__ == "__main__":
    main()
