import CoreLocation
import CoreMotion
import Foundation
import Observation
import SondaCore

struct Vector3 { var x = 0.0, y = 0.0, z = 0.0 }

/// magnetometro (campo calibrado), gravedad y aceleracion en un solo flujo.
@MainActor
@Observable
final class MotionSensors {
    static let shared = MotionSensors()

    private(set) var field = Vector3()
    private(set) var fieldMagnitude = 0.0
    private(set) var fieldHistory: [Double] = []
    private(set) var accuracy = 0                 // CMMagneticFieldCalibrationAccuracy.rawValue; -1 = sin calibrar
    private(set) var gravity = Vector3(x: 0, y: 0, z: -1)
    private(set) var acceleration = 0.0           // g totales
    private(set) var peakG = 1.0
    private(set) var metalSignal = 0.0
    private(set) var running = false
    @ObservationIgnored private var detector = MetalDetector()
    @ObservationIgnored private let manager = CMMotionManager()

    var available: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !running else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] m, _ in
            guard let m else { return }
            MainActor.assumeIsolated { self?.ingest(m) }
        }
        running = true
    }

    func stop() { manager.stopDeviceMotionUpdates(); running = false }
    func resetDetector() { detector.reset(); peakG = 1 }

    private func ingest(_ m: CMDeviceMotion) {
        let f = m.magneticField.field
        field = Vector3(x: f.x, y: f.y, z: f.z)
        accuracy = Int(m.magneticField.accuracy.rawValue)
        fieldMagnitude = (f.x * f.x + f.y * f.y + f.z * f.z).squareRoot()
        fieldHistory.append(fieldMagnitude); if fieldHistory.count > 150 { fieldHistory.removeFirst() }
        metalSignal = detector.feed(microTesla: fieldMagnitude)
        gravity = Vector3(x: m.gravity.x, y: m.gravity.y, z: m.gravity.z)
        let a = m.userAcceleration
        acceleration = ((a.x + m.gravity.x) * (a.x + m.gravity.x) + (a.y + m.gravity.y) * (a.y + m.gravity.y) + (a.z + m.gravity.z) * (a.z + m.gravity.z)).squareRoot()
        peakG = max(peakG, acceleration)
    }
}

@MainActor
@Observable
final class PressureSensor {
    static let shared = PressureSensor()
    private(set) var kPa: Double?
    private(set) var relativeAltitude = 0.0
    private(set) var history: [Double] = []
    private(set) var running = false
    @ObservationIgnored private let altimeter = CMAltimeter()
    var available: Bool { CMAltimeter.isRelativeAltitudeAvailable() }
    var hPa: Double? { kPa.map { $0 * 10 } }

    func start() {
        guard available, !running else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated {
                self?.kPa = data.pressure.doubleValue
                self?.relativeAltitude = data.relativeAltitude.doubleValue
                self?.history.append(data.pressure.doubleValue * 10); if (self?.history.count ?? 0) > 200 { self?.history.removeFirst() }
            }
        }
        running = true
    }

    func stop() { altimeter.stopRelativeAltitudeUpdates(); running = false }
}

@MainActor
@Observable
final class LocationSensors: NSObject, CLLocationManagerDelegate {
    static let shared = LocationSensors()
    private(set) var heading: Double?
    private(set) var headingAccuracy: Double?
    private(set) var location: CLLocation?
    private(set) var status: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored private let manager = CLLocationManager()

    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest; status = manager.authorizationStatus }

    func start() {
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() { manager.stopUpdatingLocation(); manager.stopUpdatingHeading() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { status = manager.authorizationStatus; if status == .authorizedWhenInUse || status == .authorizedAlways { start() } }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { location = locations.last }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        MainActor.assumeIsolated {
            heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            headingAccuracy = newHeading.headingAccuracy
        }
    }
}
