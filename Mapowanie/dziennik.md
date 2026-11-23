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
Mapa parametrów: `Sources/TM2Editor/Model/ParametryEfektow.swift`.

---
