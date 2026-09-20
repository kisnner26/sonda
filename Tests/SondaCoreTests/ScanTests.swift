import XCTest
@testable import SondaCore

final class ScanTests: XCTestCase {
    func testWifiPayload() {
        XCTAssertEqual(ScanParser.parse("WIFI:T:WPA;S:Mi Red;P:secreto;;"), .wifi(ssid: "Mi Red", password: "secreto", security: "WPA", hidden: false))
        XCTAssertEqual(ScanParser.parse("WIFI:S:abierta;T:nopass;;"), .wifi(ssid: "abierta", password: nil, security: "sin cifrar", hidden: false))
        XCTAssertEqual(ScanParser.parse("WIFI:T:WPA;S:a\\;b\\:c;P:p\\\\q;H:true;;"), .wifi(ssid: "a;b:c", password: "p\\q", security: "WPA", hidden: true), "escapes")
        XCTAssertEqual(ScanParser.parse("wifi:T:wep;S:x;P:;;"), .wifi(ssid: "x", password: nil, security: "WEP", hidden: false), "prefijo en minusculas y clave vacia")
        XCTAssertEqual(ScanParser.parse("WIFI:T:WPA;P:sinssid;;"), .text("WIFI:T:WPA;P:sinssid;;"), "sin SSID no es una red")
    }

    func testURLsAndTheirWarnings() throws {
        XCTAssertEqual(ScanParser.parse("https://example.com/a?b=1"), .url(try XCTUnwrap(URL(string: "https://example.com/a?b=1")), warning: nil))
        guard case .url(_, let http) = ScanParser.parse("http://example.com") else { return XCTFail() }
        XCTAssertEqual(http, "conexión sin cifrar (http)")
        guard case .url(_, let ip) = ScanParser.parse("https://192.168.0.1/admin") else { return XCTFail() }
        XCTAssertEqual(ip, "dirección IP en vez de un nombre de dominio")
        guard case .url(_, let puny) = ScanParser.parse("https://xn--pple-43d.com") else { return XCTFail() }
        XCTAssertTrue(puny?.contains("punycode") == true)
        guard case .url(_, let user) = ScanParser.parse("https://paypal.com@evil.example/login") else { return XCTFail() }
        XCTAssertTrue(user?.contains("evil.example") == true, "el dominio real es lo que va tras la @")
        XCTAssertEqual(ScanParser.parse("  https://x.org  "), .url(try XCTUnwrap(URL(string: "https://x.org")), warning: nil), "recorta espacios")
        XCTAssertEqual(ScanParser.parse("https://"), .text("https://"))
    }

    func testContacts() {
        let v = "BEGIN:VCARD\nVERSION:3.0\nN:Obando;Kisnner;;;\nFN:Kisnner Obando\nORG:UAM;Sistemas\nTEL;TYPE=CELL:+50589271455\nEMAIL:k@example.com\nEND:VCARD"
        XCTAssertEqual(ScanParser.parse(v), .contact(name: "Kisnner Obando", phones: ["+50589271455"], emails: ["k@example.com"], organization: "UAM Sistemas"))
        XCTAssertEqual(ScanParser.parse("BEGIN:VCARD\nN:Perez;Ana\nEND:VCARD"), .contact(name: "Ana Perez", phones: [], emails: [], organization: nil), "sin FN se arma con N")
        XCTAssertEqual(ScanParser.parse("MECARD:N:Perez,Ana;TEL:123;EMAIL:a@b.c;;"), .contact(name: "Ana Perez", phones: ["123"], emails: ["a@b.c"], organization: nil))
    }

