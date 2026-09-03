# TM-2 Editor

Edytor ustawień modułu perkusyjnego **Roland TM-2** na macOS. Czytelny ekran
zamiast dwuwierszowego wyświetlacza i grzebania w menu.

Darmowy, licencja MIT, bez łączenia się z internetem, bez zbierania czegokolwiek.

> **Stan projektu: format pliku BACKUP nie jest jeszcze rozpoznany.**
> Aplikacja otwiera plik i pozwala go obejrzeć bajt po bajcie, ale edycja
> parametrów jest wyłączona, dopóki nie znamy ich adresów. Odblokowuje ją
> seria mapowania różnicowego opisana w `DOKUMENTACJA/01-protokol-mapowania.md`.

---

## Dlaczego edytor pracuje na pliku, a nie na module

Roland nigdy nie opublikował dla TM-2 dokumentu *MIDI Implementation*.
W instrukcji nie ma nawet tabelki MIDI Implementation Chart. Modułu nie da się
zapytać „jaka jest teraz wartość parametru X" ani kazać mu „ustaw parametr X",
bo nie ma opublikowanej mapy adresów SysEx — a bez USB każde połączenie i tak
wymaga zewnętrznego interfejsu MIDI.

Jedyny udokumentowany komunikat, który TM-2 przyjmuje, to **Program Change
1–99** wybierające kit (wymaga ustawionego kanału MIDI i `PrgChg Rx = ON`).

Otwarta jest za to inna droga. Instrukcja, s. 15: funkcje **BACKUP SAVE /
BACKUP LOAD / BACKUP DELETE**, a przy nich zdanie: *„Backup will save all kits,
all settings of the TM-2, and the pad and drum trigger settings."* Czyli
komplet ustawień w jednym pliku na karcie SD.

To jest ten sam kształt pracy co pliki `.TD0` w PulsoKicie: edytujemy plik,
nie żywy sprzęt.

**I to jest bezpieczne.** Żaden bajt nie idzie kablem do modułu. Najgorsze, co
może się zdarzyć, to odrzucenie edytowanego pliku przez BACKUP LOAD — oryginał
zostaje na karcie nietknięty.

---

## Zasady bezpieczeństwa wbudowane w program

- **Nic nie jest wysyłane do modułu.** Program nie ma kodu MIDI. W ogóle.
- **Plik źródłowy nigdy nie jest nadpisywany.** Zapis idzie zawsze do nowego
  pliku, a próba zapisania pod ścieżką oryginału jest odrzucana.
- **Bez sieci.** Program nie łączy się z niczym i niczego nie wysyła.
- **Edycja tylko tego, co zmapowane.** Pole bez potwierdzonego offsetu jest
  widoczne, ale nieaktywne. Wolimy powiedzieć „nie wiem" niż wpisać bajt
  w przypadkowe miejsce.

---

## Struktura projektu

```
TM2Editor/
├─ Package.swift                  pakiet SwiftPM (otwiera się w Xcode)
├─ Sources/TM2Editor/
│  ├─ TM2EditorApp.swift          punkt wejścia i menu
│  ├─ Model/
│  │  ├─ ModuleProfile.swift      fakty o SPRZĘCIE (pewne)
│  │  ├─ BackupLayout.swift       opis PLIKU (hipotezy do potwierdzenia)
│  │  ├─ FieldSpec.swift          opis pojedynczego parametru
│  │  ├─ BackupFile.swift         odczyt i zapis bajtów
│  │  ├─ KitEditor.swift          lista zmian, cofanie, odroczony zapis
│  │  └─ AppModel.swift           stan aplikacji, wczytywanie układu
│  ├─ Support/
│  │  ├─ Checksum.swift           sumy kontrolne i ich rozpoznawanie
│  │  ├─ EditorLog.swift          dziennik zdarzeń
│  │  └─ FilePanels.swift         okna otwierania i zapisu
│  └─ Views/                      interfejs (po angielsku)
├─ Tests/TM2EditorTests/          testy na sztucznym pliku o znanym układzie
├─ tools/tm2diff.py               analizator różnicowy plików BACKUP
├─ Scripts/
│  ├─ zbuduj-app.sh               złożenie .app i podpis ad-hoc
│  ├─ sprawdz-nawiasy.py          kontrola balansu nawiasów w .swift
│  └─ Info.plist
├─ DOKUMENTACJA/
│  ├─ 00-dokument-startowy.md     założenia projektu
│  ├─ 01-protokol-mapowania.md    instrukcja serii do wykonania na module
│  └─ 02-format-pliku-backup.md   szkielet opisu formatu (do wypełnienia)
└─ .github/workflows/build.yml    kompilacja, testy, wydanie
```

Rozdzielenie `ModuleProfile` od `BackupLayout` jest celowe: pierwszy opisuje
sprzęt i pochodzi z instrukcji, drugi opisuje plik i pochodzi z naszych
pomiarów. Mieszanie ich to prosta droga do wpisania do kodu liczby, której
nikt nie zmierzył.

