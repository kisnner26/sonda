import Darwin
import Foundation
import Network
import Observation
import SondaCore

struct NetInterface: Identifiable, Equatable {
    var id: String { name + address.description }
    let name: String
    let address: IPv4
    let netmask: IPv4
    var subnet: Subnet? { Subnet(address: address, netmask: netmask) }
    var kind: String {
        if name == "en0" { return "Wi-Fi" }
        if name.hasPrefix("pdp_ip") { return "datos móviles" }
        if name.hasPrefix("bridge") { return "punto de acceso" }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") { return "VPN" }
        if name.hasPrefix("en") { return "Ethernet / otro" }
        return name
    }
}

enum LocalNet {
    /// direcciones IPv4 de las interfaces activas (sin loopback).
    static func interfaces() -> [NetInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var out: [NetInterface] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = ptr.pointee
            guard let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), let mask = a.ifa_netmask,
                  a.ifa_flags & UInt32(IFF_UP) != 0, a.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            func value(_ s: UnsafeMutablePointer<sockaddr>) -> UInt32 {
                s.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            }
            out.append(NetInterface(name: String(cString: a.ifa_name), address: IPv4(value(addr)), netmask: IPv4(value(mask))))
        }
        return out
    }

    enum Probe: Equatable { case open, refused, silent }

    /// intenta abrir una conexion TCP. "cerrado pero respondio" (RST) cuenta como equipo vivo aunque el puerto no lo este.
    static func probe(host: String, port: Int, timeout: Double = 0.8) async -> Probe {
        guard let p = NWEndpoint.Port(rawValue: UInt16(port)) else { return .silent }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        return await withCheckedContinuation { cont in
            let lock = NSLock()
            var done = false
            func finish(_ r: Probe) {
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                conn.cancel()
                cont.resume(returning: r)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.open)
                case .waiting(let e), .failed(let e):
                    if case .posix(let code) = e, code == .ECONNREFUSED { finish(.refused) } else if case .failed = state { finish(.silent) }
                default: break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(.silent) }
        }
    }

    /// reparte el trabajo en `concurrency` tareas a la vez y avisa de cada resultado, con cuantas van terminadas.
    static func run<T: Sendable, R: Sendable>(_ items: [T], concurrency: Int = 48, _ work: @escaping @Sendable (T) async -> R,
                                              onResult: @MainActor @escaping (R, Int) -> Void) async {
        var index = 0, finished = 0
        await withTaskGroup(of: R.self) { group in
            func next() {
                guard index < items.count, !Task.isCancelled else { return }
                let item = items[index]; index += 1
                group.addTask { await work(item) }
            }
            for _ in 0..<min(concurrency, items.count) { next() }
            while let result = await group.next() {
                finished += 1
                await onResult(result, finished)
                next()
            }
        }
    }

    // MARK: DNS

    static func resolve(_ host: String) -> [String] {
        var hints = addrinfo(); hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return [] }
        defer { freeaddrinfo(res) }
        var out: [String] = []
        for p in sequence(first: first, next: { $0.pointee.ai_next }) {
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(p.pointee.ai_addr, p.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                let s = String(cString: buf)
                if !out.contains(s) { out.append(s) }
            }
        }
        return out
    }

    static func reverse(_ ip: String) -> String? {
        var addr = sockaddr_in(); addr.sin_family = sa_family_t(AF_INET); addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return nil }
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &buf, socklen_t(buf.count), nil, 0, NI_NAMEREQD) } }
        return r == 0 ? String(cString: buf) : nil
    }

    // MARK: ping ICMP (socket de datagramas: no necesita privilegios en iOS)

    enum PingResult: Equatable { case reply(ms: Double, from: String), timeout, error(String) }

    static func ping(host: String, sequence: UInt16, id: UInt16, timeout: Double = 2, ttl: Int32? = nil) -> PingResult {
        guard let ip = resolve(host).first(where: { IPv4($0) != nil }) else { return .error("no se pudo resolver el nombre") }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return .error("no se pudo abrir el socket ICMP") }
        defer { close(fd) }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        if var ttl { setsockopt(fd, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size)) }
        var dest = sockaddr_in(); dest.sin_family = sa_family_t(AF_INET); dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        inet_pton(AF_INET, ip, &dest.sin_addr)
        let packet = Icmp.echoRequest(id: id, sequence: sequence)
        let start = DispatchTime.now().uptimeNanoseconds
        let sent = withUnsafePointer(to: &dest) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard sent >= 0 else { return .error(String(cString: strerror(errno))) }
        var buf = [UInt8](repeating: 0, count: 1500)
        while true {
            var from = sockaddr_in(); var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) } }
            if n < 0 { return errno == EAGAIN || errno == EWOULDBLOCK ? .timeout : .error(String(cString: strerror(errno))) }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            var src = from.sin_addr
            var name = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &src, &name, socklen_t(name.count))
            switch Icmp.parse(Array(buf[0..<n])) {
            // el nucleo cambia el identificador del paquete en los sockets de datagramas, asi que solo se comprueba la secuencia
            case .echo(_, let seq) where seq == sequence: return .reply(ms: ms, from: String(cString: name))
            case .timeExceeded: return .reply(ms: ms, from: String(cString: name))
            default: continue
            }
        }
    }
}

