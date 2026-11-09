import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The vacuum sheet's map panel: what it says while the map loads or cannot be had, the status notices and the cleaning report, the
/// wide two-column layout, tapping a room on the map and the secondary command button.
@MainActor
final class UKHostedVacuumPanelTests: DemoHouseTestCase {
    private typealias Scenario = VacuumFixtures.Scenario

    private struct Built {
        var page: UKVacuumSheetViewController
        var log: LoggingResponder
        var store: EntityStore
        var controller: VacuumController
        var window: UIWindow
        var nav: UINavigationController
    }

    private func build(_ vacuum: VacuumConfig = Vacuums.mainFloor, _ scenario: Scenario = .docked, tab: VacuumTab = .controls,
                       loader: ValetudoMapLoader? = nil, size: CGSize = HostedDriver.tall, regular: Bool = false,
                       prepare: (EntityStore) -> Void = { _ in }) -> Built {
        let store = VacuumFixtures.store(scenario)
        prepare(store)
        let log = LoggingResponder(GalleryServiceRecorder(store: store))
        let context = UKGalleryChrome.context(store: store, caller: log).with { $0.surface = .sheet }
        let controller = VacuumController(vacuum: vacuum, store: store, caller: log)
        if scenario == .areaDrawn, vacuum.areaCleaning != nil { controller.areaSelection = VacuumFixtures.drawnArea }
        let page = UKVacuumSheetViewController(controller: controller, loader: loader ?? VacuumFixtures.loader(vacuum, scenario: scenario), server: nil,
                                               catalog: nil, services: VacuumFixtures.services, initialTab: tab, context: context)
        let nav = UINavigationController(rootViewController: page)
        let window = HostedPage.show(nav, size: size)
        if regular {
            window.traitOverrides.horizontalSizeClass = .regular
            nav.view.setNeedsLayout()
        }
        hostedSettle(0.4)
        nav.view.layoutIfNeeded()
        return Built(page: page, log: log, store: store, controller: controller, window: window, nav: nav)
    }

    private func find(_ id: String, in view: UIView) -> UIView? {
        HostedPage.descendants(of: view).first { $0.accessibilityIdentifier == id }
    }

    private func texts(_ built: Built) -> String { HostedPage.labels(in: built.page.view).joined(separator: " | ") }

    private func setSession(_ store: EntityStore, _ vacuum: VacuumConfig, attributes: [String: JSONValue]) {
        guard let id = vacuum.coordinatorSessionEntityId else { return }
        store.apply([EntityState(entityId: id, state: "idle", attributes: attributes)])
    }

    // MARK: Map states

    func testWhileTheMapLoadsTheCardSaysSo() {
        let built = build(loader: ValetudoMapLoader { _ in throw URLError(.notConnectedToInternet) })
        defer { built.window.isHidden = true }
        let fallback = find("vacuum.map.fallback", in: built.page.view)
        XCTAssertEqual(fallback?.accessibilityLabel, "Loading Current Map…")
        XCTAssertTrue(texts(built).contains("Loading Current Map…"))
        XCTAssertNotNil(find("vacuum.locate", in: built.page.view), "a reachable robot can still be located")
    }

    func testAnUnreachableRobotWithNoMapSaysTheMapIsUnavailable() {
        let built = build(Vacuums.mainFloor, .unavailable, loader: ValetudoMapLoader { _ in throw URLError(.notConnectedToInternet) })
        defer { built.window.isHidden = true }
        XCTAssertEqual(find("vacuum.map.fallback", in: built.page.view)?.accessibilityLabel,
                       "Map Unavailable, Home Assistant cannot currently confirm the vacuum's map or position.")
        XCTAssertTrue(texts(built).contains("Map Unavailable"))
        XCTAssertTrue(texts(built).contains("Home Assistant does not have a current status for the vacuum."),
                      "the status card explains why: \(texts(built).prefix(300))")
        XCTAssertTrue(find("vacuum.locate", in: built.page.view)?.isHidden ?? true, "Locate is hidden while the robot is unreachable")
    }

