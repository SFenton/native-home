import Foundation
@testable import HassCore
import Testing

/// When the reconnecting arc counts the connection as down.
struct ReconnectingPolicyTests {
    @Test func everyStateThatIsNotLiveOrRefusedIsDown() {
        #expect(!ReconnectingPolicy.isDown(.connected(version: "2026.10")))
        #expect(!ReconnectingPolicy.isDown(.rejected), "a refused token ends the session; no arc")
        #expect(ReconnectingPolicy.isDown(.disconnected))
        #expect(ReconnectingPolicy.isDown(.connecting))
        #expect(ReconnectingPolicy.isDown(.waitingToReconnect))
    }

    @Test func theArcWaitsTwoSeconds() {
        #expect(ReconnectingPolicy.delay == .seconds(2))
    }
}

/// When the reconnecting arc is in the header and when it is lit.
@MainActor
struct ReconnectingIndicatorTests {
    private let fast: Duration = .milliseconds(20)

    private func settle(_ duration: Duration = .milliseconds(120)) async { try? await Task.sleep(for: duration) }

    @Test func anOutageShorterThanTheDelayNeverShows() async {
        let indicator = ReconnectingIndicator()
        let down = Task { await indicator.follow(isDown: true, delay: .seconds(60), fade: fast, lead: fast) }
        await settle(.milliseconds(60))
        down.cancel()
        await indicator.follow(isDown: false, fade: fast)
        #expect(!indicator.isPresent)
        #expect(!indicator.isLit)
    }

    @Test func theArcIsPlacedAfterTheDelayAndLitALeadLater() async {
        let indicator = ReconnectingIndicator()
        let down = Task { await indicator.follow(isDown: true, delay: .milliseconds(40), fade: fast, lead: .milliseconds(200)) }
        await settle(.milliseconds(30))
        #expect(!indicator.isPresent, "still inside the delay")
        await settle(.milliseconds(80))
        #expect(indicator.isPresent && !indicator.isLit, "placed unlit so it fades up rather than popping")
        await down.value
        #expect(indicator.isPresent && indicator.isLit)
    }

    @Test func comingBackDimsTheArcThenRemovesIt() async {
        let indicator = ReconnectingIndicator()
        await indicator.follow(isDown: true, delay: fast, fade: fast, lead: fast)
        let up = Task { await indicator.follow(isDown: false, fade: .milliseconds(200)) }
        await settle(.milliseconds(60))
        #expect(indicator.isPresent && !indicator.isLit, "dimmed but still in the bar while it fades")
        await up.value
        #expect(!indicator.isPresent && !indicator.isLit)
    }

    @Test func goingDownAgainMidFadeLightsTheArcWhereItIsWithNoWait() async {
        let indicator = ReconnectingIndicator()
        await indicator.follow(isDown: true, delay: fast, fade: fast, lead: fast)
        let up = Task { await indicator.follow(isDown: false, fade: .milliseconds(300)) }
        await settle(.milliseconds(50))
        up.cancel()
        await indicator.follow(isDown: true, delay: .seconds(60), fade: fast, lead: fast)
        #expect(indicator.isPresent && indicator.isLit, "no 2 s wait: the arc is already in the bar")
    }

    @Test func comingBackWithNothingShownDoesNothing() async {
        let indicator = ReconnectingIndicator()
        await indicator.follow(isDown: false, fade: .seconds(60))
        #expect(!indicator.isPresent && !indicator.isLit)
    }

    @Test func cancelledWhileDownLeavesNothingHalfPlaced() async {
        let indicator = ReconnectingIndicator()
        let down = Task { await indicator.follow(isDown: true, delay: .milliseconds(10), fade: fast, lead: .seconds(60)) }
        await settle(.milliseconds(60))
        down.cancel()
        await down.value
        #expect(indicator.isPresent && !indicator.isLit, "cancelled between placing and lighting; the next call lights it")
    }

    @Test func theFadeIsAThirdOfASecondAndTheLeadIsShort() {
        #expect(ReconnectingPolicy.fade == .milliseconds(350))
        #expect(ReconnectingPolicy.insertLead < ReconnectingPolicy.fade)
    }
}
