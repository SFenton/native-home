import Foundation
import HassCore
@testable import HassUI
import Testing
import HassTestSupport

/// A stream that fell back to HLS keeps trying WebRTC in the background and swaps to it on its first frame, staying live.
@MainActor
@Suite(.demoHouse)
struct CameraUpgradeTests {
    /// Opens per mode; WebRTC fails its first open (so the stream falls back to HLS) and then does what `laterWebRTC` says.
    @MainActor
    final class Opens {
        enum Later { case fails, hangs }
        var webRTC = 0
        var hls = 0
        var later = Later.hangs

        var opener: CameraStreamOpener {
            { [self] _, mode, _, _ in
                switch mode {
                case .hls: hls += 1
                case .webRTC:
                    webRTC += 1
                    if webRTC == 1 || later == .fails { throw URLError(.cannotConnectToHost) }
                }
            }
        }
    }

    private let camera = HomeConfig.cameras[0]
    /// Held for the test: the model only keeps its connection weakly.
    private let connection = HassConnection(server: .example, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())

    private func makeModel(_ opens: Opens, delays: [Duration], timeout: Duration = .seconds(30)) -> CameraLiveModel {
        CameraLiveModel(camera: camera, modes: [.webRTC, .hls], opener: opens.opener, firstFrameTimeout: { _ in timeout },
                        upgradeDelays: delays)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Starts the model and puts it live on HLS, as a stream whose WebRTC missed its budget would be.
    private func liveOnHLS(_ model: CameraLiveModel, _ opens: Opens) async {
        model.start(connection: connection)
        await waitUntil { opens.hls == 1 }
        model.firstFrame(.hls)
        #expect(model.state.phase == .live && model.state.mode == .hls)
    }

    @Test func aWebRTCFrameWhileHLSPlaysSwapsToWebRTCAndStaysLive() async {
        let opens = Opens()
        let model = makeModel(opens, delays: [.milliseconds(20)])
        var lives = 0
        model.onLive = { lives += 1 }
        await liveOnHLS(model, opens)
        await waitUntil { opens.webRTC == 2 }
        #expect(opens.webRTC == 2, "one background attempt after the first, failed one")
        #expect(model.state.mode == .hls && model.state.phase == .live, "HLS keeps playing until WebRTC has a frame")
        model.firstFrame(.webRTC)
        #expect(model.state.mode == .webRTC)
        #expect(model.state.phase == .live)
        #expect(lives == 2, "the pool is told again, which resets its retry count")
        #expect(model.liveResources["Camera.upgrades"] == 0)
        model.stop()
    }

    @Test func aFailedAttemptIsRetriedUntilTheDelaysRunOutAndHLSKeepsPlaying() async {
        let opens = Opens()
        opens.later = .fails
        let model = makeModel(opens, delays: [.milliseconds(10), .milliseconds(10)])
        await liveOnHLS(model, opens)
        await waitUntil { opens.webRTC == 3 }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(opens.webRTC == 3, "the first open plus one per delay, then no more")
        #expect(model.state.mode == .hls && model.state.phase == .live)
        #expect(model.liveResources["Camera.upgrades"] == 0)
        model.stop()
    }

    @Test func anAttemptThatShowsNoFrameTimesOutAndTriesAgain() async {
        let opens = Opens()
        let model = makeModel(opens, delays: [.milliseconds(10), .milliseconds(10)], timeout: .milliseconds(40))
        // The hung first open is the stream's own WebRTC attempt, which must fail for HLS to carry it.
        model.start(connection: connection)
        await waitUntil { opens.hls == 1 }
        model.firstFrame(.hls)
        await waitUntil { opens.webRTC == 3 }
        #expect(opens.webRTC == 3, "a hung attempt is abandoned after the WebRTC budget and the next delay follows")
        #expect(model.state.mode == .hls && model.state.phase == .live)
        try? await Task.sleep(for: .milliseconds(150)) // The last attempt's budget ends.
        #expect(opens.webRTC == 3, "the delays have run out")
        model.firstFrame(.webRTC)
        #expect(model.state.mode == .hls, "no attempt is open once they have run out: a late frame is stale")
        model.stop()
    }

    @Test func stoppingCancelsAPendingUpgrade() async {
        let opens = Opens()
        let model = makeModel(opens, delays: [.milliseconds(60)])
        await liveOnHLS(model, opens)
        #expect(model.liveResources["Camera.upgrades"] == 1)
        model.stop()
        #expect(model.liveResources["Camera.upgrades"] == 0)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(opens.webRTC == 1, "nothing opens after the stream stopped")
    }

    @Test func noUpgradeWhenWebRTCItselfWentLiveOrDelaysAreEmpty() async {
        let opens = Opens()
        let off = makeModel(opens, delays: [])
        await liveOnHLS(off, opens)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(opens.webRTC == 1, "empty delays turn upgrades off")
        off.stop()

        let direct = CameraLiveModel(camera: camera, modes: [.webRTC, .hls], opener: { _, _, _, _ in },
                                     firstFrameTimeout: { _ in .seconds(30) }, upgradeDelays: [.milliseconds(10)])
        direct.start(connection: connection)
        direct.firstFrame(.webRTC)
        #expect(direct.liveResources["Camera.upgrades"] == 0, "WebRTC has nothing better to upgrade to")
        direct.stop()
    }

    @Test func aStalledStreamRestartsFromWebRTCNotFromTheUpgrade() async {
        let opens = Opens()
        let frames = 0
        let model = CameraLiveModel(camera: camera, modes: [.webRTC, .hls], opener: opens.opener,
                                    firstFrameTimeout: { _ in .seconds(30) }, stallAfter: .milliseconds(50),
                                    stallCheckInterval: .milliseconds(10), upgradeDelays: [.seconds(30)],
                                    frameCounter: { _ in frames })
        var stalled = false
        model.onStalled = { stalled = true }
        await liveOnHLS(model, opens)
        await waitUntil { stalled }
        #expect(stalled && model.state.phase == .connecting, "the watchdog still takes a frozen HLS stream down")
        #expect(model.liveResources["Camera.upgrades"] == 0, "and its pending upgrade goes with it")
        model.stop()
    }
}
