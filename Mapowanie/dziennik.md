# Dziennik mapowania TM-2

Ten plik dokumentuje bazę, na której pracuje CI (`.github/workflows/analiza-mapowania.yml`).
Sam dziennik z wynikami analiz CI **nie jest tu automatycznie dopisywany** —
wyniki widać w logu przebiegu w zakładce Actions na GitHubie, i to ten log
się kopiuje i wkleja do rozmowy. Ten plik służy do ręcznych notatek, jeśli
się przydadzą.

## Plik bazowy

- `baza.bin` — pierwszy prawdziwy BACKUP z modułu (`0_stan_wyjsciowy.bin`),
  124 748 B, MD5 `3556feb25e4fd0eb0fef0e9f89034ca4`.
- `pola.json` — stan wiedzy o formacie na dzień 2026-09-03 (ten sam zestaw co
  `BackupLayout.mapped2026_09_02` w kodzie Swift).
