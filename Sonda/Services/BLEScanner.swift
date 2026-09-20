import CoreBluetooth
import Foundation
import Observation
import SondaCore

struct BLEDevice: Identifiable, Equatable {
    let id: UUID
    var name: String?
    var rssi: Int
    var smoothed: Double
    var history: [Int]
    var firstSeen: Date
    var lastSeen: Date
    var advertisements = 1
    var advert: Advert
    var info: AdvertInfo

    /// nombre para mostrar: el anunciado, o lo que se sabe del tipo.
    var title: String { name ?? info.kind ?? info.vendor ?? "dispositivo sin nombre" }
    var distance: Double? { Bluetooth.distance(rssi: Int(smoothed.rounded()), txPower: advert.txPower ?? -59) }
}

struct GattCharacteristic: Identifiable {
    let id: String
    let uuid: String
    let properties: CharacteristicProperties
    var value: Data?
    var notifying = false
    let peripheralCharacteristic: CBCharacteristic
}

struct GattService: Identifiable {
    let id: String
    let uuid: String
    var characteristics: [GattCharacteristic] = []
}

/// escaner de dispositivos BLE y explorador GATT. Solo en primer plano: iOS no deja escanear sin abrir la app con los anuncios completos.
@MainActor
@Observable
final class BLEScanner: NSObject {
    static let shared = BLEScanner()

    private(set) var state: CBManagerState = .unknown
    private(set) var isScanning = false
    private(set) var devices: [UUID: BLEDevice] = [:]

    // explorador GATT
    private(set) var connectedID: UUID?
    private(set) var connecting = false
    private(set) var gattServices: [GattService] = []
    private(set) var gattError: String?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var pending: [UUID: BLEDevice] = [:]
    @ObservationIgnored private var flushTimer: Timer?

    var sorted: [BLEDevice] { devices.values.sorted { $0.smoothed > $1.smoothed } }
    var trackers: [BLEDevice] { sorted.filter { $0.info.tracker != nil } }

    func start() {
        if central == nil { central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: true]) }
        guard central?.state == .poweredOn else { return }
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.flush() } }
    }

    func stop() {
        central?.stopScan()
        isScanning = false
        flushTimer?.invalidate()
        flush()
    }

    func clear() { devices = [:]; pending = [:] }

    /// vuelca a la interfaz lo acumulado: a 60 lecturas por segundo redibujar cada una seria inutil.
    private func flush() {
        guard !pending.isEmpty else { return }
        for (id, d) in pending { devices[id] = d }
        pending = [:]
        // los dispositivos que llevan un rato sin dar señal se quitan de la lista
        let limit = Date().addingTimeInterval(-60)
        devices = devices.filter { $0.value.lastSeen > limit }
    }

    private func record(_ peripheral: CBPeripheral, _ data: [String: Any], _ rssi: Int) {
        guard rssi < 0 else { return }       // 127 = sin lectura
        let id = peripheral.identifier
        peripherals[id] = peripheral
        var ad = Advert()
        ad.localName = data[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        ad.manufacturerData = data[CBAdvertisementDataManufacturerDataKey] as? Data
        ad.serviceUUIDs = (data[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        if let sd = data[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] { ad.serviceData = Dictionary(uniqueKeysWithValues: sd.map { ($0.key.uuidString, $0.value) }) }
        ad.txPower = (data[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        ad.connectable = (data[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue

        var d = pending[id] ?? devices[id] ?? BLEDevice(id: id, name: nil, rssi: rssi, smoothed: Double(rssi), history: [], firstSeen: Date(), lastSeen: Date(), advert: ad, info: Bluetooth.analyze(ad))
        // un anuncio a veces trae solo parte de los datos: se conserva lo que ya se sabia
        if ad.manufacturerData == nil { ad.manufacturerData = d.advert.manufacturerData }
        if ad.serviceUUIDs.isEmpty { ad.serviceUUIDs = d.advert.serviceUUIDs }
        if ad.localName == nil { ad.localName = d.advert.localName }
        d.advert = ad
        d.info = Bluetooth.analyze(ad)
        d.name = ad.localName
        d.rssi = rssi
        d.smoothed += (Double(rssi) - d.smoothed) * 0.25
        d.history.append(rssi); if d.history.count > 90 { d.history.removeFirst() }
        d.lastSeen = Date()
        d.advertisements += 1
        pending[id] = d
    }

    // MARK: GATT

    func connect(_ id: UUID) {
        guard let p = peripherals[id], let central else { return }
        gattServices = []; gattError = nil; connecting = true; connectedID = nil
        p.delegate = self
        central.connect(p, options: nil)
    }

    func disconnect() {
        if let id = connectedID ?? (connecting ? peripherals.keys.first { peripherals[$0]?.state == .connecting } : nil), let p = peripherals[id] { central?.cancelPeripheralConnection(p) }
        connectedID = nil; connecting = false
    }

    func read(_ c: GattCharacteristic) { peripheral(for: c)?.readValue(for: c.peripheralCharacteristic) }

    func setNotify(_ c: GattCharacteristic, _ on: Bool) { peripheral(for: c)?.setNotifyValue(on, for: c.peripheralCharacteristic) }

    func write(_ c: GattCharacteristic, data: Data) {
        let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral(for: c)?.writeValue(data, for: c.peripheralCharacteristic, type: type)
    }

    private func peripheral(for c: GattCharacteristic) -> CBPeripheral? { c.peripheralCharacteristic.service?.peripheral }

    fileprivate func update(_ characteristic: CBCharacteristic, _ mutate: (inout GattCharacteristic) -> Void) {
        for s in gattServices.indices {
            if let c = gattServices[s].characteristics.firstIndex(where: { $0.peripheralCharacteristic === characteristic }) {
                mutate(&gattServices[s].characteristics[c])
            }
        }
    }
}

extension BLEScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            state = central.state
            if central.state != .poweredOn { isScanning = false }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated { record(peripheral, advertisementData, RSSI.intValue) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            connecting = false; connectedID = peripheral.identifier
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { connecting = false; gattError = error?.localizedDescription ?? "no se pudo conectar" }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            if connectedID == peripheral.identifier { connectedID = nil }
            connecting = false
            if let error { gattError = error.localizedDescription }
        }
    }
}

extension BLEScanner: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            if let error { gattError = error.localizedDescription; return }
            gattServices = (peripheral.services ?? []).map { GattService(id: $0.uuid.uuidString, uuid: $0.uuid.uuidString) }
            for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard let i = gattServices.firstIndex(where: { $0.uuid == service.uuid.uuidString }) else { return }
            gattServices[i].characteristics = (service.characteristics ?? []).map {
                GattCharacteristic(id: "\(service.uuid.uuidString)/\($0.uuid.uuidString)", uuid: $0.uuid.uuidString,
                                   properties: CharacteristicProperties(rawValue: $0.properties.rawValue), value: $0.value, notifying: $0.isNotifying, peripheralCharacteristic: $0)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if let error { gattError = error.localizedDescription; return }
            update(characteristic) { $0.value = characteristic.value }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { update(characteristic) { $0.notifying = characteristic.isNotifying } }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { if let error { gattError = error.localizedDescription } }
    }
}