    func testALiveMapReadsItsSelectedRoomsAndHidesTheFallback() {
        let built = build()
        defer { built.window.isHidden = true }
        XCTAssertTrue(find("vacuum.map.fallback", in: built.page.view)?.isHidden ?? true)
        let map = find("vacuum.map", in: built.page.view)
        XCTAssertEqual(map?.accessibilityLabel, "\(Vacuums.mainFloor.title) Valetudo map")
        XCTAssertFalse(map?.isHidden ?? true)
    }

    // MARK: Status notices

    func testARobotInErrorShowsItsCurrentIssue() {
        let built = build(Vacuums.mainFloor, .error)
        defer { built.window.isHidden = true }
        XCTAssertTrue(texts(built).contains("Current Issue:"), "the error is spelled out; saw \(texts(built).prefix(400))")
    }

    func testAnUnreadableErrorSourceIsCalledOut() {
        let vacuum = Vacuums.mainFloor
        let built = build(vacuum) { store in
            store.apply([EntityState(entityId: vacuum.errorEntityId, state: "unavailable")])
        }
        defer { built.window.isHidden = true }
        XCTAssertTrue(texts(built).contains("Error Source Unavailable"), "saw \(texts(built).prefix(400))")
    }

    // MARK: Cleaning report

    func testATypedReportOffersARowThatOpensTheRoomDetails() throws {
        let vacuum = try XCTUnwrap(Vacuums.all.first { $0.coordinatorSessionEntityId != nil })
        let built = build(vacuum)
        defer { built.window.isHidden = true }
        let row = try XCTUnwrap(find("vacuum.report", in: built.page.view) as? UIControl, "the while-away report row")
        XCTAssertTrue(row.accessibilityLabel?.hasPrefix("Open \(vacuum.title) Automatic Cleaning Report") ?? false, "\(row.accessibilityLabel ?? "nil")")
        XCTAssertTrue(texts(built).contains("Cleaning Report"))
        row.sendActions(for: .touchUpInside)
        hostedSettle(0.2)

        // The detail page: one row per room with its status.
        guard case let .typed(contract) = built.controller.whileAway else { return XCTFail("a typed report") }
        let detail = UKVacuumOutcomeDetailViewController(vacuum: vacuum, contract: contract)
        let window = HostedPage.show(UINavigationController(rootViewController: detail), size: HostedDriver.tall)
        defer { window.isHidden = true }
        hostedSettle(0.3)
        let detailTexts = HostedPage.labels(in: detail.view)
        XCTAssertTrue(detailTexts.contains("Kitchen"), "\(detailTexts)")
        XCTAssertTrue(detailTexts.contains("Living Room"))
        XCTAssertTrue(detailTexts.contains("Dining Room"))
        XCTAssertEqual(detail.title, VacuumOutcomeText.reportTitle)
    }

    func testALegacyReportListsWhatWasCleanedAndWhatWentWrong() throws {
        let vacuum = try XCTUnwrap(Vacuums.all.first { $0.coordinatorSessionEntityId != nil })
        let built = build(vacuum) { [self] store in
            setSession(store, vacuum, attributes: ["while_away_cleaned": .array([.string("Kitchen")]), "while_away_issues": .array([.string("Stuck under the couch")])])
        }
        defer { built.window.isHidden = true }
        let all = texts(built)
        XCTAssertTrue(all.contains("\(vacuum.title) Cleaning Report"), all)
        XCTAssertTrue(all.contains("• Kitchen"))
        XCTAssertTrue(all.contains("• Stuck under the couch"))
    }

