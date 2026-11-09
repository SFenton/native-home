import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Add Item sheet's review step: the quantity stepper, the add error, the lookup notice and the permission shortcut.
@MainActor
final class UKHostedSharedScanTests: DemoHouseTestCase {
    private func sheet(source: ScanCameraController.Source = .unavailable) -> (ScanItemModel, UKScanItemViewController, UIWindow) {
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(10)
        let model = ScanItemModel(space: .pantry, client: EverShelfClient(caller: server))
        let camera = ScanCameraController(source: source)
        let page = UKScanItemViewController(model: model, camera: camera, context: UKGalleryChrome.context().with { $0.surface = .sheet }) {}
        let modal = UKHassModalController(root: page, options: UKHassModalOptions(title: "Add Item"))
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 2000))
        FeatureHost.settle(0.5)
        return (model, page, window)
    }

    func testTheStepperAndTheKeyboardBothSetTheQuantityOnTheReviewStep() {
        let (model, page, window) = sheet()
        defer { window.isHidden = true }
        model.enterNameManually()
        model.setName("Oat Milk")
        model.goToReviewStep()
        FeatureHost.settle(0.5)
        let stepper = FeatureHost.view("scan.quantity.stepper", in: page.view) as? UIStepper
        XCTAssertNotNil(stepper, "the review step has a quantity stepper")
        stepper?.value = 4
        stepper?.sendActions(for: .valueChanged)
        XCTAssertEqual(model.quantityText, "4", "the stepper writes the quantity")

        let field = HostedPage.descendants(of: page.view).compactMap { $0 as? UITextField }.first { $0.accessibilityIdentifier == "scan.quantity" }
        XCTAssertNotNil(field)
        field?.text = "0"
        field?.sendActions(for: .editingChanged)
        XCTAssertEqual(model.quantityText, "0")
        field?.sendActions(for: .editingDidEnd)
        FeatureHost.settle(0.3)
        XCTAssertNotNil(model.quantityError, "submitting zero shows the quantity error")
    }

    func testAnAddThatCannotStartShowsItsErrorOnTheForm() async {
        let (model, page, window) = sheet()
        defer { window.isHidden = true }
        model.enterNameManually()
        model.goToReviewStep()
        await model.add()
        await FeatureHost.settleAsync(0.5)
        let message = model.addError
        XCTAssertNotNil(message, "an add with no name fails")
        XCTAssertNotNil(FeatureHost.view("scan.addError", in: page.view), "and the error sits on the review page")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains { $0 == message || $0.contains("Product name is required") })
    }

    func testAnUnknownBarcodeIsSaidUnderTheCamera() async {
        let (model, page, window) = sheet(source: .simulated)
        defer { window.isHidden = true }
        await model.didDetectBarcode("0000000000000")
        await FeatureHost.settleAsync(0.8)
        guard let message = model.statusMessage else { return XCTFail("a barcode the server cannot place leaves a notice; lookup was \(model.lookupStatus)") }
        XCTAssertNotNil(FeatureHost.view("scan.status", in: page.view), "the notice is on the page")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains { $0.contains(message) }, "it reads \(message)")
    }
}
