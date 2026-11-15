import CoreGraphics
import Foundation
import HassCore
import HassDesign
import Testing
@testable import HassUI
import HassTestSupport

/// The navigation style, the profile button, the modal tab bar and the arrival motion: rules the UIKit shell reads.
@Suite(.demoHouse)
struct SharedShellAndChromeRulesTests {
    // MARK: Navigation style

    @Test func wideWindowsGetAFlyoutUnlessAHingeSplitsThemAndTheChromeFollows() {
        #expect(ShellNavigationStyle.resolve(isRegularWidth: true) == .flyout)
        #expect(ShellNavigationStyle.resolve(isRegularWidth: true, hasHinge: true) == .tabBar)
        #expect(ShellNavigationStyle.resolve(isRegularWidth: false) == .tabBar)
        let flyout = ShellChrome.resolve(style: .flyout)
        #expect(flyout == ShellChrome(showsMenuButton: true, titleInHeader: false, edgeSwipe: true))
        let phone = ShellChrome.resolve(style: .tabBar)
        #expect(phone.showsMenuButton && !phone.titleInHeader && phone.edgeSwipe)
        let vertical = ShellChrome.resolve(style: .tabBar, inVerticalBar: true)
        #expect(!vertical.showsMenuButton && vertical.titleInHeader && !vertical.edgeSwipe)
        #expect(ShellChrome(showsMenuButton: true, titleInHeader: false).edgeSwipe, "the edge swipe defaults to the menu button")
    }

    // MARK: Profile button

    @Test func initialsAreTheFirstLettersOfTheFirstTwoWordsOrNone() {
        #expect(ProfileButton.initials("Alex Demo") == "AD")
        #expect(ProfileButton.initials("  maria  de la cruz ") == "MD")
        #expect(ProfileButton.initials("Cher") == "C")
        #expect(ProfileButton.initials("   ") == nil)
        #expect(ProfileButton.initials(nil) == nil)
        #expect(ProfileButton.Presentation.resolve(name: "Alex Demo") == .monogram("AD"))
        #expect(ProfileButton.Presentation.resolve(name: nil) == .symbol)
    }

    @Test func theButtonReadsNameAttentionAndOfflineInThatOrder() {
        #expect(ProfileButton.accessibilityValue(name: "Alex", attentionCount: 0) == "Alex")
        #expect(ProfileButton.accessibilityValue(name: "Alex", attentionCount: 1) == "Alex, 1 item needs attention")
        #expect(ProfileButton.accessibilityValue(name: "Alex", attentionCount: 2, isOffline: true) == "Alex, 2 items need attention, Offline")
        #expect(ProfileButton.accessibilityValue(name: nil, attentionCount: 0, isOffline: true) == "Offline")
    }

    @Test func theLiquidGlassBarGetsABiggerUnringedButton() {
        let glass = ProfileButton.Metrics.resolve(liquidGlassBar: true)
        #expect(glass.diameter == HassTokens.minTarget && glass.overhang == ProfileButton.Metrics.hiddenGlassPadding && !glass.ringed)
        let classic = ProfileButton.Metrics.resolve(liquidGlassBar: false)
        #expect(classic.diameter == 32 && classic.overhang == 0 && classic.ringed)
        #expect([glass, classic].contains(ProfileButton.Metrics.current))
    }

    // MARK: Reconnecting arc

    @Test func theReconnectingArcScalesWithTextAndStaysCentredInItsCell() {
        let normal = ReconnectingArc.Metrics.trailingShift(scale: 1)
        let big = ReconnectingArc.Metrics.trailingShift(scale: ReconnectingArc.Metrics.maxScale)
        #expect(big < normal, "a bigger arc leaves less room on each side")
        #expect(ReconnectingArc.Metrics.trailingShift == normal)
        #expect(ReconnectingArc.label.contains("Reconnecting") && ReconnectingArc.connectingLabel.contains("Connecting"))
    }

    // MARK: Modal tab bar

