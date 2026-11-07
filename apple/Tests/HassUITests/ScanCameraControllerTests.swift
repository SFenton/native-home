import Foundation
@testable import HassCore
@testable import HassUI
import Testing

/// The Add Item camera's three sources and what each does to the scan model: a camera-less device says so, the simulated
/// camera walks the whole flow, and the Simulate Scan button reads a barcode and then a date.
@MainActor
struct ScanCameraControllerTests {
    private let calendar: InventoryCalendar = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = utc.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!
        return InventoryCalendar(calendar: utc, now: { now })
    }()

    private func makeModel() -> ScanItemModel {
        let server = EverShelfFixtureServer(rows: [])
        let model = ScanItemModel(space: .fridge, client: EverShelfClient(caller: server), calendar: calendar)
        model.makeIdempotencyKey = { "key-1" }
        return model
    }

    @Test func noCameraSaysSoAndOffersManualEntry() async {
        let model = makeModel()
        let controller = ScanCameraController(source: .unavailable)
        await controller.sync(with: model)
        #expect(model.cameraStatus == .failed(ScanCameraController.unavailableMessage))
        #expect(ScanCameraController.unavailableMessage == "Camera unavailable. Enter the details manually.")
        #expect(!ScanCameraController.offersSettings(model.cameraStatus), "Only the permission refusal offers Settings")
        #expect(ScanCameraController.offersSettings(.failed(ScanCameraController.deniedMessage)))
        #expect(!ScanCameraController.offersSettings(.ready))
        await controller.captureExpiry(for: model) // Nothing to photograph: nothing happens.
        #expect(model.expiryStatus == .idle)
    }

    @Test func theSimulatedCameraStartsAndIsStoppedWhenTheModelWantsNone() async {
        let model = makeModel()
        let controller = ScanCameraController(source: .simulated, simulatedBarcode: "0123456789012")
        await controller.sync(with: model)
        #expect(model.cameraStatus == .ready && model.lookupStatus == .scanning)
        model.enterNameManually() // Hides the barcode camera.
        #expect(model.wantedCamera == nil)
        await controller.sync(with: model)
        controller.stop() // Harmless for a source with no hardware.
        #expect(model.cameraStatus == .ready || model.cameraStatus == .idle)
    }

    @Test func simulateScanReadsTheBarcodeThenTheDate() async {
        let model = makeModel()
        let controller = ScanCameraController(source: .simulated, simulatedBarcode: "0123456789012")
        await controller.simulate(on: model)
        #expect(model.detectedBarcode == "0123456789012")
        #expect(model.name == "Greek Yogurt", "The fixture server knows this barcode")

        model.goToExpiryStep()
        await controller.captureExpiry(for: model)
        #expect(model.expiryDate == "2030-01-15")
        #expect(model.expiryStatus == .found("2030-01-15"))

        model.goToReviewStep()
        await controller.simulate(on: model) // Review has no camera: nothing happens.
        #expect(model.step == .review && model.expiryDate == "2030-01-15")
    }

    @Test func theDefaultSourceHasNoCameraOnTheHost() {
        #expect(ScanCameraController.defaultSource != .live)
    }

    @Test func theSimulatedBarcodeDefaultsToTheFixtureYogurt() {
        let controller = ScanCameraController(source: .simulated)
        #expect(controller.simulatedBarcode == (ProcessInfo.processInfo.environment["FENTON_GALLERY_BARCODE"] ?? "0123456789012"))
        #expect(controller.source == .simulated)
    }
}
