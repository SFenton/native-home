import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import Testing

/// The socket checks the camera streams rely on after a background (owner report 2026-10-16: HAKit drops a
/// command caught by a reset without answering it, so streams requested then never came back).
@MainActor
struct HassConnectionLivenessTests {
    private func makeConnection() -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "liveness-\(UUID()).json"))
        let connection = HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock)
        return (connection, mock)
    }

    /// Polls `condition` until it holds (bounded at 10 s). The mock delivers state changes on the main queue, a hop after
    /// they are set, and under a loaded host that hop took longer than the fixed 50 ms this suite used to wait: a
    /// connection that was not connected yet made `ensureLive` answer false (its own wait spins a run loop, which hangs here).
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func isConnected(_ connection: HassConnection) -> Bool {
        if case .connected = connection.status { return true }
        return false
    }

    /// Connects and waits until the connection shows it.
    private func connectAndSettle(_ connection: HassConnection) async {
        connection.connect(subscribingToStates: false)
        await waitUntil { isConnected(connection) }
    }

    private func pendingPing(_ mock: HAMockConnection) async throws -> HAMockConnection.PendingRequest {
        for _ in 0..<500 where !mock.pendingRequests.contains(where: { $0.request.type == .ping }) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return try #require(mock.pendingRequests.first { $0.request.type == .ping })
    }

    // MARK: - Commands that are never answered

    @Test func aCommandHAKitNeverAnswersTimesOut() async throws {
        let (connection, mock) = makeConnection()
        await #expect(throws: CommandTimeout.self) {
            _ = try await connection.sendCommand("auth/sign_path", data: [:], timeout: .milliseconds(80))
        }
        #expect(mock.cancelledRequests.count == 1, "The dropped request is cancelled so HAKit does not resend it")
    }

    @Test func aCommandAnsweredInTimeReturnsItsResultOnce() async throws {
        let (connection, mock) = makeConnection()
        // A timeout that a busy main actor cannot overtake between the request showing up and its answer (200 ms lost
        // that race under load); the sleep afterwards lets the timer fire and shows it does not resume a second time.
        let task = Task { try await connection.sendCommand("auth/sign_path", data: [:], timeout: .seconds(1)) }
        for _ in 0..<500 where mock.pendingRequests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        let request = try #require(mock.pendingRequests.first)
        request.completion(.success(HAData(value: ["path": "/api/webrtc/ws?authSig=x"])))
        _ = try await task.value
        try? await Task.sleep(for: .milliseconds(1300)) // The timer fires later and must not resume again.
        #expect(mock.cancelledRequests.isEmpty)
    }

    @Test func streamCommandsCarryATimeout() {
        #expect(HassConnection.streamCommandTimeout > .seconds(5))
    }

    // MARK: - Waiting for the socket

    @Test func awaitConnectedReturnsOnceTheSocketIsReady() async throws {
        let (connection, mock) = makeConnection()
        connection.connect(subscribingToStates: false)
        #expect(await connection.awaitConnected(timeout: .seconds(10)))
        if case .connected = connection.status {} else { Issue.record("Expected connected, got \(connection.status)") }
    }

    @Test func awaitConnectedGivesUpOnTimeoutAndWhenRejected() async {
        let (connection, mock) = makeConnection()
        #expect(await connection.awaitConnected(timeout: .milliseconds(150)) == false, "Never connected")
        mock.setState(.disconnected(reason: .rejected), waitForQueue: false)
        await waitUntil { connection.status == .rejected }
        #expect(await connection.awaitConnected(timeout: .seconds(10)) == false, "A rejected token stops the wait at once")
    }

    @Test func readyNotificationPostsEachTimeTheSocketBecomesReady() async {
        let (connection, mock) = makeConnection()
        var count = 0
        let token = NotificationCenter.default.addObserver(forName: HassConnection.didBecomeReadyNotification, object: connection, queue: .main) { _ in
            MainActor.assumeIsolated { count += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        /// HAKit calls back on the connection's own queue, so each state reaches the main actor a hop after it is set; wait for
        /// the connection to show it instead of guessing how long the hop takes.
        connection.connect(subscribingToStates: false)
        await waitUntil { isConnected(connection) }
        mock.setState(.disconnected(reason: .disconnected), waitForQueue: false)
        await waitUntil { connection.status == .disconnected }
        mock.setState(.ready(version: "1.0-mock"), waitForQueue: false)
        await waitUntil { isConnected(connection) }
        await waitUntil { count == 2 }
        #expect(count == 2, "First connect and the reconnect")
    }

    // MARK: - Making the socket answer

    @Test func aSocketThatAnswersIsLeftAlone() async throws {
        let (connection, mock) = makeConnection()
        await connectAndSettle(connection)
        async let live = connection.ensureLive(timeout: .seconds(10), pingTimeout: .seconds(5))
        try await pendingPing(mock).completion(.success(.empty))
        #expect(await live)
        #expect(mock.cancelledRequests.isEmpty)
        if case .connected = connection.status {} else { Issue.record("Expected connected, got \(connection.status)") }
    }

    @Test func aSocketThatDoesNotAnswerIsReplaced() async throws {
        let (connection, mock) = makeConnection()
        var transitions = 0
        let token = NotificationCenter.default.addObserver(forName: HAConnectionState.didTransitionToStateNotification, object: mock, queue: .main) { _ in
            MainActor.assumeIsolated { transitions += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        await connectAndSettle(connection)
        // The first connection's transitions have all been delivered before they are counted as "before": the count
        // holds still for several polls.
        var stable = 0, last = -1
        await waitUntil {
            stable = transitions == last ? stable + 1 : 0
            last = transitions
            return stable >= 5
        }
        let before = transitions
        let live = await connection.ensureLive(timeout: .seconds(10), pingTimeout: .milliseconds(100))
        #expect(live, "The replacement socket is ready")
        await waitUntil { transitions - before >= 4 }
        // The mock collapses the reconnect into its final state, so count its transitions: disconnected, connecting,
        // authenticating, ready.
        #expect(transitions - before == 4, "The silent socket was disconnected and connected again")
        if case .ready = mock.state {} else { Issue.record("Expected ready, got \(mock.state)") }
    }

    @Test func aDisconnectedAppIsNotReconnectedByTheCheck() async {
        let (connection, _) = makeConnection()
        #expect(await connection.ensureLive(timeout: .milliseconds(200)) == false)
        connection.reconnect()
        #expect(connection.status == .disconnected, "Only a connection the app wants is replaced")
    }
}

// MARK: - Offline

private final class FakeReachability: NetworkReachability, @unchecked Sendable {
    var isOnline: Bool
    var onChange: (@Sendable (Bool) -> Void)?
    init(online: Bool) { isOnline = online }
    func start(_ onChange: @escaping @Sendable (Bool) -> Void) { self.onChange = onChange }
    func set(_ online: Bool) { isOnline = online; onChange?(online) }
}

@MainActor
struct HassConnectionOfflineTests {
    private func make(online: Bool) -> (HassConnection, HAMockConnection, FakeReachability) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "offline-\(UUID()).json"))
        let net = FakeReachability(online: online)
        return (HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock, reachability: net), mock, net)
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(80)) }

    @Test func launchingOfflineDoesNotOpenTheSocket() async {
        let (connection, mock, _) = make(online: false)
        connection.connect(subscribingToStates: false)
        await settle()
        #expect(connection.isOffline)
        #expect(mock.state == .disconnected(reason: .disconnected))
        #expect(!ReconnectingPolicy.showsReconnecting(connection.status, isOffline: connection.isOffline))
    }

    @Test func losingThePathClosesTheSocketSoBackoffStops() async {
        let (connection, mock, net) = make(online: true)
        connection.connect(subscribingToStates: false)
        mock.setState(.ready(version: "2026.10"), waitForQueue: false)
        await settle()
        net.set(false)
        await settle()
        #expect(connection.isOffline)
        #expect(mock.state == .disconnected(reason: .disconnected), "closed on purpose, not waiting to retry")
        connection.reconnect()
        #expect(mock.state == .disconnected(reason: .disconnected), "no reconnect spin while offline")
    }

    @Test func aReturningPathReconnectsAtOnce() async {
        let (connection, mock, net) = make(online: false)
        connection.connect(subscribingToStates: false)
        await settle()
        net.set(true)
        await settle()
        #expect(!connection.isOffline)
        #expect(mock.state != .disconnected(reason: .disconnected), "connecting without waiting out a backoff")
    }

    @Test func offlineIsNotReconnecting() {
        #expect(ReconnectingPolicy.showsReconnecting(.waitingToReconnect, isOffline: false))
        #expect(!ReconnectingPolicy.showsReconnecting(.waitingToReconnect, isOffline: true))
    }
}
