import HassCore
import UIKit
import UIKit.UIGestureRecognizerSubclass
import XCTest
@testable import HassUI

/// The cleaning-area editor driven by a finger (drag to draw, drag to move, pinch to zoom) and by its accessibility actions, and the
/// Valetudo map view's drawing of rooms, skipped rooms, order badges, the area and the map's own entities.
@MainActor
final class UKHostedVacuumMapGestureTests: DemoHouseTestCase {
    private final class StubDrag: UKMapDragRecognizer {
        var stub = CGPoint.zero
        var stubState = UIGestureRecognizer.State.possible
        override var location: CGPoint { stub }
        override var state: UIGestureRecognizer.State { get { stubState } set { stubState = newValue } }
    }

    private final class StubPinch: UIPinchGestureRecognizer {
        var stubScale: CGFloat = 1
        var stubPoint = CGPoint.zero
        var stubState = UIGestureRecognizer.State.possible
        override var state: UIGestureRecognizer.State { get { stubState } set { stubState = newValue } }
        override var scale: CGFloat { get { stubScale } set { stubScale = newValue } }
        override func location(in view: UIView?) -> CGPoint { stubPoint }
    }

    /// Read when a test runs, not when the case is created: XCTest creates every case while it lists the bundle, before `setUp`
    /// installs the demo house, and `Vacuums.all` is empty until then (a stored property crashed the whole host there).
    private var vacuum: VacuumConfig { Vacuums.all.first { $0.areaCleaning != nil } ?? Vacuums.all[0] }

    private func editor(area: MapGridRect? = nil)
        -> (page: UKVacuumAreaEditorViewController, controller: VacuumController, window: UIWindow, map: UKValetudoMapView) {
        let store = VacuumFixtures.store(.docked)
        let controller = VacuumController(vacuum: vacuum, store: store, caller: GalleryServiceRecorder(store: store))
        controller.areaSelection = area
        let state = VacuumMapState(vacuum: vacuum, loader: VacuumFixtures.loader(vacuum, scenario: .docked))
        state.refresh()
        let page = UKVacuumAreaEditorViewController(controller: controller, mapState: state)
        let nav = UINavigationController(rootViewController: UIViewController())
        let window = HostedPage.show(nav)
        nav.pushViewController(page, animated: false)
        let deadline = Date().addingTimeInterval(3)
        while !state.isReady && Date() < deadline { hostedSettle(0.1) }
        hostedSettle(0.3)
        page.view.layoutIfNeeded()
        let map = HostedPage.descendants(of: page.view).compactMap { $0 as? UKValetudoMapView }.first!
        return (page, controller, window, map)
    }

    private func labels(_ page: UIViewController) -> [String] { HostedPage.labels(in: page.view) }

    private func drag(_ page: UIViewController, from start: CGPoint, to end: CGPoint) {
        let recognizer = StubDrag()
        recognizer.startLocation = start
        let selector = NSSelectorFromString("dragged:")
        recognizer.stub = start
        recognizer.state = .began
        page.perform(selector, with: recognizer)
        recognizer.stub = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        recognizer.state = .changed
        page.perform(selector, with: recognizer)
        recognizer.stub = end
        recognizer.state = .changed
        page.perform(selector, with: recognizer)
        recognizer.state = .ended
        page.perform(selector, with: recognizer)
        hostedSettle(0.2)
    }

    func testDraggingAcrossTheMapDrawsAnAreaAndTheSummaryDescribesIt() throws {
        let (page, controller, window, map) = editor()
        defer { window.isHidden = true }
        XCTAssertNil(controller.areaSelection)
        let size = map.bounds.size
        drag(page, from: CGPoint(x: size.width * 0.25, y: size.height * 0.25), to: CGPoint(x: size.width * 0.75, y: size.height * 0.75))
        let area = try XCTUnwrap(controller.areaSelection, "a long drag in draw mode draws an area")
        XCTAssertTrue(labels(page).contains { $0.hasSuffix("m² selected") }, "the summary reports its size: \(labels(page))")
        XCTAssertTrue(labels(page).contains("Drag the area to move it or use any round corner handle to resize it."), "the caption now teaches moving")
        let use = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "vacuum.area.use" }
        XCTAssertNotNil(use)
        XCTAssertTrue(HostedPage.labels(in: use ?? page.view).contains("Use This Area") || (use as? UIControl)?.isEnabled == true)

