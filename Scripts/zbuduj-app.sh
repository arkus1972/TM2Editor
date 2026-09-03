#!/usr/bin/env bash
#
# Składa binarkę z SwiftPM w bundle .app i podpisuje ją ad-hoc.
#
# Ten sam skrypt działa lokalnie i w GitHub Actions — nie ma osobnej ścieżki
# "dla CI", bo od tego się zaczyna rozjeżdżanie wyniku.
#
# Użycie:
#   Scripts/zbuduj-app.sh [release|debug]

set -euo pipefail

KONFIGURACJA="${1:-release}"
NAZWA_PRODUKTU="TM2Editor"
NAZWA_APLIKACJI="TM-2 Editor"

KATALOG_GLOWNY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KATALOG_GLOWNY"

echo "==> Kompilacja (${KONFIGURACJA})"
swift build -c "$KONFIGURACJA" --product "$NAZWA_PRODUKTU"

SCIEZKA_BINARKI="$(swift build -c "$KONFIGURACJA" --show-bin-path)/${NAZWA_PRODUKTU}"
if [[ ! -f "$SCIEZKA_BINARKI" ]]; then
    echo "BŁĄD: nie ma binarki pod $SCIEZKA_BINARKI" >&2
    exit 1
fi

BUNDLE="${KATALOG_GLOWNY}/build/${NAZWA_APLIKACJI}.app"
echo "==> Składanie bundle: $BUNDLE"

rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "$SCIEZKA_BINARKI" "${BUNDLE}/Contents/MacOS/${NAZWA_PRODUKTU}"
cp "${KATALOG_GLOWNY}/Scripts/Info.plist" "${BUNDLE}/Contents/Info.plist"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

# Zasoby pakietu SwiftPM, jeśli jakieś powstały.
KATALOG_BIN="$(swift build -c "$KONFIGURACJA" --show-bin-path)"
for pakiet in "$KATALOG_BIN"/*.bundle; do
    [[ -e "$pakiet" ]] || continue
    echo "    dokładam zasoby: $(basename "$pakiet")"
    cp -R "$pakiet" "${BUNDLE}/Contents/Resources/"
done

echo "==> Podpis ad-hoc"
# Podpis ad-hoc (-s -) nie wymaga konta developerskiego. Gatekeeper i tak
# poprosi użytkownika o potwierdzenie przy pierwszym uruchomieniu — to jest
# oczekiwane dla darmowego programu bez notaryzacji i jest opisane w README.
codesign --force --deep --sign - \
    --options runtime \
    --timestamp=none \
    "$BUNDLE"

echo "==> Weryfikacja podpisu"
codesign --verify --verbose=2 "$BUNDLE"

echo
echo "Gotowe: $BUNDLE"
