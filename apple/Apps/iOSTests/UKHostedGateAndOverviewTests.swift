import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The content gate that holds a page until its data and images are ready, and the room overview sheets.
@MainActor
final class UKHostedGateAndOverviewTests: DemoHouseTestCase {
    func testAGateHidesItsContentFromVoiceOverUntilTheDataArrives() {
        let content = UILabel(); content.text = "Pantry"
        let gate = UKContentGateView(page: "Pantry", isReady: false, timing: .page, label: "Loading Pantry", content: content)
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(gate)
        gate.frame = CGRect(x: 0, y: 60, width: 393, height: 600)
        gate.layoutIfNeeded()
        XCTAssertTrue(content.accessibilityElementsHidden, "content under a spinner is not read")
        XCTAssertFalse(content.isUserInteractionEnabled)
        gate.isReady = true
        hostedSettle(2.5)
        XCTAssertFalse(content.accessibilityElementsHidden)
        XCTAssertTrue(content.isUserInteractionEnabled)
        XCTAssertEqual(content.alpha, 1)
        XCTAssertNil(HostedPage.descendants(of: gate).first { $0.accessibilityIdentifier == "contentGate.spinner" }, "the spinner is gone")
    }

    func testASlowLoadShowsTheLabelledSpinnerAndAReloadKeepsTheContent() {
        let content = UIView()
        let gate = UKContentGateView(page: "Recipes", isReady: false, label: "Loading Recipes", content: content)
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(gate)
        gate.frame = CGRect(x: 0, y: 60, width: 393, height: 600)
        hostedSettle(3.0)
        let spinner = HostedPage.descendants(of: gate).first { $0.accessibilityIdentifier == "contentGate.spinner" }
        XCTAssertNotNil(spinner, "a load that takes a while shows the spinner")
        XCTAssertEqual(spinner?.accessibilityLabel, "Loading Recipes")
        gate.isReady = true
        hostedSettle(2.5)
        gate.isReady = false
        gate.isReady = true
        hostedSettle(1.5)
        XCTAssertEqual(content.alpha, 1)
    }

    func testAnImageHoldsTheGateUntilItCanDraw() {
        let gate = UKContentGateView(page: "Photos", isReady: true, timing: .page, content: UIView())
        let requirement = UKReadinessRequirement("image:a", tracker: gate.tracker, isReady: false)
        XCTAssertFalse(gate.tracker.isSettled)
        requirement.isReady = true
        XCTAssertTrue(gate.tracker.isSettled)
        requirement.isReady = false
        requirement.end()
        XCTAssertTrue(gate.tracker.isSettled, "leaving the screen counts as ready")
    }

    func testEveryRoomOverviewOpensWithItsTitleAndRooms() {
        let store = HomeFixtures.store(environment: [:])
        let context = UKGalleryChrome.context(store: store)
        for kind in RoomOverviewKind.allCases {
            let host = UIViewController()
            let window = HostedPage.show(host)
            let modal = UKRoomOverviewSheet.controller(context: context, kind: kind)
            modal.present(from: host, animated: false)
            hostedSettle(0.6)
            let page = modal.viewControllers.first
            XCTAssertEqual(page?.navigationItem.title.map { !$0.isEmpty }, true, "\(kind) has a title")
            XCTAssertFalse(HostedPage.labels(in: modal.view).isEmpty, "\(kind) lists something")
            XCTAssertEqual(modal.sheetPresentationController?.detents.count, 1, "an overview is a full-height sheet")
            modal.dismiss(animated: false)
            window.isHidden = true
        }
    }
}
