import XCTest
@testable import SondaCore

final class AudioSensorsTests: XCTestCase {
    private func sine(_ f: Double, n: Int = 4096, rate: Double = 48000, amp: Double = 1) -> [Double] {
        (0..<n).map { amp * sin(2 * .pi * f * Double($0) / rate) }
    }

    func testFFTOfAKnownSignal() {
        let (re, im) = Spectrum.fft([1, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(re, [Double](repeating: 1, count: 8)); XCTAssertEqual(im, [Double](repeating: 0, count: 8))
        let (r2, i2) = Spectrum.fft([1, 1, 1, 1])
        XCTAssertEqual(r2[0], 4, accuracy: 1e-12); XCTAssertEqual(r2[1], 0, accuracy: 1e-12); XCTAssertEqual(i2[1], 0, accuracy: 1e-12)
        let (r3, i3) = Spectrum.fft([0, 1, 0, -1])       // seno de un ciclo por bloque: energia en el compartimento 1
        XCTAssertEqual(i3[1], -2, accuracy: 1e-12); XCTAssertEqual(i3[3], 2, accuracy: 1e-12); XCTAssertEqual(r3[1], 0, accuracy: 1e-12)
    }

    func testFFTMatchesTheDirectDFT() {
        let x = (0..<16).map { sin(Double($0) * 0.7) + 0.3 * cos(Double($0) * 2.1) }
        let (re, im) = Spectrum.fft(x)
        for k in 0..<16 {
            var dr = 0.0, di = 0.0
            for (n, v) in x.enumerated() { let a = -2 * Double.pi * Double(k * n) / 16; dr += v * cos(a); di += v * sin(a) }
            XCTAssertEqual(re[k], dr, accuracy: 1e-9); XCTAssertEqual(im[k], di, accuracy: 1e-9)
        }
    }

    func testPeakFrequencyAndAmplitude() throws {
        for f in [440.0, 1000.0, 7350.5, 19000.0] {
            let mags = Spectrum.magnitudes(sine(f, amp: 0.5))
            let p = try XCTUnwrap(Spectrum.peak(mags, sampleRate: 48000))
            XCTAssertEqual(p.hz, f, accuracy: 3, "\(f) Hz")
            XCTAssertEqual(p.magnitude, 0.5, accuracy: 0.06, "amplitud de \(f) Hz")
        }
    }

    func testPeakIgnoresAnythingBelowMinHzAndSilence() throws {
        let mags = Spectrum.magnitudes(sine(200) .enumerated().map { $1 + 0.05 * sin(2 * .pi * 15000 * Double($0) / 48000) })
        XCTAssertEqual(try XCTUnwrap(Spectrum.peak(mags, sampleRate: 48000, minHz: 10000)).hz, 15000, accuracy: 3)
        XCTAssertNil(Spectrum.peak(Spectrum.magnitudes([Double](repeating: 0, count: 1024)), sampleRate: 48000))
    }

    func testBandLevelSeparatesBands() {
        let mags = Spectrum.magnitudes(sine(18500, amp: 0.4))
        XCTAssertEqual(Spectrum.bandLevel(mags, sampleRate: 48000, from: 18000, to: 19000), 0.4, accuracy: 0.05)
        XCTAssertLessThan(Spectrum.bandLevel(mags, sampleRate: 48000, from: 1000, to: 5000), 0.005)
        XCTAssertLessThan(Spectrum.bandLevel(mags, sampleRate: 48000, from: 19500, to: 22000), 0.01, "fuera de la banda, casi nada")
        XCTAssertEqual(Spectrum.bandLevel(mags, sampleRate: 48000, from: 5000, to: 1000), 0)
    }

    func testLevelMath() {
        XCTAssertEqual(Level.dBFS(rms: 1), 0, accuracy: 1e-12); XCTAssertEqual(Level.dBFS(rms: 0.1), -20, accuracy: 1e-9)
        XCTAssertEqual(Level.dBFS(rms: 0), -180)
        XCTAssertEqual(Level.rms([1, -1, 1, -1]), 1, accuracy: 1e-12); XCTAssertEqual(Level.rms([]), 0)
        XCTAssertEqual(Level.rms([0.5, 0.5]), 0.5, accuracy: 1e-7)
    }

    func testDtmfFrequencyTable() {
        XCTAssertEqual(Dtmf.frequencies(for: "1")?.low, 697); XCTAssertEqual(Dtmf.frequencies(for: "1")?.high, 1209)
        XCTAssertEqual(Dtmf.frequencies(for: "5")?.low, 770); XCTAssertEqual(Dtmf.frequencies(for: "5")?.high, 1336)
        XCTAssertEqual(Dtmf.frequencies(for: "#")?.low, 941); XCTAssertEqual(Dtmf.frequencies(for: "#")?.high, 1477)
        XCTAssertEqual(Dtmf.frequencies(for: "d")?.high, 1633, "minusculas tambien")
        XCTAssertNil(Dtmf.frequencies(for: "x"))
    }

    func testDtmfRoundTripForEveryKey() {
        for key in "123A456B789C*0#D" {
            let samples = Dtmf.tone(for: key, duration: 0.1, sampleRate: 8000).map(Double.init)
            XCTAssertEqual(Dtmf.detect(samples, sampleRate: 8000), key, "tecla \(key)")
        }
    }

    func testDtmfRejectsNoiseSilenceAndSingleTones() {
        XCTAssertNil(Dtmf.detect([Double](repeating: 0, count: 800), sampleRate: 8000))
        XCTAssertNil(Dtmf.detect(sine(697, n: 800, rate: 8000, amp: 0.4), sampleRate: 8000), "un solo tono no es una tecla")
        XCTAssertNil(Dtmf.detect(sine(1000, n: 800, rate: 8000, amp: 0.4), sampleRate: 8000))
        XCTAssertNil(Dtmf.detect([], sampleRate: 8000))
        var g = SystemRandomNumberGenerator()
        XCTAssertNil(Dtmf.detect((0..<800).map { _ in Double.random(in: -0.4...0.4, using: &g) }, sampleRate: 8000))
    }

    func testGoertzelMatchesTheFFTBin() {
        let x = sine(1000, n: 480, rate: 48000)
        let onTone = Dtmf.goertzel(x, frequency: 1000, sampleRate: 48000)
        let off = Dtmf.goertzel(x, frequency: 3000, sampleRate: 48000)
        XCTAssertGreaterThan(onTone, off * 1e6)
    }

    func testMorseEncodeDecode() {
        XCTAssertEqual(Morse.encode("SOS"), "... --- ...")
        XCTAssertEqual(Morse.encode("hola mundo"), ".... --- .-.. .- / -- ..- -. -.. ---")
        XCTAssertEqual(Morse.encode("a  b"), ".- / -...")
        XCTAssertEqual(Morse.encode("ñ 5"), ".....", "lo que no tiene codigo se ignora, y la palabra que se queda vacia desaparece")
        XCTAssertEqual(Morse.encode(""), "")
        XCTAssertEqual(Morse.decode("... --- ..."), "SOS"); XCTAssertEqual(Morse.decode(".... --- .-.. .- / -- ..- -. -.. ---"), "HOLA MUNDO")
        XCTAssertEqual(Morse.decode(Morse.encode("PING 42, OK?")), "PING 42, OK?")
        XCTAssertEqual(Set(Morse.table.values).count, Morse.table.count, "sin codigos repetidos")
    }

    func testMorseTimingsFollowTheStandard() {
        let s = Morse.schedule("... --- ...")
        XCTAssertEqual(s.filter { $0.on }.map(\.units), [1, 1, 1, 3, 3, 3, 1, 1, 1])
        XCTAssertEqual(s.filter { !$0.on }.map(\.units), [1, 1, 3, 1, 1, 3, 1, 1])    // 1 entre simbolos, 3 entre letras
        let words = Morse.schedule(". / .")
        XCTAssertEqual(words.map(\.units), [1, 7, 1]); XCTAssertEqual(words.map(\.on), [true, false, true])
        XCTAssertTrue(Morse.schedule("").isEmpty)
    }

    func testMetalDetectorIgnoresSlowDriftAndReactsToASpike() {
        var d = MetalDetector()
        XCTAssertEqual(d.feed(microTesla: 48), 0)
        for _ in 0..<200 { XCTAssertLessThan(d.feed(microTesla: 48), 0.01) }
        XCTAssertGreaterThan(d.feed(microTesla: 88), 0.9, "40 µT de salto llena la barra")
        XCTAssertLessThan(d.feed(microTesla: 58) , 0.4)
        d.reset(); XCTAssertNil(d.baseline)
        var slow = MetalDetector()
        _ = slow.feed(microTesla: 40)
        var peak = 0.0
        for i in 1...400 { peak = max(peak, slow.feed(microTesla: 40 + Double(i) * 0.02)) }    // deriva lenta de 8 µT en 400 lecturas
        XCTAssertLessThan(peak, 0.35)
    }

    func testBarometer() {
        XCTAssertEqual(Barometer.altitude(pressure: 1013.25, reference: 1013.25), 0, accuracy: 1e-9)
        XCTAssertEqual(Barometer.altitude(pressure: 899.0, reference: 1013.25), 1000, accuracy: 15)     // ~ 1000 m
        XCTAssertLessThan(Barometer.altitude(pressure: 1020, reference: 1013.25), 0)
        let altitude = Barometer.altitude(pressure: 950, reference: 1013.25)
        XCTAssertEqual(Barometer.seaLevel(pressure: 950, altitude: altitude), 1013.25, accuracy: 1e-6, "ida y vuelta")
    }

    func testCompassLabels() {
        XCTAssertEqual(Compass.label(degrees: 0), "N"); XCTAssertEqual(Compass.label(degrees: 44), "NE"); XCTAssertEqual(Compass.label(degrees: 90), "E")
        XCTAssertEqual(Compass.label(degrees: 180), "S"); XCTAssertEqual(Compass.label(degrees: 270), "O"); XCTAssertEqual(Compass.label(degrees: 359), "N")
        XCTAssertEqual(Compass.label(degrees: 22.4), "N"); XCTAssertEqual(Compass.label(degrees: 22.6), "NE")
        XCTAssertEqual(Compass.label(degrees: -90), "O"); XCTAssertEqual(Compass.label(degrees: 720), "N")
    }
}
