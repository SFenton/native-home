import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Your Summary's Expired Food tab: its swipe actions, the held swipe Delete, a failed delete that brings the card back, the load error
/// and pull to refresh. Every change goes through the tab's own code (the app's copy of HassCore), not through the model from test code.
@MainActor
final class UKHostedSummaryExpiredFoodTests: DemoHouseTestCase {
    private struct Rig {
        let page: UKYourSummaryViewController
        let tab: UKSummaryExpiredFoodViewController
        let fixtures: ProfileGalleryFixtures
        let window: UIWindow
    }

    private func find<T: UIViewController>(_ type: T.Type, in controller: UIViewController) -> T? {
        if let match = controller as? T { return match }
        for child in controller.children { if let match = find(type, in: child) { return match } }
        return nil
    }

    private func rig(prepare: (ProfileGalleryFixtures) -> Void = { _ in }) async throws -> Rig {
        let fixtures = ProfileGalleryFixtures(environment: ["FENTON_GALLERY_LATENCY_MS": "5"])
        prepare(fixtures)
        var context = UKGalleryChrome.context(store: fixtures.store)
        context.surface = .sheet
        context.navigator = fixtures.navigator
        context.avatars = fixtures.avatars
        let page = UKYourSummaryViewController(context: context, models: UKSummaryModels(chores: fixtures.chores, inventory: fixtures.models),
                                               opening: .expiredFood)
        let modal = UKHassModalController(root: page, options: UKHassModalOptions(title: nil))
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 1800))
        await FeatureHost.settleAsync(0.5)
        let tab = try XCTUnwrap(find(UKSummaryExpiredFoodViewController.self, in: page), "the Expired Food tab is up")
        // Rows, or the error: the spinner row is not a result.
        await FeatureHost.settleAsync(until: {
            tab.dataSource.snapshot().itemIdentifiers.contains { !["header", "spinner", "error"].contains($0) }
                || FeatureHost.view("summary.expired-food.error", in: tab.view) != nil
        })
        return Rig(page: page, tab: tab, fixtures: fixtures, window: window)
    }

    private func alert(_ r: Rig) -> UIAlertController? {
        FeatureHost.alert(on: r.tab) ?? FeatureHost.alert(on: r.page) ?? r.page.navigationController.flatMap { FeatureHost.alert(on: $0) }
    }

    /// Jasmine Rice (one unit, expired) with its trailing swipe: a Delete that asks a plain confirmation, not a quantity.
    private func deletable(_ r: Rig) throws -> (IndexPath, UISwipeActionsConfiguration) {
        let path = try XCTUnwrap(r.tab.dataSource.indexPath(for: "jasmine rice"), "Jasmine Rice is listed as expired")
        return (path, try XCTUnwrap(r.tab.swipe(at: path, leading: false), "a single-unit row offers Delete"))
    }

    func testARowOffersAddToGroceriesOnTheLeadingEdgeAndDeleteOnTheTrailingEdge() async throws {
        let r = try await rig()
        defer { r.window.isHidden = true }
        let header = r.tab.swipe(at: IndexPath(item: 0, section: 0), leading: true)
        XCTAssertNil(header, "the header has no swipe")
        let leading = try XCTUnwrap(r.tab.swipe(at: IndexPath(item: 1, section: 0), leading: true))
        XCTAssertEqual(leading.actions.first?.title, "Add to Groceries")
        var shopped: [Bool] = []
        leading.actions.first?.handler(leading.actions[0], r.tab.view) { shopped.append($0) }
        XCTAssertEqual(shopped, [true], "the swipe closes once the quantity prompt is asked")
        let (_, trailing) = try deletable(r)
        XCTAssertEqual(trailing.actions.first?.title, "Delete")
        XCTAssertTrue(r.tab.collectionView(r.tab.collectionView, shouldHighlightItemAt: IndexPath(item: 1, section: 0)) == false)
    }

    func testAHeldSwipeDeleteLeavesWithTheCardWhenConfirmed() async throws {
        let r = try await rig()
        defer { r.window.isHidden = true }
        let before = r.tab.collectionView.numberOfItems(inSection: 0)
        let (_, trailing) = try deletable(r)
        var results: [Bool] = []
        trailing.actions[0].handler(trailing.actions[0], r.tab.view) { results.append($0) }
        await FeatureHost.settleAsync(until: { alert(r) != nil })
        let confirm = try XCTUnwrap(alert(r), "Delete asks first")
        XCTAssertTrue(results.isEmpty, "the swipe stays open while the confirmation is up")
        let delete = try XCTUnwrap(confirm.actions.first { $0.style == .destructive }?.title)
        XCTAssertTrue(FeatureHost.answer(confirm, delete))
        await FeatureHost.settleAsync(until: { r.tab.collectionView.numberOfItems(inSection: 0) < before })
        XCTAssertEqual(results.last, true, "confirm completes the swipe as the card leaves")
        XCTAssertEqual(r.tab.collectionView.numberOfItems(inSection: 0), before - 1)
    }

    func testCancellingTheConfirmationClosesTheSwipeAndKeepsTheCard() async throws {
        let r = try await rig()
        defer { r.window.isHidden = true }
        let before = r.tab.collectionView.numberOfItems(inSection: 0)
        let (_, trailing) = try deletable(r)
        var results: [Bool] = []
        trailing.actions[0].handler(trailing.actions[0], r.tab.view) { results.append($0) }
        await FeatureHost.settleAsync(until: { alert(r) != nil })
        let confirm = try XCTUnwrap(alert(r))
        XCTAssertTrue(FeatureHost.answer(confirm, confirm.actions.first { $0.style == .cancel }?.title))
        await FeatureHost.settleAsync(until: { !results.isEmpty })
        XCTAssertEqual(results.last, false)
        XCTAssertEqual(r.tab.collectionView.numberOfItems(inSection: 0), before)
    }

    func testAFailedDeleteBringsTheCardBack() async throws {
        // A slow server, so the card is seen gone before the refusal brings it back.
        let r = try await rig { $0.server.failing = ["evershelf.delete_inventory"]; $0.server.latency = .milliseconds(1500) }
        defer { r.window.isHidden = true }
        let before = r.tab.collectionView.numberOfItems(inSection: 0)
        let (_, trailing) = try deletable(r)
        var results: [Bool] = []
        trailing.actions[0].handler(trailing.actions[0], r.tab.view) { results.append($0) }
        await FeatureHost.settleAsync(until: { alert(r) != nil })
        let confirm = try XCTUnwrap(alert(r))
        XCTAssertTrue(FeatureHost.answer(confirm, try XCTUnwrap(confirm.actions.first { $0.style == .destructive }?.title)))
        await FeatureHost.settleAsync(until: { !results.isEmpty })
        XCTAssertEqual(results.count, 1, "the swipe is settled once, as the card starts to leave")
        // The card leaves at once (the delete is optimistic) and comes back when the server refuses.
        var left = false
        await FeatureHost.settleAsync(until: {
            left = left || r.tab.collectionView.numberOfItems(inSection: 0) == before - 1
            return left && r.fixtures.server.calls.contains { $0.contains("delete_inventory") }
        })
        XCTAssertTrue(left, "the card left before it came back")
        await FeatureHost.settleAsync(until: { r.tab.collectionView.numberOfItems(inSection: 0) == before })
        XCTAssertEqual(r.tab.collectionView.numberOfItems(inSection: 0), before, "the card is back")
    }

    func testALoadErrorShowsInlineInPlaceOfTheRows() async throws {
        let r = try await rig { $0.server.failing = ["evershelf.list_inventory"] }
        defer { r.window.isHidden = true }
        await FeatureHost.settleAsync(until: { FeatureHost.view("summary.expired-food.error", in: r.tab.view) != nil })
        XCTAssertNotNil(FeatureHost.view("summary.expired-food.error", in: r.tab.view), "the error is said where the rows would be")
    }

    func testPullingToRefreshReloadsTheRows() async throws {
        let r = try await rig()
        defer { r.window.isHidden = true }
        let refresh = try XCTUnwrap(r.tab.collectionView.refreshControl)
        let calls = r.fixtures.server.calls.count
        refresh.sendActions(for: .valueChanged)
        await FeatureHost.settleAsync(until: { r.fixtures.server.calls.count > calls })
        XCTAssertGreaterThan(r.fixtures.server.calls.count, calls, "the pull asks the server again")
    }
}
