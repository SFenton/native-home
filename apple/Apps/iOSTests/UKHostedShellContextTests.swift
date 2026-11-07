@testable import HassCore
import UIKit
import XCTest
@testable import HassUI

/// What a page's `UKContext.push` does for the section it lives in (the tiles, room links and Settings rows that open a page).
@MainActor
final class UKHostedShellContextTests: XCTestCase {
    private func context(_ rig: HostedShellRig, section: AppSection?) -> UKContext {
        var context = UKContext(store: rig.connection.store, caller: rig.connection)
        context.navigator = rig.navigator
        context.section = section
        return context
    }

    func testAHomeRoutePushesOnHomeOnceAndSelectsHome() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        rig.navigator.selection = .climate
        let ctx = context(rig, section: .climate)
        XCTAssertTrue(ctx.push(HomeRoute.vacuums), "the page is pushed")
        XCTAssertEqual(rig.navigator.selection, .home, "from another tab it brings Home forward")
        XCTAssertFalse(rig.navigator.isAtRoot(.home))
        XCTAssertFalse(ctx.push(HomeRoute.vacuums), "a page that is already showing is not pushed again")
    }

    func testAContextWithoutANavigatorOrSectionPushesNothing() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        XCTAssertFalse(context(rig, section: nil).push(HomeRoute.vacuums), "no section, no push")
        var bare = context(rig, section: .home)
        bare.navigator = nil
        XCTAssertFalse(bare.push(HomeRoute.vacuums), "no navigator, no push")
        bare.push(SettingsRoute.vacation)
        bare.push(HouseholdSettingsPage.admin)
        XCTAssertTrue(rig.navigator.isAtRoot(.home))
        XCTAssertTrue(rig.navigator.isAtRoot(.settings))
    }

    func testSettingsTopicsAndHouseholdPagesLandOnTheContextsSection() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        let ctx = context(rig, section: .settings)
        ctx.push(SettingsRoute.vacation)
        XCTAssertEqual(rig.navigator.routes(in: .settings).count, 1)
        ctx.push(HouseholdSettingsPage.guests)
        XCTAssertEqual(rig.navigator.routes(in: .settings).count, 2, "both stack on Settings")
        XCTAssertTrue(rig.navigator.isAtRoot(.home), "nothing leaks onto Home")
    }
}