    func testOtherSchemes() {
        XCTAssertEqual(ScanParser.parse("geo:12.13,-86.25"), .geo(latitude: 12.13, longitude: -86.25))
        XCTAssertEqual(ScanParser.parse("geo:12.13,-86.25?z=11"), .geo(latitude: 12.13, longitude: -86.25))
        XCTAssertEqual(ScanParser.parse("geo:95,0"), .text("geo:95,0"), "latitud fuera de rango")
        XCTAssertEqual(ScanParser.parse("mailto:a@b.co?subject=Hola%20mundo"), .email(address: "a@b.co", subject: "Hola mundo"))
        XCTAssertEqual(ScanParser.parse("mailto:a@b.co"), .email(address: "a@b.co", subject: nil))
        XCTAssertEqual(ScanParser.parse("tel:+505123"), .phone("+505123"))
        XCTAssertEqual(ScanParser.parse("SMSTO:123:hola"), .sms(number: "123", body: "hola"))
        XCTAssertEqual(ScanParser.parse("sms:123"), .sms(number: "123", body: nil))
        XCTAssertEqual(ScanParser.parse("otpauth://totp/GitHub:kisnner?secret=ABC&issuer=GitHub"), .otp(label: "GitHub:kisnner", issuer: "GitHub", kind: "TOTP"))
        XCTAssertEqual(ScanParser.parse("hola"), .text("hola")); XCTAssertEqual(ScanParser.parse(" espacios "), .text(" espacios "), "el texto llano se devuelve tal cual")
    }

    // ---- destellos infrarrojos
    private func series(length: Int, lit: [ClosedRange<Int>], base: Double = 0.2, jump: Double = 0.4, noise: Double = 0.005, fps: Double = 60) -> [(Double, Double)] {
        var g = SystemRandomNumberGenerator()
        return (0..<length).map { i in
            let on = lit.contains { $0.contains(i) }
            return (Double(i) / fps, base + (on ? jump : 0) + Double.random(in: -noise...noise, using: &g))
        }
    }

    func testDetectsBurstsOfLight() {
        var d = IRPulseDetector()
        for (t, b) in series(length: 240, lit: [60...63, 100...101, 150...154]) { d.feed(brightness: b, at: t) }
        XCTAssertEqual(d.bursts.count, 3)
        XCTAssertEqual(d.bursts[0].start, 60.0 / 60, accuracy: 0.02); XCTAssertEqual(d.bursts[0].duration, 4.0 / 60, accuracy: 0.02)
        XCTAssertEqual(d.bursts[1].duration, 2.0 / 60, accuracy: 0.02)
        XCTAssertTrue(d.isActive(now: 155.0 / 60)); XCTAssertFalse(d.isActive(now: 240.0 / 60 + 5))
    }

    func testNoiseAndSlowLightChangesAreNotBursts() {
        var d = IRPulseDetector()
        for (t, b) in series(length: 300, lit: [], noise: 0.01) { d.feed(brightness: b, at: t) }
        XCTAssertEqual(d.bursts.count, 0)
        var slow = IRPulseDetector()
        for i in 0..<400 { slow.feed(brightness: 0.2 + Double(i) * 0.0008, at: Double(i) / 60) }   // luz que sube despacio (pasa una nube)
        XCTAssertEqual(slow.bursts.count, 0)
    }

    func testTooSmallAJumpIsIgnoredAndItAdaptsToTheBackground() {
        var d = IRPulseDetector()
        for (t, b) in series(length: 200, lit: [80...85], jump: 0.02) { d.feed(brightness: b, at: t) }
        XCTAssertEqual(d.bursts.count, 0)
        var dark = IRPulseDetector()
        for (t, b) in series(length: 200, lit: [80...84], base: 0.02, jump: 0.3) { dark.feed(brightness: b, at: t) }
        XCTAssertEqual(dark.bursts.count, 1, "tambien de noche, con fondo casi negro")
    }

    func testResetForgetsEverythingAndNeedsAWarmUp() {
        var d = IRPulseDetector()
        XCTAssertFalse(d.feed(brightness: 0.9, at: 0), "sin lecturas previas no hay fondo con que comparar")
        for (t, b) in series(length: 120, lit: [60...62]) { d.feed(brightness: b, at: t) }
        XCTAssertEqual(d.bursts.count, 1)
        d.reset(); XCTAssertEqual(d.bursts.count, 0); XCTAssertFalse(d.isLit)
    }
}
