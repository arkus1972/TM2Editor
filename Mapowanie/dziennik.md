# Dziennik mapowania TM-2

Notatki ręczne. Pełny zapis ustaleń jest w Projekcie claude.ai
„ROLAND TM-2 EDYTOR", dokument `04-dziennik-mapowania.md`.
Wyniki pojedynczych analiz widać w logach przebiegów w zakładce Actions.

## Pliki bazowe

| Plik | Data | MD5 (skrót) | Kit 1 |
|---|---|---|---|
| `archiwum/baza-2026-09-04.bin` | 2026-09-04 | `3556feb25e4f` | `Claps!` |
| `baza.bin` (aktualny) | 2026-11-21 | `571c9e36fbd3` | `CIECHOCINEK` |

Powód zmiany bazy: po przestawianiu kitów na koncert plik testowy dawał 68 grup
zmian zamiast kilku — zostałości przykryły właściwy pomiar.

## Zmapowane pola rekordu triggera (84 B)

| Offset | Pole | Kodowanie |
|---|---|---|
| +0x00 | Instrument | uint16 LE |
| +0x04 | Level | 0–100 wprost |
| +0x06 | Pitch | int16 LE ze znakiem, −120…+120 |
| +0x08 | Pan | 0…30, środek 15 (L15 / CENTER / R15) |
| +0x0E | Loop | 0 = OFF, 1 = ON |
| +0x1A | Offset | uint16 LE, 0,1 ms na jednostkę |

Rekord 1 = TRIG IN 1, rekord 2 = TRIG IN 2 (zmierzone 2026-11-21).
Head i rim jednego gniazda dzielą jeden rekord.
## 2026-11-22 — porządki: nowa baza i archiwum

Nowy plik bazowy: `pusty-2.bin` — stan modułu po serii z 2026-11-22, identyczny co do
bajtu z `pusty-1.bin` i `poly.bin`. Poprzednia baza przeniesiona do
`archiwum/baza-2026-11-21.bin`; wszystkie pliki pomiarowe z `nowe/` oraz `poly.bin`
(wrzucony do `Mapowanie/` zamiast do `nowe/`) — do `archiwum/`. Niczego nie usunięto.

Para `pusty-1.bin` / `pusty-2.bin` (dwa zapisy pod rząd, bez dotykania czegokolwiek)
jest identyczna: moduł nie ma licznika zapisów ani znacznika czasu. Każda różnica
między dwoma backupami pochodzi z przycisków.

---

## 2026-11-23 — efekty kitu: pliki pomiarowe do archiwum

| Plik | MD5 (skrót) | Co to jest |
|---|---|---|
| `archiwum/efekty-domyslne.bin` | `0e4aba7b5321` | kity 70–80 przestawione na kolejne efekty, parametry nietknięte (wartości domyślne). Wcześniej `nowe/efekty-1.bin`. |
| `archiwum/efekty-max.bin` | `1924b91704d3` | te same kity, każdy wyświetlany parametr na maksimum. Wgrany jako podmiana `nowe/efekty-1.bin` (commit `aaa7990`). |
| `archiwum/efekty-min.bin` | `93e01d29a696` | to samo na minimum (`BKUP-006`). Kit 71 przeskoczył przy tym z TAPE ECHO na DELAY. |

Uwaga na przyszłość: wgranie przez stronę GitHuba pliku o tej samej nazwie
i zawartości co istniejący daje **pusty commit** „Add files via upload". Tak
zginęły trzy próby z 23.11. TM-2 nie ma zegara — data plików na karcie jest stała,
nowy backup poznaje się tylko po numerze.

Do `archiwum/` poszły też `typy-1…9.bin` i `noise.bin` z 22.11. `nowe/` jest puste.

`archiwum/efekty-kolejnosc.bin` (`385262c5b359`, przesłany przez czat jako `plik.bin`):
FLANGER/PHASER Rate 1, Depth 2, Manual 3, Resonance 4, WAH Sens 1, Frequency 2,
Peak 3 — w pliku dokładnie po kolei, przypisanie potwierdzone. Przy okazji kit 75
przeskoczył z EQUALIZER na WAH (wartości domyślne WAH zgodne z tablicą co do bajtu),
a w kicie 70 LoCut/HiCut zostały na 800 Hz / FLAT po przeklikaniu list.
Mapa parametrów: `Sources/TM2Editor/Model/ParametryEfektow.swift`.

---
## 2026-11-23 — ustawienia SYSTEM: pliki pomiarowe

`archiwum/system-a…f.bin` — sześć backupów, każdy na poprzednim (A po
`efekty-kolejnosc.bin`). Wszystkie zmiany w nagłówku 0x2C…0x35:

| Plik | Zmiana na module | Bajty |
|---|---|---|
| a | Contrast 6, Brightness na minimum (1 — wynika ze skali z d), OutGain +12, MIDI Ch 3, TrgPreview OFF, Trig Lock ON | 0x2C 2→5, 0x2D 7→0, 0x30 0→12, 0x31 1→0, 0x32 0→1, 0x33 9→2 |
| b | PrgChg Rx OFF, Battery Ni-MH | 0x34 1→0, 0x2E 0→1 |
| c | PrgChg Tx OFF | 0x35 1→0 |
| d | Brightness 9, Limiter −23, MIDI Ch 14 | 0x2D 0→8, 0x2F 24→1, 0x33 2→13 |
| e | OutGain −6 | 0x30 12→250 |
| f | Limiter −10 | 0x2F 1→14 |

W `a` przy okazji: kit 77 DELAY z wartościami domyślnymi i Curve TRIG IN 1 na
LOUD2 (po przeklikaniu listy krzywych) — nie należą do serii.

---
## 2026-11-23 — sample z karty

| Plik | Co |
|---|---|
| `archiwum/wav-1.bin` | kit 70: TEST_A, TEST_B, TESTY/TEST_C przypisane na module |
| `archiwum/wav-2.bin` | po dodaniu TEST_0.wav (sortuje się wcześniej) — przypisania bez zmian, moduł szuka po nazwie |
| `archiwum/wav-test-z-edytora.bin` | plik zrobiony poza modułem: kit 71 z samplami, +0x00 = 0. BACKUP LOAD — oba zagrały |

Pułapka: pierwsza „cisza" na kicie 70 to nie sampel, tylko DELAY z Level 0 zostawiony
z serii minimów efektów (Level efektu to wyjście całego efektu, z sygnałem suchym).

---