---

## Kolejność prac

1. **Identity Request** — sprawdzić, czy TM-2 w ogóle odpowiada na SysEx.
   Do tego wystarczy darmowe *SysEx Librarian* albo *MIDI Monitor* (Snoize):
   wyślij `F0 7E 7F 06 01 F7` i zobacz, czy coś wróci.
   Odpowiedź = w środku jest silnik SysEx i warto sondować dalej.
   Cisza = droga plikowa jest jedyna, i mamy to potwierdzone.

   > Do tego testu **nie używaj PulsoKita**. Nie rozpozna TM-2 po nazwie portu
   > (szuka „TD-17"/„TD-27"), zostanie przy profilu TD-17 i pozwoli na zapis.

2. **BACKUP SAVE i inwentaryzacja karty** — `DOKUMENTACJA/01`, krok 0.

3. **Seria mapowania** — `DOKUMENTACJA/01`, pliki 0–5. Około 20 minut.

4. **Analiza** — `python3 tools/tm2diff.py series ~/tm2-seria`.

5. **Wypełnienie `DOKUMENTACJA/02`** i przeniesienie offsetów do
   `~/Library/Application Support/TM2Editor/tm2-layout.json`.

Dopiero po tym ma sens rozbudowa interfejsu.

---

## Analizator różnicowy

```bash
python3 tools/tm2diff.py --help
```

| Polecenie | Do czego |
|---|---|
| `inspect PLIK` | rozmiar, entropia, ciągi ASCII, kandydaci na stride |
| `diff A B` | mapa różnic dwóch plików z kontekstem heks |
| `series KATALOG` | pełna analiza serii 0–5 z odsiewaniem szumu |
| `period PLIK` | detekcja okresu struktury przez autokorelację |
| `checksum PLIK` | rozpoznanie sumy kontrolnej — policzone, nie zgadnięte |
| `hex PLIK -o OFF` | podgląd fragmentu |
| `gen KATALOG` | sztuczna seria testowa o znanym układzie |

Tylko biblioteka standardowa Pythona 3.8+. Nic nie idzie do sieci, pliki
wejściowe otwierane wyłącznie do odczytu.

**Samotest.** `gen` tworzy sztuczną serię o z góry znanym układzie (nagłówek
64 B, stride 128 B, kotwica pod 0x40, parametr pod 0x60, suma 32-bit LE na
końcu, licznik jako szum pod 0x04). `series` musi to wszystko odtworzyć.
Zanim zaufasz narzędziu na prawdziwych danych z modułu, uruchom:

```bash
python3 tools/tm2diff.py gen /tmp/testseria
python3 tools/tm2diff.py series /tmp/testseria --no-hex
```

Ten sam test jest w CI.

---

## Mapowanie przez CI (`Mapowanie/`)

Podstawowy sposób pracy nad mapowaniem — ten sam wzorzec co przy PulsoKicie
i TD-17: wrzucasz plik testowy BACKUP do `Mapowanie/nowe/`, pushujesz, GitHub
Actions go analizuje automatycznie (workflow „Analiza mapowania”), a wynik
czytasz w logu przebiegu (zakładka **Actions** na GitHubie) — ten log się
kopiuje i wkleja do rozmowy. Nic nie trzeba uruchamiać lokalnie.

Pełna instrukcja: `Mapowanie/README.md`. W skrócie:

```bash
git add Mapowanie/nowe/twoj-plik.bin
git commit -m "mapowanie: opis co zmienione"
git push
```

CI porównuje każdy plik w `Mapowanie/nowe/` względem `Mapowanie/baza.bin`,
etykietując zmiany na podstawie stanu wiedzy w `Mapowanie/pola.json` —
znane pola osobno od tego, co jeszcze nieopisane (`tools/tm2map.py` w tle,
patrz niżej).

---

## Asystent mapowania (`tm2map.py`)

Ten sam analizator co za CI, tylko do uruchomienia lokalnie — przydatny,
jeśli wolisz pracować bez wypychania każdego pliku testowego do GitHuba, albo
offline. `Mapowanie/` powyżej jest teraz preferowaną ścieżką pracy; ta sekcja
zostaje jako opcja alternatywna.

`tm2diff.py` pokazuje surową różnicę bajtów — dobre do jednorazowego
sprawdzenia, ale przy pełnej serii testów oznacza ręczne rozpoznawanie za
każdym razem, które zmienione bajty to już znane pola (zostałości
poprzednich testów — BACKUP SAVE zapisuje cały stan modułu, nie różnicę), a
które to coś naprawdę nowego. `tm2map.py` zna już potwierdzony stan wiedzy o
formacie (patrz `domyslne_pola()` w kodzie — to ten sam stan co
`BackupLayout.mapped2026_09_02` i `DOKUMENTACJA/02-format-pliku-backup.md`) i
przy każdej analizie etykietuje zmiany opisem w rodzaju „Kit 3, Trigger 1,
pole Level”, zamiast gołego offsetu. Wszystko, czego jeszcze nie umie opisać,
jest wypisywane osobno jako NOWE/NIEZNANE — tylko to wymaga uwagi.

