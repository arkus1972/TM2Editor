# Protokół serii mapowania różnicowego

Dokument roboczy. Do wydrukowania i trzymania obok modułu.

Cel: ustalić, gdzie w pliku BACKUP leżą poszczególne parametry, bez sondowania
adresów w module. Metoda: dwa backupy różniące się jednym parametrem, potem
porównanie bajt po bajcie.

Czas: około 20 minut na całą serię, w tym cierpliwe klikanie w menu.

---

## Zanim zaczniesz

**1. Obraz karty.** Zrób pełną kopię karty, zanim cokolwiek zapiszesz.

```bash
diskutil list                      # znajdź swoją kartę, np. /dev/disk4
diskutil unmountDisk /dev/disk4
sudo dd if=/dev/rdisk4 of=~/tm2-karta-obraz.img bs=4m status=progress
```

Karta 32 GB to kilkanaście minut. Masz wtedy punkt powrotu na wypadek pomyłki
w menu BACKUP DELETE albo błędu przy kopiowaniu.

**2. Zanotuj wersję systemu modułu.** Instrukcja wymienia 1.02 i 1.03. Dopóki
nie sprawdzimy, czy format jest ten sam, każdy plik musi mieć zapisaną wersję,
na której powstał.

Wersja systemu: `_______________`

**3. Katalog na pliki.** Zrób na Macu jeden katalog na całą serię. Nazwy plików
muszą się zaczynać od numeru z tabelki — analizator po tym je rozpoznaje.

---

## Krok 0 — inwentaryzacja karty

Zrób pierwszy BACKUP SAVE, wyjmij kartę, włóż do Maca i zapisz, co na niej leży.

```bash
ls -laR /Volumes/NAZWA_KARTY | tee ~/tm2-seria/00-inwentaryzacja.txt
```

Co odnotować:

| Pytanie | Odpowiedź |
|---|---|
| Jak nazywa się plik backupu? | |
| Jakie ma rozszerzenie? | |
| Ile waży? | |
| W jakim katalogu leży? | |
| Co jeszcze jest na karcie? | |
| Czy są tam próbki WAV? Ile ważą? | |

To jest krok, bez którego kopiowalibyśmy w ciemno całą kartę razem z próbkami.

Potem od razu:

```bash
python3 tools/tm2diff.py inspect ~/tm2-seria/0_*.bin
```

Patrz na entropię. Poniżej 7,5 bita na bajt — dane są surowe, projekt ma sens.
Powyżej — plik jest skompresowany albo zaszyfrowany i tu się kończy.

---

## Seria — kolejność ma znaczenie

Po każdej zmianie: BACKUP SAVE, potem skopiuj plik z karty na Maca pod nazwą
z kolumny „nazwa pliku". Przed kolejnym krokiem **przywróć poprzednią wartość**,
chyba że tabelka mówi inaczej.

### Plik 0 — stan wyjściowy

- Nic nie zmieniaj.
- BACKUP SAVE.
- Nazwa pliku: `0_stan_wyjsciowy.bin`

Punkt odniesienia dla wszystkiego, co dalej.

### Plik 1 — ten sam stan, drugi zapis

- **Nadal nic nie zmieniaj.** Po prostu zrób BACKUP SAVE jeszcze raz.
- Nazwa pliku: `1_ten_sam_stan.bin`

**To jest krok najczęściej pomijany i najważniejszy.** Bez niego nie wiadomo,
które różnice w kolejnych plikach są danymi, a które znacznikiem czasu,
licznikiem zapisów albo sumą kontrolną. Jeżeli pliki 0 i 1 są identyczne
co do bajtu — świetnie, plik nie ma szumu i dalsza analiza jest o klasę
czytelniejsza.

### Plik 2 — nazwa kitu 1

- Wybierz kit 1.
- Zmień jego nazwę na dokładnie `AAAAAAAA` (osiem wielkich liter A).
- BACKUP SAVE.
- Nazwa pliku: `2_nazwa_kitu1.bin`
- **Zanotuj oryginalną nazwę kitu 1**, żeby dało się ją przywrócić: `___________`

Osiem takich samych znaków to kotwica nie do pomylenia z niczym innym —
w pliku będzie widać ciąg `41 41 41 41 41 41 41 41`. Wskazuje początek bloku
kitu.

### Plik 3 — jeden parametr o +1

- Przywróć nazwę kitu 1.
- Wybierz kit 1, trigger 1 (wejście 1, sygnał A).
- Znajdź parametr **Level** (poziom).
- Zanotuj wartość wyjściową: `_______`
- Zwiększ dokładnie o 1. Nowa wartość: `_______`
- BACKUP SAVE.
- Nazwa pliku: `3_poziom_plus1.bin`

