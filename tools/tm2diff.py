#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tm2diff — analizator plików BACKUP modułu Roland TM-2.

Narzędzie do mapowania różnicowego: nie sondujemy adresów w module, tylko
porównujemy zrzuty BACKUP różniące się jednym parametrem i patrzymy, które
bajty się ruszyły.

Wymaga wyłącznie biblioteki standardowej Pythona 3.8+. Nic nie wysyła do sieci,
nie modyfikuje plików wejściowych — otwiera je wyłącznie do odczytu.

Polecenia
---------
  inspect PLIK...            rozpoznanie pojedynczego pliku: rozmiar, magic,
                             entropia, ciągi ASCII, wykryty okres struktury
  diff A B                   mapa różnic między dwoma plikami
  series KATALOG             pełna analiza serii 0..5 z odsiewaniem szumu
  hex PLIK -o OFFSET -n LEN  podgląd heks fragmentu
  period PLIK                sama detekcja okresu (stride) struktury
  checksum PLIK               rozpoznanie sumy kontrolnej — policzone, nie zgadnięte
  gen KATALOG                wygenerowanie sztucznej serii testowej
                             (do sprawdzenia, czy narzędzie działa)

Konwencja nazw dla polecenia `series`
-------------------------------------
W katalogu mają leżeć pliki, których nazwa zaczyna się od numeru z protokołu:
  0_*  stan wyjściowy
  1_*  ten sam stan, drugi zapis      -> z pary 0/1 wychodzi SZUM
  2_*  nazwa kitu 1 = AAAAAAAA
  3_*  poziom pada 1 w kicie 1 +1
  4_*  ten sam parametr na min / max
  5_*  ten sam parametr, ale w kicie 2
