# Format pliku BACKUP Roland TM-2

**Stan: częściowo rozpoznany, 2026-09-02.** Pierwsza runda mapowania różnicowego
na prawdziwym sprzęcie Arka. Pełna historia pomiarów (z dowodami — konkretnymi
diffami) jest w projekcie „ROLAND TM-2 EDYTOR”, `03-stan-prac.md`, wpisy (c)–(g).
Ten dokument to ich destylat, w formie do wpisania w kod.

Zasada: wpisujemy tu tylko to, co zostało **zmierzone**. Hipotezy trzymamy
w osobnej sekcji na końcu i jasno oznaczone. Roland nie opublikował dla TM-2
niczego, więc każda liczba w tym dokumencie pochodzi z naszego pomiaru albo
jest niczym.

---

## 1. Podstawy

| Pozycja | Wartość | Skąd |
|---|---|---|
| Nazwa pliku na karcie | *do ustalenia* — aplikacja celowo nie filtruje po nazwie/rozszerzeniu przy otwieraniu | krok 0 |
| Rozmiar pliku | **124 748 bajtów** (dla pliku Arka; zakładamy stały dla tej wersji formatu) | `inspect` |
| Bajty rozpoznawcze (magic) | `54 4D 2D 32 00 00 00 00` = `"TM-2"` + 4 zera, dalej `42 4B 42 61 63 6B 75 70 20 20` = `"BKBackup  "` | `inspect` |
| Entropia | **0,481 bit/bajt** — daleko poniżej progu alarmowego. Dane surowe, bez kompresji/szyfrowania. | `inspect` |
| Wersja systemu modułu | *niesprawdzone* — nie zanotowano przy pierwszym pliku | notatka |

Próg entropii: powyżej 7,5 bita na bajt plik byłby skompresowany albo
zaszyfrowany i projekt by się kończył. Zmierzone: **0,481** — droga wolna.

---

## 2. Szum

Plik 1 (identyczny resave stanu wyjściowego) **nie został jeszcze zrobiony** —
stał się mniej krytyczny, odkąd suma kontrolna została rozpoznana bezpośrednio
(sekcja 7), a nie przez odsiewanie szumu. Wciąż wart zrobienia dla higieny
(złapanie ewentualnego licznika zapisów), ale nie blokuje niczego.

| Offset | Długość | Co to prawdopodobnie jest |
|---|---|---|
| *do ustalenia (plik 1 nie zrobiony)* | | |

---

## 3. Układ ogólny

| Element | Offset | Rozmiar |
|---|---|---|
| Nagłówek | `0x000000` | 0x40 (64 B) do początku bloku kitów; w pełni rozebrane tylko pierwsze ~0x30 B, patrz sekcja 6 |
| Blok kitu 1 | `0x000040` | stride 234 B (`0xEA`) |
| Blok kitu N | `0x40 + (N-1) × 234` | 234 B |
| Koniec danych kitów / zera | od ok. `0x005AE8` | ~101 460 B wypełnienia zerami, przeznaczenie nieznane |
| Suma kontrolna | ostatnie 16 B pliku (`0x01E73C`) | 16 B, MD5 |

Sprawdzian arytmetyczny: `99 × 234 = 23 166`; `0x40 + 23 166 = 0x5A7E`, zgodne
z obserwowanym początkiem strefy zer pod `0x5AE8` (kilkadziesiąt bajtów
odchylenia to najpewniej ogon ostatniego kitu/wyrównanie — nieistotne).

Bajt pod `0x000036` zachowuje się jak wskaźnik „aktualnie wybrany kit"
(0-based) w chwili BACKUP SAVE — potwierdzone na 4 próbkach, nieużywane przez
edytor (nie wpływa na dane kitów).

---

## 4. Blok kitu

Offsety **względem początku bloku kitu** (`0x40` w pliku = offset 0 tutaj).

| Offset | Rozmiar | Pole | Kodowanie | Zakres | Uwagi |
|---|---|---|---|---|---|
| `+0x00` | ~60 B | *nieznane* | | | nagłówek/parametry kitu przed nazwą — niezmapowane |
| `+0x3C` (60) | 22 B | Kit Name | **UTF-16LE**, nie ASCII | 11 znaków, dopełnione spacjami | Znalezione przeszukiwaniem UTF-16LE, nie krokiem „AAAAAAAA" z protokołu (zbędny, ale nieszkodliwy, gdyby ktoś go i tak zrobił) |
| `+0x7E` (126) | — | *(początek rekordu triggera 1 — patrz sekcja 5)* | | | |
| `+0xD2` (210) | — | *(początek rekordu triggera 2)* | | | |
| Kit Volume | *nieznane* | | | | niezmapowane |
| Kit Tempo | *nieznane* | | | może zajmować 2 bajty | niezmapowane |

