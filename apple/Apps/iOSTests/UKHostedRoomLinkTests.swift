import HassCore
import UIKit
import XCTest
@testable import HassUI

/// A room page opened from a link (a Live Activity tap, a notification) opens the card the link names, once; and a page opened on a
/// signed-in session that cannot reach Home Assistant still draws, with plain titles.
@MainActor
final class UKHostedRoomLinkTests: DemoHouseTestCase {
    func testALinkedSheetOpensWhenThePageArrivesAndIsConsumed() throws {
        let store = RoomsFixtures.store()
        let log = LoggingResponder(RoomsGalleryCaller(recorder: GalleryServiceRecorder(store: store), bedroom: BedroomGalleryRecorder(store: store)))
        let navigator = ShellNavigator()
        var context = UKGalleryChrome.context(store: store, caller: log)
        context.navigator = navigator
        let found = RoomsConfig.pages.lazy.compactMap { page -> (RoomPage, RoomCard)? in
            page.allCards.first { $0.sheet != nil && $0.kind == .light }.map { (page, $0) }
        }.first
        let (page, card) = try XCTUnwrap(found, "a room page with a light that has a sheet")
        navigator.open(.homePage(page.id), anchor: card.sheet)
        XCTAssertNotNil(navigator.pendingSheet, "the link asks for a sheet")

        let room = UKRoomViewController(page: page, context: context, viewer: .resident1)
        let nav = UINavigationController(rootViewController: room)
        let window = HostedPage.show(nav, size: HostedDriver.tall)
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until(5) { navigator.pendingSheet == nil }, "the page takes the request")
        XCTAssertTrue(HostedPage.until(5) { HostedDriver.topmost(nav) !== nav }, "the named card's sheet opens over the page")
    }

    func testAPageOnASessionThatCannotReachTheServerStillDrawsPlainTitles() async throws {
        let signedIn = try FeatureHost.signedIn()
        let page = try XCTUnwrap(RoomsConfig.pages.first)
        let room = UKRoomViewController(page: page, context: signedIn.context)
        let window = HostedPage.show(UINavigationController(rootViewController: room), size: HostedDriver.tall)
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(1.0)
        XCTAssertFalse(HostedPage.labels(in: room.view).isEmpty, "the room draws while the account cannot be read")
    }

    func testACardWithNoControlsSaysSoInsteadOfOpeningNothing() {
        let store = RoomsFixtures.store()
        let context = UKGalleryChrome.context(store: store, caller: LoggingResponder()).with { $0.surface = .sheet }
        let controller = RoomController(page: RoomsConfig.pages[0], store: store, caller: LoggingResponder())
        let card = RoomCard("Mystery Gadget", "sensor.demo_mystery_gadget", icon: "mdi:help-circle", kind: .appliance)
        let sheet = UKRoomCardSheetPage(controller: controller, card: card, viewer: UKRoomsViewer(), context: context)
        let window = HostedPage.show(UINavigationController(rootViewController: sheet), size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: sheet.view).contains("Mystery Gadget has no controls in the app yet. Use Home Assistant to change it."),
                      "saw \(HostedPage.labels(in: sheet.view))")
    }
}
