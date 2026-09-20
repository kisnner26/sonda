import CoreBluetooth
import SwiftUI
import SondaCore

struct BluetoothView: View {
    private let scanner = BLEScanner.shared
    @State private var filter = Filter.all

    enum Filter: String, CaseIterable, Identifiable { case all = "todos", trackers = "rastreadores", named = "con nombre"; var id: String { rawValue } }

    private var shown: [BLEDevice] {
        switch filter {
        case .all: scanner.sorted
        case .trackers: scanner.trackers
        case .named: scanner.sorted.filter { $0.name != nil }
        }
    }

    var body: some View {
        Screen(title: "bluetooth", subtitle: "lo que anuncian los dispositivos a tu alrededor") {
            stateNotice
            HStack(spacing: 22) {
                Button(scanner.isScanning ? "detener" : "escanear") { scanner.isScanning ? scanner.stop() : scanner.start(); Haptics.tap() }
                    .buttonStyle(InkButtonStyle())
                    .disabled(scanner.state != .poweredOn)
                if !scanner.devices.isEmpty { Button("limpiar") { scanner.clear() }.buttonStyle(QuietButtonStyle()) }
            }
            if !scanner.trackers.isEmpty { trackerCard }
            HStack { Caption(verbatim: "\(scanner.devices.count) " + String(localized: "dispositivos")); Spacer() }
            Picker("filtro", selection: $filter) { ForEach(Filter.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }
                .pickerStyle(.segmented)
            if shown.isEmpty {
                Text(scanner.isScanning ? "buscando…" : "pulsa escanear para empezar.").font(.serif(15, italic: true)).foregroundStyle(Palette.mid).padding(.top, 8)
            }
            ForEach(shown) { d in
                NavigationLink(value: d.id) { DeviceRow(device: d) }.buttonStyle(.plain)
            }
        }
        .navigationDestination(for: UUID.self) { DeviceView(id: $0) }
        .onDisappear { scanner.stop() }
    }

    @ViewBuilder private var stateNotice: some View {
        switch scanner.state {
        case .poweredOff: Text("el Bluetooth está apagado. Actívalo en Ajustes o en el centro de control.").font(.serif(15, italic: true)).foregroundStyle(Palette.rose)
        case .unauthorized: Text("Sonda no tiene permiso de Bluetooth. Puedes darlo en Ajustes > Sonda.").font(.serif(15, italic: true)).foregroundStyle(Palette.rose)
        case .unsupported: Text("este dispositivo no tiene Bluetooth LE.").font(.serif(15, italic: true)).foregroundStyle(Palette.rose)
        default: EmptyView()
        }
    }

    private var trackerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption("rastreadores cerca", color: Palette.rose)
            Text("\(scanner.trackers.count) accesorio(s) de localización anuncian cerca de ti.").font(.serif(17, italic: true)).foregroundStyle(Palette.ink)
            Text("si uno que no es tuyo te acompaña durante horas, el iPhone también avisa por su cuenta; aquí puedes ver cuál es y si está muy cerca.")
                .font(.serif(13, italic: true)).foregroundStyle(Palette.mid)
        }
        .card()
    }
}

struct SignalBars: View {
    let rssi: Double
    private var level: Int { rssi > -55 ? 5 : rssi > -65 ? 4 : rssi > -75 ? 3 : rssi > -85 ? 2 : 1 }
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Rectangle().fill(i <= level ? Palette.ink : Palette.faint).frame(width: 3, height: CGFloat(3 + i * 3))
            }
        }
        .accessibilityLabel("señal \(Int(rssi)) dBm")
    }
}

struct DeviceRow: View {
    let device: BLEDevice
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.title).font(.serif(18, italic: device.name == nil)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text([device.info.vendor, device.info.kind].compactMap { $0 }.filter { $0 != device.title }.joined(separator: " · ").ifEmpty("sin datos de fabricante"))
                        .font(.serif(13, italic: true)).foregroundStyle(Palette.mid).lineLimit(1)
                    if device.info.tracker != nil { Caption("rastreador", color: Palette.rose) }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    SignalBars(rssi: device.smoothed)
                    Text(device.distance.map { $0 < 10 ? String(format: "≈ %.1f m", $0) : "≈ \(Int($0)) m" } ?? "").font(.serif(12, italic: true)).foregroundStyle(Palette.mid)
                }
            }
            .padding(.vertical, 11)
            Hairline(opacity: 0.2)
        }
        .contentShape(Rectangle())
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}

