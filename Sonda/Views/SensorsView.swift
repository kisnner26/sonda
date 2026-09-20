import CoreLocation
import SwiftUI
import SondaCore

private enum SensorTool: String, Hashable { case magnetic, pressure, compass, level }

struct SensorsView: View {
    var body: some View {
        Screen(title: "sensores", subtitle: "lo que mide tu iPhone sin que se lo pidas") {
            VStack(spacing: 0) {
                link(.magnetic, .target, "campo magnético", "detector de metales e imanes")
                link(.pressure, .wave, "presión", "barómetro y altura relativa")
                link(.compass, .compass, "brújula y ubicación", "rumbo, coordenadas y altitud")
                link(.level, .sliders, "nivel y movimiento", "inclinación y fuerza g")
            }
        }
        .navigationDestination(for: SensorTool.self) { t in
            switch t {
            case .magnetic: MagneticView()
            case .pressure: PressureView()
            case .compass: CompassView()
            case .level: LevelView()
            }
        }
    }

    private func link(_ t: SensorTool, _ icon: IconKind, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        NavigationLink(value: t) { ModuleRow(icon: icon, title: title, detail: detail) }.buttonStyle(.plain)
    }
}

// MARK: campo magnetico

private struct MagneticView: View {
    private let s = MotionSensors.shared
    @State private var sound = false
    @State private var lastTick = Date.distantPast

    var body: some View {
        Screen(title: "campo magnético", subtitle: "la Tierra da unos 25 a 65 µT") {
            if !s.available { Text("este dispositivo no tiene magnetómetro.").font(.serif(15, italic: true)).foregroundStyle(Palette.rose) }
            HStack(alignment: .top, spacing: 20) {
                Metric(label: "intensidad", value: String(format: "%.1f", s.fieldMagnitude), unit: "µT")
                Metric(label: "x · y · z", value: String(format: "%.0f · %.0f · %.0f", s.field.x, s.field.y, s.field.z))
            }
            Sparkline(values: s.fieldHistory).frame(height: 70)
            if s.accuracy < 2 { Text("la brújula necesita calibrarse: mueve el teléfono dibujando un ocho en el aire.").font(.serif(13, italic: true)).foregroundStyle(Palette.olive) }
            Hairline()
            Caption("detector de metales")
            PetalGauge(value: s.metalSignal, center: String(format: "%.0f", s.metalSignal * 100), caption: "señal").frame(maxWidth: 240).frame(maxWidth: .infinity)
            Toggle(isOn: $sound) { Caption("sonido") }.tint(Palette.moss)
            Button("fijar el fondo aquí") { s.resetDetector(); Haptics.tap() }.buttonStyle(QuietButtonStyle())
            Text("aleja el teléfono de metales, pulsa «fijar el fondo» y acércalo despacio a un objeto: la señal sube cuando algo altera el campo. Los imanes, los altavoces y los cables con corriente también.")
                .font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
        }
        .onAppear { s.start(); s.resetDetector() }
        .onDisappear { s.stop(); ToneGenerator.shared.stop() }
        .onChange(of: s.metalSignal) { _, v in
            guard sound else { return }
            let gen = ToneGenerator.shared
            if v > 0.05 { gen.frequency = 300 + 1100 * v; gen.amplitude = 0.25; gen.waveform = .sine; if !gen.isPlaying { gen.start() } } else { gen.stop() }
            if v > 0.1, Date().timeIntervalSince(lastTick) > max(0.06, 0.5 - v * 0.45) { lastTick = Date(); Haptics.tick(0.3 + v * 0.7) }
        }
        .onChange(of: sound) { _, on in if !on { ToneGenerator.shared.stop() } }
    }
}

// MARK: presion

private struct PressureView: View {
    private let s = PressureSensor.shared
    @State private var seaLevel = "1013.25"

    var body: some View {
        Screen(title: "presión", subtitle: "barómetro del iPhone") {
            if !s.available { Text("este dispositivo no tiene barómetro.").font(.serif(15, italic: true)).foregroundStyle(Palette.rose) }
            HStack(alignment: .top, spacing: 24) {
                Metric(label: "presión", value: s.hPa.map { String(format: "%.2f", $0) } ?? "—", unit: "hPa")
                Metric(label: "cambio de altura", value: String(format: "%+.1f", s.relativeAltitude), unit: "m")
            }
            Sparkline(values: s.history).frame(height: 70)
            if let p = s.hPa, let ref = Double(seaLevel.replacingOccurrences(of: ",", with: ".")), ref > 800 {
                Metric(label: "altura estimada", value: String(format: "%.0f", Barometer.altitude(pressure: p, reference: ref)), unit: "m")
            }
            VStack(alignment: .leading, spacing: 4) {
                Caption("presión al nivel del mar (hPa) para calcular la altura")
                TextField("", text: $seaLevel).font(.serif(18)).keyboardType(.decimalPad)
                Hairline()
            }
            Text("la presión cambia con el tiempo: la altura absoluta puede errar decenas de metros. El cambio de altura desde que abriste la pantalla es fiable: sube una escalera y míralo.")
                .font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
        }
        .onAppear { s.start() }
        .onDisappear { s.stop() }
    }
}

// MARK: brujula

