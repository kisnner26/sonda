import XCTest
@testable import SondaCore

final class BluetoothTests: XCTestCase {
    private func mfg(_ company: UInt16, _ rest: [UInt8]) -> Data { Data([UInt8(company & 0xff), UInt8(company >> 8)] + rest) }

    func testCompanyLookup() {
        XCTAssertEqual(Bluetooth.companyName(0x004C), "Apple")
        XCTAssertEqual(Bluetooth.companyName(0x0075), "Samsung")
        XCTAssertNil(Bluetooth.companyName(0xFFFE))
        XCTAssertEqual(Bluetooth.companyID(Data([0x4C, 0x00, 0x99])), 0x004C)
        XCTAssertEqual(Bluetooth.companyID(Data([0x59, 0x00])), 0x0059, "little-endian")
        XCTAssertNil(Bluetooth.companyID(Data([0x4C])))
    }

    func testUnknownCompanyShowsTheNumber() {
        let info = Bluetooth.analyze(Advert(manufacturerData: mfg(0x1234, [1, 2])))
        XCTAssertEqual(info.vendor, "empresa 0x1234")
        XCTAssertNil(info.kind)
    }

    func testIBeacon() throws {
        let uuid = (0..<16).map { UInt8($0 + 1) }
        let block: [UInt8] = [0x02, 0x15] + uuid + [0x01, 0x02, 0x03, 0x04, 0xC5]     // major 258, minor 772, tx -59
        let info = Bluetooth.analyze(Advert(manufacturerData: mfg(0x004C, block)))
        XCTAssertEqual(info.kind, "iBeacon")
        let b = try XCTUnwrap(info.beacon)
        XCTAssertEqual(b.uuid, "01020304-0506-0708-090A-0B0C0D0E0F10")
        XCTAssertEqual(b.major, 258); XCTAssertEqual(b.minor, 772); XCTAssertEqual(b.txPower, -59)
        XCTAssertEqual(info.vendor, "Apple")
    }

    func testFindMyIsFlaggedAsATracker() {
        let payload = [UInt8](repeating: 0x11, count: 25)
        let info = Bluetooth.analyze(Advert(manufacturerData: mfg(0x004C, [0x12, 0x19] + payload)))
        XCTAssertEqual(info.tracker, .findMy)
        XCTAssertEqual(info.appleTypes, [0x12])
        XCTAssertEqual(info.kind, "Find My (AirTag u otro accesorio)")
    }

    func testOtherAppleBlocksAndSeveralBlocksInOneAdvert() {
        let info = Bluetooth.analyze(Advert(manufacturerData: mfg(0x004C, [0x10, 0x02, 0xAA, 0xBB, 0x0C, 0x01, 0x00])))
        XCTAssertEqual(info.appleTypes, [0x10, 0x0C])
        XCTAssertEqual(info.kind, "Nearby Info")
        XCTAssertNil(info.tracker)
        XCTAssertEqual(Bluetooth.analyze(Advert(manufacturerData: mfg(0x004C, [0x07, 0x02, 0, 0]))).kind, "AirPods / Beats")
    }

    func testTruncatedAppleBlockIsIgnoredNotACrash() {
        let info = Bluetooth.analyze(Advert(manufacturerData: mfg(0x004C, [0x10, 0x09, 0x01])))
        XCTAssertEqual(info.appleTypes, [])
        XCTAssertEqual(Bluetooth.analyze(Advert(manufacturerData: mfg(0x004C, []))).appleTypes, [])
    }

    func testServiceBasedTrackersAndFastPair() {
        XCTAssertEqual(Bluetooth.analyze(Advert(serviceUUIDs: ["FEED"])).tracker, .tile)
        XCTAssertEqual(Bluetooth.analyze(Advert(serviceUUIDs: ["feec"])).tracker, .tile, "sin importar mayusculas")
        XCTAssertEqual(Bluetooth.analyze(Advert(serviceUUIDs: ["FD5A"])).tracker, .smartTag)
        XCTAssertEqual(Bluetooth.analyze(Advert(serviceUUIDs: ["FE2C"])).kind, "Google Fast Pair")
        XCTAssertNil(Bluetooth.analyze(Advert(serviceUUIDs: ["180F"])).tracker)
    }

