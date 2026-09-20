import SwiftUI
import SondaCore

private enum NetTool: String, Hashable { case interfaces, bonjour, hosts, ports, ping, dns }

struct NetworkView: View {
    var body: some View {
        Screen(title: "red", subtitle: "lo que hay conectado a tu red local") {
            VStack(spacing: 0) {
                link(.interfaces, .network, "esta red", "tus direcciones y la subred")
                link(.bonjour, .target, "bonjour", "servicios que se anuncian: AirPlay, impresoras, SSH…")
                link(.hosts, .compass, "equipos", "quién está conectado a la subred")
                link(.ports, .toolbox, "puertos", "qué servicios abre un equipo")
                link(.ping, .wave, "ping", "latencia, pérdida y jitter")
                link(.dns, .leaf, "dns", "resolver un nombre y su inversa")
            }
            Text("iOS pide permiso de red local la primera vez. Sin él, estas herramientas no ven nada. Escanea solo redes tuyas o con permiso.")
                .font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
        }
        .navigationDestination(for: NetTool.self) { t in
            switch t {
            case .interfaces: InterfacesView()
            case .bonjour: BonjourView()
            case .hosts: HostsView()
            case .ports: PortsView()
            case .ping: PingView()
            case .dns: DNSView()
            }
        }
    }

    private func link(_ t: NetTool, _ icon: IconKind, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        NavigationLink(value: t) { ModuleRow(icon: icon, title: title, detail: detail) }.buttonStyle(.plain)
    }
}

// MARK: esta red

private struct InterfacesView: View {
    @State private var interfaces = LocalNet.interfaces()
    var body: some View {
        Screen(title: "esta red") {
            if interfaces.isEmpty { Text("sin conexión.").font(.serif(16, italic: true)).foregroundStyle(Palette.mid) }
            ForEach(interfaces) { i in
                VStack(alignment: .leading, spacing: 6) {
                    Caption(verbatim: "\(i.kind) · \(i.name)")
                    Text(i.address.description).font(.serif(26)).foregroundStyle(Palette.ink).textSelection(.enabled)
                    if let s = i.subnet {
                        Text("subred \(s.network)/\(s.prefix) · máscara \(i.netmask) · \(s.hostCount) equipos posibles").font(.serif(14, italic: true)).foregroundStyle(Palette.mid)
                    }
                    if i.address.isPrivate == false { Text("dirección pública o de operador").font(.serif(13, italic: true)).foregroundStyle(Palette.olive) }
                }
                .card()
            }
            Button("actualizar") { interfaces = LocalNet.interfaces() }.buttonStyle(QuietButtonStyle())
            Text("el nombre de la red Wi-Fi no se puede mostrar sin una cuenta de pago de desarrollador: iOS lo reserva a apps con permiso especial.")
                .font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
        }
    }
}

// MARK: bonjour

private struct BonjourView: View {
    @State private var browser = BonjourBrowser()
    var body: some View {
        Screen(title: "bonjour", subtitle: "servicios anunciados en tu red") {
            HStack(spacing: 20) {
                Button(browser.running ? "detener" : "buscar") { browser.running ? browser.stop() : browser.start(); Haptics.tap() }.buttonStyle(InkButtonStyle())
                Caption(verbatim: "\(browser.services.count)")
            }
            if browser.running && browser.services.isEmpty { Text("buscando…").font(.serif(15, italic: true)).foregroundStyle(Palette.mid) }
            ForEach(browser.services) { s in
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name).font(.serif(18)).foregroundStyle(Palette.ink)
                    Caption(verbatim: s.friendlyType)
                    if let r = browser.resolved[s.id] { Text(r).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.moss).textSelection(.enabled) }
                    else { Button("ver dirección") { browser.resolve(s) }.buttonStyle(QuietButtonStyle()) }
                    Hairline(opacity: 0.2).padding(.top, 6)
                }
            }
        }
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }
}

// MARK: equipos

private struct HostsView: View {
    struct Host: Identifiable, Equatable { let id: IPv4; var ports: [Int]; var ms: Double; var name: String? }

    @State private var interface = LocalNet.interfaces().first { $0.name == "en0" } ?? LocalNet.interfaces().first
    @State private var hosts: [Host] = []
    @State private var progress = 0.0
    @State private var scanning = false
    @State private var task: Task<Void, Never>?
    private let probePorts = [80, 443, 22, 445, 62078, 5353, 7000, 8080, 53, 139, 548, 5900, 8008, 9100, 1883]

