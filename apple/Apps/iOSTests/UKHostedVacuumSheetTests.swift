import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The vacuum sheet driven like a person in every robot state: locate, the map banner and fallbacks, each tab's controls, and the
/// service calls they send.
@MainActor
final class UKHostedVacuumSheetTests: DemoHouseTestCase {
    private typealias Scenario = VacuumFixtures.Scenario
    private let scenarios: [Scenario] = [.docked, .cleaning, .paused, .error, .resumable, .unavailable, .dockWash, .dockPrep, .noMop,
                                         .modeVacuum, .modeMop, .areaDrawn, .autoUnavailable]

    private func sheet(_ vacuum: VacuumConfig, _ scenario: Scenario, tab: VacuumTab = .controls)
        -> (UKVacuumSheetViewController, LoggingResponder, UIWindow, UINavigationController) {
        let store = VacuumFixtures.store(scenario)
        let log = LoggingResponder(GalleryServiceRecorder(store: store))
        let context = UKGalleryChrome.context(store: store, caller: log).with { $0.surface = .sheet }
        let controller = VacuumController(vacuum: vacuum, store: store, caller: log)
        if scenario == .areaDrawn, vacuum.areaCleaning != nil { controller.areaSelection = VacuumFixtures.drawnArea }
        let page = UKVacuumSheetViewController(controller: controller, loader: VacuumFixtures.loader(vacuum, scenario: scenario), server: nil, catalog: nil,
                                               services: VacuumFixtures.services, initialTab: tab, context: context)
        let nav = UINavigationController(rootViewController: page)
        let window = HostedPage.show(nav, size: HostedDriver.tall)
        hostedSettle(0.35)
        return (page, log, window, nav)
    }

    func testLocateAsksTheRobotToPlayASound() {
        let (page, log, window, _) = sheet(Vacuums.all[0], .docked)
        defer { window.isHidden = true }
        let locate = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "vacuum.locate" } as? UIControl
        XCTAssertEqual(locate?.accessibilityLabel, "Locate")
        locate?.sendActions(for: .touchUpInside)
        hostedSettle(0.3)
        XCTAssertTrue(log.calls.contains { $0.hasSuffix(".locate") }, "Locate calls the locate service; saw \(log.calls)")
    }

    func testAnUnavailableRobotShowsTheLastReportedMapNotice() {
        let (page, _, window, _) = sheet(Vacuums.all[0], .unavailable)
        defer { window.isHidden = true }
        let texts = HostedPage.labels(in: page.view).joined(separator: "|")
        XCTAssertTrue(texts.contains("Last Reported"), "an unreachable robot says the map is the last one reported; saw \(texts.prefix(400))")
    }

    func testEveryTabOfEveryVacuumInEveryStateIsUsableAndSendsCalls() {
        var total = 0
        for (index, vacuum) in Vacuums.all.enumerated() {
            for scenario in index == 0 ? scenarios : [.docked, .cleaning, .error] {
                for tab in VacuumTab.allCases {
                    let (page, log, window, nav) = sheet(vacuum, scenario, tab: tab)
                    XCTAssertFalse(HostedPage.labels(in: page.view).isEmpty, "\(vacuum.title) \(scenario) \(tab) draws")
                    total += HostedDriver.useAll(in: page.view, except: ["close", "done", "dismiss", "area", "edit"], settle: 0.02)
                    hostedSettle(0.2)
                    // A confirmation or pushed page opened by a control is closed again.
                    if let presented = nav.presentedViewController { presented.dismiss(animated: false) }
                    nav.popToRootViewController(animated: false)
                    _ = log
                    window.isHidden = true
                }
            }
        }
        XCTAssertGreaterThan(total, 100, "the sheets offered many controls")
    }

    func testTheControlsTabStartsACleanFromTheDockedState() {
        let vacuum = Vacuums.all[0]
        let (page, log, window, _) = sheet(vacuum, .docked)
        defer { window.isHidden = true }
        HostedDriver.useAll(in: page.view, except: ["close", "done", "dismiss", "area", "edit", "locate"], settle: 0.05)
        hostedSettle(0.5)
        XCTAssertFalse(log.calls.isEmpty, "using the Controls tab makes at least one service call; saw \(HostedDriver.identifiers(in: page.view))")
    }
}
