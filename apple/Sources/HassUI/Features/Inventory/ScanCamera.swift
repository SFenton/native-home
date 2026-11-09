import Foundation
import HassCore
import Observation
import SwiftUI
#if os(iOS)
import AVFoundation
import UIKit
#endif

/// Runs the Add Item camera for ``ScanItemModel``: barcode detection on step 1, a still photo of the printed
/// date on step 2 (web `ScanItemCameraSheet` uses ZXing and a canvas grab; this uses AVFoundation).
///
/// Sources:
/// - `live`: the device's back camera.
/// - `simulated` (debug, `FENTON_SCAN_CAMERA=simulated`): a drawn viewfinder with a Simulate Scan button, so
///   journeys and screenshots can walk the whole flow on simulators, which have no camera.
/// - `unavailable`: no camera (simulator without the flag, macOS); the sheet says so and offers manual entry.
@MainActor
@Observable
final class ScanCameraController {
    enum Source: Equatable { case live, simulated, unavailable }

    let source: Source
    /// Barcode the simulated camera "reads" (`FENTON_GALLERY_BARCODE`, default the fixture's yogurt).
    let simulatedBarcode: String

    #if os(iOS)
    @ObservationIgnored let box = CaptureSessionBox()
    #endif

    init(source: Source = ScanCameraController.defaultSource,
         simulatedBarcode: String = ProcessInfo.processInfo.environment["FENTON_GALLERY_BARCODE"] ?? "0123456789012") {
        self.source = source
        self.simulatedBarcode = simulatedBarcode
    }

    static var defaultSource: Source {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FENTON_SCAN_CAMERA"] == "simulated" { return .simulated }
        #endif
        #if os(iOS) && !targetEnvironment(simulator)
        return AVCaptureDevice.default(for: .video) == nil ? .unavailable : .live
        #else
        return .unavailable
        #endif
    }

    static let unavailableMessage = "Camera unavailable. Enter the details manually."
    /// Whether the status is the camera-access-off refusal, which the sheet answers with an Open Settings button.
    static func offersSettings(_ status: ScanItemModel.CameraStatus) -> Bool {
        status == .failed(deniedMessage)
    }

    static let deniedMessage = "Camera access is off. Allow it in Settings, or enter the details manually."

    /// Starts the camera `model` wants, or stops it when it wants none.
    func sync(with model: ScanItemModel) async {
        guard let wanted = model.wantedCamera else {
            stop()
            return
        }
        model.cameraWillStart()
        switch source {
        case .unavailable:
            model.cameraDidFail(Self.unavailableMessage)
        case .simulated:
            model.cameraDidStart()
        case .live:
            #if os(iOS)
            await startLive(barcodes: wanted == .barcode, model: model)
            #else
            model.cameraDidFail(Self.unavailableMessage)
            #endif
        }
    }

    /// Stops the camera.
    func stop() {
        #if os(iOS)
        if source == .live { box.stop() }
        #endif
    }

    /// The simulated camera's Simulate Scan / capture button.
    func simulate(on model: ScanItemModel) async {
        switch model.step {
        case .barcode: await model.didDetectBarcode(simulatedBarcode)
        case .expiry: await model.readExpiry(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        default: break
        }
    }

    /// Photographs the printed date and sends it to EverShelf.
    func captureExpiry(for model: ScanItemModel) async {
        switch source {
        case .simulated:
            await simulate(on: model)
        case .live:
            #if os(iOS)
            do {
                let jpeg = try await box.capturePhoto()
                box.stop()
                await model.readExpiry(jpeg: jpeg)
            } catch {
                model.cameraDidFail(Self.unavailableMessage)
            }
            #endif
        case .unavailable:
            break
        }
    }

    #if os(iOS)
    private func startLive(barcodes: Bool, model: ScanItemModel) async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                model.cameraDidFail(Self.deniedMessage)
                return
            }
        default:
            model.cameraDidFail(Self.deniedMessage)
            return
        }
        box.onBarcode = { [weak model] code in
            Task { @MainActor in await model?.didDetectBarcode(code) }
        }
        do {
            try await box.start(barcodes: barcodes)
            guard !Task.isCancelled else { return }
            model.cameraDidStart()
        } catch {
            model.cameraDidFail(Self.unavailableMessage)
        }
    }
    #endif
}

#if os(iOS)
/// The capture session, configured and driven on its own queue.
final class CaptureSessionBox: NSObject, @unchecked Sendable, AVCaptureMetadataOutputObjectsDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    /// Called on the main actor with each detected code; set before ``start(barcodes:)``.
    var onBarcode: (@Sendable (String) -> Void)?

    private let queue = DispatchQueue(label: "fenton.scan.camera")
    private let metadata = AVCaptureMetadataOutput()
    private let photo = AVCapturePhotoOutput()
    private var configured = false
    private var photoContinuation: CheckedContinuation<Data, Error>?

    /// Grocery barcodes: EAN/UPC plus the common case and shelf codes.
    private static let symbologies: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .code39, .itf14]

    struct CaptureError: Error {}

    func start(barcodes: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.configure()
                    let types = barcodes ? Self.symbologies.filter(self.metadata.availableMetadataObjectTypes.contains) : []
                    self.metadata.metadataObjectTypes = types
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            queue.async {
                guard self.session.isRunning, self.photoContinuation == nil else {
                    continuation.resume(throwing: CaptureError())
                    return
                }
                self.photoContinuation = continuation
                self.photo.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
            }
        }
    }

    private func configure() throws {
        guard !configured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video) else { throw CaptureError() }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(metadata), session.canAddOutput(photo) else { throw CaptureError() }
        session.addInput(input)
        session.addOutput(metadata)
        session.addOutput(photo)
        metadata.setMetadataObjectsDelegate(self, queue: queue)
        if device.isFocusModeSupported(.continuousAutoFocus) {
            try? device.lockForConfiguration()
            device.focusMode = .continuousAutoFocus
            device.unlockForConfiguration()
        }
        configured = true
    }

    // MARK: Delegates

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = objects.lazy.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first,
              let onBarcode else { return }
        DispatchQueue.main.async { onBarcode(code) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let continuation = photoContinuation
        photoContinuation = nil
        guard error == nil, let data = photo.fileDataRepresentation() else {
            continuation?.resume(throwing: error ?? CaptureError())
            return
        }
        continuation?.resume(returning: Self.downscaled(data))
    }

    /// A full-resolution photo is several MB; EverShelf only needs the date legible.
    static func downscaled(_ data: Data, maxSide: CGFloat = 1600) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return data }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8) ?? data
    }
}

/// Live preview of a capture session.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}
#endif
