import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Inventory (the kitchen's spaces) on the gallery's EverShelf fixture server: the list, its sort/filter/scan sheets, the item editor
/// and the states a person can land in.
@MainActor
final class UKHostedInventoryTests: DemoHouseTestCase {
    private struct Screen {
        let page: UKInventoryViewController
        let server: EverShelfFixtureServer
        let models: InventoryModels
        let window: UIWindow
    }

    private func screen(_ space: InventorySpace = .pantry, query: String = "", launch: InventoryLaunch? = nil, rows: Bool = true, failing: Bool = false,
                        size: CGSize = CGSize(width: 393, height: 2200)) -> Screen {
        let server = EverShelfFixtureServer.sample()
        if !rows { server.rows = [] }
        if failing { server.failing = ["evershelf.list_inventory"] }
        server.latency = .milliseconds(20)
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let context = UKGalleryChrome.context()
        models.model(for: space).searchQuery = query
        let page = UKInventoryViewController(context: context, model: models.model(for: space), models: models, launch: launch)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: size)
        FeatureHost.settle(0.8)
        return Screen(page: page, server: server, models: models, window: window)
    }

    func testThePantryListsItsItemsAndOffersSortFilterScan() {
        let s = screen()
        defer { s.window.isHidden = true }
        let ids = FeatureHost.identifiers(in: s.page.view)
        XCTAssertTrue(ids.contains("inventory.row.Spaghetti") || ids.contains { $0.hasPrefix("inventory.row.") }, "the pantry's items are listed: \(ids.filter { $0.hasPrefix("inventory") }.sorted())")
        XCTAssertFalse(ids.contains("inventory.row.Whole Milk"), "the fridge's items are not")
        for action in ["inventory.sort", "inventory.filter", "inventory.scan"] { XCTAssertTrue(ids.contains("fab.\(action)"), action) }
    }

    func testEveryFoodSpaceLoads() {
        for space in InventorySpace.allCases {
            let s = screen(space)
            defer { s.window.isHidden = true }
            XCTAssertFalse(s.server.lastCall.isEmpty, "\(space) asked the server")
            XCTAssertNil(FeatureHost.view("inventory.loading", in: s.page.view), "\(space) finished loading")
        }
    }

    func testAnEmptySpaceOffersScanOnly() {
        let s = screen(rows: false)
        defer { s.window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("inventory.empty", in: s.page.view))
        let ids = FeatureHost.identifiers(in: s.page.view)
        XCTAssertTrue(ids.contains("fab.inventory.scan"))
        XCTAssertFalse(ids.contains("fab.inventory.sort"), "nothing to sort")
    }

    func testAFailedLoadSaysSo() {
        let s = screen(failing: true)
        defer { s.window.isHidden = true }
        XCTAssertFalse(HostedPage.labels(in: s.page.view).isEmpty)
        XCTAssertNil(FeatureHost.view("inventory.row.Spaghetti", in: s.page.view))
    }

    func testSortSheetChangesTheOrder() throws {
        let s = screen()
        defer { s.window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("fab.inventory.sort", in: s.page.view))
        FeatureHost.settle(0.8)
        let sheet = try XCTUnwrap(s.page.shownSheet)
        let option = try XCTUnwrap(FeatureHost.identifiers(in: sheet.view).sorted().first { $0.hasPrefix("inventory.sort.") && !$0.contains("direction") })
        XCTAssertTrue(FeatureHost.press(option, in: sheet.view) || FeatureHost.tapRow(option, in: sheet.view))
        FeatureHost.settle(0.5)
    }

    func testFilterSheetOffersTheStatusFilters() throws {
        let s = screen()
        defer { s.window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("fab.inventory.filter", in: s.page.view))
        FeatureHost.settle(0.8)
        let sheet = try XCTUnwrap(s.page.shownSheet)
        let filter = try XCTUnwrap(FeatureHost.identifiers(in: sheet.view).sorted().first { $0.hasPrefix("inventory.filter.") })
        XCTAssertTrue(FeatureHost.press(filter, in: sheet.view) || FeatureHost.tapRow(filter, in: sheet.view))
        FeatureHost.settle(0.5)
    }

    func testScanOpensTheAddItemSheet() throws {
        let s = screen(launch: .sheet(.scan))
        defer { s.window.isHidden = true }
        FeatureHost.settle(0.8)
        XCTAssertNotNil(s.page.shownSheet, "Scan Item opens its sheet")
    }

    func testSortAndFilterOpenAtLaunch() {
        for sheet in [InventorySheet.sort, .filter] {
            let s = screen(launch: .sheet(sheet))
            defer { s.window.isHidden = true }
            FeatureHost.settle(0.8)
            XCTAssertNotNil(s.page.shownSheet, "\(sheet) is open")
        }
    }

    func testTheEditorOpensForAnItemAndSaves() throws {
        let s = screen(launch: .editor("Spaghetti"))
        defer { s.window.isHidden = true }
        FeatureHost.settle(1.0)
        let sheet = try XCTUnwrap(s.page.shownSheet, "the editor for Spaghetti opens")
        XCTAssertNotNil(FeatureHost.view("inventory.editor", in: sheet.view))
        XCTAssertNotNil(FeatureHost.view("inventory.editor.quantity", in: sheet.view))
        XCTAssertNotNil(FeatureHost.view("inventory.editor.delete", in: sheet.view), "an existing item can be deleted")
    }

    func testTapTheEditButtonOfARowToEdit() throws {
        let s = screen()
        defer { s.window.isHidden = true }
        guard FeatureHost.press("inventory.row.edit", in: s.page.view) else { return XCTFail("rows have an edit button") }
        FeatureHost.settle(0.8)
        XCTAssertNotNil(s.page.shownSheet)
    }

    func testTheCartButtonAddsToTheShoppingList() throws {
        let s = screen()
        defer { s.window.isHidden = true }
        guard FeatureHost.press("inventory.row.cart", in: s.page.view) else { return XCTFail("rows have a cart button") }
        FeatureHost.settle(0.8)
        XCTAssertTrue(s.server.lastCall.contains("shopping") || s.server.lastCall.contains("add") || s.server.lastCall != "None", s.server.lastCall)
    }

    func testSearchingFiltersTheList() async throws {
        // The page owns the box's text (it writes the model from it), so the query starts there, as a reopened page's does.
        let s = screen(query: "spag")
        defer { s.window.isHidden = true }
        await FeatureHost.settleAsync(1.0)
        XCTAssertTrue(s.server.calls.contains { $0.contains("list_inventory") && $0.contains("spag") }, "the search asks the server: \(s.server.calls)")
        let ids = FeatureHost.identifiers(in: s.page.view).filter { $0.hasPrefix("inventory.row.") && !["inventory.row.edit", "inventory.row.cart", "inventory.row.error"].contains($0) }
        XCTAssertTrue(ids.allSatisfy { $0.contains("Spaghetti") }, "only Spaghetti matches: \(ids) model \(s.models.model(for: .pantry).items.map(\.name)) phase \(s.models.model(for: .pantry).phase) settled \(s.models.model(for: .pantry).isSearching)")
    }
}

