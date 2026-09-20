import Foundation

/// Lo que anuncia un dispositivo BLE, ya separado de CoreBluetooth para poder probarlo.
public struct Advert: Sendable, Equatable {
    public var localName: String?
    public var manufacturerData: Data?
    public var serviceUUIDs: [String]           // como los da CoreBluetooth: "FEED" o el UUID completo
    public var serviceData: [String: Data]
    public var txPower: Int?
    public var connectable: Bool?

    public init(localName: String? = nil, manufacturerData: Data? = nil, serviceUUIDs: [String] = [],
                serviceData: [String: Data] = [:], txPower: Int? = nil, connectable: Bool? = nil) {
        self.localName = localName; self.manufacturerData = manufacturerData; self.serviceUUIDs = serviceUUIDs
        self.serviceData = serviceData; self.txPower = txPower; self.connectable = connectable
    }
}

public enum TrackerKind: String, Sendable { case findMy, tile, smartTag }

public struct IBeacon: Sendable, Equatable {
    public var uuid: String
    public var major: Int
    public var minor: Int
    public var txPower: Int          // RSSI medido a 1 m
}

public struct AdvertInfo: Sendable, Equatable {
    public var vendor: String?
    public var kind: String?          // "iBeacon", "AirPods / Beats", "Fast Pair"…
    public var tracker: TrackerKind?
    public var beacon: IBeacon?
    public var eddystone: String?
    public var appleTypes: [UInt8]
}

public enum Bluetooth {
    /// Empresas por su identificador de la SIG. Lista corta de las que estoy seguro; el resto se muestra como número.
    public static let companies: [UInt16: String] = [
        0x0002: "Intel", 0x0006: "Microsoft", 0x000D: "Texas Instruments", 0x000F: "Broadcom", 0x004C: "Apple",
        0x0059: "Nordic Semiconductor", 0x006B: "Polar Electro", 0x0075: "Samsung", 0x0087: "Garmin", 0x009E: "Bose",
        0x00C4: "LG Electronics", 0x00E0: "Google", 0x012D: "Sony", 0x0171: "Amazon", 0x01DA: "Logitech",
        0x027D: "Huawei", 0x02E5: "Espressif", 0x038F: "Xiaomi", 0x0499: "Ruuvi Innovations", 0x067C: "Tile",
    ]

    /// tipos del protocolo de continuidad de Apple (primer byte de cada bloque TLV tras el id de empresa).
    public static let appleTypes: [UInt8: String] = [
        0x02: "iBeacon", 0x03: "AirPrint", 0x05: "AirDrop", 0x06: "HomeKit", 0x07: "AirPods / Beats", 0x08: "Hey Siri",
        0x09: "AirPlay (receptor)", 0x0A: "AirPlay (emisor)", 0x0B: "Magic Switch", 0x0C: "Handoff", 0x0D: "Wi-Fi Settings",
        0x0E: "Instant Hotspot", 0x0F: "Nearby Action", 0x10: "Nearby Info", 0x12: "Find My",
    ]

    public static func companyName(_ id: UInt16) -> String? { companies[id] }

    /// id de empresa (little-endian) de unos datos de fabricante.
    public static func companyID(_ data: Data) -> UInt16? {
        data.count >= 2 ? UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8 : nil
    }

    public static func analyze(_ ad: Advert) -> AdvertInfo {
        var info = AdvertInfo(vendor: nil, kind: nil, tracker: nil, beacon: nil, eddystone: nil, appleTypes: [])
        let uuids = Set(ad.serviceUUIDs.map { $0.uppercased() })

        if let m = ad.manufacturerData, let id = companyID(m) {
            info.vendor = companyName(id) ?? String(format: "empresa 0x%04X", id)
            if id == 0x004C {
                let blocks = appleBlocks(Data(m.dropFirst(2)))
                info.appleTypes = blocks.map(\.type)
                if let beacon = blocks.first(where: { $0.type == 0x02 && $0.payload.count == 21 }) {
                    info.beacon = parseIBeacon(beacon.payload)
                    info.kind = "iBeacon"
                } else if let first = blocks.first {
                    info.kind = appleTypes[first.type] ?? String(format: "Apple 0x%02X", first.type)
                }
                if blocks.contains(where: { $0.type == 0x12 }) { info.tracker = .findMy; info.kind = "Find My (AirTag u otro accesorio)" }
            }
        }
        if uuids.contains("FEED") || uuids.contains("FEEC") { info.tracker = info.tracker ?? .tile; info.kind = info.kind ?? "Tile" }
        if uuids.contains("FD5A") { info.tracker = info.tracker ?? .smartTag; info.kind = info.kind ?? "Samsung SmartTag" }
        if uuids.contains("FE2C") { info.kind = info.kind ?? "Google Fast Pair" }
        if let frame = ad.serviceData.first(where: { $0.key.uppercased() == "FEAA" })?.value.first {
            info.eddystone = ["UID", "URL", "TLM", "EID"][safe: Int(frame >> 4)] ?? "desconocido"
            info.kind = info.kind ?? "Eddystone"
        }
        return info
    }

    /// bloques [tipo][largo][datos] de Apple. se detiene ante un bloque que no cabe.
    static func appleBlocks(_ d: Data) -> [(type: UInt8, payload: Data)] {
        var out: [(UInt8, Data)] = []
        var i = d.startIndex
        while i + 1 < d.endIndex {
            let type = d[i], len = Int(d[i + 1])
            let start = i + 2
            guard start + len <= d.endIndex else { break }
            out.append((type, d[start..<start + len]))
            i = start + len
        }
        return out
    }

