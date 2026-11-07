import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Inventory behaviour the first hosted tests skipped: pull to refresh, swipe actions, the editor's expiration switch and error line,
/// the editor beside the list refusing to close with unsaved changes, and the Add Item sheet's failure line and quantity stepper.
@MainActor
final class UKHostedInventoryGapTests: DemoHouseTestCase {
    private struct Rig {
        let page: UKInventoryViewController
        let model: InventoryListModel
        let presentation: InventoryPresentation
        let server: EverShelfFixtureServer
        let window: UIWindow
    }

    private func rig(wide: Bool = false) async -> Rig {
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(10)
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let model = models.model(for: .pantry)
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

    private func listController(in controller: UIViewController) -> UKInventoryListViewController? {
        if let list = controller as? UKInventoryListViewController { return list }
        for child in controller.children { if let hit = listController(in: child) { return hit } }
        return nil
    }

    func testPullingTheListDownReloadsIt() async throws {
        let r = await rig()
        defer { r.window.isHidden = true }
        let list = try XCTUnwrap(HostedPage.descendants(of: r.page.view).compactMap { ($0 as? UICollectionView)?.refreshControl }.first, "the list pulls to refresh")
        let before = r.server.calls.count
        list.sendActions(for: .valueChanged)
        await FeatureHost.settleAsync(0.8)
        XCTAssertGreaterThan(r.server.calls.count, before, "pulling asks the server again: \(r.server.calls)")
    }

    func testSwipingARowOffersAddToGroceriesAndDeleteForASingleBatch() async throws {
        let r = await rig()
        defer { r.window.isHidden = true }
        let list = try XCTUnwrap(listController(in: r.page))
        let collection = try XCTUnwrap(HostedPage.descendants(of: r.page.view).compactMap { $0 as? UICollectionView }.first)
        var shopped = 0
        var deleted = 0
        list.onShop = { _ in shopped += 1 }
        list.onDelete = { _ in deleted += 1 }
        let paths = (0..<collection.numberOfSections).flatMap { section in (0..<collection.numberOfItems(inSection: section)).map { IndexPath(item: $0, section: section) } }
        let leading = paths.compactMap { list.leadingSwipe(at: $0) }
        XCTAssertFalse(leading.isEmpty, "rows swipe to Add to Groceries")
        let action = try XCTUnwrap(leading.first?.actions.first)
        XCTAssertEqual(action.title, "Add to Groceries")
        action.handler(action, UIView(), { _ in })
        XCTAssertEqual(shopped, 1)
        let trailing = paths.compactMap { list.trailingSwipe(at: $0) }
        XCTAssertFalse(trailing.isEmpty, "a one-batch row swipes to Delete")
        let delete = try XCTUnwrap(trailing.first?.actions.first)
        XCTAssertEqual(delete.title, "Delete")
        delete.handler(delete, UIView(), { _ in })
        XCTAssertEqual(deleted, 1)
    }

    // MARK: Editor

    private func editor(wide: Bool = false, item name: String = "Black Beans") async throws -> (InventoryEditorModel, UKInventoryEditorViewController, EverShelfFixtureServer, UIWindow) {
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(10)
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let list = models.model(for: .pantry)
        await list.load()
        let item = try XCTUnwrap(list.displayItems.first { $0.name == name })
        let model = InventoryEditorModel(item: item, list: list)
        let page = UKInventoryEditorViewController(model: model, style: .sheet, context: UKGalleryChrome.context().with { $0.surface = .sheet }, onClose: {})
        let window = HostedPage.show(UKHassModalController(root: page, options: UKHassModalOptions(title: model.title)), size: CGSize(width: 393, height: 2200))
        await FeatureHost.settleAsync(0.6)
        return (model, page, server, window)
    }

    func testTheExpirationSwitchSetsTodayThenClearsIt() async throws {
        let (model, page, _, window) = try await editor()
        defer { window.isHidden = true }
        let batch = try XCTUnwrap(model.batches.first)
        let had = !batch.expiryDate.isEmpty
        XCTAssertTrue(FeatureHost.flip("inventory.editor.hasExpiry", in: page.view))
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(model.hasChanges(batch), "flipping the switch edits the batch")
        if had { XCTAssertTrue(model.expiry(batch).isEmpty, "turning it off clears the date") } else {
            XCTAssertEqual(model.expiry(batch), model.calendar.isoString(model.calendar.today), "turning it on starts at today")
        }
    }

    func testChoosingADateStoresIt() async throws {
        let (model, page, _, window) = try await editor()
        defer { window.isHidden = true }
        let batch = try XCTUnwrap(model.batches.first)
        if batch.expiryDate.isEmpty { FeatureHost.flip("inventory.editor.hasExpiry", in: page.view); await FeatureHost.settleAsync(0.3) }
        let picker = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UIDatePicker }.first, "an expiring batch shows its date")
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        picker.date = date
        picker.sendActions(for: .valueChanged)
        await FeatureHost.settleAsync(0.3)
        XCTAssertEqual(model.expiry(batch), model.calendar.isoString(date))
    }

    func testASaveTheServerRefusesShowsTheErrorOnTheForm() async throws {
        let (model, page, server, window) = try await editor()
        defer { window.isHidden = true }
        server.failing = ["evershelf.update_inventory_item", "evershelf.delete_inventory", "evershelf.add_scanned_item", "evershelf.set_inventory_prepared_food"]
        let batch = try XCTUnwrap(model.batches.first)
        model.setQuantity(max(batch.quantity - 1, 0), for: batch)
        await FeatureHost.settleAsync(0.3)
        let save = try XCTUnwrap(page.navigationItem.rightBarButtonItem)
        _ = save.primaryAction?.performWithSender(nil, target: nil)
        await FeatureHost.settleAsync(1.2)
        XCTAssertEqual(model.error, "EverShelf is unavailable")
        XCTAssertNotNil(FeatureHost.view("inventory.editor.error", in: page.view), "and it is shown on the form")
    }

    func testDeletingAOneUnitBatchAsksWithTheDialogNotTheQuantityPrompt() async throws {
        let server = EverShelfFixtureServer.sample()
        XCTAssertEqual(server.rows.filter { $0.name == "Spaghetti" }.map(\.quantity), [1], "Spaghetti is one batch of one unit")
        let (_, page, _, window) = try await editor(item: "Spaghetti")
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("inventory.editor.delete", in: page.view))
        await FeatureHost.settleAsync(0.5)
        let alert = try XCTUnwrap(FeatureHost.alert(on: page), "one unit just asks to confirm")
        XCTAssertNil(alert.textFields?.first, "no quantity field for a single unit")
    }

    // MARK: Pane

    func testTheEditorBesideTheListTellsTheColumnsWhenItHasUnsavedChanges() async throws {
        let r = await rig(wide: true)
        defer { r.window.isHidden = true }
        let item = try XCTUnwrap(r.model.displayItems.first { $0.name == "Black Beans" })
        r.presentation.open(item, in: r.model)
        await FeatureHost.settleAsync(1.2)
        let pane = try XCTUnwrap(HostedPage.descendants(of: r.page.view).first { $0.accessibilityIdentifier == "inventory.editor" })
        let editor = try XCTUnwrap(r.presentation.editing)
        let batch = try XCTUnwrap(editor.batches.first)
        editor.setQuantity(batch.quantity + 3, for: batch)
        await FeatureHost.settleAsync(0.5)
        r.page.view.setNeedsLayout()
        r.window.rootViewController?.view.layoutIfNeeded()
        await FeatureHost.settleAsync(0.4)
        // The Save row is the last row: scroll the pane's list to it so its cell is live.
        XCTAssertTrue(editor.hasChanges(batch), "the quantity change is an unsaved edit")
        if let list = ([pane] + HostedPage.descendants(of: pane)).compactMap({ $0 as? UICollectionView }).first {
            list.layoutIfNeeded()
            list.setContentOffset(CGPoint(x: 0, y: max(0, list.contentSize.height - list.bounds.height)), animated: false)
            list.layoutIfNeeded()
            await FeatureHost.settleAsync(0.4)
        }
        let dump = ([pane] + HostedPage.descendants(of: pane)).prefix(25).map { "\(type(of: $0)) \($0.frame) hid=\($0.isHidden) \(($0 as? UICollectionView).map { "cells=\($0.visibleCells.count) content=\($0.contentSize)" } ?? "")" }
        XCTAssertNotNil(FeatureHost.view("inventory.editor.save", in: r.page.view), "\(dump) " + "the pane carries its own Save once something changed: \(FeatureHost.identifiers(in: r.page.view).sorted().filter { $0.contains("editor") })")
    }
}
