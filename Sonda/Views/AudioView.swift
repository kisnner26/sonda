import AVFoundation
import SwiftUI
import SondaCore

private enum AudioTool: String, Hashable { case spectrum, tone, dtmf, meter, morse }

struct AudioView: View {
    var body: some View {
        Screen(title: "audio", subtitle: "oír lo que no se oye, y sonar lo que se pide") {
            VStack(spacing: 0) {
                link(.spectrum, .wave, "espectro", "frecuencias en vivo y ultrasonido")
                link(.tone, .target, "tonos", "seno, cuadrada, sierra, ruido y barridos")
                link(.dtmf, .toolbox, "dtmf", "marcar y decodificar teclas")
                link(.meter, .compass, "sonómetro", "nivel de sonido relativo")
                link(.morse, .leaf, "morse", "texto a sonido y luz")
            }
        }
        .navigationDestination(for: AudioTool.self) { t in
            switch t {
            case .spectrum: SpectrumView()
            case .tone: ToneView()
            case .dtmf: DTMFView()
            case .meter: MeterView()
            case .morse: MorseView()
            }
        }
    }

    private func link(_ t: AudioTool, _ icon: IconKind, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        NavigationLink(value: t) { ModuleRow(icon: icon, title: title, detail: detail) }.buttonStyle(.plain)
    }
}

private struct MicNotice: View {
    let mic: MicAnalyzer
    var body: some View {
        if mic.denied { Text("Sonda no tiene permiso de micrófono. Puedes darlo en Ajustes > Sonda.").font(.serif(15, italic: true)).foregroundStyle(Palette.rose) }
    }
}

// MARK: espectro

private struct SpectrumView: View {
    private let mic = MicAnalyzer.shared

    var body: some View {
        Screen(title: "espectro", subtitle: "frecuencias que llegan al micrófono") {
            MicNotice(mic: mic)
            Canvas { ctx, size in
                let bars = mic.frame.bars
                ctx.stroke(Path(CGRect(x: 0, y: size.height - 0.5, width: size.width, height: 0.5)), with: .color(Palette.ink), lineWidth: 1)
                guard !bars.isEmpty else { return }
                let w = size.width / Double(bars.count)
                for (i, v) in bars.enumerated() {
                    let h = max(1, v * (size.height - 6))
                    ctx.fill(Path(CGRect(x: Double(i) * w + 0.5, y: size.height - h, width: max(1, w - 1.5), height: h)), with: .color(Palette.ink.opacity(0.85)))
                }
                let ultraX = 17000 / (mic.frame.sampleRate / 2) * size.width
                ctx.stroke(Path { p in p.move(to: CGPoint(x: ultraX, y: 0)); p.addLine(to: CGPoint(x: ultraX, y: size.height)) }, with: .color(Palette.rose), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            }
            .frame(height: 180)
            HStack { Caption(verbatim: "0"); Spacer(); Caption(verbatim: "\(Int(mic.frame.sampleRate / 4000)) kHz"); Spacer(); Caption(verbatim: "\(Int(mic.frame.sampleRate / 2000)) kHz") }
            HStack(alignment: .top, spacing: 24) {
                Metric(label: "pico", value: mic.frame.peakHz.map { $0 >= 1000 ? String(format: "%.2f", $0 / 1000) : String(format: "%.0f", $0) } ?? "—", unit: (mic.frame.peakHz ?? 0) >= 1000 ? "kHz" : "Hz")
                Metric(label: "nivel", value: String(format: "%.0f", mic.frame.levelDB), unit: "dBFS")
            }
            HStack {
                Caption("ultrasonido (> 17 kHz)", color: mic.frame.ultrasound > 0.01 ? Palette.rose : Palette.mid)
                Spacer()
                Text(mic.frame.ultrasound > 0.01 ? "se detecta" : "silencio").font(.serif(15, italic: true)).foregroundStyle(mic.frame.ultrasound > 0.01 ? Palette.rose : Palette.mid)
            }
            Text("el micrófono del iPhone capta hasta unos 20 kHz según el modelo. Sirve para ver zumbidos de aparatos, silbatos, repelentes ultrasónicos o balizas de sonido.")
                .font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
        }
        .task { await mic.start() }
        .onDisappear { mic.stop() }
    }
}

// MARK: tonos

private struct ToneView: View {
    @State private var position = 0.4          // 0...1 -> 20 Hz ... 20 kHz (logaritmico)
    @State private var wave = Waveform.sine
    @State private var amp = 0.25
    @State private var playing = false
    private let gen = ToneGenerator.shared

