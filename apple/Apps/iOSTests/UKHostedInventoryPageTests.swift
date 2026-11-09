import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The inventory page driven by its presentation: quantity prompts, delete confirmations, the editor beside the list in a wide
/// window, pull to refresh and the section headers.
@MainActor
final class UKHostedInventoryPageTests: DemoHouseTestCase {
    private struct Rig {
        let page: UKInventoryViewController
        let model: InventoryListModel
        let presentation: InventoryPresentation
        let server: EverShelfFixtureServer
        let window: UIWindow
    }

    private func rig(wide: Bool = false, space: InventorySpace = .pantry) async -> Rig {
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(10)
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let model = models.model(for: space)
        let presentation = InventoryPresentation()
        let context = UKGalleryChrome.context()
        let page = UKInventoryViewController(context: context, model: model, models: models, presentation: presentation)
        let host = UKGalleryChrome.wrap(page, context: context)
        let window: UIWindow
        if wide {
            let root = UIViewController()
            root.addChild(host)
            host.view.frame = root.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            root.view.addSubview(host.view)
            host.didMove(toParent: root)
            root.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .regular), forChild: host)
            window = HostedPage.show(root, size: CGSize(width: 1100, height: 800))
        } else {
            window = HostedPage.show(host, size: CGSize(width: 393, height: 2200))
        }
        await FeatureHost.settleAsync(1.0)
        return Rig(page: page, model: model, presentation: presentation, server: server, window: window)
    }

    private func item(_ name: String, _ r: Rig) throws -> InventoryDisplayItem {
        try XCTUnwrap(r.model.displayItems.first { $0.name == name }, "the pantry has \(name)")
    }

    func testStatusSectionsAreNamedWithTheirCounts() async {
        let r = await rig()
        defer { r.window.isHidden = true }
        XCTAssertFalse(FeatureHost.identifiers(in: r.page.view).contains { $0.hasPrefix("inventory.section.") }, "a title-sorted page is one list, with no status headers")
        r.model.sortMode = .expiry
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(FeatureHost.identifiers(in: r.page.view).contains { $0.hasPrefix("inventory.section.") }, "sorted by expiration, items are grouped under status headers: \(FeatureHost.describeLists(in: r.page.view))")
    }

    func testAddToGroceriesAsksForAQuantityThenSendsIt() async throws {
        let r = await rig()
        defer { r.window.isHidden = true }
        let beans = try item("Black Beans", r)
        let before = r.server.calls.count
        r.presentation.ask(.shopping(beans))
        await FeatureHost.settleAsync(0.8)
        let alert = try XCTUnwrap(FeatureHost.alert(on: r.page), "the quantity prompt is up")
        XCTAssertEqual(alert.title, "Add Black Beans to Groceries")
        let field = try XCTUnwrap(alert.textFields?.first)
        XCTAssertEqual(field.text, "1", "it starts at one")
        XCTAssertEqual(field.accessibilityIdentifier, "inventory.prompt.field")
        field.text = "3"
        XCTAssertTrue(FeatureHost.answer(alert, InventoryPrompt.shopping(beans).confirmTitle))
        await FeatureHost.settleAsync(0.8)
        XCTAssertGreaterThan(r.server.calls.count, before, "the list was updated: \(r.server.calls.suffix(3))")
        XCTAssertNil(r.presentation.prompt)
    }

    func testCancellingThePromptSendsNothing() async throws {
        let r = await rig()
        defer { r.window.isHidden = true }
        let before = r.server.calls.count
        r.presentation.ask(.shopping(try item("Black Beans", r)))
        await FeatureHost.settleAsync(0.8)
        let alert = try XCTUnwrap(FeatureHost.alert(on: r.page))
        XCTAssertTrue(FeatureHost.answer(alert, "Cancel"))
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(r.server.calls.count, before)
        XCTAssertNil(r.presentation.prompt)
    }

    func testDeletingSeveralUnitsAsksHowManyAndOneUnitJustConfirms() async throws {
        let r = await rig()
        defer { r.window.isHidden = true }
        let many = try XCTUnwrap(r.model.displayItems.first { r.model.deletableRows(of: $0).map { rows in rows.reduce(0) { $0 + $1.quantity } > 1 } == true })
        r.presentation.requestDelete(many, in: r.model)
        await FeatureHost.settleAsync(until: { FeatureHost.alert(on: r.page) != nil })
        let prompt = try XCTUnwrap(FeatureHost.alert(on: r.page), "more than one unit asks how many to delete")
        XCTAssertEqual(prompt.title, "Delete \(many.name)")
        XCTAssertTrue(FeatureHost.answer(prompt, "Cancel"))
        await FeatureHost.settleAsync(until: { FeatureHost.alert(on: r.page) == nil })

        let single = r.model.displayItems.first { r.model.deletableRows(of: $0).map { rows in rows.reduce(0) { $0 + $1.quantity } <= 1 } == true }
        guard let single else { return }
        r.presentation.requestDelete(single, in: r.model)
        await FeatureHost.settleAsync(until: { FeatureHost.alert(on: r.page)?.title == "Delete \(single.name)?" })
        let confirm = try XCTUnwrap(FeatureHost.alert(on: r.page), "one unit asks for confirmation")
        XCTAssertEqual(confirm.title, "Delete \(single.name)?")
        let destructive = try XCTUnwrap(confirm.actions.first { $0.style == .destructive }?.title)
        XCTAssertTrue(FeatureHost.answer(confirm, destructive))
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(r.server.calls.contains { $0.contains("delete_inventory") }, "\(r.server.calls.suffix(3))")
    }

    func testCancellingTheDeleteConfirmationKeepsTheItem() async throws {
        let r = await rig()
        defer { r.window.isHidden = true }
        guard let single = r.model.displayItems.first(where: { r.model.deletableRows(of: $0).map { rows in rows.reduce(0) { $0 + $1.quantity } <= 1 } == true }) else { return }
        r.presentation.requestDelete(single, in: r.model)
        await FeatureHost.settleAsync(0.8)
        let confirm = try XCTUnwrap(FeatureHost.alert(on: r.page))
        XCTAssertTrue(FeatureHost.answer(confirm, "Cancel"))
        await FeatureHost.settleAsync(0.5)
        XCTAssertFalse(r.server.calls.contains { $0.contains("delete_inventory") })
        XCTAssertNil(r.presentation.confirmDelete)
    }

    func testOnAWideWindowTheEditorOpensBesideTheList() async throws {
        let r = await rig(wide: true)
        defer { r.window.isHidden = true }
        r.presentation.open(try item("Black Beans", r), in: r.model)
        await FeatureHost.settleAsync(1.2)
        XCTAssertNotNil(FeatureHost.view("inventory.editor", in: r.page.view), "the editor sits in the trailing column")
        XCTAssertNil(r.page.presentedViewController, "and is not a sheet")
        r.presentation.editing = nil
        await FeatureHost.settleAsync(0.8)
        XCTAssertNotNil(FeatureHost.view("inventory.pane.placeholder", in: r.page.view), "closing it leaves the prompt to pick an item")
    }

    func testOnANarrowWindowTheEditorIsASheetThatClearsWhenDismissed() async throws {
        let r = await rig()
        defer { r.window.isHidden = true }
        r.presentation.open(try item("Black Beans", r), in: r.model)
        await FeatureHost.settleAsync(1.0)
        let sheet = try XCTUnwrap(r.page.shownSheet)
        XCTAssertNotNil(FeatureHost.view("inventory.editor", in: sheet.view))
        // A swipe down dismisses the sheet and tells its delegate (a programmatic dismissal does not).
        let modal = try XCTUnwrap(sheet as? UKHassModalController)
        let presentationController = try XCTUnwrap(modal.presentationController)
        modal.dismiss(animated: false)
        modal.presentationControllerDidDismiss(presentationController)
        await FeatureHost.settleAsync(0.6)
        XCTAssertNil(r.presentation.editing, "dismissing the sheet closes the editor model")
    }

    func testTheSortSheetClosesWhenTheModelClearsIt() async {
        let r = await rig()
        defer { r.window.isHidden = true }
        r.presentation.sheet = .sort
        await FeatureHost.settleAsync(0.8)
        XCTAssertNotNil(r.page.shownSheet)
        r.presentation.sheet = nil
        await FeatureHost.settleAsync(0.8)
        XCTAssertNil(r.page.presentedViewController, "the model took the sheet down")
    }
}
