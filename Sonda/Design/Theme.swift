import SwiftUI
import UIKit

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, paper, night
    var id: String { rawValue }
    var title: LocalizedStringKey { self == .system ? "según el sistema" : self == .paper ? "papel" : "noche" }
}

/// tema elegido. singleton observable para que `Palette` cambie los colores de toda la interfaz.
@Observable
final class Appearance {
    static let shared = Appearance()

    var choice: ThemeChoice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: "sonda.theme") }
    }
    var haptics: Bool {
        didSet { UserDefaults.standard.set(haptics, forKey: "sonda.haptics") }
    }

    private init() {
        choice = ThemeChoice(rawValue: UserDefaults.standard.string(forKey: "sonda.theme") ?? "") ?? .system
        haptics = UserDefaults.standard.object(forKey: "sonda.haptics") as? Bool ?? true
    }

    var isNight: Bool {
        switch choice {
        case .night: true
        case .paper: false
        case .system: UITraitCollection.current.userInterfaceStyle == .dark
        }
    }

    var colorScheme: ColorScheme? { choice == .system ? nil : (choice == .night ? .dark : .light) }
}

/// la paleta de la pagina de las flores, la misma de girasol: papel y tinta, con verdes y rojos apagados.
enum Palette {
    private static var night: Bool { Appearance.shared.isNight }
    private static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static var ink: Color { night ? hex(0xF5F0E8) : hex(0x1A1208) }
    static var paper: Color { night ? hex(0x14100A) : hex(0xF5F0E8) }
    static var paperDark: Color { night ? hex(0x2A2218) : hex(0xE8E0D0) }
    static var mid: Color { night ? hex(0xC8BFAA) : hex(0x5A4A30) }
    static var faint: Color { night ? hex(0x5A4A30) : hex(0xC8BFAA) }
    static var moss: Color { night ? hex(0x9DB89A) : hex(0x2A3A2A) }
    static var olive: Color { night ? hex(0xD2C47A) : hex(0x4A4A2A) }
    static var rose: Color { night ? hex(0xE58E84) : hex(0x7A1A1A) }
}

extension Font {
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        let f = Font.system(size: size, weight: .regular, design: .serif)
        return italic ? f.italic() : f
    }
}

/// rotulo en mayusculas espaciadas, como las etiquetas de la pagina.
struct Caption: View {
    private let text: Text
    var color: Color = Palette.mid
    init(_ key: LocalizedStringKey, color: Color = Palette.mid) { text = Text(key); self.color = color }
    init(verbatim: String, color: Color = Palette.mid) { text = Text(verbatim: verbatim); self.color = color }

    var body: some View {
        text.textCase(.uppercase)
            .font(.system(size: 11, weight: .regular, design: .serif))
            .tracking(1.8)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct Hairline: View {
    var opacity = 0.35
    var body: some View { Rectangle().fill(Palette.ink.opacity(opacity)).frame(height: 0.5) }
}
