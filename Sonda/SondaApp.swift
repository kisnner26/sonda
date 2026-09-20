import SwiftUI

@main
struct SondaApp: App {
    private let appearance = Appearance.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(appearance.colorScheme)
                .tint(Palette.ink)
        }
    }
}