---

## 5. Blok (rekord) triggera

Offsety **względem początku rekordu triggera**. Rekord triggera 1 zaczyna się
pod `+0x7E` kitu, rekord triggera 2 pod `+0xD2` — **stride 84 B (`0x54`)**,
potwierdzone na dwóch polach (Instrument, Level) i dwóch kitach.

**Liczba triggerów w pliku: 2, nie 4.** Fakty sprzętowe mówią o 2× TRIG IN,
każde dual-trigger (do 4 triggerów), ale przy origin `0x7E` i stride `0x54`
trzeci rekord wypadłby dokładnie pod `0x7E + 2×0x54 = 0xEA (234)` —
czyli na starcie NASTĘPNEGO kitu. Sprawdzone bezpośrednio (nie zgadnięte):
`0x40 + 0xEA` to adres kitu 2, a `+0x3C` tego adresu to pole nazwy kitu 2.
Najpewniejsza hipoteza: head/rim tego samego wejścia TRIG IN siedzi jako pole
wewnątrz jednego rekordu (na panelu przednim RIM = SHIFT + ten sam przycisk
TRIG IN, nie osobny przycisk), a nie jako osobny rekord. Niepotwierdzone
różnicowo — nie zgadujemy, gdzie w rekordzie to pole leży.

| Offset | Rozmiar | Pole | Kodowanie | Zakres | Uwagi |
|---|---|---|---|---|---|
| `+0x00` | 2 B | **Instrument** | uint16 LE | 0–161 zmierzone (162 brzmienia fabryczne u Arka) | Zmiana brzmienia rusza dokładnie ten bajt (+1 na pozycję). Szerokość 16-bit nie w pełni potwierdzona — starszy bajt nigdy nie musiał się ruszyć (max 162 < 256). Patrz hipotezy. |
| `+0x02` | 2 B | *nieznane* | stała `01 00` w obu triggerach dotychczas | | flaga włączenia? typ? niezmapowane |
| `+0x04` | 1 B | **Level** | wprost, 0–100 | 0=min, 100=max | Potwierdzone na 2 triggerach, 2 kitach, obu skrajnościach — 4 pomiary, spójne |
| `+0x05` | 1 B | *nieznane* | zawsze `00` dotychczas | | niezmapowane |
| `+0x06` | 2 B | *nieznane* | trigger1=`00 00`, trigger2=`FE FF` (int16 LE: 0, −2) | | kandydat: Pan albo Tune, wartości fabryczne — niezmapowane |
| `+0x08` | 4 B | *nieznane* | `0F 00 00 00` (=15) w obu triggerach dotychczas | | niezmapowane |
| `+0x0C` | 4 B | *nieznane* | trigger1=`24 00 00 00` (36), trigger2=`26 00 00 00` (38) | | rośnie o 2 na trigger — wygląda na wewnętrzny znacznik, nie parametr edytowalny |
| | | Pan | | L32–CTR–R32 | niezmapowane, kandydat pod `+0x06` |
| | | Pitch | | | niezmapowane |
| | | Decay | | | niezmapowane |
| | | Trigger Type | wyliczenie | | niezmapowane, lista może się różnić między 1.02 a 1.03 |
| | | Sensitivity | | 1–16 | niezmapowane |
| | | Threshold | | 0–15 | niezmapowane |
| | | Retrig Cancel | | 1–16 | niezmapowane |
| | | Mask Time | | | niezmapowane, w ms, skala do potwierdzenia |

**Brzmienia użytkownika.** Moduł obsługuje do 90 300 brzmień użytkownika, co
nie zmieści się w dwóch bajtach (max 65 535). Na module Arka (162 brzmienia,
same fabryczne) nie da się tego przetestować bezpośrednio — pole zachowuje
się jak prosty rosnący indeks w dostępnym zakresie. Do ponownego sprawdzenia,
jeśli kiedyś pojawi się plik z kartą mającą setki wgranych próbek.

---

## 6. Ustawienia globalne

Prawdopodobnie w nagłówku (`0x00`–`0x3F`), przed blokiem kitów — niezmapowane.
Kilka pól nagłówka ma już znane, ale niewyjaśnione wartości:

| Offset | Wartość (u Arka) | Uwagi |
|---|---|---|
| `0x14` | `03 01` | prawdopodobnie wersja formatu |
| `0x18` | uint32 LE = 112 (`0x70`) | nieznane |
| `0x1C` | uint32 LE = 2 | nieznane |
| `0x28` | uint32 LE = 2 (powtórka) | nieznane |
| `0x36` | wskaźnik "aktualnie wybrany kit" (0-based) | potwierdzone, patrz sekcja 3 |

