import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import HassTestSupport
import Testing

/// The shell's navigation intents: which tab and page a tap, a swipe or a notification link lands on.
@MainActor
@Suite(.serialized, .demoHouse) // `profileName` writes UserDefaults.
struct ShellNavigatorTests {
    @Test func startsOnTheGivenSectionAtItsRootWithTheFlyoutClosed() {
        let navigator = ShellNavigator(selection: .chores)
        #expect(navigator.selection == .chores && navigator.isShowing(.chores) && !navigator.isShowing(.home))
        #expect(navigator.isAtRoot(.chores) && !navigator.isFlyoutOpen)
        #expect(ShellNavigator().selection == .home)
    }

    @Test func profileNameIsRememberedBetweenLaunches() {
        let navigator = ShellNavigator()
        let saved = UserDefaults.standard.string(forKey: ShellNavigator.profileNameKey)
        defer { UserDefaults.standard.set(saved, forKey: ShellNavigator.profileNameKey) }
        navigator.profileName = "Pat"
        #expect(UserDefaults.standard.string(forKey: ShellNavigator.profileNameKey) == "Pat")
        #expect(ShellNavigator().profileName == "Pat")
    }

    // MARK: Paths and routes

    @Test func appendingPagesRecordsTheirRoutesAndTheyAreRestorable() {
        let navigator = ShellNavigator()
        navigator.append(.home(.media), in: .home)
        navigator.append(.chores("mine"), in: .home)
        navigator.append(.household(.guests), in: .home)
        navigator.append(.settings(.vacation), in: .home)
        navigator.append(.foodSpace("pantry"), in: .home)
        #expect(navigator.paths[.home]?.count == 5 && !navigator.isAtRoot(.home))
        #expect(navigator.routes(in: .home) == [.home(.media), .chores("mine"), .household(.guests), .settings(.vacation), .foodSpace("pantry")])
        #expect(navigator.restorableRoutes[.home]?.count == 5)
        #expect(navigator.restorableRoutes[.security] == nil)
    }

    @Test func aPageNotPushedByTheNavigatorIsAnUnknownSlotAndBlocksRestoring() {
        let navigator = ShellNavigator()
        navigator.append(.home(.media), in: .home)
        navigator.path(for: .home).wrappedValue.append("link")
        #expect(navigator.routes(in: .home) == [.home(.media), nil])
        #expect(navigator.restorableRoutes[.home] == nil)
        #expect(navigator.routes(in: .climate).isEmpty)
    }

    @Test func poppingThroughTheBindingTrimsTheKnownRoutes() {
        let navigator = ShellNavigator()
        navigator.append(.home(.media), in: .home)
        navigator.append(.home(.vacuums), in: .home)
        var path = navigator.path(for: .home).wrappedValue
        path.removeLast()
        navigator.path(for: .home).wrappedValue = path
        #expect(navigator.routes(in: .home) == [.home(.media)])
        #expect(navigator.path(for: .security).wrappedValue.isEmpty)
    }

    @Test func trimPathDropsPagesOnlyWhenDeeper() {
        let navigator = ShellNavigator()
        #expect(!navigator.trimPath(in: .home, toDepth: 0))
        navigator.append(.home(.media), in: .home)
        navigator.append(.home(.vacuums), in: .home)
        #expect(!navigator.trimPath(in: .home, toDepth: 2))
        #expect(navigator.trimPath(in: .home, toDepth: 1))
        #expect(navigator.routes(in: .home) == [.home(.media)])
        #expect(navigator.trimPath(in: .home, toDepth: 0) && navigator.isAtRoot(.home))
    }

    @Test func restoreOnlyFillsSectionsStillAtTheirRoot() {
        let navigator = ShellNavigator()
        navigator.append(.home(.food), in: .home)
        navigator.restore([.home: [.home(.media)], .settings: [.settings(.performance)], .security: []])
        #expect(navigator.routes(in: .home) == [.home(.food)], "Home already had a page")
        #expect(navigator.routes(in: .settings) == [.settings(.performance)])
        #expect(navigator.isAtRoot(.security))
    }

    // MARK: Sheets

    @Test func quickLinksAndAccountOpenOverTheSelectedSectionAndCloseTheFlyout() {
        let navigator = ShellNavigator(selection: .climate)
        navigator.openFlyout()
        navigator.openQuickLinks()
        #expect(!navigator.isFlyoutOpen && navigator.quickLinksSection == .climate)
        #expect(navigator.sheet(in: .climate).wrappedValue == .quickLinks)
        #expect(navigator.sheet(in: .home).wrappedValue == nil)
        navigator.openFlyout()
        navigator.openAccount()
        #expect(navigator.accountSection == .climate && !navigator.isFlyoutOpen)
        #expect(navigator.sheet(in: .climate).wrappedValue == .account, "Account wins when both name the section")
        navigator.sheet(in: .climate).wrappedValue = .quickLinks // Not a dismissal: ignored.
        #expect(navigator.accountSection == .climate)
        navigator.sheet(in: .climate).wrappedValue = nil
        #expect(navigator.accountSection == nil && navigator.quickLinksSection == nil)
        #expect(ShellSheet.quickLinks.id == "quickLinks" && ShellSheet.account.id == "account")
    }

