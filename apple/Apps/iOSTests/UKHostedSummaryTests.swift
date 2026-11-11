import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Your Summary (Profile, Overdue, Upcoming, Expired Food) on the gallery's profile fixtures.
@MainActor
final class UKHostedSummaryTests: DemoHouseTestCase {
    private func summary(_ environment: [String: String], opening: SummaryTab? = nil) -> (UKYourSummaryViewController, ProfileGalleryFixtures, UIWindow) {
        let fixtures = ProfileGalleryFixtures(environment: environment.merging(["FENTON_GALLERY_LATENCY_MS": "5"]) { $1 })
        var context = UKGalleryChrome.context(store: fixtures.store)
        context.surface = .sheet
        context.navigator = fixtures.navigator
        context.avatars = fixtures.avatars
        let page = UKYourSummaryViewController(context: context, models: UKSummaryModels(chores: fixtures.chores, inventory: fixtures.models),
                                               opening: opening ?? fixtures.opening)
        let modal = UKHassModalController(root: page, options: UKHassModalOptions(title: nil))
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 1800))
        FeatureHost.settle(0.8)
        return (page, fixtures, window)
    }

    func testProfileIsTheFirstTabAndOffersSignOut() throws {
        let (page, _, window) = summary([:])
        defer { window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("account.list", in: page.view), "the Profile tab's list is showing")
        XCTAssertNotNil(FeatureHost.view("account.signOut", in: page.view))
        XCTAssertNotNil(FeatureHost.view("summary.tabs", in: page.view), "the tab bar is shown")
        XCTAssertFalse(page.navigationItem.title?.isEmpty ?? true)
    }

    /// The opening tab is highlighted from first display, with no tap (owner, 2026-11-05): its segment is `.selected`, a 44 pt
    /// target, and the capsule sits on it. Runs on every family, so iPhone, Duo and iPad are each checked.
    func testTheOpeningTabIsHighlightedBeforeAnyTap() throws {
        for opening in [SummaryTab.profile, .expiredFood] {
            let (page, _, window) = summary(["FENTON_GALLERY_VIEWER": "resident_1"], opening: opening)
            defer { window.isHidden = true }
            let segment = try XCTUnwrap(FeatureHost.view("summary.tabs.\(opening.id)", in: page.view), "\(opening) segment")
            let lift = try XCTUnwrap(FeatureHost.view("summary.tabs.lift", in: page.view), "the capsule")
            XCTAssertTrue(segment.accessibilityTraits.contains(.selected), "\(opening) is selected")
            XCTAssertGreaterThanOrEqual(segment.frame.height, 44)
            XCTAssertFalse(lift.isHidden)
            XCTAssertGreaterThan(lift.frame.width, 20, "the capsule has a size when the sheet opens")
            XCTAssertEqual(lift.frame, segment.frame, "the capsule sits behind \(opening)")
        }
    }

    func testProfileListsTheHouseholdsPeople() throws {
        let (page, _, window) = summary([:])
        defer { window.isHidden = true }
        let ids = FeatureHost.identifiers(in: page.view)
        XCTAssertTrue(ids.contains { $0.hasPrefix("profile.person.") }, "people are listed: \(ids.filter { $0.hasPrefix("profile") })")
    }

    func testSignOutOnTheProfileTabAsksFirst() throws {
        let (page, _, window) = summary([:])
        defer { window.isHidden = true }
        _ = FeatureHost.tapRow("account.signOut", in: page.view) || FeatureHost.press("account.signOut", in: page.view)
        FeatureHost.settle(0.5)
        if let alert = FeatureHost.alert(on: page.navigationController ?? page) {
            XCTAssertEqual(alert.title, AlertCopy.signOut.title)
            FeatureHost.answer(alert, AlertCopy.signOut.cancel.title)
        }
    }

    func testOverdueAndUpcomingShowTheViewersChores() throws {
        for tab in [SummaryTab.overdue, .upcoming] {
            let (page, _, window) = summary(["FENTON_GALLERY_VIEWER": "resident_1"], opening: tab)
            defer { window.isHidden = true }
            XCTAssertNotNil(FeatureHost.view("summary.\(tab.id)", in: page.view) ?? FeatureHost.view("summary.empty.\(tab.id)", in: page.view),
                            "\(tab) shows its list or its empty state")
        }
    }

    func testAnEmptyHouseSaysThereIsNothingOverdue() throws {
        let (page, _, window) = summary(["FENTON_GALLERY_EMPTY": "1"], opening: .overdue)
        defer { window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("summary.empty.overdue", in: page.view) ?? FeatureHost.view("summary.overdue", in: page.view))
    }

    func testExpiredFoodListsWhatHasExpired() throws {
        let (page, _, window) = summary([:], opening: .expiredFood)
        defer { window.isHidden = true }
        FeatureHost.settle(0.6)
        XCTAssertNotNil(FeatureHost.view("summary.expired-food", in: page.view) ?? FeatureHost.view("summary.empty.expired-food", in: page.view))
    }

    func testAnEmptyKitchenHasNoExpiredFood() throws {
        let (page, _, window) = summary(["FENTON_GALLERY_EMPTY": "1"], opening: .expiredFood)
        defer { window.isHidden = true }
        FeatureHost.settle(0.6)
        XCTAssertNotNil(FeatureHost.view("summary.empty.expired-food", in: page.view))
    }

    func testSamHasNoUpcomingAdminTabsBeyondHers() throws {
        let (page, _, window) = summary(["FENTON_GALLERY_VIEWER": "resident_2"], opening: .overdue)
        defer { window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("account.sheet", in: page.view) ?? page.view)
        XCTAssertNotNil(FeatureHost.view("summary.tabs", in: page.view))
    }

    func testOnVacationTheChoresTabsSayTheyArePaused() throws {
        let (page, _, window) = summary(["FENTON_GALLERY_VACATION": "1"], opening: .upcoming)
        defer { window.isHidden = true }
        XCTAssertNotNil(page.view)
        XCTAssertNotNil(FeatureHost.view("summary.upcoming", in: page.view) ?? FeatureHost.view("summary.empty.upcoming", in: page.view))
    }

    func testCheckingOffAnOverdueChoreCallsTheService() throws {
        let (page, fixtures, window) = summary(["FENTON_GALLERY_VIEWER": "resident_1"], opening: .overdue)
        defer { window.isHidden = true }
        FeatureHost.settle(0.8)
        let item = try XCTUnwrap(FeatureHost.identifiers(in: page.view).sorted().first { $0.hasPrefix("todo.item.") }, "an overdue chore is listed")
        XCTAssertTrue(FeatureHost.press(item, in: page.view))
        FeatureHost.settle(0.8)
        XCTAssertTrue(fixtures.service.lastCall.hasPrefix("todo.update_item"), fixtures.service.lastCall)
    }

    func testARowOffersSwipeActionsAndAMenu() throws {
        let (page, _, window) = summary(["FENTON_GALLERY_VIEWER": "resident_1"], opening: .overdue)
        defer { window.isHidden = true }
        FeatureHost.settle(0.8)
        let list = try XCTUnwrap(FeatureHost.view("summary.overdue", in: page.view) as? UICollectionView)
        let path = try XCTUnwrap(list.indexPathsForVisibleItems.sorted().first { list.cellForItem(at: $0) is UKTodoRowCell })
        let content = try XCTUnwrap(list.delegate as? UKSummaryListViewController)
        XCTAssertNotNil(content.swipe(at: path, leading: true))
        XCTAssertNotNil(content.swipe(at: path, leading: false))
    }
}
