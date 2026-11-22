import SwiftUI

/// Wybór typu pada — w kolejności, w jakiej pokazuje ją moduł.
///
/// To nie jest zwykły wiersz pola, bo zmiana typu robi więcej niż zapis jednej
/// wartości: przestawia resztę ustawień wejścia na wartości domyślne nowego
/// typu, tak jak moduł. Dlatego idzie przez `KitEditor.setPadType`, a nie przez
/// ogólny zapis pola, i dlatego opis pod etykietą mówi to wprost.
struct WierszTypuPada: View {

    @ObservedObject var editor: KitEditor
    let rekord: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Pad Type")
                    .font(.title3)
                Text("Changing it resets the settings below to the pad's defaults, "
                     + "as on the module. XTLK Cancel and Input stay as they are.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Group {
                if let biezacy = editor.padType(rekord: rekord) {
                    Picker("", selection: Binding(
                        get: { biezacy.kod },
                        set: { kod in
                            if let typ = TypyPadow.typ(kod: kod) {
                                editor.setPadType(typ, rekord: rekord)
                            }
                        }
                    )) {
                        ForEach(TypyPadow.kolejnoscNaModule, id: \.self) { kod in
                            Text(TypyPadow.typ(kod: kod)?.nazwa ?? "#\(kod)").tag(kod)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.large)
                } else {
                    // Kod spoza zmierzonej tablicy: nie nazywamy go i nie dajemy
                    // zmieniać — nie wiemy, co moduł by z tym zrobił.
                    Text("unknown type")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: FieldRow.szerokoscKontrolki, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
