import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Vacuums and Chores entry points: with no connection they stand in a titled placeholder, with one they build the real pages.
@MainActor
final class UKHostedFeatureEntryTests: DemoHouseTestCase {
    private var offline: UKContext {
        let store = EntityStore()
        return UKGalleryChrome.context(store: store, caller: GalleryServiceRecorder(store: store))
    }

    func testWithoutAConnectionVacuumsStandsInAPlaceholderAndOffersNoSheet() {
        let page = UKScreens.vacuums(offline)
        XCTAssertTrue(page is UKPlaceholderViewController)
        XCTAssertEqual(page.title, "Vacuums")
        XCTAssertNil(UKScreens.sheetPage(for: Vacuums.all[0], context: offline), "a room's vacuum card cannot open a sheet without a connection")
    }

    func testOnAConnectionVacuumsBuildsThePageAndEachRobotsSheet() throws {
        let (_, _, context) = try FeatureHost.signedIn()
        XCTAssertTrue(UKScreens.vacuums(context) is UKVacuumsViewController)
        let vacuum = Vacuums.all[0]
        let sheet = try XCTUnwrap(UKScreens.sheetPage(for: vacuum, context: context))
        XCTAssertEqual(sheet.title, "\(vacuum.title) Robot Vacuum")
        XCTAssertEqual(sheet.controller.vacuum.entityId, vacuum.entityId)
    }

    func testWithoutAConnectionEveryChoresEntryStandsInAPlaceholderWithItsTitle() {
        let grocery = UKScreens.groceryList(offline)
        XCTAssertTrue(grocery is UKPlaceholderViewController)
        XCTAssertEqual(grocery.title, "Grocery List")
        let unknown = UKScreens.choresPage("no-such-page", context: offline)
        XCTAssertEqual(unknown.title, "Chores")
        let page = ChoresConfig.groceries
        let known = UKScreens.choresPage(page.id, context: offline)
        XCTAssertTrue(known is UKPlaceholderViewController)
        XCTAssertEqual(known.title, page.title)
        let admin = UKScreens.adminTodo(offline)
        XCTAssertTrue(admin is UKPlaceholderViewController)
        XCTAssertEqual(admin.title, ChoresConfig.adminTodo.title)
    }

    func testOnAConnectionTheChoresEntriesBuildTodoPages() throws {
        let (_, _, context) = try FeatureHost.signedIn()
        XCTAssertTrue(UKScreens.groceryList(context) is UKTodoPageViewController)
        XCTAssertTrue(UKScreens.choresPage(ChoresConfig.groceries.id, context: context) is UKTodoPageViewController)
        XCTAssertTrue(UKScreens.adminTodo(context) is UKTodoPageViewController)
    }
}
