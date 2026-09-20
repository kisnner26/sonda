import Foundation

/// detector de metales con el magnetometro: compara el campo con una linea base que se adapta despacio,
/// de modo que un objeto cercano (que lo cambia rapido) destaca y el campo terrestre no.
public struct MetalDetector: Sendable {
    public private(set) var baseline: Double?
    public var adaptation = 0.02          // 0...1: cuanto se acerca la base a cada lectura
    public var fullScale = 40.0           // µT de cambio que llenan la barra

    public init() {}

    /// devuelve la señal 0...1 para una lectura de intensidad de campo en µT.
    public mutating func feed(microTesla: Double) -> Double {
        let base = baseline ?? microTesla
        let delta = abs(microTesla - base)
        baseline = base + (microTesla - base) * adaptation
        return min(1, delta / fullScale)
    }

    public mutating func reset() { baseline = nil }
}

public enum Barometer {
    /// altura respecto a la presion de referencia (hPa), con la formula barometrica internacional.
    public static func altitude(pressure hPa: Double, reference: Double) -> Double {
        44330 * (1 - pow(hPa / reference, 1 / 5.255))
    }

    /// presion al nivel del mar a partir de la de aqui y la altura conocida.
    public static func seaLevel(pressure hPa: Double, altitude: Double) -> Double {
        hPa / pow(1 - altitude / 44330, 5.255)
    }
}

public enum Compass {
    static let names = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
    public static func label(degrees: Double) -> String {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return names[Int(((d < 0 ? d + 360 : d) + 22.5) / 45) % 8]
    }
}