    private var hz: Double { 20 * pow(1000, position) }

    var body: some View {
        Screen(title: "tonos", subtitle: "generador de señales") {
            Metric(label: "frecuencia", value: hz >= 1000 ? String(format: "%.2f", hz / 1000) : String(format: "%.0f", hz), unit: hz >= 1000 ? "kHz" : "Hz")
            Slider(value: $position).tint(Palette.ink).onChange(of: position) { _, _ in gen.frequency = hz }
            Picker("forma", selection: $wave) { ForEach(Waveform.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }.pickerStyle(.segmented)
                .onChange(of: wave) { _, w in gen.waveform = w }
            VStack(alignment: .leading, spacing: 2) {
                Caption("volumen")
                Slider(value: $amp, in: 0.02...0.6).tint(Palette.ink).onChange(of: amp) { _, a in gen.amplitude = a }
            }
            HStack(spacing: 22) {
                Button(playing ? "silencio" : "sonar") { toggle(sweep: false) }.buttonStyle(InkButtonStyle())
                Button("barrido 20 Hz → 20 kHz") { position = 0; toggle(sweep: true) }.buttonStyle(QuietButtonStyle())
            }
            Text("cuidado con los oídos: empieza con el volumen bajo, sobre todo con auriculares y por encima de 8 kHz.").font(.serif(12, italic: true)).foregroundStyle(Palette.rose)
        }
        .onDisappear { gen.stop() }
    }

    private func toggle(sweep: Bool) {
        if playing { gen.stop(); playing = false; return }
        gen.frequency = hz; gen.waveform = wave; gen.amplitude = amp
        sweep ? gen.start(sweepTo: 20000, seconds: 12) : gen.start()
        playing = true
    }
}

// MARK: dtmf

private struct DTMFView: View {
    @State private var dialed = ""
    @State private var listening = false
    private let mic = MicAnalyzer.shared
    private let keys: [[Character]] = [["1", "2", "3", "A"], ["4", "5", "6", "B"], ["7", "8", "9", "C"], ["*", "0", "#", "D"]]

