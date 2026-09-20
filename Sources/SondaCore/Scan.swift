import Foundation

/// Lo que dice el contenido de un QR o un codigo de barras, para mostrar algo mas util que el texto crudo.
public enum ScanPayload: Equatable, Sendable {
    case url(URL, warning: String?)
    case wifi(ssid: String, password: String?, security: String, hidden: Bool)
    case contact(name: String?, phones: [String], emails: [String], organization: String?)
    case geo(latitude: Double, longitude: Double)
    case email(address: String, subject: String?)
    case phone(String)
    case sms(number: String, body: String?)
    case otp(label: String, issuer: String?, kind: String)
    case text(String)
}

public enum ScanParser {
    public static func parse(_ raw: String) -> ScanPayload {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.hasPrefix("wifi:"), let w = wifi(String(text.dropFirst(5))) { return w }
        if lower.hasPrefix("begin:vcard") { return vcard(text) }
        if lower.hasPrefix("mecard:") { return mecard(String(text.dropFirst(7))) }
        if lower.hasPrefix("geo:"), let g = geo(String(text.dropFirst(4))) { return g }
        if lower.hasPrefix("mailto:") { return mail(String(text.dropFirst(7))) }
        if lower.hasPrefix("tel:") { return .phone(String(text.dropFirst(4))) }
        if lower.hasPrefix("smsto:") || lower.hasPrefix("sms:") {
            let rest = text.drop { $0 != ":" }.dropFirst()
            let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            return .sms(number: String(parts.first ?? ""), body: parts.count > 1 ? String(parts[1]) : nil)
        }
        if lower.hasPrefix("otpauth://"), let o = otp(text) { return o }
        if (lower.hasPrefix("http://") || lower.hasPrefix("https://")), let url = URL(string: text), url.host != nil {
            return .url(url, warning: warning(for: url))
        }
        return .text(raw)
    }

    static func warning(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.split(separator: ".").contains(where: { $0.hasPrefix("xn--") }) { return "el dominio usa caracteres especiales (punycode): puede ser una suplantación" }
        if url.scheme == "http" { return "conexión sin cifrar (http)" }
        if IPv4(host) != nil { return "dirección IP en vez de un nombre de dominio" }
        if url.user != nil { return "la dirección lleva usuario: el dominio real es \(host)" }
        return nil
    }

    /// separa por `;` respetando `\;` y demas escapes.
    static func fields(_ s: String, separator: Character = ";") -> [String] {
        var out: [String] = [], cur = "", escaped = false
        for ch in s {
            if escaped { cur.append(ch); escaped = false }
            else if ch == "\\" { escaped = true }
            else if ch == separator { out.append(cur); cur = "" }
            else { cur.append(ch) }
        }
        out.append(cur)
        return out
    }

    static func wifi(_ body: String) -> ScanPayload? {
        var ssid: String?, pass: String?, security = "sin cifrar", hidden = false
        for f in fields(body) where f.count > 2 && f[f.index(after: f.startIndex)] == ":" {
            let key = f.first!, value = String(f.dropFirst(2))
            switch key {
            case "S": ssid = value
            case "P": pass = value
            case "T": security = value.isEmpty || value.lowercased() == "nopass" ? "sin cifrar" : value.uppercased()
            case "H": hidden = value.lowercased() == "true"
            default: break
            }
        }
        guard let ssid else { return nil }
        return .wifi(ssid: ssid, password: pass?.isEmpty == true ? nil : pass, security: security, hidden: hidden)
    }

