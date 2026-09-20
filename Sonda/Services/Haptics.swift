import UIKit

enum Haptics {
    static func tap() { guard Appearance.shared.haptics else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { guard Appearance.shared.haptics else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { guard Appearance.shared.haptics else { return }; UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tick(_ intensity: CGFloat = 0.6) { guard Appearance.shared.haptics else { return }; UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: intensity) }
}