Rozszerzenie i reszta nazwy dowolne.
"""

from __future__ import annotations

import argparse
import collections
import math
import os
import re
import hashlib
import sys

CONTEXT = 16
GROUP_GAP = 8
PERIOD_MIN = 8
PERIOD_MAX = 8192
MIN_STRING = 4
ENTROPY_ALARM = 7.5


def read_file(path: str) -> bytes:
    with open(path, "rb") as fh:
        return fh.read()


def human(n: int) -> str:
    for unit in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or unit == "GiB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024.0
    return f"{n} B"


def entropy(data: bytes) -> float:
    if not data:
        return 0.0
    counts = collections.Counter(data)
    total = len(data)
    result = 0.0
    for count in counts.values():
        p = count / total
        result -= p * math.log2(p)
    return result


def printable_ratio(data: bytes) -> float:
    if not data:
        return 0.0
    good = sum(1 for b in data if 32 <= b < 127)
    return good / len(data)


def hexdump(data: bytes, start: int = 0, length: int | None = None,
            highlight: set[int] | None = None) -> str:
    highlight = highlight or set()
    if length is None:
        length = len(data) - start
    end = min(start + length, len(data))
    lines = []
    row = start - (start % 16)
    while row < end:
        cells, chars = [], []
        for col in range(16):
            off = row + col
            if off < start or off >= end:
                cells.append("   "); chars.append(" "); continue
            byte = data[off]
            cells.append(f"[{byte:02X}]" if off in highlight else f" {byte:02X} ")
            chars.append(chr(byte) if 32 <= byte < 127 else ".")
        lines.append(f"{row:08X}  {''.join(cells)}  |{''.join(chars)}|")
        row += 16
    return "\n".join(lines)


def find_strings(data: bytes, minimum: int = MIN_STRING) -> list[tuple[int, str]]:
    out = []
    current = bytearray()
    start = 0
    for index, byte in enumerate(data):
        if 32 <= byte < 127:
            if not current:
                start = index
            current.append(byte)
        else:
            if len(current) >= minimum:
                out.append((start, current.decode("ascii", "replace")))
            current = bytearray()
    if len(current) >= minimum:
        out.append((start, current.decode("ascii", "replace")))
    return out


def find_utf16le_strings(data: bytes, minimum: int = MIN_STRING) -> list[tuple[int, str]]:
    # Roland koduje nazwy (przynajmniej nazwy kitów) jako UTF-16LE, nie ASCII —
    # znalezione ręcznie na pierwszym prawdziwym backupie: "New Kit    " leżało
    # jako bajty drukowalne przeplecione zerami, których find_strings() nie
    # widzi (pojedynczy znak między zerami nie osiąga progu minimalnej długości).
    out = []
    pattern = re.compile(rb"(?:[\x20-\x7e]\x00){%d,}" % minimum)
    for match in pattern.finditer(data):
        out.append((match.start(), match.group().decode("utf-16-le")))
    return out


def find_pattern(data: bytes, needle: bytes) -> list[int]:
    out = []
    pos = data.find(needle)
    while pos != -1:
        out.append(pos)
        pos = data.find(needle, pos + 1)
    return out


def period_scores(data: bytes, pmin: int = PERIOD_MIN,
                  pmax: int = PERIOD_MAX, sample: int = 65536) -> list[tuple[int, float]]:
    n = len(data)
    if n < pmin * 4:
        return []
    limit = min(n, sample)
    window = data[:limit]
    pmax = min(pmax, limit // 3)
    scores = []
    for period in range(pmin, pmax + 1):
        comparisons = limit - period
        if comparisons < 64:
            break
        equal = 0
        for i in range(comparisons):
            if window[i] == window[i + period]:
                equal += 1
        scores.append((period, equal / comparisons))
    scores.sort(key=lambda item: item[1], reverse=True)
    return scores


def dedupe_harmonics(scores: list[tuple[int, float]], keep: int = 10) -> list[tuple[int, float]]:
    out: list[tuple[int, float]] = []
    for period, score in scores:
        if any(period % kept == 0 for kept, _ in out):
            continue
        out.append((period, score))
        if len(out) >= keep:
            break
    return out


def diff_offsets(a: bytes, b: bytes) -> list[int]:
    shorter = min(len(a), len(b))
    return [i for i in range(shorter) if a[i] != b[i]]


def group_offsets(offsets: list[int], gap: int = GROUP_GAP) -> list[tuple[int, int]]:
    if not offsets:
        return []
    groups = []
    start = previous = offsets[0]
    for off in offsets[1:]:
        if off - previous <= gap:
            previous = off
            continue
        groups.append((start, previous))
        start = previous = off
    groups.append((start, previous))
    return groups


def describe_change(a: bytes, b: bytes, offset: int) -> str:
    x, y = a[offset], b[offset]
    delta = y - x
    parts = [f"{x:02X}->{y:02X}", f"dec {x}->{y}", f"delta {delta:+d}"]
    sx = x - 256 if x > 127 else x
    sy = y - 256 if y > 127 else y
    if (sx, sy) != (x, y):
        parts.append(f"signed {sx}->{sy}")
    xor = x ^ y
    if bin(xor).count("1") <= 2:
        bits = [str(i) for i in range(8) if xor & (1 << i)]
        parts.append(f"bity {','.join(bits)}")
    if 32 <= x < 127 or 32 <= y < 127:
        ca = chr(x) if 32 <= x < 127 else "."
        cb = chr(y) if 32 <= y < 127 else "."
        parts.append(f"ascii '{ca}'->'{cb}'")
    return "  ".join(parts)


# --------------------------------------------------------------------------
# Sumy kontrolne
# --------------------------------------------------------------------------

def _crc16_modbus(data: bytes) -> int:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def _crc32(data: bytes) -> int:
    import zlib
    return zlib.crc32(data) & 0xFFFFFFFF


def checksum_candidates(data: bytes, offset: int, length: int) -> list[str]:
    """Sprawdza, czy `length` bajtów pod `offset` to suma kontrolna reszty pliku.

    To jest odpowiedź na pułapkę widoczną dopiero w praktyce: jeśli plik ma
    licznik zapisów, suma kontrolna zmienia się przy KAŻDYM zapisie — także
    między plikiem 0 a 1 — więc wpada do maski szumu i znika z mapy różnic.
    Trzeba ją wtedy znaleźć wprost, licząc, a nie wnioskując z różnic.
    """
    import hashlib
    import struct

    if offset < 0 or offset + length > len(data):
        return []

    stored = data[offset:offset + length]
    covered = data[:offset] + data[offset + length:]
    matches: list[str] = []

    if length == 1:
        total = sum(covered) & 0xFF
        if bytes([total]) == stored:
            matches.append("suma 8-bit")
        xor_value = 0
        for byte in covered:
            xor_value ^= byte
        if bytes([xor_value]) == stored:
            matches.append("XOR 8-bit")

    if length == 2:
        crc = _crc16_modbus(covered)
        if struct.pack("<H", crc) == stored:
            matches.append("CRC-16/MODBUS (LE)")
        if struct.pack(">H", crc) == stored:
            matches.append("CRC-16/MODBUS (BE)")
        total = sum(covered) & 0xFFFF
        if struct.pack("<H", total) == stored:
            matches.append("suma 16-bit (LE)")
        if struct.pack(">H", total) == stored:
            matches.append("suma 16-bit (BE)")

    if length == 4:
        crc = _crc32(covered)
        if struct.pack("<I", crc) == stored:
            matches.append("CRC-32 (LE)")
        if struct.pack(">I", crc) == stored:
            matches.append("CRC-32 (BE)")
        total = sum(covered) & 0xFFFFFFFF
        if struct.pack("<I", total) == stored:
            matches.append("suma 32-bit (LE)")
        if struct.pack(">I", total) == stored:
            matches.append("suma 32-bit (BE)")

    if length == 16 and hashlib.md5(covered).digest() == stored:
        matches.append("MD5")
    if length == 20 and hashlib.sha1(covered).digest() == stored:
        matches.append("SHA-1")
    if length == 32 and hashlib.sha256(covered).digest() == stored:
        matches.append("SHA-256")

    return matches


def hunt_checksum(data: bytes, regions: list[tuple[int, int]]) -> list[tuple[int, int, list[str]]]:
    results: list[tuple[int, int, list[str]]] = []
    seen: set[tuple[int, int]] = set()
    for start, end in regions:
        span = end - start + 1
        for length in (1, 2, 4, 16, 20, 32):
            if length < span:
                continue
            first = end - length + 1
            for offset in range(first, start + 1):
                if offset < 0 or offset + length > len(data):
                    continue
                key = (offset, length)
                if key in seen:
                    continue
                seen.add(key)
                found = checksum_candidates(data, offset, length)
                if found:
                    results.append((offset, length, found))
    return results


def cmd_checksum(args) -> int:
    data = read_file(args.file)
    if args.offset is not None:
        length = args.length or 1
        found = checksum_candidates(data, args.offset, length)
        print(f"PLIK: {args.file} ({len(data)} B)")
        print(f"Kandydat: offset {args.offset:#x}, długość {length} B")
        if found:
            for name in found:
                print(f"  PASUJE: {name}")
        else:
            print("  Żaden z prostych algorytmów nie pasuje.")
        return 0

    print(f"PLIK: {args.file} ({len(data)} B)")
    print("Przemiatam koniec i początek pliku w poszukiwaniu sumy kontrolnej...\n")
    regions = []
    for length in (1, 2, 4, 16, 20, 32):
        regions.append((len(data) - length, len(data) - 1))
    for start in range(0, min(64, len(data))):
        regions.append((start, start))
    hits = hunt_checksum(data, regions)
    if hits:
        for offset, length, names in hits:
            print(f"  {offset:#08x}  {length} B  ->  {', '.join(names)}")
    else:
        print("  Nic nie pasuje. Albo pliku nie chroni suma, albo obejmuje ona"
              " inny zakres niż 'cały plik poza sumą' — spróbuj wskazać"
              " offset i długość ręcznie (--offset, --length).")
    return 0


# --------------------------------------------------------------------------
# Polecenie: inspect
# --------------------------------------------------------------------------

def cmd_inspect(args) -> int:
    for path in args.files:
        data = read_file(path)
        print("=" * 78)
        print(f"PLIK: {path}")
        print("=" * 78)
        print(f"  rozmiar        : {len(data)} bajtów ({human(len(data))})")
        if len(data) == 0:
            print("  PUSTY PLIK")
            continue
        print(f"  pierwsze 16 B  : {data[:16].hex(' ').upper()}")
        print(f"  ostatnie 16 B  : {data[-16:].hex(' ').upper()}")

        ent = entropy(data)
        print(f"  entropia       : {ent:.3f} bit/bajt", end="")
        if ent > ENTROPY_ALARM:
            print("   <-- UWAGA: możliwa kompresja lub szyfrowanie")
        else:
            print("   (poniżej progu alarmowego — dane wyglądają na surowe)")

        print(f"  bajty drukowalne: {printable_ratio(data) * 100:.1f}%")

        counts = collections.Counter(data)
        top = counts.most_common(3)
        summary = ", ".join(f"{b:02X} x{c} ({c / len(data) * 100:.0f}%)" for b, c in top)
        print(f"  najczęstsze    : {summary}")
        print(f"  różnych wartości bajtu: {len(counts)} / 256")

        block = 4096
        if len(data) > block * 2:
            print(f"\n  Entropia w blokach po {block} B:")
            for start in range(0, len(data), block):
                chunk = data[start:start + block]
                e = entropy(chunk)
                bar = "#" * int(e * 6)
                flag = "  <-- wysoka" if e > ENTROPY_ALARM else ""
                print(f"    {start:08X}  {e:5.2f}  {bar}{flag}")

        strings = find_strings(data)
        print(f"\n  Ciągi ASCII (min {MIN_STRING} znaków): {len(strings)}")
        for off, text in strings[:args.strings]:
            print(f"    {off:08X}  {text!r}")
        if len(strings) > args.strings:
            print(f"    ... i jeszcze {len(strings) - args.strings}"
                  f" (zwiększ --strings, żeby zobaczyć więcej)")

        strings16 = find_utf16le_strings(data)
        print(f"\n  Ciągi UTF-16LE (min {MIN_STRING} znaków): {len(strings16)}")
        for off, text in strings16[:args.strings]:
            print(f"    {off:08X}  {text!r}")
        if len(strings16) > args.strings:
            print(f"    ... i jeszcze {len(strings16) - args.strings}"
                  f" (zwiększ --strings, żeby zobaczyć więcej)")
        if len(strings16) >= 2:
            gaps = collections.Counter(
                b_off - a_off for (a_off, _), (b_off, _) in zip(strings16, strings16[1:])
            )
            common_gap, hits = gaps.most_common(1)[0]
            if hits >= 2:
                print(f"    odstęp między kolejnymi ciągami: {common_gap} B "
                      f"występuje {hits}x — prawdopodobny stride bloku")

        trailer_len = 16
        if len(data) > trailer_len:
            trailer = data[-trailer_len:]
            computed = hashlib.md5(data[:-trailer_len]).digest()
            print(f"\n  Ostatnie {trailer_len} B jako możliwa suma MD5 pliku:")
            print(f"    zapisane w pliku : {trailer.hex()}")
            print(f"    MD5(reszta pliku): {computed.hex()}"
                  + ("   <-- ZGODNE" if computed == trailer else ""))

        if not args.no_period:
            print("\n  Kandydaci na okres struktury (stride):")
            scores = dedupe_harmonics(period_scores(data))
            if not scores:
                print("    plik za krótki na sensowną analizę")
            else:
                baseline = sum(s for _, s in scores) / len(scores)
                for period, score in scores:
                    mark = "  <-- wyraźnie odstaje" if score > baseline * 1.15 else ""
                    print(f"    {period:6d} B   zgodność {score * 100:5.1f}%{mark}")
                print("    (jeśli któryś okres odstaje, to prawdopodobnie rozmiar"
                      " bloku kitu; 99 x ten rozmiar powinno zmieścić się w pliku)")
                best = scores[0][0]
                if best:
                    print(f"    99 x {best} = {99 * best} B, plik ma {len(data)} B"
                          f" -> reszta {len(data) - 99 * best} B")
        print()
    return 0


# --------------------------------------------------------------------------
# Polecenie: diff
# --------------------------------------------------------------------------

def diff_report(a: bytes, b: bytes, name_a: str, name_b: str,
                ignore: set[int] | None = None, max_groups: int = 60,
                show_hex: bool = True) -> list[int]:
    ignore = ignore or set()
    print(f"  {name_a}  ->  {name_b}")
    if len(a) != len(b):
        print(f"  UWAGA: różne rozmiary: {len(a)} vs {len(b)} bajtów"
              f" (różnica {len(b) - len(a):+d}) — sam rozmiar jest informacją")

    raw = diff_offsets(a, b)
    offsets = [o for o in raw if o not in ignore]
    ignored_count = len(raw) - len(offsets)

    print(f"  różniących się bajtów: {len(raw)}", end="")
    if ignore:
        print(f"  (w tym {ignored_count} odsianych jako szum)")
    else:
        print()

    if not offsets:
        print("  Po odsianiu szumu nie zostało nic.")
        return offsets

    groups = group_offsets(offsets)
    print(f"  grup (odległość <= {GROUP_GAP} B): {len(groups)}\n")

    for index, (start, end) in enumerate(groups[:max_groups], 1):
        span = end - start + 1
        print(f"  --- grupa {index}: offset {start:#08x} ({start})"
              f"  długość {span} B ---")
        for off in range(start, end + 1):
            if off in offsets:
                print(f"      {off:#08x}  {describe_change(a, b, off)}")
        if show_hex:
            lo = max(0, start - CONTEXT)
            hi = min(len(a), end + 1 + CONTEXT)
            marked = set(range(start, end + 1)) & set(offsets)
            print("    przed:")
            for line in hexdump(a, lo, hi - lo, marked).splitlines():
                print(f"      {line}")
            print("    po:")
            for line in hexdump(b, lo, hi - lo, marked).splitlines():
                print(f"      {line}")
        print()

    if len(groups) > max_groups:
        print(f"  ... i jeszcze {len(groups) - max_groups} grup\n")
    return offsets


def cmd_diff(args) -> int:
    a = read_file(args.file_a)
    b = read_file(args.file_b)
    print("=" * 78)
    print("MAPA RÓŻNIC")
    print("=" * 78)
    diff_report(a, b, os.path.basename(args.file_a), os.path.basename(args.file_b),
                max_groups=args.max_groups, show_hex=not args.no_hex)
    return 0


# --------------------------------------------------------------------------
# Polecenie: series
# --------------------------------------------------------------------------

SERIES_LABELS = {
    0: "stan wyjściowy (punkt odniesienia)",
    1: "ten sam stan, drugi zapis — z pary 0/1 wychodzi SZUM",
    2: "nazwa kitu 1 = AAAAAAAA — kotwica ASCII",
    3: "poziom pada 1 w kicie 1 o +1 — pojedynczy bajt parametru",
    4: "ten sam parametr na min/max — zakres i skala",
    5: "ten sam parametr, ale w kicie 2 — stride między kitami",
}


def load_series(directory: str) -> dict[int, tuple[str, bytes]]:
    found: dict[int, tuple[str, bytes]] = {}
    for entry in sorted(os.listdir(directory)):
        match = re.match(r"^(\d+)", entry)
        if not match:
            continue
        path = os.path.join(directory, entry)
        if not os.path.isfile(path):
            continue
        number = int(match.group(1))
        if number in found:
            print(f"  UWAGA: numer {number} występuje więcej niż raz"
                  f" — pomijam {entry}", file=sys.stderr)
            continue
        found[number] = (entry, read_file(path))
    return found


def cmd_series(args) -> int:
    files = load_series(args.directory)
    if not files:
        print(f"Nie znalazłem w {args.directory} żadnego pliku"
              f" zaczynającego się od numeru (0_, 1_, ...).", file=sys.stderr)
        return 1

    print("=" * 78)
    print("ANALIZA SERII MAPOWANIA RÓŻNICOWEGO")
    print("=" * 78)
    print(f"katalog: {args.directory}\n")
    print("Wczytane pliki:")
    for number in sorted(files):
        name, data = files[number]
        label = SERIES_LABELS.get(number, "plik spoza standardowej serii")
        print(f"  {number}: {name:<32} {len(data):>9} B   {label}")
    print()

    sizes = {len(d) for _, d in files.values()}
    if len(sizes) > 1:
        print("UWAGA: pliki mają różne rozmiary.\n")

    noise: set[int] = set()
    if 0 in files and 1 in files:
        print("-" * 78)
        print("KROK 1 — SZUM (plik 0 vs plik 1, ten sam stan modułu)")
        print("-" * 78)
        a, b = files[0][1], files[1][1]
        raw = diff_offsets(a, b)
        noise = set(raw)
        print(f"  bajtów zmiennych mimo braku zmiany w module: {len(raw)}")
        if not raw:
            print("  Zero różnic — dobra wiadomość.")
        else:
            for start, end in group_offsets(raw):
                print(f"    szum: {start:#08x}..{end:#08x} ({end - start + 1} B)")
        print()
    else:
        print("BRAK pliku 0 lub 1 — nie mam czym odsiać szumu.\n")

    base = files[0][1] if 0 in files else None
    anchor_offset = None
    if 2 in files and base is not None:
        print("-" * 78)
        print("KROK 2 — KOTWICA ASCII (plik 0 vs plik 2, nazwa kitu 1)")
        print("-" * 78)
        data2 = files[2][1]
        hits = find_pattern(data2, args.anchor.encode("ascii"))
        if hits:
            anchor_offset = hits[0]
            print(f"  Wzorzec {args.anchor!r} znaleziony {len(hits)} raz(y):")
            for off in hits[:20]:
                print(f"    {off:#08x} ({off})")
            print(f"\n  Przyjmuję początek bloku kitu 1 = {anchor_offset:#08x}"
                  f" ({anchor_offset}).")
        else:
            print(f"  Wzorca {args.anchor!r} NIE MA w pliku 2 jako czystego ASCII.")
        diff_report(base, data2, files[0][0], files[2][0], ignore=noise,
                    max_groups=args.max_groups, show_hex=not args.no_hex)

    param_offsets: list[int] = []
    if 3 in files and base is not None:
        print("-" * 78)
        print("KROK 3 — POJEDYNCZY PARAMETR (plik 0 vs plik 3, poziom pada +1)")
        print("-" * 78)
        param_offsets = diff_report(base, files[3][1], files[0][0], files[3][0],
                                    ignore=noise, max_groups=args.max_groups,
                                    show_hex=not args.no_hex)
        if len(param_offsets) == 1:
            print("  Idealnie: dokładnie jeden bajt. To adres parametru.")
        elif param_offsets:
            print(f"  {len(param_offsets)} bajtów — druga grupa to zapewne suma kontrolna.")
        if anchor_offset is not None and param_offsets:
            print("\n  Pozycje parametru względem kotwicy (początku kitu 1):")
            for off in param_offsets[:20]:
                print(f"    {off:#08x} - {anchor_offset:#08x}"
                      f" = {off - anchor_offset:+d} B")
        print()

    if 4 in files and base is not None:
        print("-" * 78)
        print("KROK 4 — ZAKRES I SKALA (plik 0 vs plik 4, parametr na min/max)")
        print("-" * 78)
        range_offsets = diff_report(base, files[4][1], files[0][0], files[4][0],
                                    ignore=noise, max_groups=args.max_groups,
                                    show_hex=not args.no_hex)
        common = sorted(set(range_offsets) & set(param_offsets))
        if common:
            print("  Bajty ruszające się i w kroku 3, i w kroku 4:")
            for off in common:
                v0 = base[off]
                v3 = files[3][1][off] if 3 in files else None
                v4 = files[4][1][off]
                extra = f", w pliku 3 = {v3}" if v3 is not None else ""
                print(f"    {off:#08x}: w pliku 0 = {v0}{extra}, w pliku 4 = {v4}")
        print()

    if 5 in files and base is not None:
        print("-" * 78)
        print("KROK 5 — STRIDE MIĘDZY KITAMI (plik 0 vs plik 5, ten sam parametr w kicie 2)")
        print("-" * 78)
        kit2_offsets = diff_report(base, files[5][1], files[0][0], files[5][0],
                                   ignore=noise, max_groups=args.max_groups,
                                   show_hex=not args.no_hex)
        if param_offsets and kit2_offsets:
            print("  Wyliczony stride:")
            candidates = []
            for o1 in param_offsets:
                for o2 in kit2_offsets:
                    if o2 <= o1:
                        continue
                    stride = o2 - o1
                    candidates.append(stride)
                    fits = 99 * stride
                    verdict = "mieści się" if fits <= len(base) else "NIE MIEŚCI SIĘ"
                    print(f"    {o2:#08x} - {o1:#08x} = {stride} B"
                          f"   ->  99 x {stride} = {fits} B, plik ma {len(base)} B"
                          f"  ({verdict})")
            plausible = [s for s in candidates if 99 * s <= len(base)]
            if plausible:
                best = min(plausible)
                print(f"\n  Najbardziej prawdopodobny rozmiar bloku kitu: {best} B.")
                if anchor_offset is not None:
                    for kit in range(1, 6):
                        addr = anchor_offset + (kit - 1) * best
                        print(f"    kit {kit}: {addr:#08x}")
        print()

    changing_always = None
    for number in (2, 3, 4, 5):
        if number not in files or base is None:
            continue
        offs = set(diff_offsets(base, files[number][1]))
        changing_always = offs if changing_always is None else (changing_always & offs)

    print("=" * 78)
    print("PODSUMOWANIE")
    print("=" * 78)

    checksum_offsets = sorted(changing_always - noise) if changing_always else []
    counter_bytes = sorted(changing_always & noise) if changing_always else []

    if counter_bytes:
        print("  Bajty zmienne zawsze, rozpoznane wcześniej jako szum:")
        for start, end in group_offsets(counter_bytes):
            print(f"    {start:#08x}..{end:#08x} ({end - start + 1} B)")
        print()

    if checksum_offsets:
        print("  Bajty zmieniające się przy KAŻDEJ zmianie treści, a niebędące szumem:")
        for start, end in group_offsets(checksum_offsets):
            print(f"    {start:#08x}..{end:#08x} ({end - start + 1} B)")
    elif not counter_bytes:
        print("  Nie znalazłem bajtów wspólnych dla wszystkich zmian.")

    if base is not None:
        regions = group_offsets(sorted(changing_always or []))
        regions += group_offsets(sorted(noise))
        for length in (1, 2, 4, 16, 20, 32):
            if len(base) >= length:
                regions.append((len(base) - length, len(base) - 1))
        hits = hunt_checksum(base, regions)
        print()
        if hits:
            print("  ROZPOZNANA SUMA KONTROLNA (policzona, nie zgadnięta):")
            for offset, length, names in hits:
                print(f"    {offset:#08x}  {length} B  ->  {', '.join(names)}")
        else:
            print("  Polowanie na sumę: żaden prosty algorytm nie pasuje.")
    print()
    return 0


# --------------------------------------------------------------------------
# Polecenie: hex / period
# --------------------------------------------------------------------------

def cmd_hex(args) -> int:
    data = read_file(args.file)
    start = args.offset
    if start < 0:
        start = max(0, len(data) + start)
    print(hexdump(data, start, args.length))
    return 0


def cmd_period(args) -> int:
    data = read_file(args.file)
    scores = period_scores(data, args.min, args.max)
    if not scores:
        print("Plik za krótki na analizę okresu.")
        return 1
    print(f"PLIK: {args.file}  ({len(data)} B)")
    print("Kandydaci na okres struktury, po odsianiu harmonicznych:\n")
    for period, score in dedupe_harmonics(scores, keep=args.top):
        fits = 99 * period
        note = ""
        if fits <= len(data):
            note = f"   99 x {period} = {fits} B, zostaje {len(data) - fits} B"
        print(f"  {period:6d} B   zgodność {score * 100:5.1f}%{note}")
    return 0


# --------------------------------------------------------------------------
# Polecenie: gen
# --------------------------------------------------------------------------

def cmd_gen(args) -> int:
    import random
    import struct

    os.makedirs(args.directory, exist_ok=True)
    header = 64
    kit_size = 128
    kits = 99
    name_len = 8
    level_off = 32
    total = header + kits * kit_size + 4
    rng = random.Random(1972)

    def build(kit_names, levels, counter):
        buf = bytearray(total)
        buf[0:4] = b"TM2B"
        buf[4:8] = struct.pack("<I", counter)
        for i in range(8, header):
            buf[i] = rng.randrange(0, 256) if i < 16 else 0
        for kit in range(kits):
            base_off = header + kit * kit_size
            name = kit_names.get(kit, f"KIT{kit + 1:02d}   ")[:name_len]
            buf[base_off:base_off + name_len] = name.ljust(name_len).encode("ascii")
            buf[base_off + level_off] = levels.get(kit, 100)
            buf[base_off + 33] = 64
            buf[base_off + 34] = 12
        checksum = sum(buf[:-4]) & 0xFFFFFFFF
        buf[-4:] = struct.pack("<I", checksum)
        return bytes(buf)

    reference = build({}, {}, 1)
    fixed_head = reference[8:16]

    def build_fixed(kit_names, levels, counter):
        raw = bytearray(build(kit_names, levels, counter))
        raw[8:16] = fixed_head
        raw[-4:] = struct.pack("<I", sum(raw[:-4]) & 0xFFFFFFFF)
        return bytes(raw)

    series = [
        ("0_stan_wyjsciowy.bin", build_fixed({}, {}, 1)),
        ("1_ten_sam_stan.bin", build_fixed({}, {}, 2)),
        ("2_nazwa_kitu1.bin", build_fixed({0: "AAAAAAAA"}, {}, 3)),
        ("3_poziom_plus1.bin", build_fixed({}, {0: 101}, 4)),
        ("4_poziom_max.bin", build_fixed({}, {0: 127}, 5)),
        ("5_poziom_kit2.bin", build_fixed({}, {1: 101}, 6)),
    ]
    for name, blob in series:
        path = os.path.join(args.directory, name)
        with open(path, "wb") as fh:
            fh.write(blob)
        print(f"  zapisano {path}  ({len(blob)} B)")
    print(f"\nkit 1 pod {header:#x}, stride {kit_size} B, poziom +{level_off}")
    print(f"Teraz: python3 tm2diff.py series {args.directory}")
    return 0


# --------------------------------------------------------------------------
# Wiersz poleceń
# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="tm2diff.py",
        description="Analizator plików BACKUP Roland TM-2 (mapowanie różnicowe).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_inspect = sub.add_parser("inspect", help="rozpoznanie pojedynczego pliku")
    p_inspect.add_argument("files", nargs="+")
    p_inspect.add_argument("--strings", type=int, default=40)
    p_inspect.add_argument("--no-period", action="store_true")
    p_inspect.set_defaults(func=cmd_inspect)

    p_diff = sub.add_parser("diff", help="mapa różnic dwóch plików")
    p_diff.add_argument("file_a")
    p_diff.add_argument("file_b")
    p_diff.add_argument("--max-groups", type=int, default=60)
    p_diff.add_argument("--no-hex", action="store_true")
    p_diff.set_defaults(func=cmd_diff)

    p_series = sub.add_parser("series", help="analiza całej serii 0..5")
    p_series.add_argument("directory")
    p_series.add_argument("--anchor", default="AAAAAAAA")
    p_series.add_argument("--max-groups", type=int, default=30)
    p_series.add_argument("--no-hex", action="store_true")
    p_series.set_defaults(func=cmd_series)

    p_hex = sub.add_parser("hex", help="podgląd heks fragmentu")
    p_hex.add_argument("file")
    p_hex.add_argument("-o", "--offset", type=int, default=0)
    p_hex.add_argument("-n", "--length", type=int, default=256)
    p_hex.set_defaults(func=cmd_hex)

    p_period = sub.add_parser("period", help="detekcja okresu struktury")
    p_period.add_argument("file")
    p_period.add_argument("--min", type=int, default=PERIOD_MIN)
    p_period.add_argument("--max", type=int, default=PERIOD_MAX)
    p_period.add_argument("--top", type=int, default=15)
    p_period.set_defaults(func=cmd_period)

    p_check = sub.add_parser("checksum", help="rozpoznanie sumy kontrolnej")
    p_check.add_argument("file")
    p_check.add_argument("-o", "--offset", type=int, default=None)
    p_check.add_argument("-n", "--length", type=int, default=None)
    p_check.set_defaults(func=cmd_checksum)

    p_gen = sub.add_parser("gen", help="wygenerowanie sztucznej serii testowej")
    p_gen.add_argument("directory")
    p_gen.set_defaults(func=cmd_gen)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except FileNotFoundError as exc:
        print(f"Nie ma takiego pliku: {exc.filename}", file=sys.stderr)
        return 1
    except IsADirectoryError as exc:
        print(f"To katalog, nie plik: {exc.filename}", file=sys.stderr)
        return 1
    except BrokenPipeError:
        return 0


if __name__ == "__main__":
    sys.exit(main())