    static func vcard(_ text: String) -> ScanPayload {
        var name: String?, phones: [String] = [], emails: [String] = [], org: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].split(separator: ";")[0].uppercased(), value = String(parts[1])
            switch key {
            case "FN": name = value
            case "N": if name == nil { name = value.split(separator: ";").reversed().joined(separator: " ").trimmingCharacters(in: .whitespaces) }
            case "TEL": phones.append(value)
            case "EMAIL": emails.append(value)
            case "ORG": org = value.replacingOccurrences(of: ";", with: " ")
            default: break
            }
        }
        return .contact(name: name, phones: phones, emails: emails, organization: org)
    }

    static func mecard(_ body: String) -> ScanPayload {
        var name: String?, phones: [String] = [], emails: [String] = []
        for f in fields(body) {
            guard let i = f.firstIndex(of: ":") else { continue }
            let key = f[..<i].uppercased(), value = String(f[f.index(after: i)...])
            if key == "N" { name = value.split(separator: ",").reversed().joined(separator: " ") }
            else if key == "TEL" { phones.append(value) }
            else if key == "EMAIL" { emails.append(value) }
        }
        return .contact(name: name, phones: phones, emails: emails, organization: nil)
    }

    static func geo(_ body: String) -> ScanPayload? {
        let coords = body.split(separator: "?")[0].split(separator: ";")[0].split(separator: ",")
        guard coords.count >= 2, let lat = Double(coords[0]), let lon = Double(coords[1]), abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return .geo(latitude: lat, longitude: lon)
    }

    static func mail(_ body: String) -> ScanPayload {
        let parts = body.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var subject: String?
        if parts.count > 1 {
            subject = parts[1].split(separator: "&").compactMap { p -> String? in
                let kv = p.split(separator: "=", maxSplits: 1); return kv.count == 2 && kv[0].lowercased() == "subject" ? String(kv[1]).removingPercentEncoding : nil
            }.first
        }
        return .email(address: String(parts[0]), subject: subject)
    }

    static func otp(_ text: String) -> ScanPayload? {
        guard let c = URLComponents(string: text), let kind = c.host else { return nil }
        let label = String(c.path.dropFirst()).removingPercentEncoding ?? ""
        return .otp(label: label, issuer: c.queryItems?.first { $0.name == "issuer" }?.value, kind: kind.uppercased())
    }
}

/// Detecta destellos de luz infrarroja de un mando a distancia en el video de la camara: el sensor los ve como un
/// aumento breve de brillo (violeta/blanco). No decodifica la señal (el porte de 38 kHz es mucho mas rapido que la
/// camara): solo dice si el mando emite y cuantos destellos manda.
public struct IRPulseDetector: Sendable {
    public struct Burst: Sendable, Equatable { public var start: Double; public var duration: Double }

    public private(set) var bursts: [Burst] = []
    public private(set) var isLit = false
    public private(set) var threshold = 0.0

    private var window: [Double] = []
    private var burstStart: Double?
    public var windowSize = 45           // ~ 0.75 s a 60 fps
    public var minJump = 0.06            // subida minima de brillo para contar como destello
    public var sensitivity = 4.0         // desviaciones (MAD) por encima del fondo

    public init() {}

    /// una lectura de brillo medio (0...1) en el instante `t` (segundos). devuelve true si en este instante hay un destello.
    @discardableResult
    public mutating func feed(brightness: Double, at t: Double) -> Bool {
        window.append(brightness)
        if window.count > windowSize { window.removeFirst() }
        guard window.count >= 8 else { return false }
        let sorted = window.sorted()
        let median = sorted[sorted.count / 2]
        let mad = sorted.map { abs($0 - median) }.sorted()[sorted.count / 2]
        threshold = median + max(minJump, sensitivity * mad * 1.4826)
        let lit = brightness > threshold
        if lit && !isLit { burstStart = t }
        if !lit && isLit, let s = burstStart { bursts.append(Burst(start: s, duration: t - s)); burstStart = nil }
        isLit = lit
        return lit
    }

    /// hay actividad si hubo al menos `count` destellos en los ultimos `seconds`.
    public func isActive(now: Double, within seconds: Double = 1.0, count: Int = 1) -> Bool {
        bursts.filter { now - ($0.start + $0.duration) <= seconds }.count >= count || (isLit && burstStart.map { now - $0 < seconds } ?? false)
    }

    public mutating func reset() { self = IRPulseDetector() }
}