private struct CompassRose: View {
    let heading: Double
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2 - 8
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Palette.ink), lineWidth: 1)
            var g = ctx
            g.translateBy(x: c.x, y: c.y); g.rotate(by: .degrees(-heading))
            for d in stride(from: 0, to: 360, by: 10) {
                let major = d % 90 == 0, mid = d % 30 == 0
                var p = Path(); p.move(to: CGPoint(x: 0, y: -r)); p.addLine(to: CGPoint(x: 0, y: -r + (major ? 16 : mid ? 10 : 5)))
                var rot = g; rot.rotate(by: .degrees(Double(d)))
                rot.stroke(p, with: .color(major ? Palette.rose : Palette.ink), lineWidth: major ? 1.6 : 0.8)
            }
            for (i, name) in ["N", "E", "S", "O"].enumerated() {
                var rot = g; rot.rotate(by: .degrees(Double(i) * 90))
                rot.draw(Text(name).font(.serif(20)).foregroundColor(i == 0 ? Palette.rose : Palette.ink), at: CGPoint(x: 0, y: -r + 34))
            }
            var tip = Path(); tip.move(to: CGPoint(x: c.x, y: c.y - r - 2)); tip.addLine(to: CGPoint(x: c.x - 6, y: c.y - r + 10)); tip.addLine(to: CGPoint(x: c.x + 6, y: c.y - r + 10)); tip.closeSubpath()
            ctx.fill(tip, with: .color(Palette.ink))
        }
    }
}

private struct CompassView: View {
    private let l = LocationSensors.shared

    var body: some View {
        Screen(title: "brújula y ubicación") {
            if l.status == .denied || l.status == .restricted {
                Text("Sonda no tiene permiso de ubicación. Puedes darlo en Ajustes > Sonda.").font(.serif(15, italic: true)).foregroundStyle(Palette.rose)
            }
            CompassRose(heading: l.heading ?? 0).frame(height: 280)
            HStack(alignment: .top, spacing: 24) {
                Metric(label: "rumbo", value: l.heading.map { String(format: "%.0f°", $0) } ?? "—", unit: l.heading.map { Compass.label(degrees: $0) } ?? "")
                Metric(label: "precisión", value: l.headingAccuracy.map { $0 < 0 ? "—" : String(format: "±%.0f°", $0) } ?? "—")
            }
            if let loc = l.location {
                Hairline()
                Metric(label: "latitud", value: String(format: "%.6f", loc.coordinate.latitude))
                Metric(label: "longitud", value: String(format: "%.6f", loc.coordinate.longitude))
                HStack(alignment: .top, spacing: 24) {
                    Metric(label: "altitud", value: String(format: "%.0f", loc.altitude), unit: "m")
                    Metric(label: "velocidad", value: String(format: "%.1f", max(0, loc.speed) * 3.6), unit: "km/h")
                    Metric(label: "precisión", value: String(format: "±%.0f", loc.horizontalAccuracy), unit: "m")
                }
                ShareLink(item: String(format: "%.6f, %.6f", loc.coordinate.latitude, loc.coordinate.longitude)) { Text("compartir coordenadas") }.buttonStyle(QuietButtonStyle())
            }
        }
        .onAppear { l.start() }
        .onDisappear { l.stop() }
    }
}

// MARK: nivel

private struct LevelView: View {
    private let s = MotionSensors.shared

    /// inclinacion en grados respecto a la horizontal (con el telefono plano) y a la vertical (de pie).
    private var flatX: Double { asin(max(-1, min(1, s.gravity.x))) * 180 / .pi }
    private var flatY: Double { asin(max(-1, min(1, s.gravity.y))) * 180 / .pi }

    var body: some View {
        Screen(title: "nivel y movimiento") {
            ZStack {
                Circle().stroke(Palette.ink, lineWidth: 1)
                Circle().stroke(Palette.faint, lineWidth: 0.6).padding(60)
                Rectangle().fill(Palette.faint).frame(width: 0.6).padding(.vertical, 8)
                Rectangle().fill(Palette.faint).frame(height: 0.6).padding(.horizontal, 8)
                Circle().fill(Palette.ink.opacity(abs(flatX) < 1 && abs(flatY) < 1 ? 0.9 : 0.35)).frame(width: 34, height: 34)
                    .offset(x: max(-110, min(110, s.gravity.x * 240)), y: max(-110, min(110, -s.gravity.y * 240)))
            }
            .frame(width: 260, height: 260).frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 24) {
                Metric(label: "eje x", value: String(format: "%+.1f°", flatX))
                Metric(label: "eje y", value: String(format: "%+.1f°", flatY))
                Metric(label: "fuerza", value: String(format: "%.2f", s.acceleration), unit: "g")
            }
            Metric(label: "pico de fuerza", value: String(format: "%.2f", s.peakG), unit: "g")
            Button("reiniciar pico") { s.resetDetector() }.buttonStyle(QuietButtonStyle())
            Text("pon el teléfono plano sobre una superficie: la burbuja se centra cuando está a nivel (dentro de 1°). Sacúdelo o déjalo caer sobre algo blando para ver el pico de fuerza.")
                .font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
        }
        .onAppear { s.start(); s.resetDetector() }
        .onDisappear { s.stop() }
    }
}
