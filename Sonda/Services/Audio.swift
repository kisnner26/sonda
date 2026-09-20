import AVFoundation
import Foundation
import Observation
import SondaCore

enum Waveform: String, CaseIterable, Identifiable { case sine = "seno", square = "cuadrada", saw = "sierra", noise = "ruido"; var id: String { rawValue } }

/// generador de tonos: seno, cuadrada, sierra o ruido, con barrido opcional. Los parametros se leen desde el hilo de audio.
final class ToneGenerator: @unchecked Sendable {
    static let shared = ToneGenerator()

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let lock = NSLock()
    private var _frequency = 440.0, _amplitude = 0.3, _waveform = Waveform.sine
    private var sweepEnd: Double?, sweepSeconds = 0.0, sweepElapsed = 0.0, sweepStart = 440.0
    private var phase = 0.0
    private var noiseState: UInt64 = 0x9E3779B97F4A7C15
    private(set) var isPlaying = false

    var frequency: Double { get { lock.withLock { _frequency } } set { lock.withLock { _frequency = newValue } } }
    var amplitude: Double { get { lock.withLock { _amplitude } } set { lock.withLock { _amplitude = newValue } } }
    var waveform: Waveform { get { lock.withLock { _waveform } } set { lock.withLock { _waveform = newValue } } }

    func start(sweepTo end: Double? = nil, seconds: Double = 5) {
        stop()
        lock.withLock { sweepEnd = end; sweepSeconds = seconds; sweepElapsed = 0; sweepStart = _frequency; phase = 0 }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let n = AVAudioSourceNode { [self] _, _, frames, abl -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let (wave, amp) = lock.withLock { (_waveform, _amplitude) }
            for f in 0..<Int(frames) {
                let freq: Double = lock.withLock {
                    if let end = sweepEnd {
                        sweepElapsed += 1 / rate
                        let t = min(1, sweepElapsed / sweepSeconds)
                        _frequency = sweepStart * pow(end / sweepStart, t)          // barrido logaritmico
                        if sweepElapsed >= sweepSeconds { sweepElapsed = 0 }
                    }
                    return _frequency
                }
                phase += freq / rate
                phase -= phase.rounded(.down)
                let sample: Double
                switch wave {
                case .sine: sample = sin(2 * .pi * phase)
                case .square: sample = phase < 0.5 ? 1 : -1
                case .saw: sample = 2 * phase - 1
                case .noise:
                    noiseState ^= noiseState << 13; noiseState ^= noiseState >> 7; noiseState ^= noiseState << 17
                    sample = Double(Int64(bitPattern: noiseState) >> 11) / Double(1 << 52)
                }
                for b in buffers { b.mData!.assumingMemoryBound(to: Float.self)[f] = Float(sample * amp) }
            }
            return noErr
        }
        node = n
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: format)
        try? engine.start()
        isPlaying = true
    }

    func stop() {
        guard isPlaying else { return }
        engine.stop()
        if let node { engine.detach(node) }
        node = nil
        isPlaying = false
    }

    /// una nota corta (para el teclado dtmf, el morse, los pitidos del detector de metales).
    func beep(frequency f: Double, duration: Double, amplitude a: Double = 0.3) {
        let wasPlaying = isPlaying
        self.frequency = f; self.amplitude = a; self.waveform = .sine
        if !wasPlaying { start() }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in if !wasPlaying { stop() } }
    }
}

/// una cuadricula fija de compartimentos de frecuencia para dibujar, mas los numeros que interesan.
struct SpectrumFrame {
    var bars: [Double] = []           // 0...1 en escala de dB, de 0 a Nyquist
    var peakHz: Double?
    var peakDB: Double = -120
    var levelDB: Double = -120        // nivel global relativo a fondo de escala
    var ultrasound: Double = 0        // magnitud maxima por encima de 17 kHz (0...1)
    var sampleRate: Double = 48000
}

