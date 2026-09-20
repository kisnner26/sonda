import Foundation

public enum Spectrum {
    /// FFT de radix 2 sobre muestras reales. `samples.count` tiene que ser potencia de dos.
    public static func fft(_ samples: [Double]) -> (re: [Double], im: [Double]) {
        let n = samples.count
        precondition(n > 0 && n & (n - 1) == 0, "el tamaño tiene que ser potencia de dos")
        var re = samples, im = [Double](repeating: 0, count: n)
        var j = 0
        for i in 1..<n {                           // permutacion por inversion de bits
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { re.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let ang = -2 * Double.pi / Double(len)
            let wr = cos(ang), wi = sin(ang)
            var i = 0
            while i < n {
                var cr = 1.0, ci = 0.0
                for k in 0..<len / 2 {
                    let a = i + k, b = i + k + len / 2
                    let tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                    (cr, ci) = (cr * wr - ci * wi, cr * wi + ci * wr)
                }
                i += len
            }
            len <<= 1
        }
        return (re, im)
    }

    public static func hann(_ n: Int) -> [Double] { (0..<n).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n - 1)) } }

    /// magnitud (amplitud pico normalizada) de los n/2 primeros compartimentos, tras aplicar una ventana de Hann.
    public static func magnitudes(_ samples: [Double]) -> [Double] {
        let n = samples.count
        let w = hann(n)
        let gain = w.reduce(0, +) / 2                       // ganancia coherente de la ventana
        let (re, im) = fft(zip(samples, w).map { $0 * $1 })
        return (0..<n / 2).map { ($0 == 0 ? 0.5 : 1) * (re[$0] * re[$0] + im[$0] * im[$0]).squareRoot() / gain }
    }

    /// frecuencia del pico mas alto (Hz), con interpolacion parabolica entre compartimentos vecinos.
    public static func peak(_ mags: [Double], sampleRate: Double, minHz: Double = 0) -> (hz: Double, magnitude: Double)? {
        let n = mags.count * 2
        let first = max(1, Int(minHz / sampleRate * Double(n)))
        guard first < mags.count - 1, let k = (first..<mags.count - 1).max(by: { mags[$0] < mags[$1] }), mags[k] > 0 else { return nil }
        let a = mags[k - 1], b = mags[k], c = mags[k + 1]
        let denom = a - 2 * b + c
        let shift = denom == 0 ? 0 : 0.5 * (a - c) / denom
        // la amplitud tambien se interpola: una senal entre dos compartimentos se reparte y el maximo de uno solo se queda corto
        return ((Double(k) + shift) * sampleRate / Double(n), b - 0.25 * (a - c) * shift)
    }

    /// magnitud maxima entre dos frecuencias, en la misma escala que `magnitudes`.
    public static func bandLevel(_ mags: [Double], sampleRate: Double, from: Double, to: Double) -> Double {
        let n = Double(mags.count * 2)
        let lo = max(0, Int(from / sampleRate * n)), hi = min(mags.count - 1, Int(to / sampleRate * n))
        guard lo <= hi else { return 0 }
        return mags[lo...hi].max() ?? 0
    }
}

public enum Level {
    /// nivel relativo en dB respecto a fondo de escala (0 dBFS = onda cuadrada maxima). Sin calibrar: no son dB SPL reales.
    public static func dBFS(rms: Double) -> Double { rms <= 1e-9 ? -180 : 20 * log10(rms) }
    public static func rms(_ samples: [Float]) -> Double {
        samples.isEmpty ? 0 : (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }
}

public enum Dtmf {
    public static let rows: [Double] = [697, 770, 852, 941]
    public static let columns: [Double] = [1209, 1336, 1477, 1633]
    static let keys: [[Character]] = [["1", "2", "3", "A"], ["4", "5", "6", "B"], ["7", "8", "9", "C"], ["*", "0", "#", "D"]]