    var body: some View {
        Screen(title: "equipos", subtitle: "quién responde en la subred") {
            if let i = interface, let s = i.subnet {
                Caption(verbatim: "\(s.network)/\(s.prefix) · \(min(s.hostCount, 1024)) direcciones")
                HStack(spacing: 20) {
                    Button(scanning ? "detener" : "escanear") { scanning ? stop() : start(s) }.buttonStyle(InkButtonStyle())
                    if scanning { Text("\(Int(progress * 100)) %").font(.serif(15, italic: true)).foregroundStyle(Palette.mid) }
                }
                if scanning { Ring(fraction: progress, tint: Palette.moss, width: 3).frame(width: 34, height: 34) }
                Text("un equipo cuenta como presente si acepta o rechaza una conexión TCP en alguno de \(probePorts.count) puertos comunes. Uno que descarta todo sin responder no aparece.")
                    .font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
                ForEach(hosts) { h in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(h.id.description).font(.serif(20)).foregroundStyle(Palette.ink); Spacer(); Text(String(format: "%.0f ms", h.ms)).font(.serif(13, italic: true)).foregroundStyle(Palette.mid) }
                        if let n = h.name { Text(n).font(.serif(14, italic: true)).foregroundStyle(Palette.mid) }
                        if !h.ports.isEmpty { Text(h.ports.map { p in Ports.name(p).map { "\(p) \($0)" } ?? "\(p)" }.joined(separator: " · ")).font(.serif(13)).foregroundStyle(Palette.moss) }
                        Hairline(opacity: 0.2).padding(.top, 6)
                    }
                }
            } else {
                Text("conéctate a una red Wi-Fi para escanearla.").font(.serif(16, italic: true)).foregroundStyle(Palette.mid)
            }
        }
        .onDisappear { stop() }
    }

    private func stop() { task?.cancel(); scanning = false }

    private func start(_ subnet: Subnet) {
        hosts = []; progress = 0; scanning = true
        let addresses = subnet.hosts(limit: 1024)
        let ports = probePorts
        task = Task {
            await LocalNet.run(addresses, concurrency: 40, { ip -> Host? in
                let start = Date()
                var open: [Int] = [], alive = false
                for p in ports {
                    switch await LocalNet.probe(host: ip.description, port: p, timeout: 0.5) {
                    case .open: open.append(p); alive = true
                    case .refused: alive = true
                    case .silent: break
                    }
                    if alive && !open.isEmpty { break }
                }
                return alive ? Host(id: ip, ports: open, ms: Date().timeIntervalSince(start) * 1000, name: nil) : nil
            }, onResult: { result, done in
                progress = Double(done) / Double(addresses.count)
                if let h = result { hosts.append(h); hosts.sort { $0.id < $1.id } }
            })
            scanning = false
            Haptics.success()
        }
    }
}

// MARK: puertos

private struct PortsView: View {
    @State private var host = ""
    @State private var spec = "comunes"
    @State private var open: [Int] = []
    @State private var scanned = 0
    @State private var total = 0
    @State private var scanning = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        Screen(title: "puertos", subtitle: "qué servicios abre un equipo") {
            field("equipo (ip o nombre)", $host)
            field("puertos: «comunes», «22,80» o «1-1024»", $spec)
            HStack(spacing: 20) {
                Button(scanning ? "detener" : "escanear") { scanning ? stop() : start() }.buttonStyle(InkButtonStyle()).disabled(host.trimmingCharacters(in: .whitespaces).isEmpty && !scanning)
                if scanning { Text("\(scanned) / \(total)").font(.serif(15, italic: true)).foregroundStyle(Palette.mid) }
            }
            if let error { Text(error).font(.serif(14, italic: true)).foregroundStyle(Palette.rose) }
            if scanning || !open.isEmpty { Caption(verbatim: "\(open.count) " + String(localized: "abiertos")) }
            ForEach(open, id: \.self) { p in
                HStack { Text("\(p)").font(.serif(20)).foregroundStyle(Palette.ink); Text(Ports.name(p) ?? "servicio desconocido").font(.serif(15, italic: true)).foregroundStyle(Palette.mid); Spacer() }
            }
            Text("escanea solo equipos tuyos o con permiso de su dueño.").font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
        }
        .onDisappear { stop() }
    }

    private func field(_ label: LocalizedStringKey, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Caption(label)
            TextField("", text: text).font(.serif(18)).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Hairline()
        }
    }

    private func stop() { task?.cancel(); scanning = false }

    private func start() {
        error = nil; open = []; scanned = 0
        let ports: [Int]
        do { ports = spec.lowercased() == "comunes" ? Ports.common.map(\.port) : try Ports.parse(spec) }
        catch { self.error = "revisa los puertos: usa números de 1 a 65535, listas o rangos (máximo 4096)."; return }
        total = ports.count; scanning = true
        let target = host.trimmingCharacters(in: .whitespaces)
        task = Task {
            await LocalNet.run(ports, concurrency: 64, { p -> Int? in await LocalNet.probe(host: target, port: p, timeout: 0.8) == .open ? p : nil },
                               onResult: { r, done in scanned = done; if let p = r { open.append(p); open.sort() } })
            scanning = false; Haptics.success()
        }
    }
}

