import SwiftUI

enum IconKind { case bluetooth, network, compass, wave, lens, toolbox, sliders, target, leaf }

/// iconos de trazo fino en una cuadricula de 24: el mismo lenguaje que los dibujos botanicos de girasol.
struct LineIcon: View {
    let kind: IconKind

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            ctx.translateBy(x: (size.width - s) / 2, y: (size.height - s) / 2)
            ctx.scaleBy(x: s / 24, y: s / 24)
            let style = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
            let ink = GraphicsContext.Shading.color(Palette.ink)
            func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
            func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) -> Path { var p = Path(); p.move(to: CGPoint(x: a.0, y: a.1)); p.addLine(to: CGPoint(x: b.0, y: b.1)); return p }

            switch kind {
            case .bluetooth:
                var p = Path()
                p.move(to: CGPoint(x: 6, y: 8)); p.addLine(to: CGPoint(x: 17, y: 16.5)); p.addLine(to: CGPoint(x: 12, y: 21)); p.addLine(to: CGPoint(x: 12, y: 3))
                p.addLine(to: CGPoint(x: 17, y: 7.5)); p.addLine(to: CGPoint(x: 6, y: 16))
                ctx.stroke(p, with: ink, style: style)
            case .network:
                for (i, r) in [4.0, 8.0, 12.0].enumerated() {
                    var p = Path()
                    p.addArc(center: CGPoint(x: 12, y: 19), radius: CGFloat(r), startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
                    ctx.stroke(p, with: ink.self, style: style)
                    _ = i
                }
                ctx.fill(circle(12, 19, 1.4), with: ink)
            case .compass:
                ctx.stroke(circle(12, 12, 9.5), with: ink, style: style)
                var needle = Path()
                needle.move(to: CGPoint(x: 15.5, y: 8.5)); needle.addLine(to: CGPoint(x: 13.2, y: 13.2)); needle.addLine(to: CGPoint(x: 8.5, y: 15.5)); needle.addLine(to: CGPoint(x: 10.8, y: 10.8)); needle.closeSubpath()
                ctx.stroke(needle, with: ink, style: style)
                ctx.fill(circle(12, 12, 0.9), with: ink)
            case .wave:
                var p = Path()
                p.move(to: CGPoint(x: 2, y: 12))
                p.addCurve(to: CGPoint(x: 8, y: 12), control1: CGPoint(x: 4, y: 4), control2: CGPoint(x: 6, y: 4))
                p.addCurve(to: CGPoint(x: 14, y: 12), control1: CGPoint(x: 10, y: 20), control2: CGPoint(x: 12, y: 20))
                p.addCurve(to: CGPoint(x: 22, y: 12), control1: CGPoint(x: 16, y: 5), control2: CGPoint(x: 19.5, y: 5))
                ctx.stroke(p, with: ink, style: style)
            case .lens:
                ctx.stroke(Path(roundedRect: CGRect(x: 2.5, y: 6.5, width: 19, height: 13), cornerRadius: 3), with: ink, style: style)
                ctx.stroke(circle(12, 13, 4), with: ink, style: style)
                ctx.stroke(line((8.5, 6.5), (9.8, 4)), with: ink, style: style)
                ctx.stroke(line((15.5, 6.5), (14.2, 4)), with: ink, style: style)
                ctx.stroke(line((9.8, 4), (14.2, 4)), with: ink, style: style)
            case .toolbox:
                ctx.stroke(Path(roundedRect: CGRect(x: 3, y: 8, width: 18, height: 12), cornerRadius: 2), with: ink, style: style)
                ctx.stroke(Path(roundedRect: CGRect(x: 9, y: 4, width: 6, height: 4), cornerRadius: 1.5), with: ink, style: style)
                ctx.stroke(line((3, 13), (21, 13)), with: ink, style: style)
                ctx.fill(circle(12, 13, 1.3), with: GraphicsContext.Shading.color(Palette.paper))
                ctx.stroke(circle(12, 13, 1.3), with: ink, style: style)
            case .sliders:
                for (y, x) in [(6.0, 9.0), (12.0, 15.0), (18.0, 8.0)] {
                    ctx.stroke(line((4, y), (20, y)), with: ink, style: style)
                    ctx.fill(circle(CGFloat(x), CGFloat(y), 2.3), with: GraphicsContext.Shading.color(Palette.paper))
                    ctx.stroke(circle(CGFloat(x), CGFloat(y), 2.3), with: ink, style: style)
                }
            case .target:
                ctx.stroke(circle(12, 12, 9), with: ink, style: style)
                ctx.stroke(circle(12, 12, 5), with: ink, style: style)
                ctx.fill(circle(12, 12, 1.4), with: ink)
            case .leaf:
                var p = Path()
                p.move(to: CGPoint(x: 5, y: 19))
                p.addCurve(to: CGPoint(x: 20, y: 4), control1: CGPoint(x: 5, y: 9), control2: CGPoint(x: 11, y: 4))
                p.addCurve(to: CGPoint(x: 5, y: 19), control1: CGPoint(x: 20, y: 13), control2: CGPoint(x: 15, y: 19))
                ctx.stroke(p, with: ink, style: style)
                ctx.stroke(line((5, 19), (14, 10)), with: ink, style: style)
            }
        }
        .accessibilityHidden(true)
    }
}