struct BonjourService: Identifiable, Hashable {
    var id: String { "\(name).\(type).\(domain)" }
    let name: String
    let type: String
    let domain: String
    let endpoint: NWEndpoint

    static func == (a: BonjourService, b: BonjourService) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var friendlyType: String {
        [ "_http._tcp": "Web (HTTP)", "_https._tcp": "Web (HTTPS)", "_ssh._tcp": "SSH", "_sftp-ssh._tcp": "SFTP", "_smb._tcp": "Archivos (SMB)",
          "_afpovertcp._tcp": "Archivos (AFP)", "_airplay._tcp": "AirPlay", "_raop._tcp": "AirPlay (audio)", "_homekit._tcp": "HomeKit",
          "_hap._tcp": "HomeKit accesorio", "_googlecast._tcp": "Chromecast", "_ipp._tcp": "Impresora (IPP)", "_ipps._tcp": "Impresora (IPPS)",
          "_printer._tcp": "Impresora (LPD)", "_pdl-datastream._tcp": "Impresora (RAW)", "_companion-link._tcp": "Compañero de Apple",
          "_device-info._tcp": "Información del equipo", "_spotify-connect._tcp": "Spotify Connect", "_rfb._tcp": "Pantalla compartida (VNC)",
          "_mqtt._tcp": "MQTT", "_matter._tcp": "Matter", "_workstation._tcp": "Estación de trabajo" ][type] ?? type
    }
}

/// busca servicios anunciados por Bonjour/mDNS en la red local.
@MainActor
@Observable
final class BonjourBrowser {
    static let types = ["_http._tcp", "_https._tcp", "_ssh._tcp", "_sftp-ssh._tcp", "_smb._tcp", "_afpovertcp._tcp", "_airplay._tcp", "_raop._tcp",
                        "_homekit._tcp", "_hap._tcp", "_googlecast._tcp", "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp",
                        "_companion-link._tcp", "_device-info._tcp", "_spotify-connect._tcp", "_rfb._tcp", "_mqtt._tcp", "_matter._tcp", "_workstation._tcp"]

    private(set) var services: [BonjourService] = []
    private(set) var running = false
    private(set) var resolved: [String: String] = [:]
    @ObservationIgnored private var browsers: [NWBrowser] = []

    func start() {
        guard !running else { return }
        running = true; services = []
        for type in Self.types {
            let b = NWBrowser(for: .bonjour(type: type, domain: nil), using: .init())
            b.browseResultsChangedHandler = { [weak self] results, _ in
                let found = results.compactMap { r -> BonjourService? in
                    if case let .service(name, type, domain, _) = r.endpoint { return BonjourService(name: name, type: type, domain: domain, endpoint: r.endpoint) }
                    return nil
                }
                Task { @MainActor [weak self] in self?.merge(type: type, found) }
            }
            b.start(queue: .main)
            browsers.append(b)
        }
    }

    func stop() { browsers.forEach { $0.cancel() }; browsers = []; running = false }

    private func merge(type: String, _ found: [BonjourService]) {
        services.removeAll { $0.type == type || $0.type == type + "." }
        services.append(contentsOf: found)
        services.sort { ($0.friendlyType, $0.name) < ($1.friendlyType, $1.name) }
    }

    /// abre una conexion al servicio solo para saber su direccion y puerto, y la cierra.
    func resolve(_ s: BonjourService) {
        let conn = NWConnection(to: s.endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state, case let .hostPort(host, port)? = conn.currentPath?.remoteEndpoint {
                let text = "\(host):\(port)".replacingOccurrences(of: "%en0", with: "")
                Task { @MainActor [weak self] in self?.resolved[s.id] = text }
                conn.cancel()
            } else if case .failed = state { conn.cancel() }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) { conn.cancel() }
    }
}
