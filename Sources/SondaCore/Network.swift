import Foundation

public struct IPv4: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {
    public let value: UInt32
    public init(_ value: UInt32) { self.value = value }

    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var v: UInt32 = 0
        for p in parts {
            guard !p.isEmpty, p.count <= 3, p.allSatisfy(\.isASCII), p.allSatisfy(\.isNumber), let n = UInt32(p), n <= 255 else { return nil }
            v = v << 8 | n
        }
        value = v
    }

    public var description: String { "\(value >> 24).\(value >> 16 & 255).\(value >> 8 & 255).\(value & 255)" }
    public static func < (a: IPv4, b: IPv4) -> Bool { a.value < b.value }

    public var isPrivate: Bool {
        let a = value >> 24, b = value >> 16 & 255
        return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
    }
}

public struct Subnet: Sendable, Equatable {
    public let network: IPv4
    public let prefix: Int

    public init?(address: IPv4, prefix: Int) {
        guard (0...32).contains(prefix) else { return nil }
        self.prefix = prefix
        network = IPv4(address.value & Subnet.mask(prefix))
    }

    /// "192.168.1.20/24" o "192.168.1.0/24"
    public init?(cidr: String) {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let ip = IPv4(String(parts[0])), let p = Int(parts[1]) else { return nil }
        self.init(address: ip, prefix: p)
    }

    /// la mascara de red (`255.255.255.0`) a partir de su valor; nil si no es contigua.
    public init?(address: IPv4, netmask: IPv4) {
        let inverted = ~netmask.value
        guard inverted & (inverted &+ 1) == 0 else { return nil }
        self.init(address: address, prefix: netmask.value.nonzeroBitCount)
    }

    static func mask(_ prefix: Int) -> UInt32 { prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefix) }

    public var broadcast: IPv4 { IPv4(network.value | ~Subnet.mask(prefix)) }
    public var hostCount: Int { prefix >= 31 ? (prefix == 32 ? 1 : 2) : Int(broadcast.value - network.value) - 1 }

    /// direcciones utilizables, con un tope para no barrer una /8 entera por accidente.
    public func hosts(limit: Int = 1024) -> [IPv4] {
        guard prefix < 31 else { return prefix == 32 ? [network] : [network, broadcast] }
        let first = network.value + 1, last = broadcast.value - 1
        return (first...last).prefix(limit).map(IPv4.init)
    }

    public func contains(_ ip: IPv4) -> Bool { ip.value & Subnet.mask(prefix) == network.value }
}

public enum Ports {
    public static let common: [(port: Int, name: String)] = [
        (20, "FTP datos"), (21, "FTP"), (22, "SSH"), (23, "Telnet"), (25, "SMTP"), (53, "DNS"), (67, "DHCP"), (80, "HTTP"),
        (110, "POP3"), (111, "RPC"), (123, "NTP"), (135, "RPC (Windows)"), (139, "NetBIOS"), (143, "IMAP"), (161, "SNMP"),
        (389, "LDAP"), (443, "HTTPS"), (445, "SMB"), (515, "LPD (impresora)"), (548, "AFP"), (554, "RTSP"), (587, "SMTP (envío)"),
        (631, "IPP (impresora)"), (993, "IMAPS"), (995, "POP3S"), (1883, "MQTT"), (1900, "SSDP / UPnP"), (3000, "web de desarrollo"),
        (3306, "MySQL"), (3389, "Escritorio remoto"), (5000, "AirPlay / web"), (5353, "mDNS"), (5432, "PostgreSQL"), (5900, "VNC"),
        (7000, "AirPlay"), (8000, "web alterno"), (8008, "Chromecast"), (8080, "HTTP alterno"), (8443, "HTTPS alterno"),
        (8883, "MQTT TLS"), (9100, "impresora (JetDirect)"), (32400, "Plex"), (62078, "iPhone (lockdown)"),
    ]

    public static func name(_ port: Int) -> String? { common.first { $0.port == port }?.name }

    /// "22, 80, 8000-8010" -> [22, 80, 8000...8010]. lanza si hay un valor fuera de 1...65535 o mal escrito.
    public static func parse(_ text: String, limit: Int = 4096) throws -> [Int] {
        var out: [Int] = []
        var seen = Set<Int>()
        for raw in text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }) {
            let bounds = raw.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            guard bounds.count <= 2, let a = Int(bounds[0]), (1...65535).contains(a) else { throw PortError.invalid(String(raw)) }
            let b = bounds.count == 2 ? Int(bounds[1]) : a
            guard let b, (1...65535).contains(b), b >= a else { throw PortError.invalid(String(raw)) }
            for p in a...b where seen.insert(p).inserted { out.append(p) }
            if out.count > limit { throw PortError.tooMany(limit) }
        }
        guard !out.isEmpty else { throw PortError.invalid(text) }
        return out
    }

    public enum PortError: Error, Equatable { case invalid(String), tooMany(Int) }
}

/// mensajes ICMP de eco (ping). Se arman y se leen a mano porque iOS permite sockets ICMP sin privilegios pero no da los paquetes.
public enum Icmp {
    public static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count { sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]); i += 2 }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(truncatingIfNeeded: sum)
    }

    public static func echoRequest(id: UInt16, sequence: UInt16, payload: [UInt8] = Array("sonda".utf8)) -> [UInt8] {
        var p: [UInt8] = [8, 0, 0, 0, UInt8(id >> 8), UInt8(id & 255), UInt8(sequence >> 8), UInt8(sequence & 255)] + payload
        let c = checksum(p)
        p[2] = UInt8(c >> 8); p[3] = UInt8(c & 255)
        return p
    }

    public enum Reply: Equatable {
        case echo(id: UInt16, sequence: UInt16)
        case timeExceeded
        case unreachable
    }

    /// interpreta una respuesta; en iOS llega con la cabecera IP delante, y se quita si esta.
    public static func parse(_ bytes: [UInt8]) -> Reply? {
        var b = bytes
        if let first = b.first, first >> 4 == 4 {
            let ihl = Int(first & 15) * 4
            guard b.count > ihl else { return nil }
            b = Array(b[ihl...])
        }
        guard b.count >= 8 else { return nil }
        switch b[0] {
        case 0: return .echo(id: UInt16(b[4]) << 8 | UInt16(b[5]), sequence: UInt16(b[6]) << 8 | UInt16(b[7]))
        case 11: return .timeExceeded
        case 3: return .unreachable
        default: return nil
        }
    }
}

public struct PingStats: Sendable, Equatable {
    public var sent = 0
    public var times: [Double] = []      // ms
    public init() {}
    public var received: Int { times.count }
    public var lossPercent: Double { sent == 0 ? 0 : Double(sent - received) / Double(sent) * 100 }
    public var min: Double? { times.min() }
    public var max: Double? { times.max() }
    public var avg: Double? { times.isEmpty ? nil : times.reduce(0, +) / Double(times.count) }
    /// desviacion media entre muestras consecutivas (jitter, como lo calcula ping).
    public var jitter: Double? {
        guard times.count > 1 else { return nil }
        return zip(times.dropFirst(), times).map { abs($0 - $1) }.reduce(0, +) / Double(times.count - 1)
    }
}
