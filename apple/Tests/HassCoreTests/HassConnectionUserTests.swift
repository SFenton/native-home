import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import Testing

@MainActor
struct HassConnectionUserTests {
    private func makeConnection() -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "user-\(UUID()).json"))
        let connection = HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock)
        return (connection, mock)
    }

    /// Waits for the request `currentUser()` sends over the mock.
    private func pendingRequest(_ mock: HAMockConnection) async throws -> HAMockConnection.PendingRequest {
        for _ in 0..<1_000 where mock.pendingRequests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return try #require(mock.pendingRequests.first)
    }

    @Test func currentUserMapsTheServerUser() async throws {
        let (connection, mock) = makeConnection()
        async let user = connection.currentUser()
        let request = try await pendingRequest(mock)
        #expect(request.request.type == .currentUser)
        request.completion(.success(HAData(value: ["id": "abc", "name": "Alex", "is_owner": true, "is_admin": true])))
        #expect(try await user == HassUser(id: "abc", name: "Alex", isOwner: true, isAdmin: true))
    }

    @Test func currentUserThrowsTheServerError() async throws {
        let (connection, mock) = makeConnection()
        let user = Task { try await connection.currentUser() }
        let request = try await pendingRequest(mock)
        request.completion(.failure(.internal(debugDescription: "offline")))
        await #expect(throws: HAError.self) { try await user.value }
    }

    @Test func roleTitles() {
        #expect(HassUser(id: "1", name: nil, isOwner: true, isAdmin: true).roleTitle == "Owner")
        #expect(HassUser(id: "2", name: nil, isOwner: false, isAdmin: true).roleTitle == "Administrator")
        #expect(HassUser(id: "3", name: nil, isOwner: false, isAdmin: false).roleTitle == "User")
    }
}
