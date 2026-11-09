import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTelemetry
import Testing

/// Every resume-time registration is idempotent and torn down on background (owner report 2026-10-16: scrolling got
/// worse after every background and foreground, so something was added each time and never removed;
/// `.agents/platforms/apple/connection-lifecycle.md`, "Resume rule"). The connection and its lifecycle are cycled
/// through the same calls the app's scene phase makes, and what each holds must come back to the same set.
@MainActor
struct ResumeLifecycleTests {
    private func make() -> (HassConnection, ConnectionLifecycle, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "resume-\(UUID()).json"))
        let connection = HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock)
        return (connection, ConnectionLifecycle(connection: connection), mock)
    }

    // MARK: - Connect

    @Test func connectingTwiceHoldsOneStatesSubscriptionAndOneObserver() {
        let (connection, _, _) = make()
        connection.connect()
        let once = connection.liveResources
        connection.connect()
        connection.connect()
        #expect(connection.liveResources == once)
        #expect(once["Connection.statesSubscription"] == 1)
        #expect(once["Connection.stateObserver"] == 1)
    }

    @Test func disconnectDropsTheSubscriptionAndConnectRestoresExactlyOne() {
        let (connection, _, _) = make()
        connection.connect()
        connection.disconnect()
        #expect(connection.liveResources["Connection.statesSubscription"] == 0)
        #expect(connection.liveResources["Connection.routeTask"] == 0)
        connection.connect()
        connection.connect()
        #expect(connection.liveResources["Connection.statesSubscription"] == 1)
    }

    @Test func theStateObserverIsRemovedWhenTheConnectionGoes() async throws {
        let mock = HAMockConnection()
        var connection: HassConnection? = HassConnection(
            server: .example, store: EntityStore(),
            snapshotCache: EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "gone-\(UUID()).json")),
            connection: mock
        )
        weak var released = connection
        connection?.connect(subscribingToStates: false)
        connection = nil
        #expect(released == nil)
        // A transition after the connection is gone reaches no observer (none is left to retain or call).
        mock.setState(.ready(version: "2026.10"), waitForQueue: false)
        try await Task.sleep(for: .milliseconds(30))
    }

    // MARK: - Scene phases

    @Test func manyBackgroundAndForegroundCyclesLeaveTheFirstLaunchSet() {
        let (connection, lifecycle, _) = make()
        lifecycle.didBecomeActive()
        let launch = connection.liveResources.merging(lifecycle.liveResources) { $1 }
        for _ in 0..<10 {
            lifecycle.didEnterBackground()
            #expect(lifecycle.liveResources["Lifecycle.pendingDisconnect"] == 1, "Only the grace-period disconnect is pending")
            lifecycle.didBecomeActive()
        }
        #expect(connection.liveResources.merging(lifecycle.liveResources) { $1 } == launch)
    }

    @Test func backgroundingAgainReplacesThePendingDisconnectInsteadOfAddingOne() {
        let (_, lifecycle, _) = make()
        lifecycle.didBecomeActive()
        lifecycle.didEnterBackground()
        lifecycle.didEnterBackground()
        lifecycle.didEnterBackground()
        #expect(lifecycle.liveResources["Lifecycle.pendingDisconnect"] == 1)
        lifecycle.didBecomeActive()
        #expect(lifecycle.liveResources["Lifecycle.pendingDisconnect"] == 0)
    }

    @Test func aLongBackgroundDisconnectsOnceAndTheReturnResubscribesOnce() async {
        let (connection, lifecycle, _) = make()
        lifecycle.didBecomeActive()
        // The grace period itself is 30 s; drive its outcome directly.
        for _ in 0..<5 {
            lifecycle.didEnterBackground()
            connection.disconnect()
            #expect(connection.liveResources["Connection.statesSubscription"] == 0)
            lifecycle.didBecomeActive()
            #expect(connection.liveResources["Connection.statesSubscription"] == 1)
            #expect(connection.liveResources["Connection.stateObserver"] == 1)
            #expect(lifecycle.liveResources["Lifecycle.pendingDisconnect"] == 0)
        }
    }

    @Test func theCensusSeesTheConnectionWhileItLivesAndNotAfter() {
        var connection: HassConnection? = make().0
        connection?.connect()
        // The census sums every live connection (other tests make theirs), so compare before and after.
        let during = ResourceCensus.shared.counts()["Connection.statesSubscription"] ?? 0
        #expect(during >= 1)
        connection = nil
        let after = ResourceCensus.shared.counts()["Connection.statesSubscription"] ?? 0
        #expect(after < during)
    }
}
