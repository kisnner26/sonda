import Foundation
import CryptoKit

public enum Hex {
    /// volcado como el de `hexdump -C`: desplazamiento, bytes en hex y columna ASCII.
    public static func dump(_ data: Data, columns: Int = 16, startOffset: Int = 0) -> [String] {
        precondition(columns > 0)
        let bytes = Array(data)
        return stride(from: 0, to: bytes.count, by: columns).map { row in
            let chunk = bytes[row..<min(row + columns, bytes.count)]
            let hex = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
            let padded = hex.padding(toLength: columns * 3 - 1, withPad: " ", startingAt: 0)
            let ascii = String(chunk.map { $0 >= 0x20 && $0 < 0x7f ? Character(UnicodeScalar($0)) : "." })
            return String(format: "%08x  ", startOffset + row) + padded + "  |" + ascii + "|"
        }
    }

    /// "de ad BE-EF 0x12" -> bytes. Acepta separadores comunes y "0x"; lanza si sobra un medio byte o hay algo que no es hex.
    public static func parse(_ text: String) throws -> Data {
        var clean = text.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        clean.removeAll { " \n\t\r:-,_".contains($0) }
        guard clean.count % 2 == 0 else { throw Failure.oddLength }
        guard clean.allSatisfy(\.isHexDigit) else { throw Failure.notHex }
        var out = Data()
        var i = clean.startIndex
        while i < clean.endIndex {
            let j = clean.index(i, offsetBy: 2)
            out.append(UInt8(clean[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    public enum Failure: Error, Equatable { case oddLength, notHex }
}

public enum Hashing {
    public enum Algorithm: String, CaseIterable, Sendable { case md5 = "MD5", sha1 = "SHA-1", sha256 = "SHA-256", sha384 = "SHA-384", sha512 = "SHA-512", crc32 = "CRC-32" }

    public static func hex(_ data: Data, _ algorithm: Algorithm) -> String {
        func h<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 { digest.map { String(format: "%02x", $0) }.joined() }
        switch algorithm {
        case .md5: return h(Insecure.MD5.hash(data: data))
        case .sha1: return h(Insecure.SHA1.hash(data: data))
        case .sha256: return h(SHA256.hash(data: data))
        case .sha384: return h(SHA384.hash(data: data))
        case .sha512: return h(SHA512.hash(data: data))
        case .crc32: return String(format: "%08x", crc32(data))
        }
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xffff_ffff
        for b in data {
            c ^= UInt32(b)
            for _ in 0..<8 { c = c & 1 != 0 ? (c >> 1) ^ 0xedb8_8320 : c >> 1 }
        }
        return ~c
    }
}

public enum Convert {
    public enum Format: String, CaseIterable, Sendable { case text = "Texto", hex = "Hex", base64 = "Base64", binary = "Binario", url = "URL", decimal = "Decimal" }

    public static func bytes(from text: String, format: Format) throws -> Data {
        switch format {
        case .text: return Data(text.utf8)
        case .hex: return try Hex.parse(text)
        case .base64:
            let clean = text.filter { !$0.isWhitespace }.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            let padded = clean + String(repeating: "=", count: (4 - clean.count % 4) % 4)
            guard let d = Data(base64Encoded: padded) else { throw Failure.invalid }
            return d
        case .binary:
            let bits = text.filter { !$0.isWhitespace }
            guard !bits.isEmpty, bits.count % 8 == 0, bits.allSatisfy({ $0 == "0" || $0 == "1" }) else { throw Failure.invalid }
            return Data(stride(from: 0, to: bits.count, by: 8).map { i in
                let s = bits.index(bits.startIndex, offsetBy: i)
                return UInt8(bits[s..<bits.index(s, offsetBy: 8)], radix: 2)!
            })
        case .url:
            guard let s = text.removingPercentEncoding else { throw Failure.invalid }
            return Data(s.utf8)
        case .decimal:
            let parts = text.split(whereSeparator: { $0 == " " || $0 == "," }).map { UInt8($0) }
            guard !parts.isEmpty, !parts.contains(nil) else { throw Failure.invalid }
            return Data(parts.compactMap { $0 })
        }
    }

    public static func string(from data: Data, format: Format) -> String {
        switch format {
        case .text: return String(decoding: data, as: UTF8.self)
        case .hex: return data.map { String(format: "%02x", $0) }.joined(separator: " ")
        case .base64: return data.base64EncodedString()
        case .binary: return data.map { s in String(repeating: "0", count: 8 - String(s, radix: 2).count) + String(s, radix: 2) }.joined(separator: " ")
        case .url: return String(decoding: data, as: UTF8.self).addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
        case .decimal: return data.map(String.init).joined(separator: " ")
        }
    }

    public enum Failure: Error, Equatable { case invalid }
}

public struct PasswordSpec: Sendable, Equatable {
    public var length = 16
    public var lower = true, upper = true, digits = true, symbols = true
    public var avoidAmbiguous = true
    public init() {}

    var alphabets: [[Character]] {
        let ambiguous = Set("O0oIl1|")
        func f(_ s: String) -> [Character] { s.filter { !avoidAmbiguous || !ambiguous.contains($0) }.map { $0 } }
        return [lower ? f("abcdefghijklmnopqrstuvwxyz") : [], upper ? f("ABCDEFGHIJKLMNOPQRSTUVWXYZ") : [],
                digits ? f("0123456789") : [], symbols ? f("!@#$%^&*-_=+?.:;") : []].filter { !$0.isEmpty }
    }

    /// bits de entropia de una contraseña generada con este esquema (uniforme sobre el alfabeto conjunto).
    public var entropyBits: Double {
        let size = alphabets.flatMap { $0 }.count
        return size > 1 ? Double(length) * log2(Double(size)) : 0
    }
}

public enum Password {
    public enum Failure: Error, Equatable { case noCharacters, tooShort }

    /// una contraseña con al menos un caracter de cada grupo elegido.
    public static func generate<G: RandomNumberGenerator>(_ spec: PasswordSpec, using g: inout G) throws -> String {
        let groups = spec.alphabets
        guard !groups.isEmpty else { throw Failure.noCharacters }
        guard spec.length >= groups.count else { throw Failure.tooShort }
        let all = groups.flatMap { $0 }
        var chars = groups.map { $0.randomElement(using: &g)! }
        while chars.count < spec.length { chars.append(all.randomElement(using: &g)!) }
        chars.shuffle(using: &g)
        return String(chars)
    }
}
