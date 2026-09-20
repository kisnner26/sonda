import SwiftUI

enum Module: String, CaseIterable, Identifiable, Hashable {
    case bluetooth, network, sensors, audio, camera, tools, settings
    var id: String { rawValue }
}

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 6) {
                    Sprig().frame(width: 58, height: 82).padding(.top, 18)
                    Text("sonda").font(.serif(40, italic: true)).tracking(6).foregroundStyle(Palette.ink)
                    Text("radio, red y sensores de tu iPhone").font(.serif(16, italic: true)).foregroundStyle(Palette.mid)
                        .padding(.bottom, 14)
                    Hairline()
                    ForEach(Module.allCases) { m in
                        NavigationLink(value: m) { row(m) }.buttonStyle(.plain)
                    }
                    Text("no clona ni interfiere: mira, mide y explica lo que hay a tu alrededor.")
                        .font(.serif(12, italic: true)).foregroundStyle(Palette.faint).multilineTextAlignment(.center).padding(.top, 18)
                }
                .padding(.horizontal, 22).padding(.bottom, 30)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationDestination(for: Module.self) { m in
                switch m {
                case .bluetooth: BluetoothView()
                case .network: NetworkView()
                case .sensors: SensorsView()
                case .audio: AudioView()
                case .camera: CameraView()
                case .tools: ToolsView()
                case .settings: SettingsView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder private func row(_ m: Module) -> some View {
        switch m {
        case .bluetooth: ModuleRow(icon: .bluetooth, title: "bluetooth", detail: "dispositivos cercanos, rastreadores y servicios")
        case .network: ModuleRow(icon: .network, title: "red", detail: "equipos, puertos, ping y bonjour")
        case .sensors: ModuleRow(icon: .compass, title: "sensores", detail: "campo magnético, presión, brújula y nivel")
        case .audio: ModuleRow(icon: .wave, title: "audio", detail: "espectro, tonos, dtmf, morse y sonómetro")
        case .camera: ModuleRow(icon: .lens, title: "cámara", detail: "códigos qr y detector de infrarrojo")
        case .tools: ModuleRow(icon: .toolbox, title: "herramientas", detail: "hex, hashes, conversiones y contraseñas")
        case .settings: ModuleRow(icon: .sliders, title: "ajustes", detail: "tema, háptico y acerca de")
        }
    }
}