    var body: some View {
        Screen(title: "dtmf", subtitle: "los tonos del teclado telefónico") {
            Caption("marcar")
            Text(dialed.isEmpty ? "—" : dialed).font(.serif(30)).foregroundStyle(Palette.ink).lineLimit(2)
            VStack(spacing: 10) {
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { k in
                            Button { press(k) } label: {
                                Text(String(k)).font(.serif(26)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 54).overlay(Rectangle().stroke(Palette.faint, lineWidth: 0.8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(spacing: 22) {
                Button("borrar") { dialed = "" }.buttonStyle(QuietButtonStyle())
                Button("sonar la secuencia") { playSequence() }.buttonStyle(QuietButtonStyle()).disabled(dialed.isEmpty)
            }
            Hairline()
            Toggle(isOn: $listening) { Caption("escuchar teclas") }.tint(Palette.moss)
                .onChange(of: listening) { _, on in
                    mic.listensDTMF = on
                    if on { mic.clearDTMF(); Task { await mic.start() } } else { mic.stop() }
                }
            MicNotice(mic: mic)
            if listening { Text(mic.dtmf.isEmpty ? "acerca el teléfono a otro que marque…" : mic.dtmf).font(.serif(24, italic: mic.dtmf.isEmpty)).foregroundStyle(mic.dtmf.isEmpty ? Palette.mid : Palette.moss) }
        }
        .onDisappear { mic.listensDTMF = false; mic.stop(); ToneGenerator.shared.stop() }
    }

    private func press(_ k: Character) {
        dialed.append(k)
        guard let f = Dtmf.frequencies(for: k) else { return }
        Haptics.tap()
        DTMFPlayer.play([k], frequencies: [(f.low, f.high)])
    }

    private func playSequence() { DTMFPlayer.play(Array(dialed), frequencies: dialed.compactMap { Dtmf.frequencies(for: $0) }) }
}

/// reproduce tonos dtmf de 120 ms con 80 ms de silencio entre teclas, con dos osciladores sumados.
enum DTMFPlayer {
    private static let engine = AVAudioEngine()
    private static var player = AVAudioPlayerNode()

    static func play(_ keys: [Character], frequencies: [(Double, Double)]) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let rate = 44100.0
        var samples: [Float] = []
        for k in keys { samples += Dtmf.tone(for: k, duration: 0.12, sampleRate: rate) + [Float](repeating: 0, count: Int(0.08 * rate)) }
        guard !samples.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        player.stop(); engine.detach(player); player = AVAudioPlayerNode(); engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buffer)
        player.play()
    }
}

// MARK: sonometro

private struct MeterView: View {
    private let mic = MicAnalyzer.shared

    var body: some View {
        Screen(title: "sonómetro", subtitle: "nivel relativo, sin calibrar") {
            MicNotice(mic: mic)
            PetalGauge(value: max(0, min(1, (mic.frame.levelDB + 80) / 80)), center: String(format: "%.0f", mic.frame.levelDB), caption: "dBFS")
                .frame(maxWidth: 260).frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 24) {
                Metric(label: "mínimo", value: mic.readingCount == 0 ? "—" : String(format: "%.0f", mic.minDB))
                Metric(label: "media", value: mic.readingCount == 0 ? "—" : String(format: "%.0f", mic.averageDB))
                Metric(label: "máximo", value: mic.maxDB < -170 ? "—" : String(format: "%.0f", mic.maxDB))
            }
            Sparkline(values: mic.levels, range: -90 ... 0).frame(height: 70)
            Button("reiniciar") { mic.resetStats() }.buttonStyle(QuietButtonStyle())
            Text("0 dBFS es el máximo que admite el micrófono; una conversación ronda −40 a −25. Son decibelios relativos: para dB SPL reales haría falta calibrar con un sonómetro de referencia.")
                .font(.serif(12, italic: true)).foregroundStyle(Palette.faint)
        }
        .task { await mic.start() }
        .onDisappear { mic.stop() }
    }
}

// MARK: morse

private struct MorseView: View {
    @State private var text = "SOS"
    @State private var wpm = 12.0
    @State private var sound = true
    @State private var light = false
    @State private var playing = false
    @State private var task: Task<Void, Never>?

    private var code: String { Morse.encode(text) }

    var body: some View {
        Screen(title: "morse", subtitle: "de texto a sonido y luz") {
            VStack(alignment: .leading, spacing: 4) {
                Caption("mensaje")
                TextField("", text: $text).font(.serif(20)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                Hairline()
            }
            Text(code.isEmpty ? "—" : code).font(.system(size: 18, design: .monospaced)).foregroundStyle(Palette.ink).textSelection(.enabled)
            VStack(alignment: .leading, spacing: 2) {
                Caption(verbatim: String(localized: "velocidad") + " · \(Int(wpm)) wpm")
                Slider(value: $wpm, in: 5...25, step: 1).tint(Palette.ink)
            }
            Toggle(isOn: $sound) { Caption("sonido") }.tint(Palette.moss)
            if Torch.available { Toggle(isOn: $light) { Caption("linterna") }.tint(Palette.moss) }
            Button(playing ? "detener" : "emitir") { playing ? stop() : play() }.buttonStyle(InkButtonStyle()).disabled(code.isEmpty)
        }
        .onDisappear { stop() }
    }

    private func stop() { task?.cancel(); playing = false; Torch.set(false); ToneGenerator.shared.stop() }

    private func play() {
        let unit = 1.2 / wpm          // duracion de un punto, en segundos (regla PARIS)
        let steps = Morse.schedule(code)
        playing = true
        task = Task {
            for s in steps {
                if Task.isCancelled { break }
                if s.on {
                    if light { Torch.set(true) }
                    if sound { ToneGenerator.shared.frequency = 650; ToneGenerator.shared.waveform = .sine; ToneGenerator.shared.amplitude = 0.3; ToneGenerator.shared.start() }
                }
                try? await Task.sleep(for: .seconds(unit * Double(s.units)))
                if s.on { Torch.set(false); ToneGenerator.shared.stop() }
            }
            stop()
        }
    }
}
