import SwiftUI
import SondaCore

private enum CameraTool: String, Hashable { case codes, ir }

struct CameraView: View {
    var body: some View {
        Screen(title: "cámara", subtitle: "leer códigos y ver luz infrarroja") {
            VStack(spacing: 0) {
                NavigationLink(value: CameraTool.codes) { ModuleRow(icon: .lens, title: "códigos", detail: "qr y códigos de barras, con lo que contienen") }.buttonStyle(.plain)
                NavigationLink(value: CameraTool.ir) { ModuleRow(icon: .target, title: "infrarrojo", detail: "¿emite este mando a distancia?") }.buttonStyle(.plain)
            }
        }
        .navigationDestination(for: CameraTool.self) { t in
            switch t {
            case .codes: CodesView()
            case .ir: IRView()
            }
        }
    }
}

// MARK: codigos

private struct CodesView: View {
    @State private var scanner = CodeScanner()

    var body: some View {
        Screen(title: "códigos") {
            if scanner.denied { Text("Sonda no tiene permiso de cámara. Puedes darlo en Ajustes > Sonda.").font(.serif(15, italic: true)).foregroundStyle(Palette.rose) }
            CameraPreview(session: scanner.session).frame(height: 260).overlay(Rectangle().stroke(Palette.ink, lineWidth: 0.8))
            if scanner.records.isEmpty { Text("apunta a un código.").font(.serif(15, italic: true)).foregroundStyle(Palette.mid) }
            ForEach(scanner.records) { r in ResultCard(record: r) }
            if !scanner.records.isEmpty { Button("borrar la lista") { scanner.clear() }.buttonStyle(QuietButtonStyle()) }
        }
        .task { await scanner.start() }
        .onDisappear { scanner.stop() }
    }
}

private struct ResultCard: View {
    let record: ScanRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(verbatim: record.symbology)
            switch record.payload {
            case .url(let url, let warning):
                Text(url.host ?? url.absoluteString).font(.serif(20)).foregroundStyle(Palette.ink)
                Text(url.absoluteString).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.mid).lineLimit(3)
                if let w = warning { Text(w).font(.serif(14, italic: true)).foregroundStyle(Palette.rose) }
                Link("abrir en Safari", destination: url).buttonStyle(QuietButtonStyle())
            case .wifi(let ssid, let password, let security, let hidden):
                Text("red Wi-Fi: \(ssid)").font(.serif(20)).foregroundStyle(Palette.ink)
                Text("\(security)\(hidden ? " · oculta" : "")").font(.serif(14, italic: true)).foregroundStyle(Palette.mid)
                if let password { Text(password).font(.system(size: 15, design: .monospaced)).foregroundStyle(Palette.moss).textSelection(.enabled) }
            case .contact(let name, let phones, let emails, let org):
                Text(name ?? "contacto").font(.serif(20)).foregroundStyle(Palette.ink)
                Text(([org].compactMap { $0 } + phones + emails).joined(separator: "\n")).font(.serif(14)).foregroundStyle(Palette.mid)
            case .geo(let lat, let lon):
                Text(String(format: "%.5f, %.5f", lat, lon)).font(.serif(20)).foregroundStyle(Palette.ink)
                Link("abrir en Mapas", destination: URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)")!).buttonStyle(QuietButtonStyle())
            case .email(let address, let subject):
                Text(address).font(.serif(20)).foregroundStyle(Palette.ink); if let subject { Text(subject).font(.serif(14, italic: true)).foregroundStyle(Palette.mid) }
            case .phone(let n): Text(n).font(.serif(20)).foregroundStyle(Palette.ink)
            case .sms(let n, let body): Text(n).font(.serif(20)).foregroundStyle(Palette.ink); if let body { Text(body).font(.serif(14)).foregroundStyle(Palette.mid) }
            case .otp(let label, let issuer, let kind):
                Text(label).font(.serif(20)).foregroundStyle(Palette.ink)
                Text("clave de un solo uso (\(kind))\(issuer.map { " · \($0)" } ?? "")").font(.serif(14, italic: true)).foregroundStyle(Palette.mid)
                Text("contiene el secreto de tu verificador: no lo compartas.").font(.serif(13, italic: true)).foregroundStyle(Palette.rose)
            case .text(let t): Text(t).font(.serif(17)).foregroundStyle(Palette.ink).textSelection(.enabled)
            }
            HStack(spacing: 20) {
                Button("copiar") { UIPasteboard.general.string = record.raw; Haptics.tap() }.buttonStyle(QuietButtonStyle())
                Text(record.date, style: .time).font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
            }
            Hairline(opacity: 0.25)
        }
    }
}

// MARK: infrarrojo

private struct IRView: View {
    @State private var ir = IRScanner()

    var body: some View {
        Screen(title: "infrarrojo", subtitle: "un mando a distancia emite luz que tú no ves") {
            if ir.denied { Text("Sonda no tiene permiso de cámara. Puedes darlo en Ajustes > Sonda.").font(.serif(15, italic: true)).foregroundStyle(Palette.rose) }
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Palette.ink, lineWidth: 1)
                    Circle().fill(ir.lit ? Palette.rose : Palette.paperDark).padding(10)
                }
                .frame(width: 86, height: 86)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ir.lit ? "¡destello!" : "esperando…").font(.serif(24, italic: true)).foregroundStyle(ir.lit ? Palette.rose : Palette.mid)
                    Caption(verbatim: "\(ir.burstCount) " + String(localized: "destellos"))
                    Caption(verbatim: String(format: "%.0f fps", ir.fps))
                }
            }
            Sparkline(values: ir.brightness).frame(height: 70)
            HStack(spacing: 22) {
                Button("reiniciar") { ir.reset() }.buttonStyle(QuietButtonStyle())
                Button(ir.front ? "usar cámara trasera" : "usar cámara frontal") { ir.flip() }.buttonStyle(QuietButtonStyle())
            }
            Text("apunta el emisor del mando a la cámara, a unos centímetros, y pulsa un botón. La cámara ve el infrarrojo como un destello violeta. Prueba las dos cámaras: unas filtran el infrarrojo mejor que otras. No decodifica el mando: la señal va a 38 kHz, mucho más rápida que la cámara. Sirve para comprobar si el mando emite o si sus pilas están agotadas.")
                .font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
        }
        .task { await ir.start() }
        .onDisappear { ir.stop() }
    }
}