/// micrófono: espectro, nivel y deteccion de teclas DTMF. Nada de lo que oye se guarda ni sale del telefono.
@MainActor
@Observable
final class MicAnalyzer {
    static let shared = MicAnalyzer()

    private(set) var running = false
    private(set) var denied = false
    private(set) var frame = SpectrumFrame()
    private(set) var levels: [Double] = []
    private(set) var minDB = 0.0
    private(set) var maxDB = -180.0
    private(set) var dtmf = ""
    var listensDTMF = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var lastKey: Character?
    @ObservationIgnored private var keyHold = 0
    @ObservationIgnored private var sumDB = 0.0
    @ObservationIgnored private var count = 0

    var averageDB: Double { count == 0 ? -180 : sumDB / Double(count) }
    var readingCount: Int { count }

    func start() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { denied = true; return }
        denied = false
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
        try? session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        let size: AVAudioFrameCount = 4096
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: size, format: format) { [weak self] buffer, _ in
            guard let ch = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
            let rate = buffer.format.sampleRate
            let frame = MicAnalyzer.analyze(samples, rate: rate)
            let key = MicAnalyzer.dtmfKey(samples, rate: rate)
            Task { @MainActor [weak self] in self?.ingest(frame, key) }
        }
        try? engine.start()
        running = true
        resetStats()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }

    func resetStats() { levels = []; minDB = 0; maxDB = -180; sumDB = 0; count = 0; dtmf = "" }
    func clearDTMF() { dtmf = "" }

    private func ingest(_ f: SpectrumFrame, _ key: Character?) {
        frame = f
        levels.append(f.levelDB); if levels.count > 120 { levels.removeFirst() }
        if f.levelDB > -100 {
            minDB = count == 0 ? f.levelDB : min(minDB, f.levelDB); maxDB = max(maxDB, f.levelDB)
            sumDB += f.levelDB; count += 1
        }
        if listensDTMF {
            // una tecla cuenta cuando se mantiene dos bloques seguidos, y se vuelve a contar cuando suena silencio entre medias
            if let k = key { if k == lastKey { keyHold += 1; if keyHold == 2 { dtmf.append(k); Haptics.tick() } } else { lastKey = k; keyHold = 1 } }
            else { lastKey = nil; keyHold = 0 }
        }
    }

    nonisolated static func analyze(_ raw: [Float], rate: Double) -> SpectrumFrame {
        var n = 1; while n * 2 <= raw.count { n *= 2 }
        let samples = raw.suffix(n).map(Double.init)
        let mags = Spectrum.magnitudes(samples)
        var f = SpectrumFrame()
        f.sampleRate = rate
        f.levelDB = Level.dBFS(rms: Level.rms(raw))
        if let p = Spectrum.peak(mags, sampleRate: rate, minHz: 20), p.magnitude > 1e-5 { f.peakHz = p.hz; f.peakDB = 20 * log10(p.magnitude) }
        f.ultrasound = Spectrum.bandLevel(mags, sampleRate: rate, from: 17000, to: rate / 2 - 500)
        let bars = 96
        f.bars = (0..<bars).map { b in
            let lo = Int(Double(b) / Double(bars) * Double(mags.count)), hi = max(lo + 1, Int(Double(b + 1) / Double(bars) * Double(mags.count)))
            let m = mags[lo..<min(hi, mags.count)].max() ?? 0
            return max(0, min(1, (20 * log10(max(m, 1e-9)) + 100) / 100))     // -100 dB..0 dB
        }
        return f
    }

    nonisolated static func dtmfKey(_ raw: [Float], rate: Double) -> Character? {
        Dtmf.detect(raw.prefix(2048).map(Double.init), sampleRate: rate, minPower: 2e-4)
    }
}

/// linterna: la usa el morse por luz.
enum Torch {
    static func set(_ on: Bool) {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch else { return }
        try? d.lockForConfiguration()
        d.torchMode = on ? .on : .off
        d.unlockForConfiguration()
    }
    static var available: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }
}
