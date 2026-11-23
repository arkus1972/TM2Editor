import Foundation

/// Nazwy 162 brzmień wewnętrznych TM-2, w formie „108 Boom Out".
///
/// Źródło: Roland „TM-2 Sound List" (TM-2_SoundList_e01_W.pdf, s. 3,
/// „Instrument list"), WYGENEROWANE z tekstu PDF. Typograficzny apostrof
/// zamieniony na zwykły (wyświetlacz modułu ma tylko ASCII).
///
/// Numer w pliku = numer z listy MINUS JEDEN (pole `trig.instrument`, +0x00
/// slotu). Sprawdzone na fabrycznych kitach w backupie Arka: Kick&Tmbrin
/// 005/074/070/069 → 4/73/69/68, Cowbells 065/066/063/064 → 64/65/62/63,
/// Side Snares, BT-1 XStick — bez wyjątku. Do tego cała lista kitów
/// fabrycznych w tym samym PDF (52 kity × 4 brzmienia = 208 odwołań) zgadza
/// się z tą listą co do nazwy.
///
/// Nazwa „Dance Lo" występuje w PDF dwa razy (123 i 147) — numer na początku
/// rozróżnia je jednoznacznie.
///
/// Dotyczy TYLKO brzmień wewnętrznych. Jak moduł zapisuje przypisanie pliku
/// WAV z karty, nie jest jeszcze zmierzone — dlatego edytor pokazuje nazwę
/// tylko wtedy, gdy slot wygląda tak jak każdy slot z brzmieniem wewnętrznym
/// w plikach Arka (+0x02 = 1), a w każdym innym przypadku gołą liczbę.
enum Instrumenty {

    static let nazwy: [String] = [
        "001 Acous K", "002 Small K", "003 Soft K", "004 Round K",
        "005 Slammin' K", "006 Dance K", "007 House K", "008 FatElec K",
        "009 DubStep K", "010 HipHop K", "011 Impact K", "012 Drumn' Bs K",
        "013 Knock K", "014 DistTightK", "015 Thump K", "016 TR-808 K1",
        "017 TR-808 K2", "018 TR-909 K", "019 Steel S", "020 Steel SR",
        "021 Small S", "022 Small SR", "023 Piccolo S", "024 Piccolo SR",
        "025 Bright S", "026 Power S", "027 House S", "028 Electro S",
        "029 DubStep S1", "030 DubStep S2", "031 DistPunchS", "032 HipHop S1",
        "033 HipHop S2", "034 Drumn' Bs S", "035 Jungle S", "036 Clap S",
        "037 Metallic S", "038 TR-808 S", "039 TR-909 S", "040 XStick 1",
        "041 XStick 2", "042 XStick 3", "043 XStick 4", "044 XStick 5",
        "045 ElecTom Hi", "046 ElecTom Lo", "047 RotoTom Hi", "048 RotoTom Md",
        "049 RotoTom Lo", "050 Acous CHH", "051 Acous PHH", "052 TR-808 CHH",
        "053 TR-808 OHH", "054 TR-909 CHH", "055 TR-909 OHH", "056 Club HH1",
        "057 Club HH2", "058 Noise HH", "059 Splash Cym", "060 StackedCym",
        "061 ReverseCym", "062 ElectroCym", "063 Cowbell 1", "064 Cowbell 2",
        "065 Cowbell 3", "066 Cowbell 4", "067 Cowbell808", "068 Tambrine 1",
        "069 Tambrine 2", "070 Tambrine 3", "071 WoodBlk Hi", "072 WoodBlk Lo",
        "073 Claves", "074 Shaker", "075 VibraSlap", "076 Triangle",
        "077 TriangleMt", "078 Agogo Hi", "079 Agogo Lo", "080 Timbale Hi",
        "081 Timbale HR", "082 Timbale Lo", "083 Conga Hi", "084 Conga Slap",
        "085 Conga Lo", "086 Cajon Bass", "087 Cajon Slap", "088 Tabla Na",
        "089 Tabla Ge", "090 Tabla Ti", "091 Timpani C", "092 Timpani G",
        "093 Gong", "094 Tree Chime", "095 TR-808Clap", "096 TR-909Clap",
        "097 Live Clap", "098 Club Clap1", "099 Club Clap2", "100 Club Clap3",
        "101 Gate Clap", "102 Mini Clap", "103 ThumpAtk 1", "104 ThumpAtk 2",
        "105 High Q", "106 Sine Shot", "107 Super Low", "108 Boom Out",
        "109 Stomp", "110 Explosion", "111 SolidTight", "112 HardAttack",
        "113 Metal", "114 HeavyMetal", "115 DanceHiLo1", "116 DanceHiLo2",
        "117 Crush HiLo", "118 DistImpact", "119 ElecSizzle", "120 Sub Lo 1",
        "121 Sub Lo 2", "122 Sub Lo 3", "123 Dance Lo", "124 Elec Lo",
        "125 Attack 1", "126 Attack 2", "127 Attack 3", "128 LoudSteel",
        "129 LoudSteelR", "130 BrassHiLo", "131 BrassHiLoR", "132 ImpactAtk",
        "133 ImpactAtkR", "134 ImpactHiLo", "135 ShinyBuzz", "136 ShinyBuzzR",
        "137 Loud Buzz", "138 Loud BuzzR", "139 Buzz Long", "140 Deep Lo",
        "141 SteelTone", "142 SteelToneR", "143 BrassTone", "144 BrassToneR",
        "145 Dance HiLo", "146 Dance Buzz", "147 Dance Lo", "148 Clappin'",
        "149 BrightSlap", "150 Elec Sweep", "151 Elec Phase", "152 Dist HiLo",
        "153 Dist Hi", "154 Dist Gate", "155 Tight T1", "156 Tight T2",
        "157 Tight T3", "158 Tight T4", "159 Edge T1", "160 Edge T2",
        "161 Edge T3", "162 Edge T4",
    ]
}
