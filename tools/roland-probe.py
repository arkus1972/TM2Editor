#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
roland-probe — generator komunikatów SysEx do sondowania modułu Roland.

Po co to jest
-------------
TM-2 odpowiedział na Identity Request, czyli ma w środku silnik SysEx. To
jeszcze nie znaczy, że obsługuje RQ1/DT1 — czyli odczyt i zapis parametrów pod
adresami. Żeby to sprawdzić, trzeba wysłać RQ1 i zobaczyć, czy wróci DT1.

Kłopot: RQ1 zawiera model ID, a Roland go dla TM-2 nie opublikował. Identity
Reply podaje kod rodziny (u nas 0x0303), a nie model ID, i nie ma między nimi
pewnego przełożenia. Dlatego zamiast zgadywać jeden — zamiatamy wszystkie
i patrzymy, na który moduł zareaguje.

BEZPIECZEŃSTWO
--------------
Ten skrypt generuje WYŁĄCZNIE komunikaty RQ1 (polecenie 0x11), czyli PYTANIA.
RQ1 niczego w module nie zmienia — prosi o odczyt. Nigdzie w tym pliku nie ma
generowania DT1 (0x12), czyli zapisu, i celowo nie będzie: dopóki nie wiemy,
co jest pod jakim adresem, wysyłanie zapisu do modułu to proszenie się
o kłopoty. Najgorsze, co może zrobić RQ1 z błędnym model ID, to zostać
zignorowane.

Format komunikatu Rolanda
-------------------------
    F0 41 <dev> <model ID...> 11 <adres...> <rozmiar...> <suma> F7

    F0        początek SysEx
    41        Roland
    <dev>     device ID (u nas 0x10, z Identity Reply)
    <model>   1 albo 4 bajty, zależnie od generacji urządzenia
    11        RQ1 — prośba o dane (0x12 byłoby zapisem; tu nie występuje)
    <adres>   3 albo 4 bajty
    <rozmiar> 3 albo 4 bajty
    <suma>    suma kontrolna Rolanda po adresie i rozmiarze
    F7        koniec SysEx

Użycie
------
    # jeden plik z pełnym zamiataniem, do odtworzenia w SysEx Librarian
    python3 roland-probe.py sweep --out ~/probe-tm2.syx

    # pojedyncze zapytanie o znanym model ID
    python3 roland-probe.py rq1 --model 00,00,00,4B --addr 00,00,00,00 \
        --size 00,00,00,10 --out ~/jedno.syx

    # rozbiór odpowiedzi Identity Reply
    python3 roland-probe.py identity "F0 7E 10 06 02 41 03 03 00 00 00 00 00 00 F7"

    # rozbiór dowolnej odpowiedzi Rolanda (np. DT1, które wróci)
    python3 roland-probe.py decode "F0 41 10 00 00 00 4B 12 ..."