/// anillo fino de progreso.
struct Ring: View {
    let fraction: Double
    let tint: Color
    var width: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(Palette.faint, lineWidth: 0.7)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// fila de una lista: icono, rotulo en mayusculas, detalle en cursiva y una linea fina debajo.
struct ModuleRow: View {
    let icon: IconKind
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                LineIcon(kind: icon).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Caption(title)
                    Text(detail).font(.serif(17, italic: true)).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Text("›").font(.serif(20)).foregroundStyle(Palette.mid)
            }
            .padding(.vertical, 14)
            Hairline(opacity: 0.2)
        }
        .contentShape(Rectangle())
    }
}

/// pantalla con titulo grande en serif y papel de fondo; todas las pantallas cuelgan de aqui.
struct Screen<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.serif(32)).foregroundStyle(Palette.ink)
                    if let subtitle { Text(subtitle).font(.serif(15, italic: true)).foregroundStyle(Palette.mid) }
                }
                Hairline()
                content
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.paper, for: .navigationBar)
    }
}

/// boton principal: recuadro fino de tinta, letras espaciadas.
struct InkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular, design: .serif)).textCase(.uppercase).tracking(2)
            .foregroundStyle(configuration.isPressed ? Palette.paper : Palette.ink)
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(configuration.isPressed ? Palette.ink : Color.clear)
            .overlay(Rectangle().stroke(Palette.ink, lineWidth: 0.8))
    }
}

/// boton de texto discreto.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.serif(14, italic: true))
            .foregroundStyle(configuration.isPressed ? Palette.ink : Palette.mid)
            .underline()
    }
}

/// un petalo: elipse alargada que arranca fuera del centro, girada `index` pasos.
struct Petal: Shape {
    let index: Int
    let count: Int
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let inner = r * 0.36, outer = r * length, w = r * 0.15
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - w, y: c.y - outer, width: 2 * w, height: outer - inner))
        let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
        return p.applying(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).translatedBy(x: -c.x, y: -c.y))
    }
}

/// una medida 0...1 como un girasol: un petalo entintado por cada doceavo.
struct PetalGauge: View {
    let value: Double
    let center: String
    var caption: String = ""
    var petals = 12