// MARK: ping

private struct PingView: View {
    @State private var host = "1.1.1.1"
    @State private var stats = PingStats()
    @State private var log: [String] = []
    @State private var running = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        Screen(title: "ping", subtitle: "latencia, pérdida y jitter") {
            VStack(alignment: .leading, spacing: 4) {
                Caption("equipo")
                TextField("", text: $host).font(.serif(18)).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Hairline()
            }
            Button(running ? "detener" : "empezar") { running ? stop() : start() }.buttonStyle(InkButtonStyle())
            HStack(spacing: 24) {
                Metric(label: "mínimo", value: stats.min.map { String(format: "%.0f", $0) } ?? "—", unit: "ms")
                Metric(label: "media", value: stats.avg.map { String(format: "%.0f", $0) } ?? "—", unit: "ms")
                Metric(label: "máximo", value: stats.max.map { String(format: "%.0f", $0) } ?? "—", unit: "ms")
            }
            HStack(spacing: 24) {
                Metric(label: "pérdida", value: String(format: "%.0f", stats.lossPercent), unit: "%")
                Metric(label: "jitter", value: stats.jitter.map { String(format: "%.1f", $0) } ?? "—", unit: "ms")
                Metric(label: "enviados", value: "\(stats.sent)")
            }
            Sparkline(values: stats.times).frame(height: 60)
            ForEach(Array(log.suffix(12).enumerated()), id: \.offset) { _, line in Text(line).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.mid) }
        }
        .onDisappear { stop() }
    }

    private func stop() { task?.cancel(); running = false }

    private func start() {
        stats = PingStats(); log = []; running = true
        let target = host.trimmingCharacters(in: .whitespaces)
        task = Task {
            var seq: UInt16 = 0
            while !Task.isCancelled {
                seq &+= 1
                let s = seq
                let result = await Task.detached { LocalNet.ping(host: target, sequence: s, id: 0x5044) }.value
                stats.sent += 1
                switch result {
                case .reply(let ms, let from): stats.times.append(ms); log.append(String(format: "%d  %@  %.1f ms", s, from, ms))
                case .timeout: log.append("\(s)  sin respuesta")
                case .error(let e): log.append("\(s)  \(e)"); running = false; return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

// MARK: dns

private struct DNSView: View {
    @State private var query = ""
    @State private var results: [String] = []
    @State private var reverse: String?
    @State private var searched = false

    var body: some View {
        Screen(title: "dns", subtitle: "nombre ⇄ dirección") {
            VStack(alignment: .leading, spacing: 4) {
                Caption("nombre o dirección")
                TextField("", text: $query).font(.serif(18)).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).onSubmit(run)
                Hairline()
            }
            Button("resolver", action: run).buttonStyle(InkButtonStyle()).disabled(query.isEmpty)
            if searched && results.isEmpty { Text("sin resultados.").font(.serif(15, italic: true)).foregroundStyle(Palette.mid) }
            ForEach(results, id: \.self) { Text($0).font(.system(size: 15, design: .monospaced)).foregroundStyle(Palette.ink).textSelection(.enabled) }
            if let reverse { Caption("nombre inverso"); Text(reverse).font(.serif(17)).foregroundStyle(Palette.moss) }
        }
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        searched = true
        results = LocalNet.resolve(q)
        reverse = IPv4(q) != nil ? LocalNet.reverse(q) : nil
    }
}
