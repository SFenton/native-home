import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The edges around a row's removal: a bad quantity in the Delete or shopping prompt, the sheet editor closing, a module card that loses
/// its rounded corners on screen, and the list classes that offer no cells, swipes or selection. Every change goes
/// through the app's own code.
@MainActor
final class UKHostedRowRemovalDetailsTests: DemoHouseTestCase {
    private func pantry() async throws -> (InventoryListModel, InventoryDisplayItem) {
        let server = EverShelfFixtureServer.sample()
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let model = models.model(for: .pantry)
        await model.load()
        return (model, try XCTUnwrap(model.displayItems.first { $0.name == "Black Beans" }, "the pantry has Black Beans"))
    }

    func testAShoppingQuantityBelowOneIsSaidOnTheRow() async throws {
        let (model, item) = try await pantry()
        let presentation = InventoryPresentation()
        presentation.promptText = "0"
        await presentation.submit(.shopping(item), in: model)
        XCTAssertEqual(model.rowErrors[item.id], "Enter a number of 1 or more.")
    }

    func testAValidDeleteQuantityRemovesThatManyUnits() async throws {
        let (model, item) = try await pantry()
        let presentation = InventoryPresentation()
        presentation.promptText = "1"
        await presentation.submit(.delete(item, 3), in: model)
        XCTAssertNil(model.rowErrors[item.id], "a quantity in range says nothing")
        let after = try XCTUnwrap(model.displayItems.first { $0.name == "Black Beans" }, "two units are left, so the card stays")
        XCTAssertLessThan(after.shownQuantity ?? 3, 3)
    }

