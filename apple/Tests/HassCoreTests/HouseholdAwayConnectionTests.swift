import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import Testing

/// `HassConnection.callServiceWithResponse`, the real `HassServiceResponding`, over HAKit's mock socket.
@MainActor
struct HouseholdAwayConnectionTests {
    private func makeConnection() -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "away-\(UUID()).json"))
        return (HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock), mock)
    }

    private func pendingRequest(_ mock: HAMockConnection) async throws -> HAMockConnection.PendingRequest {
        for _ in 0..<1_000 where mock.pendingRequests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return try #require(mock.pendingRequests.first)
    }

    @Test func sendsCallServiceWithReturnResponseOnceAndReturnsTheResponse() async throws {
        let (connection, mock) = makeConnection()
        let call = Task { try await connection.callServiceWithResponse("script", "household_away_command", data: ["operation": "cancel", "expected_revision": 4]) }
        let pending = try await pendingRequest(mock)
        #expect(pending.request.type == .webSocket("call_service"))
        #expect(pending.request.data["domain"] as? String == "script")
        #expect(pending.request.data["service"] as? String == "household_away_command")
        #expect(pending.request.data["return_response"] as? Bool == true)
        let serviceData = try #require(pending.request.data["service_data"] as? [String: any Sendable])
        #expect(serviceData["operation"] as? String == "cancel")
        #expect(serviceData["expected_revision"] as? Int == 4)
        // A command must never run twice, so a reconnect may not resend it.
        #expect(!pending.request.shouldRetry)
        pending.completion(.success(HAData(value: ["context": ["id": "c1"], "response": ["status": "accepted", "revision": 5]])))
        // The connection returns the whole result; the controller reads its `response`.
        let result = try await call.value
        #expect(result["response"]?["status"]?.string == "accepted")
        #expect(HouseholdAwayController.outcome(from: .success(result)) == .accepted(revision: 5))
    }

    @Test func aFailureIsThrown() async throws {
        let (connection, mock) = makeConnection()
        let failing = Task { try await connection.callServiceWithResponse("script", "household_away_command", data: [:]) }
        try await pendingRequest(mock).completion(.failure(.internal(debugDescription: "offline")))
        await #expect(throws: HAError.self) { try await failing.value }
    }

    @Test func theControllerTreatsAThrownCallAsTransport() async throws {
        let (connection, mock) = makeConnection()
        connection.store.replaceAll([awayEntity()])
        let controller = HouseholdAwayController(store: connection.store, responder: connection, timeout: .seconds(600), makeRequestId: { "req-9" })
        let outcome = Task { await controller.cancel() }
        let pending = try await pendingRequest(mock)
        let sent = try #require(pending.request.data["service_data"] as? [String: any Sendable])
        #expect(sent["request_id"] as? String == "req-9")
        pending.completion(.failure(.internal(debugDescription: "offline")))
        #expect(await outcome.value == .rejected(errorCode: "transport"))
        #expect(controller.errorCode == "transport")
    }
}