    @Test func theTabBarPicksIconsTextBadgesOrAMenuByWidthSymbolsAndTextSize() {
        func form(_ symbols: Bool, _ badges: Bool, _ compact: Bool, _ ax: Bool) -> ModalTabBarStyle.Form {
            ModalTabBarStyle.form(hasSymbols: symbols, hasBadges: badges, compactWidth: compact, accessibilitySize: ax)
        }
        #expect(form(true, false, true, true) == .menu)
        #expect(form(true, true, true, false) == .badged)
        #expect(form(true, true, false, false) == .badgedWithTitles)
        #expect(form(false, true, true, false) == .badgedWithTitles)
        #expect(form(true, false, true, false) == .icons)
        #expect(form(true, false, false, false) == .text)
        #expect(form(false, false, true, false) == .text)
        #expect(ModalTabBarStyle.positionValue(index: 1, count: 4) == "2 of 4")
        #expect(ModalTabBarStyle.accessibilityTitle("Alarms", badge: 0) == "Alarms")
        #expect(ModalTabBarStyle.accessibilityTitle("Alarms", badge: 1) == "Alarms, 1 item")
        #expect(ModalTabBarStyle.accessibilityTitle("Alarms", badge: 3) == "Alarms, 3 items")
        #expect(ModalTabBarStyle.badgeText(3) == "3")
        #expect(ModalTabBarStyle.iconSegmentHeight >= 44 && ModalTabBarStyle.titledSegmentHeight > ModalTabBarStyle.iconSegmentHeight)
        let segment = ModalTabSegment(item: ModalTabItem(id: "home"), title: "Home", symbol: nil, badge: 0)
        #expect(segment.id == "home")
    }

    @Test func everyModalTabHasAnMDIIconAndAnSFSymbol() {
        for tab in MediaRemoteTab.allCases { #expect(ModalTabSymbols.mdi(for: tab).hasPrefix("mdi:")); #expect(!ModalTabSymbols.symbol(for: tab).isEmpty) }
        for tab in HumidifierTab.allCases { #expect(ModalTabSymbols.mdi(for: tab).hasPrefix("mdi:")); #expect(!ModalTabSymbols.symbol(for: tab).isEmpty) }
        for tab in BedSideSheet.Tab.allCases { #expect(ModalTabSymbols.mdi(for: tab).hasPrefix("mdi:")); #expect(!ModalTabSymbols.symbol(for: tab).isEmpty) }
        for tab in WakeLightSheet.Tab.allCases { #expect(ModalTabSymbols.mdi(for: tab).hasPrefix("mdi:")); #expect(!ModalTabSymbols.symbol(for: tab).isEmpty) }
        for tab in ClimateConfig.Tab.allCases { #expect(ModalTabSymbols.mdi(for: tab) == tab.icon); #expect(!ModalTabSymbols.symbol(for: tab).isEmpty) }
        #expect(ModalTabSymbols.mdi(for: MediaRemoteTab.controls) == "mdi:remote")
        #expect(ModalTabSymbols.mdi(for: WakeLightSheet.Tab.defaults) == "mdi:tune-vertical")
    }

    // MARK: Room overview

    @Test func overviewKindsHaveTheirFamilyAndOnlyActiveSwitchesFill() {
        let families: [RoomOverviewKind: ColorFamily] = [.lights: .lights, .climate: .climate, .occupancy: .occupancy, .contacts: .contact, .airQuality: .air]
        for kind in RoomOverviewKind.allCases {
            #expect(RoomOverviewStyle.family(kind) == families[kind])
            _ = RoomOverviewStyle.tint(kind)
            let fills = [RoomOverviewKind.lights, .occupancy, .contacts].contains(kind)
            #expect(RoomOverviewStyle.isFilled(kind, active: true) == fills)
            #expect(!RoomOverviewStyle.isFilled(kind, active: false))
        }
        #expect(RoomOverviewStyle.contactSymbol(window: true, open: true) != RoomOverviewStyle.contactSymbol(window: true, open: false))
        #expect(RoomOverviewStyle.contactSymbol(window: false, open: true) != RoomOverviewStyle.contactSymbol(window: true, open: true))
        #expect(RoomOverviewStyle.contactSymbol(window: false, open: false) != RoomOverviewStyle.contactSymbol(window: false, open: true))
    }

    // MARK: Home arrival

    @MainActor @Test func theArrivalHidesHomeUntilRevealedAndFinishesRevealed() {
        let arrival = HomeArrival()
        #expect(!arrival.isActive && arrival.isRevealed)
        arrival.begin()
        #expect(arrival.isActive && !arrival.isRevealed)
        arrival.reveal()
        #expect(arrival.isActive && arrival.isRevealed)
        arrival.begin()
        arrival.finish()
        #expect(!arrival.isActive && arrival.isRevealed)
    }

    @Test func eachRowRisesLaterThanTheLastUntilTheStaggerLimit() {
        #expect(HomeArrival.riseDelay(index: -3) == HomeArrival.riseDelay(index: 0))
        #expect(HomeArrival.riseDelay(index: 1) > HomeArrival.riseDelay(index: 0))
        #expect(HomeArrival.riseDelay(index: 1_000) == HomeArrival.riseDelay(index: MotionTokens.Arrival.staggerLimit))
        #expect(HomeArrival.duration == .milliseconds(900))
    }
}

private struct ModalTabItem: Hashable, Identifiable { let id: String }
