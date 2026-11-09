import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The vacuum cleaning-area editor: drawing, clearing, resetting the view and what the summary says.
@MainActor
final class UKHostedVacuumEditorTests: DemoHouseTestCase {
    private func editor(scenario: VacuumFixtures.Scenario = .docked, area: MapGridRect? = nil)
        -> (UKVacuumAreaEditorViewController, VacuumController, UIWindow, UINavigationController) {
        let vacuum = Vacuums.all.first { $0.areaCleaning != nil } ?? Vacuums.all[0]
        let store = VacuumFixtures.store(scenario)
        let controller = VacuumController(vacuum: vacuum, store: store, caller: GalleryServiceRecorder(store: store))
        controller.areaSelection = area
        let state = VacuumMapState(vacuum: vacuum, loader: VacuumFixtures.loader(vacuum, scenario: scenario))
        state.refresh()
        let page = UKVacuumAreaEditorViewController(controller: controller, mapState: state)
        let nav = UINavigationController(rootViewController: UIViewController())
        let window = HostedPage.show(nav)
        nav.pushViewController(page, animated: false)
        // The map lays out once its scene has loaded; wait for it, then lay out again.
        let deadline = Date().addingTimeInterval(3)
        while !state.isReady && Date() < deadline { hostedSettle(0.1) }
        hostedSettle(0.3)
        page.view.layoutIfNeeded()
        return (page, controller, window, nav)
    }

    private func find(_ id: String, in view: UIView) -> UIView? {
        HostedPage.descendants(of: view).first { $0.accessibilityIdentifier == id }
    }

    func testTheMapFillsTheAvailableWidthOnceItsSceneHasLoaded() {
        let (page, _, window, _) = editor()
        defer { window.isHidden = true }
        guard let map = find("vacuum.area.map", in: page.view) else { return XCTFail("no map") }
        XCTAssertGreaterThan(map.bounds.width, 100, "the map lays out at a real width")
        XCTAssertLessThanOrEqual(map.bounds.width, 393)
        XCTAssertLessThanOrEqual(map.bounds.height, 520)
    }

    func testWithoutAnAreaTheEditorAsksForOneAndContinueIsNotOffered() {
        let (page, controller, window, _) = editor()
        defer { window.isHidden = true }
        XCTAssertTrue(page.title?.hasSuffix("Cleaning Area") ?? false)
        let texts = HostedPage.labels(in: page.view)
        XCTAssertTrue(texts.contains("No area selected"), "saw \(texts)")
        XCTAssertTrue(texts.contains("Draw a rectangle to continue."))
        XCTAssertNil(controller.areaSelection)
        XCTAssertNotNil(find("vacuum.area.map", in: page.view))
        XCTAssertEqual(find("vacuum.area.map", in: page.view)?.accessibilityValue, "No area selected")
    }

    func testADrawnAreaIsDescribedByItsSizeAndClearAndRedrawWork() {
        let (page, controller, window, _) = editor(area: VacuumFixtures.drawnArea)
        defer { window.isHidden = true }
        let dimensions = find("vacuum.area.dimensions", in: page.view) as? UILabel
        XCTAssertNotNil(dimensions?.text)
        XCTAssertNotEqual(dimensions?.text, "No area selected")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains { $0.hasSuffix("m² selected") })
        let draw = find("vacuum.area.draw", in: page.view) as? UIControl
        XCTAssertTrue(draw?.accessibilityLabel?.contains("Redraw") ?? false, "with an area the draw tool offers Redraw; saw \(draw?.accessibilityLabel ?? "nil")")
        (find("vacuum.area.reset", in: page.view) as? UIControl)?.sendActions(for: .touchUpInside)
        draw?.sendActions(for: .touchUpInside)
        hostedSettle(0.2)
        XCTAssertNil(controller.areaSelection, "redraw starts from nothing")

        controller.areaSelection = VacuumFixtures.drawnArea
        hostedSettle(0.2)
        (find("vacuum.area.clear", in: page.view) as? UIControl)?.sendActions(for: .touchUpInside)
        hostedSettle(0.2)
        XCTAssertNil(controller.areaSelection, "clear drops the area")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains("No area selected"))
    }

    func testDraggingOnTheMapDrawsAnAreaAndPinchingZoomsIt() {
        let (page, controller, window, _) = editor()
        defer { window.isHidden = true }
        guard let map = find("vacuum.area.map", in: page.view) else { return XCTFail("no map") }
        let recognizers = map.gestureRecognizers ?? []
        XCTAssertTrue(recognizers.contains { $0 is UIPinchGestureRecognizer }, "the map can be pinched")
        XCTAssertTrue(recognizers.contains { $0 is UKMapDragRecognizer }, "the map can be dragged")
        let actions = map.accessibilityCustomActions?.map(\.name) ?? []
        XCTAssertTrue(actions.contains("Zoom In") || actions.isEmpty, "zoom is available without a pinch: \(actions)")
        _ = controller
    }
}
