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
