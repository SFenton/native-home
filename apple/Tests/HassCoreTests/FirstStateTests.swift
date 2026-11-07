import Foundation
import Observation
@testable import HassCore
import HassTestSupport
import Testing

/// `EntityStore.hasReceivedFirstState` and the header arc that follows it (pattern: connection-lifecycle; owner decision
/// 2026-10-24, `proposals/loading-states` section 5).
@MainActor
@Suite(.demoHouse)
struct FirstStateTests {
    private let light = EntityState(entityId: "light.demo_kitchen_item_1", state: "on")

    @Test func aStoreWithNothingHasNotHeardYet() {
        #expect(!EntityStore().hasReceivedFirstState)
    }

    @Test func aSnapshotCountsAsTheFirstState() {
        // A relaunch draws the snapshot at once: no placeholder, even before the live set arrives.
        let store = EntityStore()
        store.replaceAll([light], freshness: .snapshot(savedAt: Date(timeIntervalSince1970: 1)))
        #expect(store.hasReceivedFirstState)
    }

    @Test func anEmptySnapshotStillCounts() {
        let store = EntityStore()
        store.replaceAll([], freshness: .snapshot(savedAt: Date(timeIntervalSince1970: 1)))
        #expect(store.hasReceivedFirstState)
    }

    @Test func theFirstLiveSetCountsAndStaysAcrossDeliveries() {
        let store = EntityStore()
        store.replaceAll([light], freshness: .live)
        #expect(store.hasReceivedFirstState)
        store.apply([EntityState(entityId: "light.demo_kitchen_item_1", state: "off")], removing: [], freshness: .live)
        store.replaceAll([], freshness: .live)
        #expect(store.hasReceivedFirstState, "an empty live set is still an answer")
    }

    @Test func signingOutPutsItBack() {
        let store = EntityStore()
        store.replaceAll([light])
        store.reset()
        #expect(!store.hasReceivedFirstState)
    }

    @Test func individualChangesBeforeAnyFreshnessDoNotFlipIt() {
        // `apply(_:)` alone carries no freshness; only a delivery does.
        let store = EntityStore()
        store.apply([light])
        #expect(!store.hasReceivedFirstState)
    }

    @Test func readingItTracksTheStore() {
        let store = EntityStore()
        final class Flag: @unchecked Sendable { var raised = false }
        let changed = Flag()
        withObservationTracking { _ = store.hasReceivedFirstState } onChange: { changed.raised = true }
        store.replaceAll([light])
        #expect(changed.raised)
    }

    // MARK: Arc

    @Test func theArcFollowsARetryOrAWaitForTheFirstState() {
        typealias P = ReconnectingPolicy
        // Retrying shows it, as before.
        #expect(P.showsArc(.waitingToReconnect, isOffline: false, hasReceivedFirstState: true))
        // Live and heard: nothing.
        #expect(!P.showsArc(.connected(version: "x"), isOffline: false, hasReceivedFirstState: true))
        // Connected but the first set has not arrived: still waiting.
        #expect(P.showsArc(.connected(version: "x"), isOffline: false, hasReceivedFirstState: false))
        #expect(P.showsArc(.connecting, isOffline: false, hasReceivedFirstState: false))
        // Offline is the chip's business, and a refused token ends the session.
        #expect(!P.showsArc(.connecting, isOffline: true, hasReceivedFirstState: false))
        #expect(!P.showsArc(.rejected, isOffline: false, hasReceivedFirstState: false))
    }
}
