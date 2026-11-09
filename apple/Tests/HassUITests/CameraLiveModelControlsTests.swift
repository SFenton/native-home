import CoreImage
import CoreVideo
import Foundation
import HassCore
@testable import HassUI
import Testing
import HassTestSupport

/// What a person controls on a live camera: sound, and the picture kept when the stream is paused.
@MainActor
@Suite(.demoHouse)
struct CameraLiveModelControlsTests {
    private let camera = HomeConfig.cameras[0]
    private let connection = HassConnection(server: .example, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())

    @Test func camerasOpenMutedAndOnlyAChangeTellsThePool() {
        let model = CameraLiveModel(camera: camera, modes: [], upgradeDelays: [])
        var changes = 0
        model.onMuteChange = { changes += 1 }
        #expect(model.isMuted)
        model.setMuted(true)
        #expect(changes == 0, "Already muted")
        model.setMuted(false)
        #expect(!model.isMuted && changes == 1)
        model.setMuted(false)
        #expect(changes == 1)
        model.setMuted(true)
        #expect(model.isMuted && changes == 2)
    }

    @Test func aModelWithNoLiveModeGivesUpAtOnceAndKeepsTheSnapshot() {
        let model = CameraLiveModel(camera: camera, modes: [], upgradeDelays: [])
        var exhausted = 0
        model.onExhausted = { exhausted += 1 }
        model.start(connection: connection)
        #expect(!model.isRunning && model.state.phase == .failed && exhausted == 1)
        #expect(model.liveFrameSource() == nil)
        #expect(model.liveResources["Camera.players"] == 0 && model.liveResources["Camera.attempts"] == 0)
    }

    @Test func pausingWithNoPictureLeavesNothingOverTheSnapshot() async {
        let model = CameraLiveModel(camera: camera, modes: [], upgradeDelays: [])
        await model.pause()
        #expect(model.pausedFrame == nil && !model.isRunning)
    }

    @Test func suspendingALiveStreamRemembersWhenItWasLast() async {
        let opened = Opened()
        let model = CameraLiveModel(camera: camera, modes: [.hls], opener: { _, _, _, _ in opened.count += 1 },
                                    firstFrameTimeout: { _ in .seconds(30) }, upgradeDelays: [])
        model.start(connection: connection)
        for _ in 0..<200 where opened.count == 0 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.lastLiveAt == nil)
        model.firstFrame(.hls)
        #expect(model.state.phase == .live)
        model.suspend()
        #expect(model.lastLiveAt != nil && model.state.phase == .connecting && !model.isRunning)
        model.start(connection: connection)
        model.firstFrame(.hls)
        #expect(model.lastLiveAt == nil, "The next first frame clears it")
        model.stop()
    }

    @MainActor final class Opened { var count = 0 }

    @Test func aPixelBufferFrameBecomesAnImageOfTheSameSize() async throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 16, 9, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixels = try #require(buffer)
        let image = try #require(await CameraFrame.pixels(pixels).image())
        #expect(image.width == 16 && image.height == 9)
    }
}