    private var filled: Int { value <= 0 ? 0 : min(petals, Int((value * Double(petals)).rounded(.up))) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<petals, id: \.self) { i in
                    if i < filled { Petal(index: i, count: petals, length: 0.95).fill(Palette.ink.opacity(0.9)) }
                    Petal(index: i, count: petals, length: 0.95).stroke(Palette.ink.opacity(i < filled ? 1 : 0.32), lineWidth: 0.9)
                }
                Circle().fill(Palette.paper).frame(width: side * 0.44, height: side * 0.44)
                Circle().stroke(Palette.ink, lineWidth: 1).frame(width: side * 0.38, height: side * 0.38)
                VStack(spacing: 0) {
                    Text(center).font(.serif(side * 0.15)).foregroundStyle(Palette.ink).minimumScaleFactor(0.5).lineLimit(1)
                    if !caption.isEmpty { Text(caption).font(.serif(side * 0.055, italic: true)).foregroundStyle(Palette.mid).lineLimit(1) }
                }
                .frame(width: side * 0.32)
            }
            .frame(width: side, height: side).position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(center) \(caption)")
    }
}

/// ramito de linea fina para la portada y los estados vacios.
struct Sprig: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 60, size.height / 84)
            ctx.translateBy(x: (size.width - 60 * s) / 2, y: (size.height - 84 * s) / 2)
            ctx.scaleBy(x: s, y: s)
            let style = StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
            var stem = Path()
            stem.move(to: .init(x: 30, y: 82)); stem.addCurve(to: .init(x: 30, y: 28), control1: .init(x: 29, y: 64), control2: .init(x: 31, y: 46))
            ctx.stroke(stem, with: .color(Palette.ink), style: style)
            for k in 0..<5 {
                var p = Path()
                p.addEllipse(in: CGRect(x: -4.5, y: -10, width: 9, height: 20))
                ctx.stroke(p.applying(CGAffineTransform(translationX: 30, y: 20).rotated(by: CGFloat(k) * 2 * .pi / 5)), with: .color(Palette.ink), style: style)
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: 26.6, y: 16.6, width: 6.8, height: 6.8)), with: .color(Palette.ink), style: style)
            var leaf1 = Path()
            leaf1.move(to: .init(x: 30, y: 58)); leaf1.addCurve(to: .init(x: 16, y: 39), control1: .init(x: 20, y: 54), control2: .init(x: 14, y: 46))
            leaf1.addCurve(to: .init(x: 30, y: 58), control1: .init(x: 25, y: 39), control2: .init(x: 30, y: 47))
            var leaf2 = Path()
            leaf2.move(to: .init(x: 30, y: 66)); leaf2.addCurve(to: .init(x: 44, y: 49), control1: .init(x: 39, y: 63), control2: .init(x: 45, y: 56))
            leaf2.addCurve(to: .init(x: 30, y: 66), control1: .init(x: 36, y: 50), control2: .init(x: 30, y: 57))
            ctx.stroke(leaf1, with: .color(Palette.ink), style: style)
            ctx.stroke(leaf2, with: .color(Palette.ink), style: style)
        }
        .accessibilityHidden(true)
    }
}

/// grafica de linea fina de una serie que se va llenando (senal, campo magnetico, presion…).
struct Sparkline: View {
    let values: [Double]
    var range: ClosedRange<Double>?
    var tint: Color = Palette.ink

    var body: some View {
        Canvas { ctx, size in
            ctx.stroke(Path(CGRect(x: 0, y: size.height - 0.5, width: size.width, height: 0.5)), with: .color(Palette.faint), lineWidth: 1)
            guard values.count > 1 else { return }
            let lo = range?.lowerBound ?? (values.min() ?? 0), hi = range?.upperBound ?? (values.max() ?? 1)
            let span = max(1e-9, hi - lo)
            var p = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: size.width * Double(i) / Double(values.count - 1), y: size.height - (min(hi, max(lo, v)) - lo) / span * (size.height - 4) - 2)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            ctx.stroke(p, with: .color(tint), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// un dato: rotulo pequeño y valor grande en serif.
struct Metric: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Caption(label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.serif(26)).foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
                if !unit.isEmpty { Text(unit).font(.serif(14, italic: true)).foregroundStyle(Palette.mid) }
            }
        }
    }
}

extension View {
    func card() -> some View {
        padding(14).overlay(Rectangle().stroke(Palette.faint, lineWidth: 0.8))
    }
}