    func testEddystoneFrames() {
        func frame(_ b: UInt8) -> AdvertInfo { Bluetooth.analyze(Advert(serviceData: ["FEAA": Data([b, 0, 0])])) }
        XCTAssertEqual(frame(0x00).eddystone, "UID"); XCTAssertEqual(frame(0x10).eddystone, "URL")
        XCTAssertEqual(frame(0x20).eddystone, "TLM"); XCTAssertEqual(frame(0x30).eddystone, "EID")
        XCTAssertEqual(frame(0x40).eddystone, "desconocido")
        XCTAssertEqual(frame(0x00).kind, "Eddystone")
    }

    func testDistanceModel() throws {
        XCTAssertEqual(try XCTUnwrap(Bluetooth.distance(rssi: -59)), 1.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Bluetooth.distance(rssi: -79)), 10.0, accuracy: 1e-9)      // 20 dB mas = 10x con n = 2
        XCTAssertEqual(try XCTUnwrap(Bluetooth.distance(rssi: -69, txPower: -69)), 1.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Bluetooth.distance(rssi: -79, pathLoss: 3)), pow(10, 20.0 / 30), accuracy: 1e-9)
        XCTAssertNil(Bluetooth.distance(rssi: 0)); XCTAssertNil(Bluetooth.distance(rssi: -127))
    }

    func testProximityBuckets() {
        XCTAssertEqual(Bluetooth.proximity(rssi: -50), .immediate)
        XCTAssertEqual(Bluetooth.proximity(rssi: -60), .near)
        XCTAssertEqual(Bluetooth.proximity(rssi: -70), .near)
        XCTAssertEqual(Bluetooth.proximity(rssi: -90), .far)
        XCTAssertEqual(Bluetooth.proximity(rssi: 12), .unknown)
    }
}

final class GattTests: XCTestCase {
    func testShortUUIDs() {
        XCTAssertEqual(Gatt.short("0000180f-0000-1000-8000-00805f9b34fb"), "180F")
        XCTAssertEqual(Gatt.short("180f"), "180F")
        XCTAssertEqual(Gatt.short("6E400001-B5A3-F393-E0A9-E50E24DCCA9E"), "6E400001-B5A3-F393-E0A9-E50E24DCCA9E", "uuid propio: se deja")
        XCTAssertEqual(Gatt.short("0001180F-0000-1000-8000-00805F9B34FB"), "0001180F-0000-1000-8000-00805F9B34FB", "solo la base 0000xxxx")
    }

    func testStandardNames() {
        XCTAssertEqual(Gatt.serviceName("180A"), "Device Information"); XCTAssertEqual(Gatt.serviceName("0000180f-0000-1000-8000-00805f9b34fb"), "Battery")
        XCTAssertNil(Gatt.serviceName("FFE0")); XCTAssertEqual(Gatt.characteristicName("2a19"), "Battery Level")
        XCTAssertEqual(Set(Gatt.services.keys).intersection(Gatt.characteristics.keys), [], "un id no es servicio y caracteristica a la vez")
    }

    func testValueDescriptions() {
        XCTAssertEqual(Gatt.describe(characteristic: "2A19", value: Data([87])), "87 %")
        XCTAssertNil(Gatt.describe(characteristic: "2A19", value: Data()))
        XCTAssertEqual(Gatt.describe(characteristic: "2A29", value: Data("Acme\0".utf8)), "Acme")
        XCTAssertEqual(Gatt.describe(characteristic: "2A37", value: Data([0x00, 72])), "72 lpm")
        XCTAssertEqual(Gatt.describe(characteristic: "2A37", value: Data([0x01, 0x2C, 0x01])), "300 lpm", "16 bits")
        XCTAssertNil(Gatt.describe(characteristic: "2A37", value: Data([0x01, 0x2C])), "16 bits pero solo un byte de dato")
        XCTAssertNil(Gatt.describe(characteristic: "FFF1", value: Data([1])))
    }

    func testPropertyNames() {
        let p: CharacteristicProperties = [.read, .notify, .write]
        XCTAssertEqual(p.names, ["leer", "escribir", "notificar"]); XCTAssertTrue(p.canWrite)
        XCTAssertFalse(CharacteristicProperties([.read]).canWrite); XCTAssertTrue(CharacteristicProperties([.writeWithoutResponse]).canWrite)
        XCTAssertEqual(CharacteristicProperties(rawValue: 0x12).names, ["leer", "notificar"])
    }
}
