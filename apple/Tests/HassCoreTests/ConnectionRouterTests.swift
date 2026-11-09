import Foundation
@testable import HassCore
import Testing

/// The reconnect policy as pure decisions: feed events, assert actions (owner, 2026-10-27: a network change never
/// reconnects by itself; the socket dropping does). No timers, no mocks.
struct ConnectionRouterTests {
    private let publicURL = URL(string: "https://homeassistant.example.com")!
    private let homeURL = URL(string: "http://192.0.2.11:8123")!

    /// A router for an app that wants the socket, online, with a ready socket on `url`.
    private func router(socketOn url: URL?, ready: Bool = true) -> ConnectionRouter {
        var router = ConnectionRouter(publicURL: publicURL)
        _ = router.wantsConnection(true)
        _ = router.online(true)
        router.socketOpened(url: url)
        if ready { router.socketReady() }
        return router
    }

    @Test func aNetworkChangeOnAPublicSocketForgetsHomeAndChecksWithoutReconnecting() {
        var onPublic = router(socketOn: publicURL)
        #expect(onPublic.networkChanged() == [.forgetHome, .checkRoute], "no churn on cellular or public Wi-Fi")
    }

    @Test func aNetworkChangeOnAHomeSocketMovesToPublicNowThenChecksForHome() {
        var onHome = router(socketOn: homeURL)
        onHome.routeIs(homeURL)
        #expect(onHome.networkChanged() == [.forgetHome, .reconnect(to: publicURL), .checkRoute],
                "leaving the house: the home socket is dead, do not wait for HAKit's ping")
        var notReady = router(socketOn: homeURL, ready: false)
        #expect(notReady.networkChanged() == [.forgetHome, .reconnect(to: publicURL), .checkRoute])
    }

    @Test func aNetworkChangeWhileOfflineOrUnwantedDoesNotReconnect() {
        var offline = router(socketOn: homeURL)
        _ = offline.online(false)
        #expect(offline.networkChanged() == [.forgetHome, .checkRoute])
        var stopped = router(socketOn: homeURL)
        _ = stopped.wantsConnection(false)
        #expect(stopped.networkChanged() == [.forgetHome, .checkRoute])
    }

    @Test func connectRequestedNeverChangesTheUrlUnderAWorkingSocket() {
        var pending = router(socketOn: publicURL)
        _ = pending.homeFound(url: homeURL)
        #expect(pending.connectRequested() == [], "route is home, socket public and working: leave it, switch stays pending")
        #expect(pending.hasPendingSwitch)
        #expect(pending.tick(idle: .seconds(5)) == [.reconnect(to: homeURL)], "the deferred switch still lands")

        var stale = router(socketOn: homeURL)
        #expect(stale.connectRequested() == [], "route forgot home, home socket working: leave it")

        var same = router(socketOn: publicURL)
        #expect(same.connectRequested() == [.connect])
        var fresh = router(socketOn: nil, ready: false)
        #expect(fresh.connectRequested() == [.connect])
    }

    @Test func connectRequestedOnASocketThatIsNotReadyReconnectsOnTheRightURLAndEndsThePendingSwitch() {
        var router = router(socketOn: publicURL, ready: false)
        router.routeIs(homeURL)
        #expect(router.connectRequested() == [.reconnect(to: homeURL)])
        var pending = self.router(socketOn: publicURL)
        _ = pending.homeFound(url: homeURL)
        pending.socketNotReady()
        #expect(pending.connectRequested() == [.reconnect(to: homeURL)])
        #expect(!pending.hasPendingSwitch)
        var off = self.router(socketOn: publicURL)
        _ = off.online(false)
        #expect(off.connectRequested() == [])
    }

    @Test func aFailoverChecksHomeOnceWhenThePublicSocketIsReady() {
        var router = router(socketOn: homeURL)
        router.routeIs(homeURL)
        _ = router.socketFailed()
        #expect(router.socketBecameReady() == [.checkRoute])
        #expect(router.socketBecameReady() == [], "one check per failover")
        var plain = self.router(socketOn: publicURL, ready: false)
        #expect(plain.socketBecameReady() == [], "an ordinary connect does not check")
    }

    @Test func aNetworkChangeDropsAPendingSwitch() {
        var router = router(socketOn: publicURL)
        _ = router.homeFound(url: homeURL)
        #expect(router.networkChanged() == [.cancelSwitch, .forgetHome, .checkRoute])
        #expect(router.tick(idle: .seconds(5)) == [], "the home address is gone, nothing to switch to")
    }

    @Test func homeFoundWhileAPublicSocketIsReadyAndIdleSwitchesOnce() {
        var router = router(socketOn: publicURL)
        #expect(router.homeFound(url: homeURL) == [.scheduleSwitchCheck(after: .zero)])
        #expect(router.tick(idle: .seconds(30)) == [.reconnect(to: homeURL)])
        #expect(router.tick(idle: .seconds(30)) == [], "exactly one switch")
    }

    @Test func homeFoundWhileScrollingDefersUntilTheScrollHasStopped() {
        var router = router(socketOn: publicURL)
        _ = router.homeFound(url: homeURL)
        #expect(router.tick(idle: .zero) == [.scheduleSwitchCheck(after: .seconds(1))])
        #expect(router.tick(idle: .milliseconds(400)) == [.scheduleSwitchCheck(after: .milliseconds(600))])
        #expect(router.tick(idle: .seconds(1)) == [.reconnect(to: homeURL)])
    }

    @Test func aDeferredSwitchChecksEverythingAgain() {
        var router = router(socketOn: publicURL)
        _ = router.homeFound(url: homeURL)
        router.routeIs(nil)
        #expect(router.tick(idle: .seconds(5)) == [], "home was forgotten while waiting")

        var closed = self.router(socketOn: publicURL)
        _ = closed.homeFound(url: homeURL)
        closed.socketNotReady()
        #expect(closed.tick(idle: .seconds(5)) == [], "the socket is no longer a working public one")

        var stopped = self.router(socketOn: publicURL)
        _ = stopped.homeFound(url: homeURL)
        #expect(stopped.wantsConnection(false) == [.cancelSwitch])
        #expect(stopped.tick(idle: .seconds(5)) == [])
    }

    @Test func homeFoundWhileTheSocketIsNotReadyConnectsNow() {
        var router = router(socketOn: publicURL, ready: false)
        #expect(router.homeFound(url: homeURL) == [.reconnect(to: homeURL)])
    }

    @Test func homeFoundWhileAlreadyOnHomeDoesNothing() {
        var ready = router(socketOn: homeURL)
        #expect(ready.homeFound(url: homeURL) == [])
        var connecting = router(socketOn: homeURL, ready: false)
        #expect(connecting.homeFound(url: homeURL) == [])
    }

    @Test func homeFoundWhenTheAppDoesNotWantTheSocketDoesNothing() {
        var offline = router(socketOn: publicURL)
        _ = offline.online(false)
        #expect(offline.homeFound(url: homeURL) == [])
        var idle = router(socketOn: publicURL)
        _ = idle.wantsConnection(false)
        #expect(idle.homeFound(url: homeURL) == [])
    }

    @Test func aHomeSocketThatDropsGoesPublicOnceAndOnlyOnce() {
        var router = router(socketOn: homeURL)
        router.routeIs(homeURL)
        #expect(router.socketFailed() == [.forgetHome, .reconnect(to: publicURL)])
        #expect(router.socketFailed() == [], "the public socket failing is HAKit's to retry")
    }

    @Test func aDropIsNotReportedWhileOfflineOrUnwanted() {
        var offline = router(socketOn: homeURL)
        _ = offline.online(false)
        #expect(offline.socketFailed() == [])
        var stopped = router(socketOn: homeURL)
        _ = stopped.wantsConnection(false)
        #expect(stopped.socketFailed() == [])
    }

    @Test func aDropAfterANetworkChangeNeverReturnsToTheHomeAddress() {
        var router = router(socketOn: homeURL)
        router.routeIs(homeURL)
        _ = router.networkChanged()
        router.routeIs(nil)
        #expect(router.socketFailed() == [], "the network change already moved the socket to the public URL")
        #expect(router.socketURL == publicURL)
    }

    @Test func aSocketThatNeverOpenedHasNothingToFallBackFrom() {
        var router = router(socketOn: nil, ready: false)
        #expect(router.socketFailed() == [])
    }
}