Najprościej: uruchom bez argumentów i wybieraj z menu.

```bash
python3 tools/tm2map.py
```

Albo z linii poleceń:

```bash
python3 tools/tm2map.py init stan_wyjsciowy.bin
python3 tools/tm2map.py analizuj 01max.bin --opis "poziom pada 1, kit 1, na max"
python3 tools/tm2map.py ustal --offset 3145 --nazwa "trig.pan" --opis "panorama" \
                         --dlugosc 2 --zakres trigger --kit 1 --trigger 1
python3 tools/tm2map.py raport
```

`init` zakłada katalog sesji (`sesja-tm2/` obok skryptu, konfigurowalny flagą
`--sesja`) z kopią pliku bazowego, `pola.json` (znane pola — zwykły JSON, do
edycji też ręcznie) i `dziennik.md` (dopisywany automatycznie przy każdej
analizie — ten plik, nie surowy diff, warto wklejać do rozmowy). `ustal`
zapisuje nowo rozpoznane pole na stałe, licząc offset względny samodzielnie
z geometrii (podajesz tylko bezwzględny offset z raportu `analizuj` i numer
kitu/triggera, w którym go zaobserwowano). `raport` zbiera cały stan wiedzy
do jednego pliku `raport.md`.

Tylko biblioteka standardowa Pythona 3.8+, wszystko lokalnie na plikach.

---

## Budowanie

W sesji roboczej nad tym projektem nie ma Xcode ani kompilatora Swift — kod
jest weryfikowany przez czytanie, a kompiluje się dopiero na GitHub Actions.
Dlatego projekt stoi na `Package.swift`, a nie na ręcznie pisanym
`project.pbxproj`: pakiet SwiftPM czyta się jak zwykły kod, a Xcode otwiera go
bezpośrednio.

Lokalnie:

```bash
swift build                       # kompilacja
swift test                        # testy jednostkowe
Scripts/zbuduj-app.sh release     # złożenie .app z podpisem ad-hoc
python3 Scripts/sprawdz-nawiasy.py Sources Tests
```

W Xcode: **File → Open…** i wskaż `Package.swift`.

> **Uwaga:** Cmd+R w Xcode na surowym `Package.swift` bywa zawodne jako sposób
> *uruchamiania* aplikacji — build potrafi przejść bez błędu, a okno się nie
> pojawia (proces startuje bez pełnego pakietu `.app`, więc bywa, że nie
> dostaje właściwej aktywacji/fokusu). Xcode w tym trybie jest wygodny do
> edycji i do `Cmd+U` (testy), ale do faktycznego **uruchomienia** aplikacji
> używaj `Scripts/zbuduj-app.sh release` i otwórz powstały `.app` z Findera —
> to jest droga sprawdzona i opisana niżej w „Pierwsze uruchomienie".

CI robi to samo przy każdym pushu i wystawia Wydanie przy tagu `v*`.

### Pierwsze uruchomienie

Aplikacja jest podpisana ad-hoc, bez notaryzacji Apple (program jest darmowy
i nie ma konta developerskiego). macOS zapyta o potwierdzenie: kliknij plik
prawym przyciskiem i wybierz **Otwórz**.

---

## Fakty o sprzęcie

| Pozycja | Wartość |
|---|---|
| Kity | 99 |
| Wejścia | 2 × TRIG IN (1/4" TRS), każde dual-trigger → do 4 triggerów |
| Brzmienia | 162 fabryczne + do 90 300 użytkownika (WAV 44,1 kHz / 16 bit) |
| Karta | SD / SDHC do 32 GB |
| Złącza | OUTPUT (L/MONO, R), PHONES, TRIG IN ×2, MIDI (IN, OUT), DC IN |
| USB | brak |
| Wersje systemu | 1.02, 1.03 |

Aktualizacja systemu idzie plikiem `_BOOTPRG.ES_` w katalogu głównym karty —
dowód, że karta jest u tego modułu kanałem danych.

---

## Konwencje

- **Interfejs po angielsku.** Etykiety pól odpowiadają nazwom z wyświetlacza
  modułu i z instrukcji Rolanda — tłumaczenie ich utrudniałoby porównywanie.
- **Komentarze w kodzie i dokumentacja po polsku.**
- Nazwy plików skryptów i dokumentów po polsku, nazwy typów Swift po angielsku.

---

## Licencja

MIT. Zobacz `LICENSE`.

Projekt nie jest w żaden sposób związany z Roland Corporation. „Roland" i
„TM-2" są znakami towarowymi swoich właścicieli i użyto ich wyłącznie
w celu wskazania, jakiego sprzętu program dotyczy.
