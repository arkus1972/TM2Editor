# Edytor TM-2 — dokument startowy

Dokument bazowy projektu. Zawiera wszystko, czego świeża sesja potrzebuje, żeby ruszyć bez wypytywania od zera.

## 1. Cel

Edytor ustawień modułu Roland TM-2 na macOS (SwiftUI), na tej samej zasadzie co PulsoKit dla TD-17: czytelny ekran zamiast dwuwierszowego wyświetlacza i grzebania w menu.

Autor: Arek. Ma moduł pod ręką oraz interfejs Roland UM-ONE (USB↔DIN MIDI).

## 2. Fakty o sprzęcie (sprawdzone u źródła, nie z pamięci)

| Pozycja | Wartość |
|---|---|
| Kity | 99 |
| Wejścia | 2 × TRIG IN (1/4" TRS), każde dual-trigger → do 4 triggerów |
| Brzmienia | 162 fabryczne + do 90 300 użytkownika (WAV 44,1 kHz / 16 bit z karty) |
| Karta | SD / SDHC do 32 GB |
| Złącza | OUTPUT (L/MONO, R), PHONES, TRIG IN ×2, MIDI (IN, OUT), DC IN |
| USB | brak |
| Wersje systemu | 1.02 (typy RT-30, poprawki delay), 1.03 (2022, zmiana porządkowa) |

Aktualizacja systemu idzie plikiem `_BOOTPRG.ES_` w katalogu głównym karty — dowód, że karta jest u tego modułu kanałem danych.

Źródła: specyfikacja i instrukcja obsługi Rolanda, artykuły wsparcia „TM-2: Selecting Kits via MIDI" i strona aktualizacji systemu.

## 3. Dlaczego NIE da się tego zrobić tak jak w TD-17

PulsoKit stoi na opublikowanej przez Rolanda mapie adresów SysEx (RQ1/DT1). Dla TM-2 tej mapy nie ma i nie będzie:

- **Brak USB** — połączenie wymaga interfejsu MIDI. Arek ma UM-ONE, więc akurat to jest załatwione.
- Roland **nigdy nie opublikował** dla TM-2 dokumentu „MIDI Implementation". W instrukcji nie ma nawet tabelki MIDI Implementation Chart, ani jednego wystąpienia „System Exclusive" czy „Device ID".
- Co MIDI IN realnie przyjmuje: **Program Change 1–99 = wybór kitu** (wymaga MIDI Ch ustawionego i PrgChg Rx = ON). Żadnego innego odbieranego komunikatu Roland nie dokumentuje.

Czyli: „przeczytaj parametr, zmień, odeślij" nie ma czym jechać.

**Test do wykonania na starcie** (5 minut, darmowy): podłączyć TM-2 przez UM-ONE, wysłać Identity Request (`F0 7E 7F 06 01 F7`) i zobaczyć, czy moduł odpowie. PulsoKit już to wysyła — wystarczy wybrać porty UM-ONE i zajrzeć w zakładkę Log. Odpowiedź = w środku jest silnik SysEx i warto sondować. Cisza = droga plikowa jest jedyna, i mamy to potwierdzone.

**Uwaga bezpieczeństwa przy tym teście.** PulsoKit nie rozpozna TM-2 po nazwie portu (szuka „TD-17"/„TD-27"), więc zostanie przy profilu TD-17 i pozwoli na zapis. Przy podłączonym TM-2 **nie wolno naciskać Send, Fast write ani Restore**. Odczyt i Log są bezpieczne — to tylko pytania, które moduł zignoruje.

> Uwaga dopisana w trakcie prac: ten test da się zrobić całkowicie bez PulsoKita.
> Darmowe **SysEx Librarian** albo **MIDI Monitor** (Snoize) wyślą Identity Request
> i pokażą odpowiedź, a nie mają żadnego przycisku prowadzącego do zapisu
> parametrów. Ryzyko pomyłki spada do zera, więc to jest zalecana droga.

## 4. Droga, która jest otwarta: BACKUP na karcie SD

Instrukcja TM-2, s. 15: funkcje BACKUP SAVE / BACKUP LOAD / BACKUP DELETE. Cytat: „Backup will save all kits, all settings of the TM-2, and the pad and drum trigger settings."

To jest ten sam kształt co pliki `.TD0` w PulsoKicie. Edytor TM-2 pracuje więc **na pliku, nie na żywym module**.

I to jest bezpieczne: żaden bajt nie idzie na kabel do sprzętu. Najgorsze, co może się stać, to odrzucenie pliku przez BACKUP LOAD. Oryginał zostaje na karcie. Zasadnicza różnica wobec sondowania adresów.

## 5. Metoda: mapowanie różnicowe

Nie sondujemy adresów. Robimy dwa backupy różniące się jednym parametrem i patrzymy, które bajty się ruszyły. Jedna runda ≈ 2 minuty na module.

**Krok 0 — inwentaryzacja karty.** Po pierwszym BACKUP SAVE: co leży na karcie, jakie nazwy, jakie rozmiary. Bez tego kopiowalibyśmy w ciemno całą kartę razem z próbkami WAV.

Seria (kolejność ma znaczenie):

| Plik | Co zmienić przed zapisem | Co da |
|---|---|---|
| 0 | nic (stan wyjściowy) | punkt odniesienia |
| 1 | nic — drugi backup tego samego stanu | bajty-szum: znacznik czasu, licznik, suma kontrolna |
| 2 | nazwa kitu 1 na `AAAAAAAA` | kotwica ASCII — początek bloku kitu |
| 3 | poziom pada 1 w kicie 1 o +1 | pojedynczy bajt parametru |
| 4 | ten sam parametr na minimum, potem na maksimum | zakres i skala bajtu |
| 5 | ten sam parametr, ale w kicie 2 | stride między kitami — odblokowuje cały układ naraz |

**Plik 1 jest krytyczny i najczęściej pomijany**: bez niego nie wiadomo, które różnice są danymi, a które szumem.

Do każdego pliku notatka: co dokładnie zmienione, z jakiej wartości na jaką, oraz wersja systemu modułu.

Szczegółowa instrukcja krok po kroku: `01-protokol-mapowania.md`.

## 6. Ryzyka, uczciwie

- **Suma kontrolna / podpis.** Jeśli plik nosi CRC albo hash, BACKUP LOAD odrzuci edytowany plik, dopóki tego nie złamiemy. Precedens jest dobry: pliki TD0 noszą MD5 i PulsoKit już sobie z tym radzi.
- **Kompresja albo szyfrowanie** — wtedy projekt się kończy. Mało prawdopodobne w budżetowym module z 2013, ale sprawdzane na pierwszym pliku.
- **Różnice między wersjami systemu** (1.02 / 1.03) — stąd notowanie wersji.

> Uwaga dopisana w trakcie prac, wykryta na testach analizatora: jeżeli plik nosi
> licznik zapisów albo znacznik czasu, to **suma kontrolna zmienia się także
> między plikiem 0 a 1**, czyli wpada do maski szumu i w mapie różnic w ogóle jej
> nie widać. Wnioskowanie „nie ma bajtów wspólnych dla wszystkich zmian, czyli nie
> ma sumy" jest wtedy fałszywe. Dlatego analizator sumy nie zgaduje, tylko ją
> **liczy** i sprawdza, czy któryś algorytm daje wartość leżącą w pliku.

## 7. Co da się przenieść z PulsoKita

Zakres TM-2 to ułamek TD-17: 99 kitów × 4 triggery zamiast 100 × 20 stref. Do wzięcia gotowe wzorce (nie kod jeden do jednego — inspiracja i struktura):

- `TD0EditorModel.swift`, `TD0StudioView.swift` — edytor pliku, czyli dokładnie ten tryb pracy, którego TM-2 potrzebuje.
- `KitEditor.swift` — model edycji: jedna lista zmian, cofanie, odroczony zapis. Sprawdzony i wart powtórzenia.
- `ModuleProfile.swift` — wydzielenie tego, co zależy od modelu, w jedno miejsce.
- Scena z padami — przy dwóch wejściach będzie prostsza, ale zasada (klikasz pad, słyszysz go, widzisz co gra) zostaje.
- CI na GitHub Actions z `.github/workflows/build.yml` — kompilacja, podpis ad-hoc, spakowanie, wystawienie Wydania, poświadczenie pochodzenia. Gotowiec, do przeniesienia niemal bez zmian.
- Ekrany audytu bezpieczeństwa i oba PDF-y z instrukcją — wzór, jak to domknąć na koniec.

## 8. Jak pracujemy (ważne dla świeżej sesji)

- W sesji **nie ma Xcode ani kompilatora Swift**. Kod jest weryfikowany przez czytanie: agent-recenzent na każdą partię zmian plus skrypt sprawdzający balans nawiasów. Kompilację robi GitHub Actions, testy na sprzęcie robi Arek.
- Dostarczanie: **cały projekt jako zip, za każdym razem**.
- Arek pushuje sam. Nie ma tokenu do GitHuba w sesji — zmiany w repo idą jako pliki do ręcznego wgrania przez stronę GitHuba.
- **Interfejs po angielsku, komentarze w kodzie i dokumentacja po polsku.**
- Program ma być darmowy, MIT, bez łączenia się z internetem i bez zbierania czegokolwiek.
- Przed każdą operacją zapisu do sprzętu: ostrzeżenie i kopia zapasowa.

## 9. Pierwsze trzy kroki

1. **Identity Request** przez UM-ONE — sprawdzić, czy TM-2 w ogóle mówi SysEx-em.
2. **BACKUP SAVE i inwentaryzacja karty** — co, jak się nazywa, ile waży.
3. **Seria z tabelki w punkcie 5**, zaczynając od pliku 0 i 1.

Po tych trzech krokach wiadomo, czy projekt jest wykonalny, i jak wygląda układ danych. Dopiero potem pisanie kodu.