    static func parseIBeacon(_ p: Data) -> IBeacon? {
        guard p.count == 21 else { return nil }
        let b = Array(p)
        let hex = b[0..<16].map { String(format: "%02X", $0) }.joined()
        let uuid = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { r in String(hex[hex.index(hex.startIndex, offsetBy: r.lowerBound)..<hex.index(hex.startIndex, offsetBy: r.upperBound)]) }.joined(separator: "-")
        return IBeacon(uuid: uuid, major: Int(b[16]) << 8 | Int(b[17]), minor: Int(b[18]) << 8 | Int(b[19]), txPower: Int(Int8(bitPattern: b[20])))
    }

    // MARK: distancia

    public enum Proximity: String, Sendable { case immediate, near, far, unknown }

    /// distancia aproximada en metros con el modelo de perdida logaritmica. `txPower` es el RSSI a 1 m (-59 si no se sabe).
    /// El RSSI fluctua mucho (cuerpo, paredes, antena): es una idea de "cerca o lejos", no una medida.
    public static func distance(rssi: Int, txPower: Int = -59, pathLoss n: Double = 2.0) -> Double? {
        guard rssi < 0, rssi > -120 else { return nil }
        return pow(10, Double(txPower - rssi) / (10 * n))
    }

    public static func proximity(rssi: Int) -> Proximity {
        guard let d = distance(rssi: rssi) else { return .unknown }
        return d < 1 ? .immediate : d < 5 ? .near : .far
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Nombres de servicios y caracteristicas GATT estandar (16 bits asignados por la SIG).
public enum Gatt {
    public static let services: [String: String] = [
        "1800": "Generic Access", "1801": "Generic Attribute", "1802": "Immediate Alert", "1803": "Link Loss", "1804": "Tx Power",
        "1805": "Current Time", "180A": "Device Information", "180D": "Heart Rate", "180F": "Battery", "1809": "Health Thermometer",
        "1810": "Blood Pressure", "1812": "Human Interface Device", "1816": "Cycling Speed and Cadence", "1818": "Cycling Power",
        "181A": "Environmental Sensing", "181C": "User Data", "181D": "Weight Scale", "1826": "Fitness Machine",
    ]

    public static let characteristics: [String: String] = [
        "2A00": "Device Name", "2A01": "Appearance", "2A04": "Preferred Connection Parameters", "2A05": "Service Changed",
        "2A19": "Battery Level", "2A23": "System ID", "2A24": "Model Number", "2A25": "Serial Number", "2A26": "Firmware Revision",
        "2A27": "Hardware Revision", "2A28": "Software Revision", "2A29": "Manufacturer Name", "2A2A": "IEEE Regulatory Certification",
        "2A37": "Heart Rate Measurement", "2A38": "Body Sensor Location", "2A50": "PnP ID", "2A6E": "Temperature", "2A6F": "Humidity",
    ]

    /// UUID de 128 bits de la base de Bluetooth (0000xxxx-0000-1000-8000-00805F9B34FB) -> "xxxx"; el resto tal cual.
    public static func short(_ uuid: String) -> String {
        let u = uuid.uppercased()
        if u.count == 36, u.hasPrefix("0000"), u.hasSuffix("-0000-1000-8000-00805F9B34FB") { return String(u.dropFirst(4).prefix(4)) }
        return u
    }

    public static func serviceName(_ uuid: String) -> String? { services[short(uuid)] }
    public static func characteristicName(_ uuid: String) -> String? { characteristics[short(uuid)] }

    /// interpretacion legible de algunos valores conocidos (nivel de bateria, textos); nil si no se sabe.
    public static func describe(characteristic uuid: String, value: Data) -> String? {
        switch short(uuid) {
        case "2A19": return value.first.map { "\($0) %" }
        case "2A00", "2A24", "2A25", "2A26", "2A27", "2A28", "2A29":
            return String(data: value, encoding: .utf8).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) }
        case "2A37":
            guard let flags = value.first, value.count >= 2 else { return nil }
            let wide = flags & 1 == 1
            guard !wide || value.count >= 3 else { return nil }
            let bpm = wide ? Int(value[value.startIndex + 1]) | Int(value[value.startIndex + 2]) << 8 : Int(value[value.startIndex + 1])
            return "\(bpm) lpm"
        default: return nil
        }
    }
}

public struct CharacteristicProperties: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let broadcast = CharacteristicProperties(rawValue: 0x01)
    public static let read = CharacteristicProperties(rawValue: 0x02)
    public static let writeWithoutResponse = CharacteristicProperties(rawValue: 0x04)
    public static let write = CharacteristicProperties(rawValue: 0x08)
    public static let notify = CharacteristicProperties(rawValue: 0x10)
    public static let indicate = CharacteristicProperties(rawValue: 0x20)
    public static let authenticatedSignedWrites = CharacteristicProperties(rawValue: 0x40)

    public var names: [String] {
        var out: [String] = []
        if contains(.read) { out.append("leer") }
        if contains(.write) { out.append("escribir") }
        if contains(.writeWithoutResponse) { out.append("escribir sin respuesta") }
        if contains(.notify) { out.append("notificar") }
        if contains(.indicate) { out.append("indicar") }
        if contains(.broadcast) { out.append("difundir") }
        if contains(.authenticatedSignedWrites) { out.append("firmado") }
        return out
    }

    public var canWrite: Bool { contains(.write) || contains(.writeWithoutResponse) }
}