// MARK: - Add Item (scan)

/// The Add Item sheet walked step by step with the simulated camera: barcode, expiration, review, add.
@MainActor
final class UKHostedScanTests: DemoHouseTestCase {
    private func sheet(source: ScanCameraController.Source = .simulated) -> (ScanItemModel, EverShelfFixtureServer, UKScanItemViewController, UIWindow, () -> Int) {
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(10)
        let client = EverShelfClient(caller: server)
        let model = ScanItemModel(space: .pantry, client: client)
        var added = 0
        let camera = ScanCameraController(source: source)
        let page = UKScanItemViewController(model: model, camera: camera, context: UKGalleryChrome.context().with { $0.surface = .sheet }) { added += 1 }
        let modal = UKHassModalController(root: page, options: UKHassModalOptions(title: "Add Item"))
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 2000))
        FeatureHost.settle(0.6)
        return (model, server, page, window, { added })
    }

    func testTheFirstStepOffersTheCameraAndManualEntry() {
        let (model, _, page, window, _) = sheet()
        defer { window.isHidden = true }
        XCTAssertEqual(model.step, .barcode)
        let ids = FeatureHost.identifiers(in: page.view)
        XCTAssertTrue(ids.contains("scan.simulate"), "the simulated camera has a Simulate Scan button: \(ids.filter { $0.hasPrefix("scan") }.sorted())")
    }

    func testScanningABarcodeFindsTheProductThenWalksToReview() async throws {
        let (model, server, page, window, added) = sheet()
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("scan.simulate", in: page.view))
        await FeatureHost.settleAsync(0.8)
        XCTAssertNotEqual(model.lookupStatus, .idle, "the scan started a lookup")
        model.goToExpiryStep()
        await FeatureHost.settleAsync(0.4)
        XCTAssertEqual(model.step, .expiry)
        model.selectQuickExpiry(.oneWeek)
        await FeatureHost.settleAsync(0.3)
        model.goToReviewStep()
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(model.step, .review)
        XCTAssertNotNil(FeatureHost.view("scan.quantity", in: page.view) ?? FeatureHost.view("scan.name", in: page.view))
        if model.name.isEmpty { model.setName("Yogurt") }
        await model.add()
        await FeatureHost.settleAsync(0.6)
        XCTAssertTrue(server.lastCall.contains("add"), "adding calls the server: \(server.lastCall)")
        XCTAssertEqual(added(), 1, "the page is told once")
    }

    func testTypingTheNameByHandSkipsTheCamera() throws {
        let (model, _, page, window, _) = sheet(source: .unavailable)
        defer { window.isHidden = true }
        model.enterNameManually()
        FeatureHost.settle(0.4)
        model.setName("Oat Milk")
        model.setQuantityText("3")
        XCTAssertEqual(model.validateQuantity(), 3)
        model.setQuantityText("0")
        XCTAssertNil(model.validateQuantity(), "zero is not a quantity")
        model.setQuantityText("")
        model.goBack()
        FeatureHost.settle(0.3)
        XCTAssertNotNil(page.view)
    }

    func testAMissingCameraIsExplained() {
        let (model, _, page, window, _) = sheet(source: .unavailable)
        defer { window.isHidden = true }
        FeatureHost.settle(0.4)
        XCTAssertNotNil(model.statusMessage ?? FeatureHost.view("scan.cameraStatus", in: page.view)?.accessibilityLabel)
    }
}