    // MARK: Flyout

    @Test func edgeSwipeOpensTheFlyoutOnlyAtARootAndOnlyOnce() {
        let navigator = ShellNavigator()
        let swipe = CGSize(width: 200, height: 0)
        navigator.edgeSwipeEnded(startX: 400, translation: swipe)
        #expect(!navigator.isFlyoutOpen, "Not from the leading edge")
        navigator.append(.home(.media), in: .home)
        navigator.edgeSwipeEnded(startX: 0, translation: swipe)
        #expect(!navigator.isFlyoutOpen, "Deeper, the back swipe owns the edge")
        navigator.trimPath(in: .home, toDepth: 0)
        navigator.edgeSwipeEnded(startX: 0, translation: swipe)
        #expect(navigator.isFlyoutOpen)
    }

    @Test func dismissingTheFlyoutReturnsFocusOnlyWhenItWasOpen() {
        let navigator = ShellNavigator()
        navigator.dismissFlyout()
        #expect(navigator.focusReturnToken == 0)
        navigator.openFlyout()
        navigator.dismissFlyout()
        #expect(!navigator.isFlyoutOpen && navigator.focusReturnToken == 1)
    }

    // MARK: Selecting and reselecting

    @Test func anotherTabIsACutAndTheSelectedTabPopsThenScrolls() {
        let navigator = ShellNavigator()
        navigator.tabTapped(.security)
        #expect(navigator.selection == .security)
        navigator.append(.home(.media), in: .security)
        #expect(navigator.reselect(.security) == .poppedToRoot)
        #expect(navigator.isAtRoot(.security) && navigator.routes(in: .security).isEmpty)
        #expect(navigator.scrollToTopRequests[.security] == nil)
        navigator.tabTapped(.security)
        #expect(navigator.scrollToTopRequests[.security] == 1)
        #expect(navigator.reselect(.security) == .scrolledToTop)
        #expect(navigator.scrollToTopRequests[.security] == 2)
    }

    @Test func selectingFromTheFlyoutClosesIt() {
        let navigator = ShellNavigator()
        navigator.openFlyout()
        navigator.select(.chores)
        #expect(navigator.selection == .chores && !navigator.isFlyoutOpen)
    }

    // MARK: Links

    @Test func aSectionLinkLandsOnTheRootAndClosesEverythingInTheWay() {
        let navigator = ShellNavigator()
        navigator.append(.home(.media), in: .security)
        navigator.openFlyout()
        navigator.quickLinksSection = .home
        navigator.accountSection = .home
        navigator.open(.section(.security))
        #expect(navigator.selection == .security && navigator.isAtRoot(.security))
        #expect(!navigator.isFlyoutOpen && navigator.quickLinksSection == nil && navigator.accountSection == nil)
        #expect(navigator.routes(in: .security).isEmpty)
    }

    @Test func aHomePageLinkPushesItAndAVacuumLinkCarriesItsSheetOnce() {
        let navigator = ShellNavigator(selection: .climate)
        navigator.open(.homePage("media"))
        #expect(navigator.selection == .home && navigator.routes(in: .home) == [.home(.media)])
        navigator.open(.homePage("all-food"))
        #expect(navigator.routes(in: .home) == [.home(.food)])
        navigator.open(.homePage("no-such-page"))
        #expect(navigator.isAtRoot(.home) && navigator.routes(in: .home).isEmpty)

        navigator.open(.homePage("media"), anchor: "not-a-room-anchor")
        #expect(navigator.takeSheet(forPage: "media") == nil, "Only room pages take a sheet")
        let room = HomeRoute.room("studio")
        navigator.open(.homePage(room.path), anchor: "robot-vacuum")
        #expect(navigator.takeSheet(forPage: "media-room") == nil)
        #expect(navigator.takeSheet(forPage: room.path) == "robot-vacuum")
        #expect(navigator.takeSheet(forPage: room.path) == nil)
    }

    // MARK: Quick Links pushes

    @Test func quickLinksPushesAPageOnceAndPopsBackToOneAlreadyOpen() {
        let navigator = ShellNavigator()
        #expect(navigator.push(.media, in: .home))
        #expect(navigator.push(.vacuums, in: .home))
        navigator.routeAppeared(.vacuums, in: .home)
        #expect(!navigator.push(.vacuums, in: .home), "Already on top")
        #expect(navigator.routes(in: .home).count == 2)
        #expect(!navigator.push(.media, in: .home), "Deeper down: pop back to it")
        #expect(navigator.routes(in: .home) == [.home(.media)])
        #expect(navigator.paths[.home]?.count == 1)
        #expect(!navigator.push(.media, in: .home), "Already the top page: nothing to drop")
        #expect(navigator.routes(in: .home) == [.home(.media)])
    }

    @Test func aRouteLeavingTheScreenIsForgottenOnlyIfItWasTheTopOne() {
        let navigator = ShellNavigator()
        navigator.routeAppeared(.media, in: .home)
        navigator.routeDisappeared(.vacuums, in: .home)
        #expect(navigator.shownRoutes[.home] == .media)
        navigator.routeDisappeared(.media, in: .home)
        #expect(navigator.shownRoutes[.home] == nil)
    }
}