    func testAnIncompatibleReportExplainsItAndHidesTheOldLinesBehindADisclosure() throws {
        let vacuum = try XCTUnwrap(Vacuums.all.first { $0.coordinatorSessionEntityId != nil })
        let built = build(vacuum) { [self] store in
            setSession(store, vacuum, attributes: ["while_away_outcomes": .object(["version": .number(99)]),
                                                   "while_away_cleaned": .array([.string("Office")])])
        }
        defer { built.window.isHidden = true }
        XCTAssertFalse(texts(built).contains("• Office"), "the old lines stay folded away")
        let show = HostedPage.descendants(of: built.page.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityLabel == "Show \(vacuum.title) Unstructured Report Details" }
        let header = try XCTUnwrap(show, "the disclosure header")
        header.sendActions(for: .touchUpInside)
        hostedSettle(0.2)
        XCTAssertTrue(texts(built).contains("• Office"), "opening the disclosure lists them")
        XCTAssertTrue(texts(built).contains("These details may be inconsistent with the typed status."))
        let hide = HostedPage.descendants(of: built.page.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityLabel == "Hide \(vacuum.title) Unstructured Report Details" }
        XCTAssertNotNil(hide, "the header now offers Hide")
    }

    // MARK: Layout

    func testWhereASplitIsAllowedTheMapLeadsAndTheTabsFollowInASecondColumn() {
        let wide = build(size: CGSize(width: 1024, height: 768), regular: true)
        defer { wide.window.isHidden = true }
        XCTAssertNotNil(find("vacuum.layout.twoColumn", in: wide.page.view), "landscape regular width splits")
        XCTAssertNotNil(find("vacuum.tabs", in: wide.page.view))
        let narrow = build()
        defer { narrow.window.isHidden = true }
        XCTAssertNotNil(find("vacuum.layout.singleColumn", in: narrow.page.view), "a phone stays one column")
    }

    func testTheSectionBarSwitchesTheSheetToAnotherTab() throws {
        let built = build()
        defer { built.window.isHidden = true }
        let bar = try XCTUnwrap(HostedPage.descendants(of: built.page.view).first { $0.accessibilityIdentifier == "vacuum.tabs" })
        XCTAssertFalse(bar.isHidden, "the section bar is shown")
        built.page.state.requestedTab = .info
        hostedSettle(0.6)
        XCTAssertEqual(built.page.state.displayed.tab, .info, "the content follows the pick after its fade")
    }

    // MARK: Map taps

    private final class StubTap: UITapGestureRecognizer {
        var point = CGPoint.zero
        override func location(in view: UIView?) -> CGPoint { point }
    }

    private func roomPoint(in map: UIView, vacuum: VacuumConfig) -> CGPoint? {
        let scene = ValetudoMapScene(map: ValetudoMapFixtures.map(vacuum.vacuumMapId), vacuum: vacuum, provenance: .live)
        let size = map.bounds.size
        for y in stride(from: 4.0, to: size.height, by: 6) {
            for x in stride(from: 4.0, to: size.width, by: 6) {
                let point = CGPoint(x: x, y: y)
                if let room = scene.room(at: point, size: size), vacuum.zones.contains(where: { $0.entityId == room.entityId }) { return point }
            }
        }
        return nil
    }

    func testTappingARoomOnTheLiveMapSelectsIt() throws {
        let built = build()
        defer { built.window.isHidden = true }
        let frame = try XCTUnwrap(HostedPage.descendants(of: built.page.view).first { $0 is UKVacuumMapFrame })
        let map = try XCTUnwrap(find("vacuum.map", in: built.page.view))
        let point = try XCTUnwrap(roomPoint(in: map, vacuum: Vacuums.mainFloor), "a room under some point of the map")
        let tap = StubTap()
        tap.point = point
        frame.perform(NSSelectorFromString("mapTapped:"), with: tap)
        hostedSettle(0.3)
        XCTAssertTrue(built.log.calls.contains { $0.hasPrefix("input_boolean.turn_") }, "a room tap switches that room; saw \(built.log.calls)")
    }

