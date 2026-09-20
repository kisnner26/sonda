import XCTest
@testable import SondaCore

final class ToolsTests: XCTestCase {
    func testHexDumpMatchesTheClassicFormat() {
        let lines = Hex.dump(Data("Hello, hexdump!\n\u{01}".utf8))
        XCTAssertEqual(lines[0], "00000000  48 65 6c 6c 6f 2c 20 68 65 78 64 75 6d 70 21 0a  |Hello, hexdump!.|")
        XCTAssertEqual(lines[1], "00000010  01                                               |.|")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(Hex.dump(Data([0x41, 0x42]), columns: 4, startOffset: 0x100), ["00000100  41 42        |AB|"])
        XCTAssertEqual(Hex.dump(Data()), [])
        XCTAssertTrue(Hex.dump(Data([0x7f, 0x20, 0x1f, 0x7e]))[0].hasSuffix("|. .~|"), "solo son imprimibles 0x20...0x7e")
    }

    func testHexParsing() throws {
        XCTAssertEqual(try Hex.parse("de ad BE-EF"), Data([0xde, 0xad, 0xbe, 0xef]))
        XCTAssertEqual(try Hex.parse("0x01, 0x02:0x03_04"), Data([1, 2, 3, 4]))
        XCTAssertEqual(try Hex.parse(""), Data())
        XCTAssertEqual(try Hex.parse("A\nB"), Data([0xAB]), "el salto de linea es un separador y A B se juntan")
        XCTAssertThrowsError(try Hex.parse("abc")) { XCTAssertEqual($0 as? Hex.Failure, .oddLength) }
        XCTAssertThrowsError(try Hex.parse("zz")) { XCTAssertEqual($0 as? Hex.Failure, .notHex) }
    }

    func testHashesAgainstKnownVectors() {
        let abc = Data("abc".utf8)
        XCTAssertEqual(Hashing.hex(abc, .md5), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(Hashing.hex(abc, .sha1), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(Hashing.hex(abc, .sha256), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(Hashing.hex(abc, .sha384), "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")
        XCTAssertTrue(Hashing.hex(abc, .sha512).hasPrefix("ddaf35a193617aba"))
        XCTAssertEqual(Hashing.hex(Data(), .md5), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(Hashing.hex(Data("123456789".utf8), .crc32), "cbf43926")
        XCTAssertEqual(Hashing.hex(Data(), .crc32), "00000000")
        XCTAssertEqual(Hashing.Algorithm.allCases.count, 6)
    }

    func testConversionsRoundTripAndFail() throws {
        let data = Data("¡Hola, ñandú!".utf8)
        for f in Convert.Format.allCases {
            XCTAssertEqual(try Convert.bytes(from: Convert.string(from: data, format: f), format: f), data, f.rawValue)
        }
        XCTAssertEqual(Convert.string(from: Data("Man".utf8), format: .base64), "TWFu")
        XCTAssertEqual(Convert.string(from: Data([5]), format: .binary), "00000101")
        XCTAssertEqual(Convert.string(from: Data("a b&c".utf8), format: .url), "a%20b%26c")
        XCTAssertEqual(Convert.string(from: Data([1, 255]), format: .decimal), "1 255")
        XCTAssertEqual(try Convert.bytes(from: "TWE", format: .base64), Data("Ma".utf8), "base64 sin relleno")
        XCTAssertEqual(try Convert.bytes(from: "a-_b", format: .base64), try Convert.bytes(from: "a+/b", format: .base64), "variante URL-safe")
        for (text, f) in [("!!", Convert.Format.base64), ("0101", .binary), ("012", .binary), ("", .binary), ("256", .decimal), ("a", .decimal), ("%zz", .url), ("", .decimal)] {
            XCTAssertThrowsError(try Convert.bytes(from: text, format: f), "\(text) como \(f.rawValue)")
        }
    }

    func testPasswordGeneration() throws {
        var g = SystemRandomNumberGenerator()
        var spec = PasswordSpec()
        let p = try Password.generate(spec, using: &g)
        XCTAssertEqual(p.count, 16)
        XCTAssertTrue(p.contains { $0.isLowercase } && p.contains { $0.isUppercase } && p.contains { $0.isNumber } && p.contains { "!@#$%^&*-_=+?.:;".contains($0) })
        XCTAssertFalse(p.contains { "O0oIl1|".contains($0) }, "sin caracteres ambiguos")
        spec.symbols = false; spec.avoidAmbiguous = false; spec.length = 200
        let long = try Password.generate(spec, using: &g)
        XCTAssertEqual(long.count, 200); XCTAssertFalse(long.contains { !$0.isLetter && !$0.isNumber })
        spec.lower = false; spec.upper = false; spec.digits = false
        XCTAssertThrowsError(try Password.generate(spec, using: &g)) { XCTAssertEqual($0 as? Password.Failure, .noCharacters) }
        spec = PasswordSpec(); spec.length = 3
        XCTAssertThrowsError(try Password.generate(spec, using: &g)) { XCTAssertEqual($0 as? Password.Failure, .tooShort) }
    }

    func testPasswordEntropyAndDeterminism() throws {
        var spec = PasswordSpec()
        spec.lower = false; spec.upper = false; spec.symbols = false; spec.avoidAmbiguous = false; spec.length = 10
        XCTAssertEqual(spec.entropyBits, 10 * log2(10), accuracy: 1e-9)
        spec.digits = false
        XCTAssertEqual(spec.entropyBits, 0)
        struct Counter: RandomNumberGenerator { var n: UInt64 = 1; mutating func next() -> UInt64 { n = n &* 6364136223846793005 &+ 1442695040888963407; return n } }
        var a = Counter(), b = Counter()
        XCTAssertEqual(try Password.generate(PasswordSpec(), using: &a), try Password.generate(PasswordSpec(), using: &b))
    }
}
