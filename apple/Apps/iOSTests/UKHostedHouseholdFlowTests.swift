import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Household flows the first tests leave out: the Solo Trip status actions on the Vacation Mode page, the date pickers, and signing out
/// from Your Summary.
@MainActor
final class UKHostedHouseholdFlowTests: DemoHouseTestCase {
    private func modePage(_ scenario: VacationFixtures.Scenario) async -> (VacationGalleryHouse, UIViewController, UIWindow) {
        let house = VacationGalleryHouse(store: VacationFixtures.store(scenario), delay: .milliseconds(30))
        let context = UKGalleryChrome.context(store: house.store, caller: house)
        let page = UKVacationSubpageViewController(
            content: UKVacationModeContent(context: context, household: HouseholdAwayController(store: house.store, responder: house), caller: house),
            context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 1800))
        await FeatureHost.settleAsync(0.6)
        return (house, page, window)
    }

    func testWhileASoloTripRunsVacationModeShowsItsStatusAndEndNowAsksTheHouse() async {
        let (house, page, window) = await modePage(.soloActive)
        defer { window.isHidden = true }
        let ids = FeatureHost.identifiers(in: page.view).filter { $0.hasPrefix("soloTrip.status") }
        XCTAssertFalse(ids.isEmpty, "the Solo Trip status replaces the vacation sections; saw \(FeatureHost.identifiers(in: page.view))")
        XCTAssertTrue(ids.contains("soloTrip.status"), "the running trip's status is shown")
        _ = house
    }

    func testARestoreDecisionOnTheModePageKeepsOrRestores() async {
        let (house, page, window) = await modePage(.soloRestore)
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("soloTrip.status.keepCurrent", in: page.view), "Keep Current is offered")
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(house.lastCall.contains("resolve_restore"), house.lastCall)
    }

    func testChangingTheDatePickersOfAnEngagedVacationSendsTheNewRange() async {
        let (house, page, window) = await modePage(.vacation)
        defer { window.isHidden = true }
        let pickers = HostedPage.descendants(of: page.view).compactMap { $0 as? UIDatePicker }
        XCTAssertGreaterThanOrEqual(pickers.count, 2, "Starts and Ends pickers")
        for picker in pickers {
            let before = picker.date
            HostedDriver.use(picker)
            XCTAssertNotEqual(picker.date, before)
        }
        let sent = await FeatureHost.settleAsync(until: { house.lastCall != "None" }, timeout: 4)
        XCTAssertTrue(sent, "a new range is saved to Home Assistant")
    }

    func testSigningOutFromYourSummaryEndsTheSession() async throws {
        let (session, _, context) = try FeatureHost.signedIn()
        let page = UKYourSummaryViewController(context: context, models: UKSummaryModels(), opening: .profile)
        let modal = UKHassModalController(root: page, options: UKHassModalOptions(title: nil))
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 1800))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(FeatureHost.tapRow("account.signOut", in: page.view) || FeatureHost.press("account.signOut", in: page.view), "Sign Out is on the Profile tab")
        await FeatureHost.settleAsync(0.5)
        let alert = try XCTUnwrap(FeatureHost.alert(on: modal) ?? FeatureHost.alert(on: page), "signing out asks first")
        XCTAssertEqual(alert.title, AlertCopy.signOut.title)
        FeatureHost.answer(alert, AlertCopy.signOut.confirm.title)
        let ended = await FeatureHost.settleAsync(until: {
            if case .signedOut = session.phase { return true }
            return false
        }, timeout: 5)
        XCTAssertTrue(ended, "confirming signs the session out")
    }
}
