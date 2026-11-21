# Mapowanie różnicowe przez CI

Dane robocze do mapowania formatu BACKUP. Nie jest to kod aplikacji.

## Jak z tego korzystać

1. Zmień **jeden** parametr na module TM-2 i **zapisz sobie, co to było**.
2. BACKUP SAVE na kartę, wyjmij plik.
3. **W przeglądarce**, na github.com/arkus1972/TM2Editor: folder `Mapowanie/nowe`
   → **Add file** → **Upload files** → przeciągnij plik → **Commit changes**.
   Nazwa dowolna, byle rozszerzenie `.bin` i opisowa, np. `kit40-sens-max.bin` —
   nazwa trafia do logu.
4. Napisz w rozmowie, co zmieniłeś. Resztę robi Claude: klonuje repo i analizuje
   plik u siebie. Nie musisz wklejać logów z Actions.

Workflow `Analiza mapowania` i tak odpala się automatycznie po wrzuceniu pliku,
więc wynik możesz też podejrzeć sam w zakładce **Actions**.

## Pliki w tym katalogu

- **`baza.bin`** — plik odniesienia. Wszystkie analizy liczą się względem niego.
  Aktualny: BACKUP z 2026-11-21, MD5 `571c9e36fbd3…`, kit 1 = `CIECHOCINEK`.
- **`pola.json`** — stan wiedzy o formacie. Zwykły JSON, można go edytować ręcznie.
- **`nowe/`** — tu wrzucasz kolejne pliki testowe. Tylko te są analizowane przez CI.
- **`archiwum/`** — zrobione testy i poprzednie pliki bazowe. CI ich nie rusza.
- **`dziennik.md`** — notatki ręczne.

## Kiedy odświeżyć plik bazowy

Moduł zapisuje w BACKUP **cały swój aktualny stan**, nie różnicę. Każda zmiana,
której nie cofniesz — także zrobiona przypadkiem albo przy zwykłym używaniu
modułu — zostaje w pamięci i pojawia się w KAŻDYM kolejnym pliku jako zostałość.

Przy jednej, dwóch rundach to nie przeszkadza: analizator rozpoznaje znane pola
i odkłada je do osobnej sekcji. Ale gdy zostałości się nazbiera, prawdziwy pomiar
tonie w szumie — po przestawianiu kitów na koncert jeden plik dał **68 grup zmian**
zamiast spodziewanych kilku.

Wtedy trzeba odświeżyć bazę:

1. **Na module:** nic nie zmieniaj, zrób BACKUP SAVE.
2. **W przeglądarce:** wrzuć plik do `Mapowanie/` pod nazwą `baza.bin`
   (podmieniając istniejący), a stary przenieś do `archiwum/` z datą w nazwie.

Stare pliki testowe przenieś przy tej okazji do `archiwum/` — ich wyniki są już
zapisane w dzienniku projektu, a diffowanie ich względem nowej bazy nie ma sensu.

## Historia plików bazowych

| Plik | Data | Kit 1 | Uwagi |
|---|---|---|---|
| `archiwum/baza-2026-09-04.bin` | 2026-09-04 | `Claps!` | pierwszy BACKUP, na nim zmapowano 6 pól rekordu triggera |
| `baza.bin` | 2026-11-21 | `CIECHOCINEK` | po przestawieniu kitów na koncert |