Zmiana o 1 daje jeden bajt różnicy. Jeżeli w mapie różnic wyjdzie więcej niż
jeden bajt, druga grupa to prawie na pewno suma kontrolna.

### Plik 4 — ten sam parametr na maksimum

- Ten sam parametr, ten sam trigger, ten sam kit.
- Ustaw na wartość **maksymalną**. Zanotuj ją: `_______`
- BACKUP SAVE.
- Nazwa pliku: `4_poziom_max.bin`

Stąd wychodzi skala: czy bajt 0…100 odpowiada wyświetlanym 0…100 wprost, czy
z przesunięciem albo mnożnikiem.

*(Opcjonalnie, jeśli chcesz mieć pewność: zrób jeszcze jeden zapis z wartością
minimalną jako `4b_poziom_min.bin`. Analizator go uwzględni.)*

### Plik 5 — ten sam parametr, ale w kicie 2

- Przywróć poziom w kicie 1 do wartości wyjściowej.
- Przejdź do **kitu 2**, trigger 1.
- Ustaw ten sam parametr na tę samą wartość, którą wpisywałeś w pliku 3
  (czyli wyjściowa +1). Zanotuj wartość wyjściową w kicie 2: `_______`
- BACKUP SAVE.
- Nazwa pliku: `5_poziom_kit2.bin`

**To jest krok, który odblokowuje wszystko naraz.** Odległość między tym samym
parametrem w kicie 1 i kicie 2 to rozmiar bloku kitu. Znając ją, znamy adres
każdego z 99 kitów.

---

## Po serii

```bash
python3 tools/tm2diff.py series ~/tm2-seria
```

Raport powie:

1. które bajty są szumem (plik 0 vs 1),
2. gdzie zaczyna się blok kitu (kotwica ASCII),
3. pod jakim offsetem siedzi parametr i o ile od początku kitu,
4. jaka jest skala bajtu,
5. jaki jest stride między kitami,
6. czy plik nosi sumę kontrolną i jaką — policzoną, nie zgadniętą.

Weryfikacja niezależną metodą:

```bash
python3 tools/tm2diff.py period ~/tm2-seria/0_stan_wyjsciowy.bin
```

Autokorelacja powinna wskazać ten sam stride co krok 5. Zgodność dwóch metod
= układ rozpoznany, można pisać kod.

Zapisz raport obok plików:

```bash
python3 tools/tm2diff.py series ~/tm2-seria > ~/tm2-seria/RAPORT.txt
```

---

## Notatka do każdego pliku

Do katalogu z serią wrzuć plik `NOTATKI.txt` z takim wzorem, wypełniony:

```
wersja systemu modułu: ____
data: ____

0_stan_wyjsciowy.bin   nic nie zmieniane
1_ten_sam_stan.bin     nic nie zmieniane, drugi zapis
2_nazwa_kitu1.bin      kit 1, nazwa: "________" -> "AAAAAAAA"
3_poziom_plus1.bin     kit 1, trigger 1, Level: ____ -> ____
4_poziom_max.bin       kit 1, trigger 1, Level: ____ -> ____ (maks)
5_poziom_kit2.bin      kit 2, trigger 1, Level: ____ -> ____
```

Bez tej notatki po tygodniu nikt (łącznie z autorem) nie odtworzy, co dokładnie
było w którym pliku.

---

## Czego NIE robić

- **Nie podłączaj modułu do PulsoKita i nie naciskaj Send, Fast write ani
  Restore.** PulsoKit rozpoznaje moduł po nazwie portu — szuka „TD-17"/„TD-27"
  — więc przy TM-2 zostanie przy profilu TD-17 i pozwoli na zapis. Odczyt i Log
  są bezpieczne, bo to tylko pytania, które moduł zignoruje.
- **Do testu Identity Request użyj czegoś innego.** Darmowe SysEx Librarian
  albo MIDI Monitor (Snoize) wyślą `F0 7E 7F 06 01 F7` i pokażą odpowiedź, a nie
  mają przycisku prowadzącego do zapisu parametrów. Zero ryzyka pomyłki.
- **Nie nadpisuj oryginalnych plików backupu.** Edytor z tego projektu zapisuje
  wyłącznie do nowych plików i odmawia nadpisania pliku źródłowego — ale przy
  ręcznym kopiowaniu przez Findera tej ochrony nie ma.