"""

from __future__ import annotations

import argparse
import sys

ROLAND = 0x41
RQ1 = 0x11          # prośba o dane — jedyne polecenie, jakie ten skrypt generuje
DT1 = 0x12          # zapis danych — TYLKO do rozpoznawania odpowiedzi, nigdy do wysyłki


# --------------------------------------------------------------------------
# Pomocnicze
# --------------------------------------------------------------------------

def parse_bytes(text: str) -> list[int]:
    """Zamienia '00,00,00,4B' albo '00 00 00 4B' na listę liczb."""
    czyste = text.replace(",", " ").split()
    wynik = []
    for kawalek in czyste:
        kawalek = kawalek.lower().removeprefix("0x")
        wynik.append(int(kawalek, 16))
    return wynik


def roland_checksum(data: list[int]) -> int:
    """Suma kontrolna Rolanda: liczona po adresie i rozmiarze.

    Dodaj wszystkie bajty, weź resztę z dzielenia przez 128, odejmij ją od 128
    i znowu weź resztę. Wynik zawsze mieści się w siedmiu bitach, bo w SysEx
    bajt danych nie może mieć ustawionego najstarszego bitu.
    """
    return (128 - (sum(data) % 128)) % 128


def build_rq1(device: int, model: list[int],
              address: list[int], size: list[int]) -> list[int]:
    """Składa jeden komunikat RQ1. To jest pytanie, nie zapis."""
    ladunek = address + size
    return ([0xF0, ROLAND, device] + model + [RQ1]
            + ladunek + [roland_checksum(ladunek), 0xF7])


def as_hex(data: list[int]) -> str:
    return " ".join(f"{b:02X}" for b in data)


def write_syx(path: str, messages: list[list[int]]) -> None:
    """Zapisuje komunikaty jeden po drugim do pliku .syx.

    SysEx Librarian czyta taki plik jako listę osobnych komunikatów i wysyła
    je po kolei — dokładnie to, czego potrzebujemy przy zamiataniu.
    """
    with open(path, "wb") as fh:
        for message in messages:
            fh.write(bytes(message))


# --------------------------------------------------------------------------
# Polecenie: sweep
# --------------------------------------------------------------------------

def model_bytes(schemat: str, kandydat: int) -> list[int]:
    """Buduje model ID według jednego z czterech schematów Rolanda.

    `ext3` to konwencja rozszerzonego identyfikatora, ta sama, której MMA
    używa dla ID producenta: pierwszy bajt 0x00 zapowiada, że prawdziwy numer
    jest w kolejnych DWÓCH bajtach — czyli ID ma w sumie TRZY bajty, nie
    cztery. Pierwsza wersja tego skryptu miała tu błąd (dokładała czwarty
    bajt), więc nie testowała w ogóle tego schematu.
    """
    if schemat == "1B":
        return [kandydat]
    if schemat == "ext3":
        return [0x00, 0x00, kandydat]
    if schemat == "4B":
        return [0x00, 0x00, 0x00, kandydat]
    raise ValueError(schemat)


def cmd_sweep(args) -> int:
    device = args.device
    messages: list[list[int]] = []
    opis: list[str] = []

    # Cztery warianty, bo Roland zmieniał format przez lata i nie wiemy, do
    # której generacji należy TM-2 (2013 — akurat na styku). Dla każdego
    # schematu model ID próbujemy adresu 3- i 4-bajtowego, bo i to bywało
    # różne między urządzeniami.
    warianty = []
    if not args.only_4byte and not args.only_ext3:
        warianty.append(("1B model / 3B adres", "1B", 3))
        warianty.append(("1B model / 4B adres", "1B", 4))
    if not args.only_1byte and not args.only_4byte:
        # Schemat rozszerzony 00 00 XX — pominięty w pierwszej wersji skryptu.
        warianty.append(("ext3 model / 3B adres", "ext3", 3))
        warianty.append(("ext3 model / 4B adres", "ext3", 4))
    if not args.only_1byte and not args.only_ext3:
        warianty.append(("4B model / 4B adres", "4B", 4))

    for nazwa, schemat, dlugosc_adresu in warianty:
        for kandydat in range(args.first, args.last + 1):
            model = model_bytes(schemat, kandydat)

            adres = [0x00] * dlugosc_adresu
            rozmiar = [0x00] * (dlugosc_adresu - 1) + [args.request_size]

            wiadomosc = build_rq1(device, model, adres, rozmiar)
            messages.append(wiadomosc)
            opis.append(f"{nazwa:22s}  model {as_hex(model):11s}  ->  {as_hex(wiadomosc)}")

    write_syx(args.out, messages)

    print(f"Zapisano {len(messages)} komunikatów RQ1 do: {args.out}")
    print(f"  device ID       : 0x{device:02X}")
    print(f"  model ID od..do : 0x{args.first:02X}..0x{args.last:02X}")
    print(f"  warianty        : {', '.join(n for n, _, _ in warianty)}")
    print(f"  adres           : same zera")
    print(f"  proszony rozmiar: {args.request_size} bajt(ów)")
    print()
    print("WSZYSTKIE komunikaty to RQ1 (polecenie 0x11), czyli pytania.")
    print("Żaden nie zapisuje niczego w module.")
    print()
    print("Jak tego użyć:")
    print("  1. MIDI Monitor: Sources -> UM-ONE, okno wyczyszczone (Clear).")
    print("  2. SysEx Librarian: przeciągnij ten plik, Destination = UM-ONE.")
    print("  3. Ustaw odstęp między komunikatami: menu SysEx Librarian ->")
    print("     Preferences -> pauza ok. 100 ms. Bez tego moduł dostanie")
    print("     kilkaset komunikatów w ułamku sekundy i może je pogubić.")
    print("  4. Play. Całość potrwa około"
          f" {len(messages) * 0.1:.0f} sekund.")
    print("  5. Cokolwiek pojawi się w MIDI Monitor od UM-ONE — to jest trop.")
    print()
    if args.list:
        print("Pełna lista wygenerowanych komunikatów:")
        for linia in opis:
            print("  " + linia)
    else:
        print("(--list wypisze wszystkie wygenerowane komunikaty)")
    return 0


# --------------------------------------------------------------------------
# Polecenie: rq1
# --------------------------------------------------------------------------

def cmd_rq1(args) -> int:
    model = parse_bytes(args.model)
    adres = parse_bytes(args.addr)
    rozmiar = parse_bytes(args.size)

    if len(adres) != len(rozmiar):
        print("Adres i rozmiar muszą mieć tyle samo bajtów.", file=sys.stderr)
        return 1

    wiadomosc = build_rq1(args.device, model, adres, rozmiar)
    print("RQ1 (pytanie, nic nie zapisuje):")
    print("  " + as_hex(wiadomosc))
    print(f"  suma kontrolna: {wiadomosc[-2]:02X}")

    if args.out:
        write_syx(args.out, [wiadomosc])
        print(f"\nZapisano do: {args.out}")
    return 0


# --------------------------------------------------------------------------
# Polecenie: identity
# --------------------------------------------------------------------------

def cmd_identity(args) -> int:
    b = parse_bytes(args.hex)

    print(f"Długość: {len(b)} bajtów")
    if len(b) < 6 or b[0] != 0xF0 or b[-1] != 0xF7:
        print("To nie wygląda na kompletny komunikat SysEx (F0 ... F7).")
        return 1
    if b[1] != 0x7E:
        print("To nie jest Universal Non-Real Time (0x7E) — nie Identity Reply.")
        return 1
    if len(b) < 7 or b[3] != 0x06 or b[4] != 0x02:
        print("To nie jest Identity Reply (oczekiwane 06 02 po device ID).")
        return 1

    producenci = {0x41: "Roland", 0x43: "Yamaha", 0x42: "Korg",
                  0x40: "Kawai", 0x47: "Akai"}
    man = b[5]

    print(f"  device ID     : 0x{b[2]:02X} ({b[2]})")
    print(f"  producent     : 0x{man:02X}"
          f" ({producenci.get(man, 'nieznany')})")

    if man == 0x00:
        # Trzybajtowy identyfikator producenta.
        print("  (trzybajtowy ID producenta — inny rozkład dalszych pól)")
        return 0

    if len(b) >= 15:
        family = (b[7] << 8) | b[6]
        member = (b[9] << 8) | b[8]
        wersja = b[10:14]
        print(f"  rodzina       : 0x{family:04X}  (LSB {b[6]:02X}, MSB {b[7]:02X})")
        print(f"  model rodziny : 0x{member:04X}")
        print(f"  wersja        : {'.'.join(str(x) for x in wersja)}")
        print()
        print("  UWAGA: kod rodziny to NIE jest model ID używany w RQ1/DT1.")
        print("  Roland nie publikuje przełożenia jednego na drugie, więc"
              " model ID trzeba ustalić zamiataniem (polecenie `sweep`).")
    return 0


# --------------------------------------------------------------------------
# Polecenie: decode
# --------------------------------------------------------------------------

def cmd_decode(args) -> int:
    b = parse_bytes(args.hex)

    if len(b) < 5 or b[0] != 0xF0 or b[-1] != 0xF7:
        print("To nie wygląda na kompletny komunikat SysEx (F0 ... F7).")
        return 1

    if b[1] == 0x7E:
        return cmd_identity(args)

    if b[1] != ROLAND:
        print(f"Producent 0x{b[1]:02X} — to nie Roland.")
        return 1

    print(f"Długość: {len(b)} bajtów")
    print(f"  device ID : 0x{b[2]:02X}")

    # Polecenie to 0x11 albo 0x12; szukamy go, żeby ustalić długość model ID.
    for dlugosc_modelu in (1, 2, 3, 4):
        pozycja = 3 + dlugosc_modelu
        if pozycja < len(b) and b[pozycja] in (RQ1, DT1):
            model = b[3:pozycja]
            polecenie = b[pozycja]
            reszta = b[pozycja + 1:-2]
            suma = b[-2]

            nazwa = "RQ1 (prośba o dane)" if polecenie == RQ1 else "DT1 (dane)"
            print(f"  model ID  : {as_hex(model)}  ({dlugosc_modelu} B)")
            print(f"  polecenie : 0x{polecenie:02X} — {nazwa}")

            if polecenie == DT1:
                # Przy DT1 nie wiemy z góry, ile bajtów zajmuje adres.
                # Pokazujemy oba prawdopodobne rozbiory.
                for dlugosc_adresu in (3, 4):
                    if len(reszta) > dlugosc_adresu:
                        adres = reszta[:dlugosc_adresu]
                        dane = reszta[dlugosc_adresu:]
                        print(f"    przy {dlugosc_adresu}-bajtowym adresie:")
                        print(f"      adres : {as_hex(adres)}")
                        print(f"      dane  : {as_hex(dane)}  ({len(dane)} B)")
            else:
                print(f"  ładunek   : {as_hex(reszta)}")

            oczekiwana = roland_checksum(reszta)
            zgodna = "zgadza się" if oczekiwana == suma else \
                     f"NIE zgadza się (policzona {oczekiwana:02X})"
            print(f"  suma      : {suma:02X} — {zgodna}")
            print()
            print("  Jeśli to DT1 i suma się zgadza — moduł obsługuje odczyt")
            print("  parametrów po SysEx. To jest wynik, na który czekamy.")
            return 0

    print("  Nie znalazłem polecenia 0x11 ani 0x12 w spodziewanym miejscu.")
    print(f"  Surowo: {as_hex(b)}")
    return 0


# --------------------------------------------------------------------------
# Wiersz poleceń
# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="roland-probe.py",
        description="Generator komunikatów RQ1 do sondowania modułu Roland."
                    " Generuje wyłącznie pytania — nigdy zapisu.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_sweep = sub.add_parser("sweep", help="zamiatanie po model ID")
    p_sweep.add_argument("--out", default="probe-tm2.syx")
    p_sweep.add_argument("--device", type=lambda x: int(x, 0), default=0x10,
                         help="device ID z Identity Reply (domyślnie 0x10)")
    p_sweep.add_argument("--first", type=lambda x: int(x, 0), default=0x00)
    p_sweep.add_argument("--last", type=lambda x: int(x, 0), default=0x7F)
    p_sweep.add_argument("--request-size", type=int, default=1,
                         help="ile bajtów prosimy (domyślnie 1)")
    p_sweep.add_argument("--only-1byte", action="store_true",
                         help="tylko warianty z jednobajtowym model ID")
    p_sweep.add_argument("--only-ext3", action="store_true",
                         help="tylko warianty z rozszerzonym ID 00 00 XX (3 B)")
    p_sweep.add_argument("--only-4byte", action="store_true",
                         help="tylko wariant z czterobajtowym model ID")
    p_sweep.add_argument("--list", action="store_true",
                         help="wypisać wszystkie wygenerowane komunikaty")
    p_sweep.set_defaults(func=cmd_sweep)

    p_rq1 = sub.add_parser("rq1", help="pojedyncze zapytanie o znanym model ID")
    p_rq1.add_argument("--model", required=True, help="np. 00,00,00,4B")
    p_rq1.add_argument("--addr", required=True, help="np. 00,00,00,00")
    p_rq1.add_argument("--size", required=True, help="np. 00,00,00,10")
    p_rq1.add_argument("--device", type=lambda x: int(x, 0), default=0x10)
    p_rq1.add_argument("--out", default=None)
    p_rq1.set_defaults(func=cmd_rq1)

    p_id = sub.add_parser("identity", help="rozbiór Identity Reply")
    p_id.add_argument("hex", help="bajty w hex, np. \"F0 7E 10 06 02 41 ...\"")
    p_id.set_defaults(func=cmd_identity)

    p_dec = sub.add_parser("decode", help="rozbiór dowolnego komunikatu Rolanda")
    p_dec.add_argument("hex", help="bajty w hex")
    p_dec.set_defaults(func=cmd_decode)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
