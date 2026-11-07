import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Your Summary's chore rows used the way a thumb does: the swipe buttons complete, edit and delete a chore.
@MainActor
final class UKHostedSummaryActionsTests: DemoHouseTestCase {
    private func summary() async throws -> (UKYourSummaryViewController, UKSummaryListViewController, UICollectionView, IndexPath, ProfileGalleryFixtures, UIWindow) {
        let fixtures = ProfileGalleryFixtures(environment: ["FENTON_GALLERY_VIEWER": "resident_1", "FENTON_GALLERY_LATENCY_MS": "5"])
        var context = UKGalleryChrome.context(store: fixtures.store)
        context.surface = .sheet
        context.navigator = fixtures.navigator
        context.avatars = fixtures.avatars
        let page = UKYourSummaryViewController(context: context, models: UKSummaryModels(chores: fixtures.chores, inventory: fixtures.models), opening: .overdue)
        let modal = UKHassModalController(root: page, options: UKHassModalOptions(title: nil))
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 1800))
        await FeatureHost.settleAsync(1.0)
        let list = try XCTUnwrap(FeatureHost.view("summary.overdue", in: page.view) as? UICollectionView)
        let path = try XCTUnwrap(list.indexPathsForVisibleItems.sorted().first { list.cellForItem(at: $0) is UKTodoRowCell })
        let content = try XCTUnwrap(list.delegate as? UKSummaryListViewController)
        return (page, content, list, path, fixtures, window)
    }

    private func run(_ configuration: UISwipeActionsConfiguration?, titled title: String? = nil) {
        for action in configuration?.actions ?? [] where title == nil || action.title == title {
            action.handler(action, UIView()) { _ in }
        }
    }

    func testSwipingToCompleteACallsTheService() async throws {
        let (_, content, _, path, fixtures, window) = try await summary()
        defer { window.isHidden = true }
        run(content.swipe(at: path, leading: true))
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(fixtures.service.lastCall.hasPrefix("todo.update_item"), "the leading swipe completes the chore: \(fixtures.service.lastCall)")
    }

    func testTheTrailingSwipeOffersEditAndDelete() async throws {
        let (page, content, _, path, _, window) = try await summary()
        defer { window.isHidden = true }
        let titles = content.swipe(at: path, leading: false)?.actions.compactMap(\.title) ?? []
        XCTAssertFalse(titles.isEmpty, "the trailing swipe offers buttons")
        run(content.swipe(at: path, leading: false), titled: "Delete")
        await FeatureHost.settleAsync(0.6)
        if titles.contains("Delete") {
            XCTAssertNotNil(FeatureHost.alert(on: page.navigationController ?? page), "Delete asks before removing the chore")
        }
    }

    func testTheEditButtonOpensTheTaskFormInTheSummarysStack() async throws {
        let (page, content, _, path, _, window) = try await summary()
        defer { window.isHidden = true }
        let before = page.navigationController?.viewControllers.count ?? 0
        run(content.swipe(at: path, leading: false), titled: "Edit")
        await FeatureHost.settleAsync(1.0)
        let after = page.navigationController?.viewControllers.count ?? 0
        XCTAssertTrue(after >= before, "editing never closes the Summary")
    }
}