// MARK: detalle

struct DeviceView: View {
    let id: UUID
    private let scanner = BLEScanner.shared
    @State private var finder = false
    @State private var lastTick = Date.distantPast
    @State private var confirmWrite: GattCharacteristic?
    @State private var writeText = ""

    var body: some View {
        if let d = scanner.devices[id] {
            Screen(title: LocalizedStringKey(d.title), subtitle: LocalizedStringKey(d.info.vendor ?? "")) {
                PetalGauge(value: max(0, min(1, (d.smoothed + 100) / 60)),
                           center: d.distance.map { $0 < 10 ? String(format: "%.1f m", $0) : "\(Int($0)) m" } ?? "—",
                           caption: "\(Int(d.smoothed.rounded())) dBm")
                    .frame(maxWidth: 260).frame(maxWidth: .infinity)
                Sparkline(values: d.history.map(Double.init), range: -100 ... -30).frame(height: 56)
                Text("la distancia sale de la potencia de la señal: fluctúa con el cuerpo, las paredes y la orientación. Sirve para saber si está cerca o lejos, no para medir.")
                    .font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
                Toggle(isOn: $finder) { Caption("modo búsqueda") }.tint(Palette.moss)
                    .onChange(of: d.rssi) { _, rssi in if finder { tick(rssi) } }
                info(d)
                gatt(d)
            }
        } else {
            Screen(title: "dispositivo") { Text("ya no se ve: salió del alcance.").font(.serif(15, italic: true)).foregroundStyle(Palette.mid) }
        }
    }

    /// vibra mas rapido cuanto mas fuerte llega la señal: para encontrar un dispositivo dando vueltas por la habitacion.
    private func tick(_ rssi: Int) {
        let strength = max(0, min(1, Double(rssi + 100) / 60))
        let interval = 1.0 - 0.85 * strength
        guard Date().timeIntervalSince(lastTick) > interval else { return }
        lastTick = Date()
        Haptics.tick(0.35 + 0.65 * strength)
    }

    @ViewBuilder private func info(_ d: BLEDevice) -> some View {
        Caption("anuncio")
        VStack(alignment: .leading, spacing: 8) {
            line("identificador", d.id.uuidString.lowercased())
            if let n = d.name { line("nombre", n) }
            if let v = d.info.vendor { line("fabricante", v) }
            if let k = d.info.kind { line("tipo", k) }
            if let b = d.info.beacon { line("iBeacon", "\(b.uuid)\nmayor \(b.major) · menor \(b.minor) · \(b.txPower) dBm a 1 m") }
            if let e = d.info.eddystone { line("Eddystone", e) }
            if let c = d.advert.connectable { line("conectable", c ? "sí" : "no") }
            if let t = d.advert.txPower { line("potencia anunciada", "\(t) dBm") }
            line("anuncios recibidos", "\(d.advertisements) en \(Int(d.lastSeen.timeIntervalSince(d.firstSeen))) s")
            if !d.advert.serviceUUIDs.isEmpty {
                line("servicios", d.advert.serviceUUIDs.map { u in Gatt.serviceName(u).map { "\(Gatt.short(u)) · \($0)" } ?? Gatt.short(u) }.joined(separator: "\n"))
            }
            if let m = d.advert.manufacturerData { line("datos de fabricante", Hex.dump(m, columns: 8).joined(separator: "\n"), mono: true) }
            ForEach(d.advert.serviceData.keys.sorted(), id: \.self) { k in line("datos de servicio \(Gatt.short(k))", Hex.dump(d.advert.serviceData[k]!, columns: 8).joined(separator: "\n"), mono: true) }
        }
        if let t = d.info.tracker {
            Text(t == .findMy ? "es un accesorio de la red Encontrar de Apple (un AirTag u otro compatible)."
                 : t == .tile ? "es un rastreador Tile." : "es un rastreador Samsung SmartTag.")
                .font(.serif(14, italic: true)).foregroundStyle(Palette.rose)
        }
    }

