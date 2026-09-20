import SwiftUI
import UniformTypeIdentifiers
import SondaCore

private enum Tool: String, Hashable { case hex, hash, convert, password, random }

struct ToolsView: View {
    var body: some View {
        Screen(title: "herramientas", subtitle: "las pequeñas utilidades de un banco de trabajo") {
            VStack(spacing: 0) {
                link(.hex, .toolbox, "hex", "abrir un archivo y ver sus bytes")
                link(.hash, .target, "hashes", "md5, sha y crc de un texto o archivo")
                link(.convert, .leaf, "conversiones", "texto, hex, base64, binario, url")
                link(.password, .sliders, "contraseñas", "generar y medir su entropía")
                link(.random, .wave, "azar", "dados, moneda y números")
            }
        }
        .navigationDestination(for: Tool.self) { t in
            switch t {
            case .hex: HexViewer()
            case .hash: HashView()
            case .convert: ConvertView()
            case .password: PasswordView()
            case .random: RandomView()
            }
        }
    }

    private func link(_ t: Tool, _ icon: IconKind, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        NavigationLink(value: t) { ModuleRow(icon: icon, title: title, detail: detail) }.buttonStyle(.plain)
    }
}

private struct Field: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var mono = false
    var lines = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Caption(label)
            TextField("", text: $text, axis: .vertical).lineLimit(lines...max(lines, 6))
                .font(mono ? .system(size: 15, design: .monospaced) : .serif(18)).textInputAutocapitalization(.never).autocorrectionDisabled()
            Hairline()
        }
    }
}

// MARK: hex

private struct HexViewer: View {
    @State private var data = Data()
    @State private var name = ""
    @State private var page = 0
    @State private var importing = false
    @State private var error: String?
    private let pageSize = 2048           // 128 filas de 16 bytes

    private var pages: Int { max(1, (data.count + pageSize - 1) / pageSize) }

    var body: some View {
        Screen(title: "hex") {
            Button(name.isEmpty ? "abrir un archivo" : "abrir otro archivo") { importing = true }.buttonStyle(InkButtonStyle())
            if let error { Text(error).font(.serif(14, italic: true)).foregroundStyle(Palette.rose) }
            if !data.isEmpty {
                Caption(verbatim: "\(name) · \(data.count.formatted()) bytes")
                let start = page * pageSize
                let lines = Hex.dump(data.subdata(in: start..<min(data.count, start + pageSize)), startOffset: start)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(lines.joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.ink).textSelection(.enabled).fixedSize()
                }
                HStack(spacing: 22) {
                    Button("‹ anterior") { page = max(0, page - 1) }.buttonStyle(QuietButtonStyle()).disabled(page == 0)
                    Caption(verbatim: "\(page + 1) / \(pages)")
                    Button("siguiente ›") { page = min(pages - 1, page + 1) }.buttonStyle(QuietButtonStyle()).disabled(page >= pages - 1)
                }
            } else {
                Text("se leen los primeros 4 MB del archivo. No se modifica ni se sube.").font(.serif(14, italic: true)).foregroundStyle(Palette.mid)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do { let h = try FileHandle(forReadingFrom: url); data = try h.read(upToCount: 4 << 20) ?? Data(); name = url.lastPathComponent; page = 0; error = nil }
                catch { self.error = error.localizedDescription }
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}

// MARK: hashes

private struct HashView: View {
    @State private var text = ""
    @State private var fileData: Data?
    @State private var fileName = ""
    @State private var expected = ""
    @State private var importing = false

    private var input: Data { fileData ?? Data(text.utf8) }

    var body: some View {
        Screen(title: "hashes") {
            if fileData == nil { Field(label: "texto", text: $text, lines: 2) }
            else { Caption(verbatim: "\(fileName) · \(input.count.formatted()) bytes"); Button("usar texto") { fileData = nil }.buttonStyle(QuietButtonStyle()) }
            Button("hashear un archivo") { importing = true }.buttonStyle(QuietButtonStyle())
            ForEach(Hashing.Algorithm.allCases, id: \.self) { a in
                let hex = Hashing.hex(input, a)
                VStack(alignment: .leading, spacing: 2) {
                    Caption(verbatim: a.rawValue, color: !expected.isEmpty && hex == expected.lowercased().trimmingCharacters(in: .whitespaces) ? Palette.moss : Palette.mid)
                    Text(hex).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.ink).textSelection(.enabled)
                }
            }
            Field(label: "comparar con un hash conocido", text: $expected, mono: true)
            if !expected.isEmpty {
                let match = Hashing.Algorithm.allCases.first { Hashing.hex(input, $0) == expected.lowercased().trimmingCharacters(in: .whitespaces) }
                Text(match.map { "coincide con \($0.rawValue)" } ?? "no coincide con ninguno").font(.serif(16, italic: true)).foregroundStyle(match == nil ? Palette.rose : Palette.moss)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url, options: .mappedIfSafe) { fileData = d; fileName = url.lastPathComponent }
        }
    }
}

// MARK: conversiones

private struct ConvertView: View {
    @State private var input = ""
    @State private var from = Convert.Format.text

