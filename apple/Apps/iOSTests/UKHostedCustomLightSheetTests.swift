import HassCore
import UIKit
import XCTest
@testable import HassUI

/// One front-yard light's sheet: a picked colour is sent once the picker settles, "Apply to All Lights" asks first, and the sheet
/// keeps its swatches and colour well readable at accessibility text sizes.
@MainActor
final class UKHostedCustomLightSheetTests: DemoHouseTestCase {
    private var light: CustomLightsConfig.Light { CustomLightsConfig.lights[0] }

    private func open() throws -> (UKCustomLightSheetViewController, LoggingResponder, UIWindow) {
        let store = EntityStore()
        var states: [EntityState] = []
        for item in CustomLightsConfig.lights {
            states.append(EntityState(entityId: item.entityId, state: "on", attributes: [
                "supported_color_modes": .array([.string("rgb")]), "rgb_color": .array([.number(255), .number(120), .number(0)]), "brightness": .number(200),
            ]))
        }
        store.replaceAll(states, freshness: .live)
        let responder = LoggingResponder()
        let context = UKGalleryChrome.context(store: store, caller: responder)
        let page = UKCustomLightSheetViewController(light: light, context: context)
        let window = HostedPage.show(UINavigationController(rootViewController: page), size: CGSize(width: 393, height: 1600))
        FeatureHost.settle(0.3)
        return (page, responder, window)
    }

    func testAPickedColourIsSentOnceAfterThePickerSettles() throws {
        let (page, responder, window) = try open()
        defer { window.isHidden = true }
        let well = try XCTUnwrap(HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "customLight.color" } as? UIColorWell)
        for blue in [0.2, 0.5, 0.9] {
            well.selectedColor = UIColor(red: 0, green: 0.4, blue: blue, alpha: 1)
            well.sendActions(for: .valueChanged)
        }
        XCTAssertTrue(responder.calls.isEmpty, "nothing is sent while the colour is still moving")
        XCTAssertTrue(HostedPage.until(3) { !responder.calls.isEmpty }, "the colour is sent once it settles")
        FeatureHost.settle(0.5)
        XCTAssertEqual(responder.calls, ["light.turn_on"], "dragging across the wheel sends one call, not three")
        let rgb = responder.data.last?["rgb_color"]
        XCTAssertNotNil(rgb, "the call carries the picked colour; saw \(String(describing: responder.data.last))")
    }

    func testApplyToAllLightsAsksBeforeSendingTheColourToTheGroup() throws {
        let (page, responder, window) = try open()
        defer { window.isHidden = true }
        let apply = try XCTUnwrap(HostedDriver.control("customLight.applyAll", in: page.view), "Apply to All Lights is enabled for a coloured light")
        apply.sendActions(for: .touchUpInside)
        FeatureHost.settle(0.5)
        XCTAssertTrue(responder.calls.isEmpty, "nothing is sent before the person confirms")
        let alert = try XCTUnwrap(FeatureHost.alert(on: page), "a confirmation appears")
        let confirm = try XCTUnwrap(alert.actions.first { $0.style != .cancel }, "a confirming action")
        XCTAssertTrue(FeatureHost.answer(alert, confirm.title))
        XCTAssertTrue(HostedPage.until(3) { !responder.calls.isEmpty })
        XCTAssertEqual(responder.calls, ["light.turn_on"])
        XCTAssertEqual(responder.data.last?["entity_id"] as? String, CustomLightsConfig.groupEntityId, "the whole group gets the colour")
    }

    func testSwatchesAndTheSheetStayReadableAtTheLargestTextSize() throws {
        let (page, _, window) = try open()
        defer { window.isHidden = true }
        let before = page.view.bounds.width
        page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        HostedPage.wait(0.4)
        page.view.layoutIfNeeded()
        XCTAssertEqual(page.view.bounds.width, before)
        XCTAssertNotNil(HostedDriver.control("customLight.reset", in: page.view), "Reset to Warm White is still there")
        let swatches = HostedPage.descendants(of: page.view).compactMap { $0 as? UKOtherLightSwatchView }
        XCTAssertEqual(swatches.count, CustomLightsConfig.lights.count - 1, "one swatch per other light")
        let measured = swatches.first?.sizeThatFits(CGSize(width: 150, height: 10))
        XCTAssertEqual(measured?.width, 150)
        XCTAssertGreaterThanOrEqual(measured?.height ?? 0, 44, "a swatch is at least a 44 pt target")
    }
}