    func testTappingAnUnselectedRoomWhileAnAreaIsDrawnAsksFirst() throws {
        let built = build(Vacuums.mainFloor, .areaDrawn)
        defer { built.window.isHidden = true }
        let frame = try XCTUnwrap(HostedPage.descendants(of: built.page.view).first { $0 is UKVacuumMapFrame })
        let map = try XCTUnwrap(find("vacuum.map", in: built.page.view))
        let point = try XCTUnwrap(roomPoint(in: map, vacuum: Vacuums.mainFloor))
        let tap = StubTap()
        tap.point = point
        frame.perform(NSSelectorFromString("mapTapped:"), with: tap)
        hostedSettle(0.4)
        XCTAssertTrue(built.log.calls.isEmpty, "nothing is sent before the person confirms; saw \(built.log.calls)")
        XCTAssertNotNil(built.page.presentedViewController as? UIAlertController, "switching to rooms drops the area, so it asks")
        XCTAssertNotNil(built.controller.areaSelection, "the area is kept until confirmed")
    }

    func testTappingEmptySpaceOnTheMapDoesNothing() throws {
        let built = build()
        defer { built.window.isHidden = true }
        let frame = try XCTUnwrap(HostedPage.descendants(of: built.page.view).first { $0 is UKVacuumMapFrame })
        let tap = StubTap()
        tap.point = CGPoint(x: -50, y: -50)
        frame.perform(NSSelectorFromString("mapTapped:"), with: tap)
        hostedSettle(0.2)
        XCTAssertTrue(built.log.calls.isEmpty)
    }

    // MARK: Secondary button

    func testASecondaryCommandIsAGreyCapsuleThatRunsAndDims() throws {
        var runs = 0
        let enabled = VacuumController.Action(kind: .dryMops, title: "Dry Mops", icon: "mdi:weather-windy", tone: .neutral,
                                              detail: "Start drying the attached mop pads.", isDisabled: false)
        let button = UKVacuumActionButton(action: enabled) { runs += 1 }
        let window = HostedPage.show(UIViewController(), size: CGSize(width: 393, height: 300))
        defer { window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController)
        host.view.addSubview(button)
        button.frame = CGRect(x: 0, y: 100, width: 393, height: 120)
        button.layoutIfNeeded()
        let capsule = try XCTUnwrap(HostedPage.descendants(of: button).first { $0 is UKVacuumSecondaryButton } as? UKVacuumSecondaryButton)
        XCTAssertEqual(capsule.accessibilityLabel, "Dry Mops")
        XCTAssertEqual(capsule.accessibilityValue, "Start drying the attached mop pads.")
        XCTAssertTrue(capsule.accessibilityTraits.contains(.button))
        XCTAssertGreaterThanOrEqual(capsule.bounds.height, 44)
        XCTAssertTrue(HostedPage.labels(in: button).contains("Start drying the attached mop pads."), "the detail shows under the button")
        capsule.sendActions(for: .touchUpInside)
        XCTAssertEqual(runs, 1)
        capsule.isHighlighted = true
        XCTAssertEqual(capsule.alpha, 0.75, accuracy: 0.01)
        capsule.isHighlighted = false

        let disabled = VacuumController.Action(kind: .emptyBin, title: "Empty Bin", icon: "mdi:delete-restore", tone: .neutral, detail: nil, isDisabled: true)
        let off = UKVacuumActionButton(action: disabled) { runs += 1 }
        host.view.addSubview(off)
        off.frame = CGRect(x: 0, y: 200, width: 393, height: 60)
        off.layoutIfNeeded()
        let dim = try XCTUnwrap(HostedPage.descendants(of: off).first { $0 is UKVacuumSecondaryButton } as? UKVacuumSecondaryButton)
        XCTAssertFalse(dim.isEnabled)
        XCTAssertTrue(dim.accessibilityTraits.contains(.notEnabled))
        XCTAssertEqual(dim.alpha, 0.45, accuracy: 0.01)
    }
}
