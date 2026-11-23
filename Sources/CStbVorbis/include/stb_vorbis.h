// Dekoder Ogg Vorbis — stb_vorbis (Sean Barrett, domena publiczna / MIT),
// dołączony w całości w ../stb_vorbis.c, bez zmian.
//
// Po co: macOS nie umie sam czytać plików .ogg (AVFoundation obsługuje
// WAV, AIFF, MP3, M4A, CAF, FLAC — Vorbisa nie). Arek chciał, żeby edytor
// przyjmował też ogg. Dekoder działa offline, w procesie, bez żadnych
// dodatkowych bibliotek systemowych.
//
// Wystawiamy tylko jedną funkcję: dekodowanie całego pliku do 16-bitowych
// próbek z przeplotem. Pamięć wyniku zwalnia wołający przez free().
#ifndef CSTB_VORBIS_H
#define CSTB_VORBIS_H

int stb_vorbis_decode_filename(const char *filename, int *channels, int *sample_rate, short **output);

#endif