    public static func frequencies(for key: Character) -> (low: Double, high: Double)? {
        for (r, row) in keys.enumerated() { if let c = row.firstIndex(of: Character(key.uppercased())) { return (rows[r], columns[c]) } }
        return nil
    }

    /// potencia de una frecuencia concreta en un bloque (algoritmo de Goertzel).
    public static func goertzel(_ samples: [Double], frequency: Double, sampleRate: Double) -> Double {
        let k = 2 * cos(2 * .pi * frequency / sampleRate)
        var s1 = 0.0, s2 = 0.0
        for x in samples { let s = x + k * s1 - s2; s2 = s1; s1 = s }
        return s1 * s1 + s2 * s2 - k * s1 * s2
    }

    /// la tecla de un bloque de audio, o nil si no hay dos tonos claros y separados del resto.
    public static func detect(_ samples: [Double], sampleRate: Double, minPower: Double = 1e-3) -> Character? {
        guard !samples.isEmpty else { return nil }
        let norm = Double(samples.count * samples.count) / 4
        let low = rows.map { goertzel(samples, frequency: $0, sampleRate: sampleRate) / norm }
        let high = columns.map { goertzel(samples, frequency: $0, sampleRate: sampleRate) / norm }
        guard let r = low.indices.max(by: { low[$0] < low[$1] }), let c = high.indices.max(by: { high[$0] < high[$1] }),
              low[r] > minPower, high[c] > minPower else { return nil }
        // el ganador tiene que destacar sobre los otros tonos de su grupo
        func dominant(_ p: [Double], _ i: Int) -> Bool { p.indices.allSatisfy { $0 == i || p[i] > p[$0] * 4 } }
        return dominant(low, r) && dominant(high, c) ? keys[r][c] : nil
    }

    public static func tone(for key: Character, duration: Double, sampleRate: Double, amplitude: Double = 0.4) -> [Float] {
        guard let f = frequencies(for: key) else { return [] }
        return (0..<Int(duration * sampleRate)).map { i in
            let t = Double(i) / sampleRate
            return Float(amplitude * 0.5 * (sin(2 * .pi * f.low * t) + sin(2 * .pi * f.high * t)))
        }
    }
}

public enum Morse {
    public static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--", "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "/": "-..-.", "-": "-....-", "@": ".--.-.", "=": "-...-",
    ]

    /// "SOS" -> "... --- ..."; palabras separadas por " / ". Lo que no tiene código se ignora.
    public static func encode(_ text: String) -> String {
        text.uppercased().split(separator: " ", omittingEmptySubsequences: true).map { word in
            word.compactMap { table[$0] }.joined(separator: " ")
        }.filter { !$0.isEmpty }.joined(separator: " / ")
    }

    public static func decode(_ morse: String) -> String {
        let inverse = Dictionary(uniqueKeysWithValues: table.map { ($1, $0) })
        return morse.split(separator: "/", omittingEmptySubsequences: false).map { word in
            String(word.split(separator: " ").compactMap { inverse[String($0)] })
        }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// (encendido?, unidades): punto = 1, raya = 3, entre simbolos 1, entre letras 3, entre palabras 7.
    public static func schedule(_ morse: String) -> [(on: Bool, units: Int)] {
        var out: [(Bool, Int)] = []
        func gap(_ n: Int) { if let last = out.last, !last.0 { out[out.count - 1].1 = max(last.1, n) } else if !out.isEmpty { out.append((false, n)) } }
        for word in morse.split(separator: "/", omittingEmptySubsequences: true) {
            if !out.isEmpty { gap(7) }
            for letter in word.split(separator: " ", omittingEmptySubsequences: true) {
                if !out.isEmpty { gap(3) }
                for (i, symbol) in letter.enumerated() {
                    if i > 0 { out.append((false, 1)) }
                    out.append((true, symbol == "-" ? 3 : 1))
                }
            }
        }
        return out
    }
}