    private func descendants<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants(type, in: $0) }
    }

    private func controllers<T: UIViewController>(_ type: T.Type, in controller: UIViewController) -> [T] {
        ((controller as? T).map { [$0] } ?? []) + controller.children.flatMap { controllers(type, in: $0) }
    }

    func testTheInventoryListSelectsNothingAndATapOnARowOpensItsEditor() async throws {
        let server = EverShelfFixtureServer.sample()
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let model = models.model(for: .pantry)
        let presentation = InventoryPresentation()
        let context = UKGalleryChrome.context()
        let page = UKInventoryViewController(context: context, model: model, models: models, presentation: presentation)
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 2200))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(until: { !self.descendants(UKInventoryRowView.self, in: page.view).isEmpty })
        let list = try XCTUnwrap(controllers(UKInventoryListViewController.self, in: page).first, "the page has its list")
        let path = IndexPath(item: 0, section: 0)
        XCTAssertFalse(list.collectionView(list.collectionView, shouldSelectItemAt: path), "rows open the editor by their own tap")
        XCTAssertFalse(list.collectionView(list.collectionView, shouldHighlightItemAt: path))
        let row = try XCTUnwrap(descendants(UKInventoryRowView.self, in: page.view).first)
        XCTAssertTrue(row.opensEditor)
        row.perform(NSSelectorFromString("rowTapped"))
        XCTAssertNotNil(presentation.editing, "the tap opens the row's editor")
        presentation.editing = nil
        row.performEdit()
        XCTAssertNotNil(presentation.editing, "so does the row's Edit action")
    }

    func testADeleteQuantityAboveWhatIsStockedIsSaidOnTheRowAndClosesTheSwipe() async throws {
        let (model, item) = try await pantry()
        let presentation = InventoryPresentation()
        var results: [Bool] = []
        presentation.swipeCompletion = { results.append($0) }
        presentation.promptText = "99"
        await presentation.submit(.delete(item, 3), in: model)
        XCTAssertEqual(model.rowErrors[item.id], "Enter a number from 1 to 3.")
        XCTAssertEqual(results, [false], "the held swipe closes")
    }

    func testClearingTheSheetEditorClosesTheEditorOnlyWhileTheWindowCannotSplit() async throws {
        let (model, item) = try await pantry()
        let presentation = InventoryPresentation(canSplit: false)
        presentation.open(item, in: model)
        XCTAssertNotNil(presentation.sheetEditor)
        presentation.sheetEditor = nil
        XCTAssertNil(presentation.editing, "clearing the sheet closes the editor")
        let wide = InventoryPresentation(canSplit: true)
        wide.open(item, in: model)
        XCTAssertNil(wide.sheetEditor, "beside the list the editor is a pane, not a sheet")
        wide.sheetEditor = nil
        XCTAssertNotNil(wide.editing, "so clearing the sheet leaves it")
    }

    func testTheModuleCardLosesItsCornersWithAnAnimatedRadiusOnScreen() async throws {
        let host = UIViewController()
        let card = UKModuleRowBackgroundView()
        card.frame = CGRect(x: 20, y: 100, width: 300, height: 60)
        host.view.addSubview(card)
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        card.configure(density: .dense, surface: .page, isFirst: false, isLast: true, selected: false)
        card.configure(density: .dense, surface: .page, isFirst: false, isLast: false, selected: false, animated: true)
        XCTAssertFalse(card.layer.maskedCorners.isEmpty, "the corners stay while the radius shrinks")
        await FeatureHost.settleAsync(until: { card.layer.maskedCorners.isEmpty })
        XCTAssertTrue(card.layer.maskedCorners.isEmpty, "and are dropped when it lands")
        XCTAssertEqual(card.layer.cornerRadius, 0)
        card.configure(density: .dense, surface: .page, isFirst: true, isLast: true, selected: false, animated: true)
        XCTAssertEqual(card.layer.maskedCorners, [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner], "growing from square sets the mask at once")
    }

    func testAListWithNothingToShowOffersNoCellsAndNoSwipes() async throws {
        let base = UKSummaryListViewController(nibName: nil, bundle: nil)
        let window = HostedPage.show(base, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        let path = IndexPath(item: 0, section: 0)
        XCTAssertNil(base.reapplyGeneration(), "a list the store does not feed has no generation")
        XCTAssertNil(base.cell(base.collectionView, path, "x"))
        XCTAssertNil(base.swipe(at: path, leading: true))
        XCTAssertNil(base.swipe(at: path, leading: false))
    }

    func testTheExpiredFoodTabWithoutAnInventoryShowsNoRows() async throws {
        let fixtures = ProfileGalleryFixtures(environment: ["FENTON_GALLERY_LATENCY_MS": "5"])
        var context = UKGalleryChrome.context(store: fixtures.store)
        context.surface = .sheet
        let tab = UKSummaryExpiredFoodViewController(context: context, models: nil)
        let window = HostedPage.show(tab, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(tab.collectionView.numberOfItems(inSection: 0), 0, "with no Food models there is nothing to list")
    }

    func testASettingsListSelectsOnlyRowsThatActAndAreEnabled() async throws {
        let driver = UKSettingsListDriver(style: .sheet)
        func row(_ id: String, enabled: Bool = true, acts: Bool = true) -> UKSettingsListRow {
            UKSettingsListRow(id: id, signature: id, isEnabled: enabled, action: acts ? {} : nil) { cell in
                let label = UILabel()
                label.text = id
                cell.show(label)
            }
        }
        func sections(_ signature: String) -> [UKSettingsListSection] {
            [UKSettingsListSection(id: "s", header: .view(label: "Header", signature: signature, build: { UILabel() }),
                                   rows: [row("act"), row("off", enabled: false), row("plain", acts: false)])]
        }
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        let view: UICollectionView = driver.collectionView
        host.view.addSubview(view)
        view.frame = host.view.bounds
        driver.setSections(sections("one"))
        await FeatureHost.settleAsync(0.4)
        driver.setSections(sections("two"))
        await FeatureHost.settleAsync(0.2)
        XCTAssertEqual((0 ..< 3).map { driver.collectionView(view, shouldHighlightItemAt: IndexPath(item: $0, section: 0)) }, [true, false, false])
        XCTAssertEqual((0 ..< 3).map { driver.collectionView(view, shouldSelectItemAt: IndexPath(item: $0, section: 0)) }, [true, false, false])
        XCTAssertFalse(driver.collectionView(view, shouldHighlightItemAt: IndexPath(item: 9, section: 0)), "no row, no highlight")
        XCTAssertFalse(driver.collectionView(view, shouldSelectItemAt: IndexPath(item: 9, section: 0)))
    }
}
