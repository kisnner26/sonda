import AVFoundation
import Foundation
import Observation
import SondaCore
import SwiftUI
import UIKit

struct ScanRecord: Identifiable, Equatable {
    let id = UUID()
    let raw: String
    let payload: ScanPayload
    let symbology: String
    let date: Date
}

/// camara para leer codigos (QR y de barras). Todo se decodifica en el telefono.
@MainActor
@Observable
final class CodeScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private(set) var records: [ScanRecord] = []
    private(set) var denied = false
    private(set) var running = false
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private var configured = false

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { denied = true; return }
        denied = false
        if !configured { configure() }
        DispatchQueue.global(qos: .userInitiated).async { [session] in if !session.isRunning { session.startRunning() } }
        running = true
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in if session.isRunning { session.stopRunning() } }
        running = false
    }

    func clear() { records = [] }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr, .ean13, .ean8, .upce, .code128, .code39, .code93, .pdf417, .aztec, .dataMatrix, .itf14, .interleaved2of5, .codabar].filter { output.availableMetadataObjectTypes.contains($0) }
        configured = true
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        MainActor.assumeIsolated {
            for case let code as AVMetadataMachineReadableCodeObject in objects {
                guard let raw = code.stringValue, records.first?.raw != raw else { continue }
                records.insert(ScanRecord(raw: raw, payload: ScanParser.parse(raw), symbology: code.type.rawValue.replacingOccurrences(of: "org.iso.", with: "").replacingOccurrences(of: "org.gs1.", with: ""), date: Date()), at: 0)
                if records.count > 50 { records.removeLast() }
                Haptics.success()
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView { let v = PreviewView(); v.previewLayer.session = session; v.previewLayer.videoGravity = .resizeAspectFill; return v }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// detector de destellos infrarrojos: mide el brillo de cada fotograma y se lo pasa a `IRPulseDetector`.
@MainActor
@Observable
final class IRScanner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private(set) var brightness: [Double] = []
    private(set) var burstCount = 0
    private(set) var lit = false
    private(set) var lastBurst: Date?
    private(set) var fps = 0.0
    private(set) var denied = false
    private(set) var front = false
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private var detector = IRPulseDetector()
    @ObservationIgnored private var input: AVCaptureDeviceInput?
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var frameClock = Date()
    @ObservationIgnored private var startTime: Double?

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { denied = true; return }
        denied = false
        if !configured { configure(front: false) }
        DispatchQueue.global(qos: .userInitiated).async { [session] in if !session.isRunning { session.startRunning() } }
    }

    func stop() { DispatchQueue.global(qos: .userInitiated).async { [session] in if session.isRunning { session.stopRunning() } } }

    func reset() { detector.reset(); burstCount = 0; brightness = []; lastBurst = nil }

    func flip() { configure(front: !front); reset() }

    private func configure(front useFront: Bool) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480
        if let old = input { session.removeInput(old) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: useFront ? .front : .back) ?? AVCaptureDevice.default(for: .video),
              let new = try? AVCaptureDeviceInput(device: device), session.canAddInput(new) else { return }
        session.addInput(new); input = new; front = useFront
        // el mayor numero de fotogramas por segundo que admita: mas fotogramas, destellos mas cortos detectables
        if let best = device.formats.filter({ $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 } && CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <= 1280 }).first,
           (try? device.lockForConfiguration()) != nil {
            device.activeFormat = best
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60); device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
            device.unlockForConfiguration()
        }
        if !configured {
            let out = AVCaptureVideoDataOutput()
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sonda.ir"))
            if session.canAddOutput(out) { session.addOutput(out) }
            configured = true
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { return }
        let w = CVPixelBufferGetWidth(pixels), h = CVPixelBufferGetHeight(pixels), rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        var sum = 0.0, n = 0.0
        // la zona central (un tercio) y una muestra de cada 4 pixeles: el destello de un mando suele llenar esa zona
        for y in stride(from: h / 3, to: 2 * h / 3, by: 4) {
            for x in stride(from: w / 3, to: 2 * w / 3, by: 4) {
                let p = base + y * rowBytes + x * 4
                sum += (Double(p[0]) + Double(p[2])) / 2      // azul y rojo: el infrarrojo se ve violeta
                n += 1
            }
        }
        let value = sum / max(1, n) / 255
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        Task { @MainActor [weak self] in self?.feed(value, at: t) }
    }

    private func feed(_ value: Double, at t: Double) {
        if startTime == nil { startTime = t }
        let before = detector.bursts.count
        lit = detector.feed(brightness: value, at: t)
        brightness.append(value); if brightness.count > 180 { brightness.removeFirst() }
        if detector.bursts.count > before { burstCount = detector.bursts.count; lastBurst = Date(); Haptics.tick() }
        frames += 1
        let dt = Date().timeIntervalSince(frameClock)
        if dt >= 1 { fps = Double(frames) / dt; frames = 0; frameClock = Date() }
    }
}