    private func line(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Caption(verbatim: label)
            Text(value).font(mono ? .system(size: 12, design: .monospaced) : .serif(15)).foregroundStyle(Palette.ink).textSelection(.enabled)
        }
    }

    // MARK: GATT

    @ViewBuilder private func gatt(_ d: BLEDevice) -> some View {
        Hairline().padding(.top, 6)
        Caption("servicios (GATT)")
        if d.advert.connectable == false {
            Text("este dispositivo no acepta conexiones.").font(.serif(14, italic: true)).foregroundStyle(Palette.mid)
        } else if scanner.connectedID == id {
            HStack(spacing: 20) {
                Text("conectado").font(.serif(15, italic: true)).foregroundStyle(Palette.moss)
                Button("desconectar") { scanner.disconnect() }.buttonStyle(QuietButtonStyle())
            }
            ForEach(scanner.gattServices) { s in serviceView(s) }
        } else {
            Text("conectar solo lee sus servicios: no cambia nada del dispositivo. Muchos rechazan conexiones desconocidas.").font(.serif(13, italic: true)).foregroundStyle(Palette.mid)
            Button(scanner.connecting ? "conectando…" : "explorar servicios") { scanner.connect(id) }.buttonStyle(InkButtonStyle()).disabled(scanner.connecting)
        }
        if let e = scanner.gattError { Text(e).font(.serif(13, italic: true)).foregroundStyle(Palette.rose) }
    }

    private func serviceView(_ s: GattService) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Gatt.serviceName(s.uuid) ?? Gatt.short(s.uuid)).font(.serif(17, italic: true)).foregroundStyle(Palette.ink)
            if Gatt.serviceName(s.uuid) != nil { Text(Gatt.short(s.uuid)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.mid) }
            ForEach(s.characteristics) { c in characteristicView(c) }
            Hairline(opacity: 0.2)
        }
    }

    private func characteristicView(_ c: GattCharacteristic) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Gatt.characteristicName(c.uuid) ?? Gatt.short(c.uuid)).font(.serif(15)).foregroundStyle(Palette.ink)
            Text(c.properties.names.joined(separator: " · ")).font(.serif(12, italic: true)).foregroundStyle(Palette.mid)
            if let v = c.value {
                if let human = Gatt.describe(characteristic: c.uuid, value: v) { Text(human).font(.serif(15, italic: true)).foregroundStyle(Palette.moss) }
                Text(v.map { String(format: "%02x", $0) }.joined(separator: " ").ifEmpty("(vacío)")).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.ink).textSelection(.enabled)
            }
            HStack(spacing: 18) {
                if c.properties.contains(.read) { Button("leer") { scanner.read(c) }.buttonStyle(QuietButtonStyle()) }
                if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                    Button(c.notifying ? "dejar de escuchar" : "escuchar") { scanner.setNotify(c, !c.notifying) }.buttonStyle(QuietButtonStyle())
                }
                if c.properties.canWrite { Button("escribir…") { writeText = ""; confirmWrite = c }.buttonStyle(QuietButtonStyle()) }
            }
        }
        .padding(.vertical, 4)
        .alert("escribir en el dispositivo", isPresented: Binding(get: { confirmWrite?.id == c.id }, set: { if !$0 { confirmWrite = nil } })) {
            TextField("bytes en hex, p. ej. 01 ff", text: $writeText).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("cancelar", role: .cancel) {}
            Button("enviar", role: .destructive) {
                if let data = try? Hex.parse(writeText) { scanner.write(c, data: data); Haptics.warning() }
            }
        } message: {
            Text("escribir puede cambiar el comportamiento del dispositivo. Hazlo solo con uno tuyo y si sabes qué envías.")
        }
    }
}