| Pole | Offset | Kodowanie | Zakres |
|---|---|---|---|
| MIDI Channel | *nieznane* | | 1–16 |
| Program Change Rx | *nieznane* | | 0/1 |
| Master Volume | *nieznane* | | |

MIDI Channel i Program Change Rx są o tyle istotne, że to jedyny
udokumentowany sposób sterowania modułem po MIDI: Program Change 1–99
wybiera kit, o ile kanał się zgadza i odbiór jest włączony.

---

## 7. Suma kontrolna

| Pozycja | Wartość |
|---|---|
| Offset | `rozmiar_pliku - 16` (`0x01E73C` = 124 732, dla pliku 124 748 B) |
| Długość | 16 B |
| Algorytm | **MD5** |
| Obejmowany zakres | cały plik poza samą sumą (czyli bajty `0x0..0x01E73C`) |

Potwierdzone bezpośrednio, bez potrzeby pary plików: `MD5(bajty[:-16])` liczone
z pierwszego prawdziwego pliku dało dokładnie ostatnie 16 bajtów tego pliku.
Ten sam mechanizm co pliki `.TD0` obsługiwane przez PulsoKit.

---

## 8. Hipotezy — jeszcze niepotwierdzone

Ta sekcja jest celowo oddzielona. Nic z niej nie trafia do kodu jako pewnik,
dopóki nie zostanie zmierzone.

- Pole pod `+0x06` w rekordzie triggera (obecnie `00 00` / `FE FF`) to Pan albo
  Tune. *(Sprawdzian: zmienić na module, zdiffować.)*
- Pole pod `+0x02` (stałe `01 00` dotychczas) to flaga włączenia triggera albo
  typ. *(Sprawdzian: wyłączyć/zmienić typ triggera, zdiffować.)*
- Instrument to naprawdę pełne 16 bitów, nie 8+coś innego. *(Nie do
  sprawdzenia na sprzęcie Arka — tylko 162 brzmienia. Do zrobienia, jeśli
  pojawi się karta z większą biblioteką brzmień użytkownika.)*
- Strefa ~101 KB zer po bloku kitów to zarezerwowane miejsce, nie osobna
  sekcja danych. *(Sprawdzian: sprawdzić, czy rośnie po dodaniu brzmień
  użytkownika albo wzorców.)*
- Format nie różni się między systemem 1.02 a 1.03. *(Sprawdzian: powtórzenie
  kroku 0 po aktualizacji — na razie nieplanowane.)*
- Bajty nagłówka pod `0x18`/`0x1C`/`0x28` (uint32 LE: 112, 2, 2) to wersja
  podformatu albo liczniki — nieistotne dla edycji kitów, niezbadane głębiej.

---

## 9. Jak przenieść wyniki do aplikacji

Opis układu jest danymi, nie kodem — ale **stan na 2026-09-02 jest już wpisany
wprost do kodu** jako `BackupLayout.mapped2026_09_02`
(`Sources/TM2Editor/Model/BackupLayout.swift`), bo w tej sesji nie było jak
skompilować i przetestować wygenerowany JSON, a hardkodowany, przetestowany
`BackupLayout` był bezpieczniejszy niż ręcznie pisany plik, którego nikt nie
zweryfikował. Aplikacja używa go jako domyślnego układu, dopóki nie istnieje
plik:

```
~/Library/Application Support/TM2Editor/tm2-layout.json
```

Ten plik, jeśli istnieje, **nadal ma pierwszeństwo** — to on jest właściwym
miejscem na kolejne odkrycia z dalszego mapowania różnicowego, bez potrzeby
nowego wydania aplikacji. Struktura odpowiada typowi `BackupLayout`.
Minimalny przykład, startujący od tego, co już wiemy:

```json
{
  "layoutVersion": 2,
  "moduleSystemVersion": "1.03",
  "expectedFileSize": 124748,
  "kitBlockOrigin": 64,
  "kitStride": 234,
  "kitCount": 99,
  "triggerBlockOrigin": 126,
  "triggerStride": 84,
  "triggerCount": 2,
  "checksum": { "offset": 124732, "length": 16, "algorithm": "md5" },
  "noiseRanges": [],
  "globalFields": [],
  "kitFields": [],
  "triggerFields": []
}
```

Aplikacja wczyta go przy otwieraniu pliku i od razu odblokuje edycję tych pól,
które mają wpisany offset. Pola bez offsetu zostaną widoczne, ale nieaktywne —
zakładka **Layout** pokazuje, ile z nich jest już zmapowanych.

Rekompilacja nie jest potrzebna — ale w tej pierwszej rundzie i tak jest
(nowy typ kodowania `.utf16LE`, patrz `FieldSpec.swift`).
