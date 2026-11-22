import SwiftUI

/// Wybór efektu kitu — dwanaście efektów w kolejności, w jakiej pokazuje je
/// moduł.
///
/// Tak jak przy typie pada: zmiana efektu to nie zapis jednej wartości, tylko
/// typ plus wartości domyślne wszystkich jego parametrów, dokładnie jak moduł.
/// Same parametry efektu nie są jeszcze do edycji — wiemy, gdzie leżą, ale nie
/// dla każdego efektu wiemy, które pole jest którym parametrem.
struct WierszEfektuKitu: View {

    @ObservedObject var editor: KitEditor
    let kit: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Kit Effect")
                    .font(.title3)
                Text("Changing it resets the effect's parameters to their defaults, "
                     + "as on the module. The parameters themselves are not editable yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Group {
                if let biezacy = editor.kitEffect(kit: kit) {
                    Picker("", selection: Binding(
                        get: { biezacy.kod },
                        set: { kod in
                            if let efekt = TypyEfektow.typ(kod: kod) {
                                editor.setKitEffect(efekt, kit: kit)
                            }
                        }
                    )) {
                        ForEach(TypyEfektow.wszystkie, id: \.kod) { efekt in
                            Text(efekt.nazwa).tag(efekt.kod)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.large)
                } else {
                    Text("unknown effect")
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
