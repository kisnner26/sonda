import XCTest
@testable import SondaCore

final class NetworkTests: XCTestCase {
    func testIPv4ParsingAndFormatting() throws {
        XCTAssertEqual(IPv4("192.168.1.20")?.description, "192.168.1.20")
        XCTAssertEqual(IPv4("0.0.0.0")?.value, 0); XCTAssertEqual(IPv4("255.255.255.255")?.value, UInt32.max)
        for bad in ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "a.b.c.d", "1..2.3", "1.2.3.-4", "1.2.3.4444", " "] { XCTAssertNil(IPv4(bad), bad) }
        XCTAssertEqual(IPv4(" 10.0.0.1 ")?.description, "10.0.0.1", "tolera espacios alrededor")
        XCTAssertTrue(try XCTUnwrap(IPv4("10.1.2.3")).isPrivate); XCTAssertTrue(try XCTUnwrap(IPv4("172.16.0.1")).isPrivate)
        XCTAssertTrue(try XCTUnwrap(IPv4("172.31.255.255")).isPrivate); XCTAssertFalse(try XCTUnwrap(IPv4("172.32.0.1")).isPrivate)
        XCTAssertTrue(try XCTUnwrap(IPv4("192.168.0.1")).isPrivate); XCTAssertFalse(try XCTUnwrap(IPv4("8.8.8.8")).isPrivate)
        XCTAssertLessThan(try XCTUnwrap(IPv4("1.2.3.4")), try XCTUnwrap(IPv4("1.2.3.5")))
    }

    func testSubnetFromCIDRAndNetmask() throws {
        let s = try XCTUnwrap(Subnet(cidr: "192.168.1.77/24"))
        XCTAssertEqual(s.network.description, "192.168.1.0"); XCTAssertEqual(s.broadcast.description, "192.168.1.255")
        XCTAssertEqual(s.hostCount, 254); XCTAssertEqual(s.prefix, 24)
        XCTAssertEqual(try XCTUnwrap(Subnet(address: try XCTUnwrap(IPv4("10.0.5.9")), netmask: try XCTUnwrap(IPv4("255.255.252.0")))).prefix, 22)
        XCTAssertNil(Subnet(address: IPv4(1), netmask: IPv4(0xFF00FF00)), "mascara no contigua")
        XCTAssertNil(Subnet(cidr: "1.2.3.4/33")); XCTAssertNil(Subnet(cidr: "1.2.3.4")); XCTAssertNil(Subnet(cidr: "x/24"))
    }

    func testHostsExcludeNetworkAndBroadcastAndRespectTheLimit() throws {
        let s = try XCTUnwrap(Subnet(cidr: "192.168.1.0/24"))
        let hosts = s.hosts()
        XCTAssertEqual(hosts.count, 254); XCTAssertEqual(hosts.first?.description, "192.168.1.1"); XCTAssertEqual(hosts.last?.description, "192.168.1.254")
        XCTAssertEqual(try XCTUnwrap(Subnet(cidr: "10.0.0.0/8")).hosts(limit: 500).count, 500)
        XCTAssertEqual(try XCTUnwrap(Subnet(cidr: "10.0.0.0/30")).hosts().map(\.description), ["10.0.0.1", "10.0.0.2"])
        XCTAssertEqual(try XCTUnwrap(Subnet(cidr: "10.0.0.4/31")).hosts().count, 2)
        XCTAssertEqual(try XCTUnwrap(Subnet(cidr: "10.0.0.4/32")).hosts().map(\.description), ["10.0.0.4"])
        XCTAssertEqual(try XCTUnwrap(Subnet(cidr: "10.0.0.0/8")).hostCount, 16_777_214)
        XCTAssertTrue(s.contains(try XCTUnwrap(IPv4("192.168.1.99")))); XCTAssertFalse(s.contains(try XCTUnwrap(IPv4("192.168.2.1"))))
        XCTAssertTrue(try XCTUnwrap(Subnet(cidr: "0.0.0.0/0")).contains(try XCTUnwrap(IPv4("8.8.8.8"))))
    }

    func testPortParsing() throws {
        XCTAssertEqual(try Ports.parse("22, 80,443"), [22, 80, 443])
        XCTAssertEqual(try Ports.parse("8000-8003"), [8000, 8001, 8002, 8003])
        XCTAssertEqual(try Ports.parse("80 80 79-81"), [80, 79, 81], "sin duplicados y en orden de aparicion")
        XCTAssertEqual(try Ports.parse("65535"), [65535])
        for bad in ["", "0", "65536", "abc", "10-5", "1-2-3", "-5", "80-"] { XCTAssertThrowsError(try Ports.parse(bad), bad) }
        XCTAssertThrowsError(try Ports.parse("1-5000")) { XCTAssertEqual($0 as? Ports.PortError, .tooMany(4096)) }
    }

    func testCommonPortNames() {
        XCTAssertEqual(Ports.name(22), "SSH"); XCTAssertEqual(Ports.name(443), "HTTPS"); XCTAssertNil(Ports.name(31337))
        XCTAssertEqual(Set(Ports.common.map(\.port)).count, Ports.common.count, "sin puertos repetidos")
    }

    func testIcmpChecksumWithARealVector() {
        // eco con id 1, secuencia 1 y sin datos: 0x0800 + 0x0001 + 0x0001 = 0x0802 -> complemento 0xF7FD
        XCTAssertEqual(Icmp.checksum([8, 0, 0, 0, 0, 1, 0, 1]), 0xF7FD)
        let empty = Icmp.echoRequest(id: 1, sequence: 1, payload: [])
        XCTAssertEqual([empty[2], empty[3]], [0xF7, 0xFD])
        let req = Icmp.echoRequest(id: 0xABCD, sequence: 1, payload: [0x61, 0x62, 0x63, 0x64])
        XCTAssertEqual(Icmp.checksum(req), 0, "un paquete con su suma bien puesta suma cero")
        XCTAssertEqual(req[0], 8); XCTAssertEqual(req[4], 0xAB); XCTAssertEqual(req[7], 1)
    }

    func testChecksumOddLengthAndCarry() {
        XCTAssertEqual(Icmp.checksum([]), 0xFFFF)
        XCTAssertEqual(Icmp.checksum([0xFF, 0xFF]), 0)
        XCTAssertEqual(Icmp.checksum([0x01]), ~0x0100 & 0xFFFF)
        XCTAssertEqual(Icmp.checksum([0xFF, 0xFF, 0x00, 0x01]), 0xFFFE, "el acarreo se vuelve a sumar")
        let odd = Icmp.echoRequest(id: 1, sequence: 2, payload: [1, 2, 3])
        XCTAssertEqual(Icmp.checksum(odd), 0)
    }

    func testReplyParsingWithAndWithoutIpHeader() {
        let echo: [UInt8] = [0, 0, 0, 0, 0x12, 0x34, 0x00, 0x07, 1, 2]
        XCTAssertEqual(Icmp.parse(echo), .echo(id: 0x1234, sequence: 7))
        let ip: [UInt8] = [0x45, 0, 0, 30, 0, 0, 0, 0, 64, 1, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2]
        XCTAssertEqual(Icmp.parse(ip + echo), .echo(id: 0x1234, sequence: 7))
        XCTAssertEqual(Icmp.parse(ip + [11, 0, 0, 0, 0, 0, 0, 0]), .timeExceeded)
        XCTAssertEqual(Icmp.parse([3, 1, 0, 0, 0, 0, 0, 0]), .unreachable)
        XCTAssertNil(Icmp.parse([8, 0, 0, 0, 0, 0, 0, 0]), "una peticion no es una respuesta")
        XCTAssertNil(Icmp.parse([0, 0, 0])); XCTAssertNil(Icmp.parse([]))
        XCTAssertNil(Icmp.parse([0x45, 0, 0, 0]), "cabecera IP sin nada detras")
    }

    func testPingStats() {
        var s = PingStats()
        XCTAssertNil(s.avg); XCTAssertNil(s.jitter); XCTAssertEqual(s.lossPercent, 0)
        s.sent = 4; s.times = [10, 20, 30]
        XCTAssertEqual(s.received, 3); XCTAssertEqual(s.lossPercent, 25); XCTAssertEqual(s.min, 10); XCTAssertEqual(s.max, 30)
        XCTAssertEqual(s.avg, 20); XCTAssertEqual(s.jitter, 10)
        s.times = [5]
        XCTAssertNil(s.jitter)
    }
}