        // A drag that starts inside the drawn area moves it.
        let scene = try XCTUnwrap(ValetudoMapScene(map: ValetudoMapFixtures.map(vacuum.vacuumMapId), vacuum: vacuum, provenance: .live) as ValetudoMapScene?)
        let matrix = scene.matrix(size: size, viewport: .initial)
        let center = MapGeometry.framePoint(scene.geometry, matrix: matrix, gridPoint: .init(x: Double(area.x0 + area.x1) / 2, y: Double(area.y0 + area.y1) / 2))
        let before = area
        drag(page, from: CGPoint(x: center.x, y: center.y), to: CGPoint(x: center.x + 12, y: center.y + 12))
        XCTAssertNotNil(controller.areaSelection)
        XCTAssertNotEqual(controller.areaSelection, before, "dragging inside the area moves it")
    }

    func testACancelledDragLeavesNoArea() {
        let (page, controller, window, map) = editor()
        defer { window.isHidden = true }
        let recognizer = StubDrag()
        recognizer.startLocation = CGPoint(x: map.bounds.width * 0.3, y: map.bounds.height * 0.3)
        recognizer.stub = CGPoint(x: map.bounds.width * 0.7, y: map.bounds.height * 0.7)
        recognizer.state = .began
        page.perform(NSSelectorFromString("dragged:"), with: recognizer)
        recognizer.state = .changed
        page.perform(NSSelectorFromString("dragged:"), with: recognizer)
        recognizer.state = .cancelled
        page.perform(NSSelectorFromString("dragged:"), with: recognizer)
        hostedSettle(0.2)
        XCTAssertNil(controller.areaSelection, "a cancelled drag does not commit")
        XCTAssertTrue(labels(page).contains("No area selected"))
    }

    func testPinchingZoomsTheMapAndLettingGoKeepsTheZoom() {
        let (page, _, window, map) = editor()
        defer { window.isHidden = true }
        XCTAssertEqual(map.viewport, .initial)
        let pinch = StubPinch()
        pinch.stubPoint = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
        let selector = NSSelectorFromString("pinched:")
        pinch.state = .began
        page.perform(selector, with: pinch)
        pinch.stubScale = 2
        pinch.state = .changed
        page.perform(selector, with: pinch)
        XCTAssertNotEqual(map.viewport, .initial, "spreading two fingers zooms in")
        pinch.state = .ended
        page.perform(selector, with: pinch)
        XCTAssertNotEqual(map.viewport, .initial)
        // Reset View goes back.
        (HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "vacuum.area.reset" } as? UIControl)?.sendActions(for: .touchUpInside)
        hostedSettle(0.2)
        XCTAssertEqual(map.viewport, .initial)
    }

    func testAccessibilityActionsZoomResetAndNudgeTheArea() throws {
        let (_, controller, window, map) = editor(area: VacuumFixtures.drawnArea)
        defer { window.isHidden = true }
        func run(_ name: String) throws {
            let action = try XCTUnwrap(map.accessibilityCustomActions?.first { $0.name == name }, "\(name) is offered; saw \(map.accessibilityCustomActions?.map(\.name) ?? [])")
            _ = action.actionHandler?(action)
            hostedSettle(0.1)
        }
        try run("Zoom In")
        XCTAssertNotEqual(map.viewport, .initial)
        try run("Zoom Out")
        try run("Reset Zoom")
        XCTAssertEqual(map.viewport, .initial)
        for nudge in MapAreaEdit.Nudge.allCases {
            let before = controller.areaSelection
            try run(nudge.title)
            XCTAssertNotNil(controller.areaSelection)
            _ = before
        }
        let original = VacuumFixtures.drawnArea
        controller.areaSelection = original
        hostedSettle(0.2)
        try run("Move area right")
        XCTAssertNotEqual(controller.areaSelection, original, "Move area right shifts the area")
        XCTAssertGreaterThan(controller.areaSelection?.x0 ?? 0, original.x0)
    }

    // MARK: The map view

    private func mapView(_ map: ValetudoMap, provenance: ValetudoMapProvenance = .live) -> (UKValetudoMapView, ValetudoMapScene, UIWindow) {
        let scene = ValetudoMapScene(map: map, vacuum: Vacuums.mainFloor, provenance: provenance)
        let view = UKValetudoMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 420))
        let host = UIViewController()
        let window = HostedPage.show(host)
        host.view.addSubview(view)
        view.frame = CGRect(x: 20, y: 80, width: 300, height: 420)
        view.scene = scene
        view.layoutIfNeeded()
        return (view, scene, window)
    }

    private func layers(of layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(layers(of:)) }

    func testSelectedRoomsGetNumberedBadgesAndSkippedRoomsAreHatched() throws {
        let (view, scene, window) = mapView(ValetudoMapFixtures.map(Vacuums.mainFloor.vacuumMapId))
        defer { window.isHidden = true }
        let rooms = scene.rooms.prefix(3).map(\.entityId)
        XCTAssertEqual(rooms.count, 3)
        view.roomOrders = [rooms[0]: 1, rooms[1]: 2]
        view.skippedRooms = [rooms[2]]
        view.layoutIfNeeded()
        let badges = HostedPage.descendants(of: view).compactMap { $0 as? UILabel }.filter { !$0.isHidden }.compactMap(\.text)
        XCTAssertEqual(Set(badges), ["1", "2"], "each chosen room shows its place in the cleaning order")
        let hatches = layers(of: view.layer).filter { ($0 as? CAShapeLayer)?.mask != nil }
        XCTAssertEqual(hatches.filter { !$0.isHidden }.count, 1, "one skipped room is hatched")
        view.skippedRooms = []
        XCTAssertEqual(layers(of: view.layer).filter { ($0 as? CAShapeLayer)?.mask != nil && !$0.isHidden }.count, 0, "unskipping hides the hatch")
        view.roomOrders = [:]
        XCTAssertTrue(HostedPage.descendants(of: view).compactMap { $0 as? UILabel }.allSatisfy { $0.isHidden })
    }

    func testTheAreaOutlineShowsHandlesOnlyWhenAskedAndZoomRescalesLines() throws {
        var map = ValetudoMapFixtures.map(Vacuums.mainFloor.vacuumMapId)
        map.entities += [
            .init(type: "path", points: [3100, 3100, 3200, 3150, 3300, 3250]),
            .init(type: "predicted_path", points: [3300, 3250, 3400, 3300]),
            .init(type: "no_go_area", points: [3000, 3000, 3200, 3000, 3200, 3200, 3000, 3200]),
            .init(type: "virtual_wall", points: [3000, 3300, 3300, 3300]),
            .init(type: "obstacle", points: [3150, 3150]),
            .init(type: "go_to_target", points: [3250, 3250]),
        ]
        let (view, scene, window) = mapView(map)
        defer { window.isHidden = true }
        let layerCount = layers(of: view.layer).count
        XCTAssertGreaterThan(layerCount, 10, "paths, restrictions and markers each add a layer")
        view.area = VacuumFixtures.drawnArea
        view.layoutIfNeeded()
        func handles() -> [CAShapeLayer] { layers(of: view.layer).compactMap { $0 as? CAShapeLayer }.filter { $0.path?.boundingBox.width == 16 } }
        XCTAssertTrue(handles().allSatisfy(\.isHidden), "no handles until editing")
        view.showsHandles = true
        XCTAssertEqual(handles().filter { !$0.isHidden }.count, 4, "four corner handles")
        view.area = nil
        XCTAssertTrue(handles().allSatisfy(\.isHidden))
        let widthBefore = (layers(of: view.layer).compactMap { $0 as? CAShapeLayer }.first { $0.lineDashPattern == nil && $0.strokeColor != nil })?.lineWidth
        view.viewport = scene.zoomed(.initial, by: 3, size: view.bounds.size)
        view.layoutIfNeeded()
        let widthAfter = (layers(of: view.layer).compactMap { $0 as? CAShapeLayer }.first { $0.lineDashPattern == nil && $0.strokeColor != nil })?.lineWidth
        XCTAssertNotNil(widthBefore)
        XCTAssertNotNil(widthAfter)
        view.scene = nil
        XCTAssertLessThan(layers(of: view.layer).count, layerCount, "clearing the scene drops the map's layers")
    }

    func testALastReportedMapStillDrawsItsRobot() {
        let (view, _, window) = mapView(ValetudoMapFixtures.map(Vacuums.mainFloor.vacuumMapId).reportedOnly(), provenance: .reported)
        defer { window.isHidden = true }
        XCTAssertGreaterThan(layers(of: view.layer).count, 3)
        XCTAssertNotNil(view.scene)
    }
}
