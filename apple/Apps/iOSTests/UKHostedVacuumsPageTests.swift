import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Robot Vacuums page: its summary line, the robot tiles' discs, opening a robot's sheet, the Auto-Clean switches and the split.
@MainActor
final class UKHostedVacuumsPageTests: DemoHouseTestCase {
    private typealias Scenario = VacuumFixtures.Scenario

    private func page(_ scenario: Scenario = .docked, size: CGSize = CGSize(width: 393, height: 1400), regular: Bool = false, initial: VacuumConfig? = nil)
        -> (UKVacuumsViewController, LoggingResponder, UIWindow) {
        let store = VacuumFixtures.store(scenario)
        let log = LoggingResponder(GalleryServiceRecorder(store: store))
        let context = UKGalleryChrome.context(store: store, caller: log)
        let sheetContext = context.with { $0.surface = .sheet }
        let page = UKVacuumsViewController(context: context, caller: log, initialVacuum: initial) { vacuum in
            let controller = VacuumController(vacuum: vacuum, store: store, caller: log)
            return UKVacuumSheetViewController(controller: controller, loader: VacuumFixtures.loader(vacuum, scenario: scenario), server: nil, catalog: nil,
                                               services: VacuumFixtures.services, context: sheetContext)
        }
        let nav = UINavigationController(rootViewController: page)
        let window = HostedPage.show(nav, size: size)
        if regular {
            window.traitOverrides.horizontalSizeClass = .regular
            nav.view.setNeedsLayout()
        }
        hostedSettle(0.5)
        nav.view.layoutIfNeeded()
        return (page, log, window)
    }

    private func tile(_ vacuum: VacuumConfig, in page: UIViewController) -> UKGlassTileView? {
        HostedPage.descendants(of: page.view).compactMap { $0 as? UKGlassTileView }
            .first { $0.accessibilityIdentifier?.hasPrefix("vacuums.tile.\(vacuum.vacuumMapId)") ?? false }
    }

    func testTheSummaryLineCountsWhatEachRobotIsDoing() {
        let (cleaning, _, w1) = page(.cleaning)
        defer { w1.isHidden = true }
        let line = HostedPage.descendants(of: cleaning.view).first { $0.accessibilityIdentifier == "vacuums.summary" } as? UILabel
        XCTAssertTrue(line?.text?.contains("Cleaning") ?? false, "saw \(line?.text ?? "nil")")
        XCTAssertFalse(line?.isHidden ?? true)
        let (broken, _, w2) = page(.error)
        defer { w2.isHidden = true }
        let errorLine = HostedPage.descendants(of: broken.view).first { $0.accessibilityIdentifier == "vacuums.summary" } as? UILabel
        XCTAssertTrue(errorLine?.text?.contains("Needs Attention") ?? false, "saw \(errorLine?.text ?? "nil")")
    }

    func testEachRobotTileStartsPausesAndDocksThroughItsDiscs() throws {
        let vacuum = Vacuums.all[0]
        let (docked, dockedLog, w1) = page(.docked)
        defer { w1.isHidden = true }
        let idle = try XCTUnwrap(tile(vacuum, in: docked), "a tile for \(vacuum.title)")
        idle.onPerform?("start_pause")
        hostedSettle(0.3)
        XCTAssertTrue(dockedLog.calls.contains("vacuum.start"), "Start on a docked robot starts it; saw \(dockedLog.calls)")

        let (busy, busyLog, w2) = page(.cleaning)
        defer { w2.isHidden = true }
        let working = try XCTUnwrap(tile(vacuum, in: busy))
        working.onPerform?("start_pause")
        hostedSettle(0.3)
        XCTAssertTrue(busyLog.calls.contains("vacuum.pause"), "the same disc pauses a cleaning robot; saw \(busyLog.calls)")
        working.onPerform?("dock")
        hostedSettle(0.3)
        XCTAssertTrue(busyLog.calls.contains("vacuum.return_to_base"), "Dock sends it home; saw \(busyLog.calls)")
        working.onPerform?("not-a-disc")
    }

    func testTappingARobotOpensItsSheet() throws {
        let vacuum = Vacuums.all[0]
        let (vacuums, _, window) = page()
        defer { window.isHidden = true }
        let robot = try XCTUnwrap(tile(vacuum, in: vacuums))
        robot.action?()
        XCTAssertTrue(HostedPage.until(5) { vacuums.presentedViewController != nil || vacuums.navigationController?.presentedViewController != nil },
                      "the robot's sheet comes up")
        robot.action?()
    }

    func testAnInitialRobotOpensItsSheetOnAppear() {
        let (vacuums, _, window) = page(initial: Vacuums.all[0])
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until(5) { vacuums.presentedViewController != nil || vacuums.navigationController?.presentedViewController != nil },
                      "the gallery's deep link opens the sheet")
    }

    func testAutoCleanSwitchesSendTheirCalls() async {
        let (vacuums, log, window) = page()
        defer { window.isHidden = true }
        for control in Vacuums.autoCleanControls {
            XCTAssertTrue(FeatureHost.press("vacuums.autoClean.\(control.entityId)", in: vacuums.view), "\(control.title) has a switch row")
            await FeatureHost.settleAsync(0.1)
        }
        await FeatureHost.settleAsync(0.3)
        XCTAssertFalse(log.calls.isEmpty, "flipping switches calls services; saw \(log.calls)")
        XCTAssertTrue(HostedPage.labels(in: vacuums.view).contains("Auto-Clean"))
    }

    func testWhereASplitIsAllowedRobotsLeadAndAutoCleanSitsBeside() {
        let (vacuums, _, window) = page(size: CGSize(width: 1024, height: 768), regular: true)
        defer { window.isHidden = true }
        let layout = HostedPage.descendants(of: vacuums.view).first { $0.accessibilityIdentifier?.hasPrefix("vacuums.layout") ?? false }
        XCTAssertEqual(layout?.accessibilityIdentifier, "vacuums.layout.split")
        XCTAssertTrue(HostedPage.labels(in: vacuums.view).contains("Auto-Clean"))
        window.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController?.view.setNeedsLayout()
        window.layoutIfNeeded()
        hostedSettle(0.3)
        XCTAssertNotNil(HostedPage.descendants(of: vacuums.view).first { $0.accessibilityIdentifier == "vacuums.layout.single" }, "compact width goes back to one column")
    }
}
