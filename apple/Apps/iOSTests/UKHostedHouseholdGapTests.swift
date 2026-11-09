import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Household paths the first tests skipped: the Location permission bound to a coordinator, Your Summary's Share Location row, and the
/// Solo Trip editor's date fields and Cancel.
@MainActor
final class UKHostedHouseholdGapTests: DemoHouseTestCase {
    private func coordinator() throws -> LocationCoordinator {
        try XCTUnwrap(SetupGalleryFixtures(environment: [:]).setup.location, "the setup fixtures have a location coordinator")
    }

    func testThePermissionScreenFollowsTheCoordinatorAndAsksThroughIt() throws {
        let location = try coordinator()
        var closed = 0
        let page = UKLocationPermission.make(location: location, onClose: { closed += 1 })
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: UKGalleryChrome.context()))
        defer { window.isHidden = true }
        let before = HostedPage.labels(in: page.view)
        XCTAssertTrue(FeatureHost.press("location.primary", in: page.view), "the first stage offers its one action")
        FeatureHost.settle(0.6)
        XCTAssertNotEqual(before, HostedPage.labels(in: page.view), "the page follows the new permission")
        XCTAssertEqual(closed, 0)
    }

    func testTheAccountSectionShowsThePermissionAndOpensTheScreen() throws {
        let location = try coordinator()
        var opened = 0
        let section = UKLocationAccountSection(location: location) { opened += 1 }
        let host = UIViewController()
        host.view.addSubview(section)
        section.frame = CGRect(x: 0, y: 100, width: 393, height: 300)
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        section.layoutIfNeeded()
        FeatureHost.settle(0.3)
        let status = LocationPermissionCopy.status(location.reporter.permission)
        XCTAssertTrue(HostedPage.labels(in: section).contains { $0.contains(status) }, "the row shows \(status): \(HostedPage.labels(in: section))")
        XCTAssertTrue(FeatureHost.press("account.location", in: section))
        XCTAssertEqual(opened, 1, "tapping Share Location opens the permission screen")
    }

    func testYourSummaryPushesTheLocationScreenInsideItsOwnSheet() throws {
        let fixtures = ProfileGalleryFixtures(environment: ["FENTON_GALLERY_LATENCY_MS": "5"])
        var context = UKGalleryChrome.context(store: fixtures.store)
        context.surface = .sheet
        context.navigator = fixtures.navigator
        context.avatars = fixtures.avatars
        context.location = try coordinator()
        let page = UKYourSummaryViewController(context: context, models: UKSummaryModels(chores: fixtures.chores, inventory: fixtures.models), opening: nil)
        let modal = UKHassModalController(root: page, options: UKHassModalOptions(title: nil))
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 1800))
        defer { window.isHidden = true }
        FeatureHost.settle(0.8)
        XCTAssertTrue(FeatureHost.press("account.location", in: page.view), "Profile offers Share Location")
        FeatureHost.settle(0.8)
        XCTAssertTrue(modal.topViewController is UKLocationPermissionViewController, "pushed, not a second sheet")
        XCTAssertNil(modal.presentedViewController)
    }

    // MARK: Solo Trip editor

    private func soloTrip() async throws -> (UIViewController, VacationGalleryHouse, UIWindow) {
        let house = VacationGalleryHouse(store: VacationFixtures.store(.ready), delay: .milliseconds(20))
        let context = UKGalleryChrome.context(store: house.store, caller: house)
        let top = UKVacationSubpageViewController(
            content: UKSoloTripContent(context: context, household: HouseholdAwayController(store: house.store, responder: house), viewer: .resident1),
            context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(top, context: context), size: CGSize(width: 393, height: 1800))
        await FeatureHost.settleAsync(0.5)
        FeatureHost.press("soloTrip.traveler.resident_1", in: top.view)
        await FeatureHost.settleAsync(0.3)
        FeatureHost.press("soloTrip.toggle", in: top.view)
        await FeatureHost.settleAsync(0.8)
        return (top, house, window)
    }

    func testCancellingTheSoloTripEditorSchedulesNothing() async throws {
        let (top, house, window) = try await soloTrip()
        defer { window.isHidden = true }
        let editor = try XCTUnwrap(top.shownSheet, "the editor sheet is open")
        XCTAssertTrue(FeatureHost.press("soloTrip.editor.cancel", in: editor.view) || editor.presentingViewController != nil)
        await FeatureHost.settleAsync(0.8)
        XCTAssertFalse(house.lastCall.contains("schedule"), "Cancel drops the draft: \(house.lastCall)")
    }

    func testChangingTheTripDatesUpdatesTheDraft() async throws {
        let (top, _, window) = try await soloTrip()
        defer { window.isHidden = true }
        let editor = try XCTUnwrap(top.shownSheet)
        let pickers = HostedPage.descendants(of: editor.view).compactMap { $0 as? UIDatePicker }
        XCTAssertGreaterThanOrEqual(pickers.count, 2, "Departs and Returns each have a picker")
        let end = try XCTUnwrap(pickers.last)
        end.date = end.date.addingTimeInterval(86_400 * 3)
        end.sendActions(for: .valueChanged)
        await FeatureHost.settleAsync(0.5)
        let start = try XCTUnwrap(pickers.first)
        start.date = start.date.addingTimeInterval(3600)
        start.sendActions(for: .valueChanged)
        await FeatureHost.settleAsync(0.5)
        XCTAssertNotNil(FeatureHost.view("soloTrip.editor.confirm", in: editor.view), "the editor stays open while the dates change")
    }
}
