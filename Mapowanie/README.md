# Mapowanie różnicowe przez CI

Ten katalog to nie kod aplikacji — to dane robocze do mapowania formatu
BACKUP, analizowane automatycznie przez GitHub Actions przy każdym pushu.
Ten sam wzorzec pracy co przy PulsoKicie/TD-17: wrzucasz plik, CI go
analizuje, kopiujesz log przebiegu i wklejasz do rozmowy. Nic nie trzeba
uruchamiać lokalnie.

## Jak z tego korzystać

1. Zmień **jeden** parametr na module TM-2.
2. BACKUP SAVE na kartę, wyjmij plik.
3. Wrzuć ten plik do `Mapowanie/nowe/` w swojej kopii repo, pod dowolną
   nazwą (najlepiej opisową, np. `03-kit5-pan-max.bin` — nazwa trafia do
   logu, więc czytelna nazwa = czytelniejszy log).
4. `git add Mapowanie/nowe/twoj-plik.bin`, `git commit`, `git push`.
5. Wejdź na GitHubie w zakładkę **Actions**, znajdź przebieg
   „Analiza mapowania” (uruchamia się automatycznie po pushu), otwórz krok
   „Analiza plików w Mapowanie/nowe”.
6. Skopiuj log tego kroku (cały, albo przynajmniej sekcję dla swojego
   pliku) i wklej mi w rozmowie razem z opisem, co dokładnie zmieniłeś na
   module.

## Co robi CI

Dla każdego pliku `*.bin` w `Mapowanie/nowe/` uruchamia
`tools/tm2map.py analizuj` względem `Mapowanie/baza.bin`, korzystając ze
stanu wiedzy w `Mapowanie/pola.json`. W logu widać dwie sekcje: „już znane”
(zostałości poprzednich testów i spodziewane zmiany) i „NOWE / NIEZNANE” —
na tym drugim warto się skupić przy czytaniu.

## Pliki w tym katalogu

- `baza.bin` — plik odniesienia (pierwszy prawdziwy BACKUP z modułu,
  `0_stan_wyjsciowy.bin`). Nie zmieniaj go bez wyraźnego powodu — wszystkie
  analizy liczą się względem niego. Jeśli kiedyś potrzebna nowa baza (np. po
  uporządkowaniu ustawień na module), podmień plik i napisz o tym w rozmowie.
- `pola.json` — to, co już wiemy o formacie (ten sam stan co
  `BackupLayout.mapped2026_09_02` w kodzie Swift). Aktualizowany przeze mnie
  w miarę ustaleń — kolejne dostarczone paczki projektu będą to nosić.
- `nowe/` — tu wrzucasz kolejne pliki testowe. Zostają w repo (mała objętość,
  ~125 KB/plik) jako historia — nie trzeba ich usuwać.
- `dziennik.md` — luźne notatki ręczne, nie jest automatycznie aktualizowany
  przez CI (log przebiegu w Actions jest źródłem prawdy dla wyników).

## Dlaczego nie lokalny skrypt z menu

Wcześniejsza wersja (`tools/tm2map.py` uruchamiany lokalnie, z menu) też
działa i zostaje w repo jako opcja — ale wymaga uruchamiania Pythona
u siebie. To rozwiązanie (CI) jest bliższe temu, jak wyglądała praca przy
PulsoKicie: wrzucasz plik do repo, resztę robi GitHub.