    var body: some View {
        Screen(title: "conversiones") {
            Picker("de", selection: $from) { ForEach(Convert.Format.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).tint(Palette.ink)
            Field(label: "entrada", text: $input, mono: from != .text, lines: 3)
            if input.isEmpty {
                Text("escribe algo y se muestra en todos los formatos.").font(.serif(14, italic: true)).foregroundStyle(Palette.mid)
            } else if let data = try? Convert.bytes(from: input, format: from) {
                ForEach(Convert.Format.allCases.filter { $0 != from }, id: \.self) { f in
                    VStack(alignment: .leading, spacing: 2) {
                        Caption(verbatim: f.rawValue)
                        Text(Convert.string(from: data, format: f)).font(.system(size: 14, design: .monospaced)).foregroundStyle(Palette.ink).textSelection(.enabled)
                    }
                }
            } else {
                Text("eso no es válido como \(from.rawValue).").font(.serif(15, italic: true)).foregroundStyle(Palette.rose)
            }
        }
    }
}

// MARK: contraseñas

private struct PasswordView: View {
    @State private var spec = PasswordSpec()
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        Screen(title: "contraseñas") {
            Text(password.isEmpty ? "—" : password).font(.system(size: 20, design: .monospaced)).foregroundStyle(Palette.ink).textSelection(.enabled).lineLimit(4)
            HStack(spacing: 22) {
                Button("generar") { generate() }.buttonStyle(InkButtonStyle())
                Button("copiar") { UIPasteboard.general.string = password; Haptics.tap() }.buttonStyle(QuietButtonStyle()).disabled(password.isEmpty)
            }
            if let error { Text(error).font(.serif(14, italic: true)).foregroundStyle(Palette.rose) }
            VStack(alignment: .leading, spacing: 2) {
                Caption(verbatim: String(localized: "longitud") + " · \(spec.length)")
                Slider(value: Binding(get: { Double(spec.length) }, set: { spec.length = Int($0); generate() }), in: 4...64, step: 1).tint(Palette.ink)
            }
            Toggle(isOn: $spec.lower) { Caption("minúsculas") }.tint(Palette.moss)
            Toggle(isOn: $spec.upper) { Caption("mayúsculas") }.tint(Palette.moss)
            Toggle(isOn: $spec.digits) { Caption("números") }.tint(Palette.moss)
            Toggle(isOn: $spec.symbols) { Caption("símbolos") }.tint(Palette.moss)
            Toggle(isOn: $spec.avoidAmbiguous) { Caption("evitar O 0 l 1") }.tint(Palette.moss)
            Metric(label: "entropía", value: String(format: "%.0f", spec.entropyBits), unit: "bits")
            Text(strength).font(.serif(14, italic: true)).foregroundStyle(spec.entropyBits < 60 ? Palette.rose : Palette.moss)
        }
        .onChange(of: spec) { _, _ in generate() }
        .onAppear { generate() }
    }

    private var strength: LocalizedStringKey {
        spec.entropyBits < 40 ? "débil" : spec.entropyBits < 60 ? "aceptable para cuentas sin importancia" : spec.entropyBits < 90 ? "fuerte" : "muy fuerte"
    }

    private func generate() {
        var g = SystemRandomNumberGenerator()
        do { password = try Password.generate(spec, using: &g); error = nil }
        catch { password = ""; self.error = "elige al menos un tipo de caracteres y una longitud mayor." }
    }
}

// MARK: azar

private struct RandomView: View {
    @State private var result = "—"
    @State private var detail = ""
    @State private var max = "100"
    @State private var options = ""

    var body: some View {
        Screen(title: "azar") {
            Text(result).font(.serif(60)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity)
            Text(detail).font(.serif(15, italic: true)).foregroundStyle(Palette.mid).frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                ForEach([4, 6, 8, 10, 12, 20], id: \.self) { n in
                    Button("d\(n)") { roll(n) }.buttonStyle(QuietButtonStyle())
                }
            }.frame(maxWidth: .infinity)
            Button("moneda") { result = Bool.random() ? "cara" : "cruz"; detail = "moneda"; Haptics.tap() }.buttonStyle(InkButtonStyle()).frame(maxWidth: .infinity)
            Hairline()
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) { Caption("del 1 al"); TextField("", text: $max).font(.serif(20)).keyboardType(.numberPad); Hairline() }.frame(width: 120)
                Button("número") { if let m = Int(max), m >= 1 { roll(m) } }.buttonStyle(InkButtonStyle())
            }
            Field(label: "elegir uno (separados por comas)", text: $options)
            Button("elegir") { let items = options.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }; if let p = items.randomElement() { result = p; detail = "de \(items.count)"; Haptics.tap() } }.buttonStyle(QuietButtonStyle())
        }
    }

    private func roll(_ n: Int) { result = "\(Int.random(in: 1...n))"; detail = "1 – \(n)"; Haptics.tap() }
}
