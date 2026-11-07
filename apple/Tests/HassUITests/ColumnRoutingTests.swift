import SwiftUI
import XCTest
@testable import HassUI

/// Which routes a window that splits shows as columns (``ColumnRouting``), and that the Chores and Food routes survive a restart
/// (``RouteRestore``): the rules the UIKit port's section stacks follow (`.agents/design/apple/split-view.md`, "Column navigation").
final class ColumnRoutingTests: XCTestCase {
    private let hub = ShellRoute.home(.food)

    func testNarrowWindowsHostNothing() {
        XCTAssertEqual(ColumnRouting.hostedCount(in: [.chores("groceries")], splitting: false, rootHostsColumns: true), 0)
        XCTAssertEqual(ColumnRouting.hostedCount(in: [hub, .foodSpace("fridge")], splitting: false, rootHostsColumns: false), 0)
    }

    func testSectionRootHostsAllOfItsPages() {
        XCTAssertEqual(ColumnRouting.hostedCount(in: [.chores("alexs-chores")], splitting: true, rootHostsColumns: true), 1)
        XCTAssertEqual(ColumnRouting.hostedCount(in: [.settings(.vacation), .settings(.performance)], splitting: true, rootHostsColumns: true), 2)
        XCTAssertEqual(ColumnRouting.hostedCount(in: [.household(.guests)], splitting: true, rootHostsColumns: true), 1)
    }

    func testRootThatHostsNothingKeepsItsPagesOnTheStack() {
        XCTAssertEqual(ColumnRouting.hostedCount(in: [.chores("groceries")], splitting: true, rootHostsColumns: false), 0)
    }

    func testFoodSpacesAreColumnsOfTheHub() {
        XCTAssertEqual(ColumnRouting.hostedCount(in: [hub, .foodSpace("fridge")], splitting: true, rootHostsColumns: false), 1)
        XCTAssertEqual(ColumnRouting.hostedCount(in: [.home(.room("kitchen")), hub, .foodSpace("pantry")], splitting: true, rootHostsColumns: false), 1)
    }

    func testFoodSpacesWithoutTheHubBeforeThemStayPushed() {
        XCTAssertEqual(ColumnRouting.hostedCount(in: [.foodSpace("fridge")], splitting: true, rootHostsColumns: false), 0)
        XCTAssertEqual(ColumnRouting.hostedCount(in: [.home(.media), .foodSpace("fridge")], splitting: true, rootHostsColumns: false), 0)
    }

    func testAPageTheNavigatorDidNotPushHostsNothing() {
        XCTAssertEqual(ColumnRouting.hostedCount(in: [hub, nil], splitting: true, rootHostsColumns: false), 0)
        XCTAssertEqual(ColumnRouting.hostedCount(in: [], splitting: true, rootHostsColumns: true), 0)
    }

    func testTheHubItselfIsAStackPage() {
        XCTAssertEqual(ColumnRouting.hostedCount(in: [hub], splitting: true, rootHostsColumns: false), 0)
    }

    func testChoresAndFoodRoutesRestoreAfterARestart() {
        let routes: [AppSection: [ShellRoute]] = [.chores: [.chores("unassigned-chores")], .home: [hub, .foodSpace("freezer")]]
        let decoded = RouteRestore.decode(RouteRestore.encode(routes))
        XCTAssertEqual(decoded, routes)
    }

    func testRoutesPushOntoAPath() {
        var path = NavigationPath()
        ShellRoute.chores("groceries").append(to: &path)
        ShellRoute.foodSpace("pantry").append(to: &path)
        XCTAssertEqual(path.count, 2)
    }
}