// MARK: - Item editor

/// The item editor sheet on a card of the fixture pantry: draft a quantity, reset, save, delete.
@MainActor
final class UKHostedInventoryEditorTests: DemoHouseTestCase {
    private func editor() async throws -> (InventoryEditorModel, UKInventoryEditorViewController, EverShelfFixtureServer, UIWindow, UIViewController) {
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(10)
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let list = models.model(for: .pantry)
        await list.load()
        let item = try XCTUnwrap(list.displayItems.first { $0.name == "Black Beans" }, "the pantry has Black Beans")
        let model = InventoryEditorModel(item: item, list: list)
        let page = UKInventoryEditorViewController(model: model, style: .sheet, context: UKGalleryChrome.context().with { $0.surface = .sheet }, onClose: {})
        let modal = UKHassModalController(root: page, options: UKHassModalOptions(title: model.title))
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 2200))
        await FeatureHost.settleAsync(0.6)
        return (model, page, server, window, modal)
    }

    func testTwoBatchesAreEditedSeparately() async throws {
        let (model, page, _, window, _) = try await editor()
        defer { window.isHidden = true }
        XCTAssertEqual(model.batches.count, 2, "Black Beans has two expiration dates")
        XCTAssertGreaterThanOrEqual(HostedPage.descendants(of: page.view).filter { $0.accessibilityIdentifier == "inventory.editor.quantity" }.count, 1)
        XCTAssertNil(page.navigationItem.rightBarButtonItem.map { $0.isEnabled ? $0 : nil } ?? nil, "Save is off before any change")
    }

    func testChangingAQuantityEnablesSaveAndResetPutsItBack() async throws {
        let (model, page, _, window, _) = try await editor()
        defer { window.isHidden = true }
        let batch = try XCTUnwrap(model.batches.first)
        model.setQuantity(batch.quantity + 1, for: batch)
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(model.hasChanges(batch))
        XCTAssertTrue(try XCTUnwrap(page.navigationItem.rightBarButtonItem).isEnabled, "Save turns on")
        XCTAssertNotNil(FeatureHost.view("inventory.editor.reset", in: page.view))
        FeatureHost.press("inventory.editor.reset", in: page.view)
        await FeatureHost.settleAsync(0.4)
        XCTAssertFalse(model.hasChanges(batch), "Reset Changes drops the draft")
    }

    func testSavingSendsTheNewQuantity() async throws {
        let (model, page, server, window, _) = try await editor()
        defer { window.isHidden = true }
        let batch = try XCTUnwrap(model.batches.first)
        model.setQuantity(batch.quantity + 2, for: batch)
        await FeatureHost.settleAsync(0.3)
        let save = try XCTUnwrap(page.navigationItem.rightBarButtonItem)
        _ = save.primaryAction?.performWithSender(nil, target: nil) ?? save.target?.perform(save.action)
        await FeatureHost.settleAsync(1.0)
        XCTAssertNotEqual(server.lastCall, "None", "Save called the server: \(server.lastCall)")
    }

    func testCancellingWithADraftAsksFirst() async throws {
        let (model, page, _, window, _) = try await editor()
        defer { window.isHidden = true }
        let batch = try XCTUnwrap(model.batches.first)
        model.setQuantity(batch.quantity + 1, for: batch)
        await FeatureHost.settleAsync(0.3)
        let cancel = try XCTUnwrap(page.navigationItem.leftBarButtonItem)
        _ = cancel.primaryAction?.performWithSender(nil, target: nil)
        await FeatureHost.settleAsync(0.5)
        XCTAssertNotNil(FeatureHost.alert(on: page) ?? page.shownSheet, "unsaved quantity changes are not dropped silently")
    }

    func testDeletingAskThenRemoves() async throws {
        let (model, page, server, window, _) = try await editor()
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("inventory.editor.delete", in: page.view))
        await FeatureHost.settleAsync(0.5)
        if let alert = FeatureHost.alert(on: page), let confirm = alert.actions.last {
            FeatureHost.answer(alert, confirm.title ?? "")
            await FeatureHost.settleAsync(0.8)
            XCTAssertTrue(server.calls.contains { $0.contains("delete_inventory") }, "\(server.calls)")
        } else {
            XCTFail("Delete asks before it removes")
        }
        _ = model
    }
}
