import SwiftUI

struct SettingsView: View {
    @Bindable private var appearance = Appearance.shared

    var body: some View {
        Screen(title: "ajustes") {
            VStack(alignment: .leading, spacing: 4) {
                Caption("tema")
                Picker("tema", selection: $appearance.choice) { ForEach(ThemeChoice.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            }
            Toggle(isOn: $appearance.haptics) { Caption("háptico") }.tint(Palette.moss)
            Hairline()
            Caption("acerca de")
            Text("sonda").font(.serif(24, italic: true)).foregroundStyle(Palette.ink)
            Caption(verbatim: String(localized: "versión") + " \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            Text("una caja de herramientas de radio, red y sensores para el iPhone, hecha con lo que iOS permite sin cuenta de pago de desarrollador.")
                .font(.serif(14, italic: true)).foregroundStyle(Palette.mid)
            Hairline()
            Caption("lo que no puede hacer")
            Text("no tiene radio de frecuencias bajas, sub-GHz ni infrarrojo emisor; no emula ni clona tarjetas NFC (iOS lo bloquea y la lectura de etiquetas exige cuenta de pago); no pone la Wi-Fi en modo monitor; no interfiere con nada. Todo lo que hace es mirar y medir.")
                .font(.serif(14, italic: true)).foregroundStyle(Palette.mid)
            Text("lo que se lee se queda en tu iPhone: no hay cuentas, servidores ni analíticas.").font(.serif(14, italic: true)).foregroundStyle(Palette.mid)
        }
    }
}
