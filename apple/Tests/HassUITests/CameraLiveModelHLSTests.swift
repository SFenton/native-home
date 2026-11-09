import Foundation
import HassTestSupport
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
@testable import HassUI
import Testing

/// The HLS path of a live camera against a mocked Home Assistant socket and a stream address nothing answers on: asking for the
/// stream, building the player, and what happens when the picture never arrives or stops.
@MainActor
@Suite(.demoHouse)
struct CameraLiveModelHLSTests {
    private let camera = HomeConfig.cameras[0]

    private func connected() async -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "camera-hls-\(UUID()).json"))
        let server = HassServer(baseURL: URL(string: "http://127.0.0.1:1")!)
        let connection = HassConnection(server: server, store: EntityStore(), snapshotCache: cache, connection: mock)
        connection.connect(subscribingToStates: false)
        for _ in 0..<1000 {
            if case .connected = connection.status { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return (connection, mock)
    }

    private func pending(_ mock: HAMockConnection, named command: String) async -> HAMockConnection.PendingRequest? {
        for _ in 0..<1000 {
            if let found = mock.pendingRequests.first(where: { "\($0.request.type)".contains(command) }) { return found }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aPlaylistThatCannotBeLoadedFailsTheModeAndLeavesTheSnapshot() async throws {
        let (connection, mock) = await connected()
        let model = CameraLiveModel(camera: camera, modes: [.hls], firstFrameTimeout: { _ in .seconds(30) }, upgradeDelays: [])
        var exhausted = 0
        model.onExhausted = { exhausted += 1 }
        model.start(connection: connection)
        let request = try #require(await pending(mock, named: "camera/stream"))
        request.completion(.success(HAData(value: ["url": "/api/hls/token/master_playlist.m3u8"])))
        await waitUntil { exhausted > 0 }
        #expect(exhausted == 1 && model.state.phase == .failed && !model.isRunning)
        #expect(model.hlsPlayer == nil, "The failed player is released")
    }

    @Test func aRefusedStreamRequestFailsTheMode() async throws {
        let (connection, mock) = await connected()
        let model = CameraLiveModel(camera: camera, modes: [.hls], firstFrameTimeout: { _ in .seconds(30) }, upgradeDelays: [])
        var exhausted = 0
        model.onExhausted = { exhausted += 1 }
        model.start(connection: connection)
        let request = try #require(await pending(mock, named: "camera/stream"))
        request.completion(.failure(.internal(debugDescription: "no stream")))
        await waitUntil { exhausted > 0 }
        #expect(model.state.phase == .failed)
    }
}
