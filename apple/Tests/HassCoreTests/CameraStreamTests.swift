import Foundation
@testable import HassCore
import Testing
import HassTestSupport

struct CameraStreamStateTests {
    @Test func startsConnectingTheFirstMode() {
        let state = CameraStreamState()
        #expect(state.mode == .webRTC)
        #expect(state.phase == .connecting)
    }

    @Test func firstFrameGoesLiveOnlyForTheCurrentMode() {
        var state = CameraStreamState()
        state.firstFrame(.hls)
        #expect(state.phase == .connecting, "a stale HLS frame must not mark WebRTC live")
        state.firstFrame(.webRTC)
        #expect(state.phase == .live)
    }

    @Test func failureFallsBackThenStops() {
        var state = CameraStreamState()
        state.failed(.webRTC)
        #expect(state.mode == .hls)
        #expect(state.phase == .connecting)
        state.failed(.webRTC)
        #expect(state.mode == .hls, "a stale WebRTC failure is ignored")
        state.failed(.hls)
        #expect(state.phase == .failed)
        #expect(state.mode == nil)
    }

    @Test func dropWhileLiveFallsBack() {
        var state = CameraStreamState()
        state.firstFrame(.webRTC)
        state.failed(.webRTC)
        #expect(state.mode == .hls)
        #expect(state.phase == .connecting)
    }

    @Test func aFallbackStreamCanUpgradeToAPreferredModeAndStaysLive() {
        var state = CameraStreamState()
        #expect(!state.canUpgrade, "connecting is not live")
        state.failed(.webRTC)
        state.firstFrame(.hls)
        #expect(state.canUpgrade)
        state.upgrade(to: .hls)
        #expect(state.mode == .hls, "only a more preferred mode is an upgrade")
        state.upgrade(to: .webRTC)
        #expect(state.mode == .webRTC)
        #expect(state.phase == .live, "the swap never leaves live")
        #expect(!state.canUpgrade, "the first mode has nothing better")
    }

    @Test func upgradeIsIgnoredUnlessLive() {
        var state = CameraStreamState()
        state.failed(.webRTC)
        state.upgrade(to: .webRTC)
        #expect(state.mode == .hls, "a connecting HLS stream is not upgraded")
        state.failed(.hls)
        state.upgrade(to: .webRTC)
        #expect(state.phase == .failed)
    }

    @Test func restartReturnsToTheFirstMode() {
        var state = CameraStreamState()
        state.failed(.webRTC)
        state.failed(.hls)
        state.restart()
        #expect(state.mode == .webRTC)
        #expect(state.phase == .connecting)
    }

    @Test func noModesMeansFailed() {
        var state = CameraStreamState(modes: [])
        #expect(state.phase == .failed)
        #expect(state.mode == nil)
        state.restart()
        #expect(state.phase == .failed)
    }

    /// HLS waits out Home Assistant's cold-stream warm-up (about 10 to 13 s) before falling back.
    @Test func hlsGetsALongerFirstFrameBudgetThanWebRTC() {
        #expect(CameraStreamMode.webRTC.firstFrameTimeout == .seconds(10))
        #expect(CameraStreamMode.hls.firstFrameTimeout > .seconds(15))
    }
}

struct CameraStreamEndpointTests {
    let base = URL(string: "https://ha.example.com")!

    @Test func hlsPathResolvesAgainstTheServer() {
        let url = CameraStreamEndpoints.hlsURL(path: "/api/hls/abc/master_playlist.m3u8", baseURL: base)
        #expect(url?.absoluteString == "https://ha.example.com/api/hls/abc/master_playlist.m3u8")
    }

    @Test func webRTCSocketKeepsTheSignatureAndAddsTheStream() {
        let url = CameraStreamEndpoints.webRTCSocketURL(
            signedPath: "/api/webrtc/ws?authSig=eyJ.a-b_c.d",
            streamId: "front_door",
            baseURL: base
        )
        #expect(url?.absoluteString == "wss://ha.example.com/api/webrtc/ws?authSig=eyJ.a-b_c.d&url=front_door")
    }

    @Test func webRTCSocketUsesWsForHttpAndEscapesTheStream() {
        let url = CameraStreamEndpoints.webRTCSocketURL(
            signedPath: "/api/webrtc/ws?authSig=x",
            streamId: "rtsp://cam/a&b",
            baseURL: URL(string: "http://192.0.2.10:8123")!
        )
        #expect(url?.scheme == "ws")
        #expect(url?.absoluteString.hasSuffix("&url=rtsp://cam/a%26b") == true)
    }

    @Test func webRTCSocketRejectsOtherSchemes() {
        #expect(CameraStreamEndpoints.webRTCSocketURL(signedPath: "/x", streamId: "a", baseURL: URL(string: "ftp://h")!) == nil)
    }
}

struct WebRTCSignalTests {
    @Test func roundTripsEveryMessage() {
        for signal in [WebRTCSignal.offer("v=0\r\n"), .answer("v=0"), .candidate("candidate:1 1 udp 1 1.2.3.4 5 typ host"), .error("no stream")] {
            #expect(WebRTCSignal(text: signal.encoded()) == signal)
        }
    }

    @Test func encodesTheGo2rtcShape() throws {
        let json = try #require(JSONSerialization.jsonObject(with: Data(WebRTCSignal.offer("sdp").encoded().utf8)) as? [String: String])
        #expect(json == ["type": "webrtc/offer", "value": "sdp"])
    }

    @Test func ignoresUnknownAndMalformedMessages() {
        #expect(WebRTCSignal(text: #"{"type":"mse","value":"avc1"}"#) == nil)
        #expect(WebRTCSignal(text: "not json") == nil)
        #expect(WebRTCSignal(text: #"{"value":"x"}"#) == nil)
    }

    @Test func missingValueDecodesEmpty() {
        #expect(WebRTCSignal(text: #"{"type":"webrtc/candidate"}"#) == .candidate(""))
    }
}

struct CameraStreamRetentionTests {
    @Test func firstViewStartsAndLaterViewsShareTheStream() {
        var retention = CameraStreamRetention()
        #expect(retention.appear("front", isRunning: false) == .start)
        #expect(retention.appear("front", isRunning: true) == .none, "The viewer attaches to the tile's stream")
        #expect(retention.viewers["front"] == 2)
    }

    @Test func shownStreamsAreRetainedAfterTheirLastView() {
        var retention = CameraStreamRetention()
        _ = retention.appear("front", isRunning: false)
        #expect(retention.disappear("front") == .none)
        #expect(retention.shouldRun("front"))
        #expect(retention.viewers["front"] == nil)
        #expect(retention.appear("front", isRunning: true) == .none, "A later page reuses the retained stream")
    }

    @Test func withoutRetentionTheLastViewStops() {
        var retention = CameraStreamRetention(retainsShownStreams: false)
        _ = retention.appear("front", isRunning: false)
        _ = retention.appear("front", isRunning: true)
        #expect(retention.disappear("front") == .none, "Another view still shows it")
        #expect(retention.disappear("front") == .stop)
        #expect(retention.disappear("front") == .stop, "Extra disappearances never go negative")
        #expect(!retention.shouldRun("front"))
    }

    @Test func aFailedStreamDropsItsRetention() {
        var retention = CameraStreamRetention()
        _ = retention.appear("front", isRunning: false)
        retention.failed("front")
        #expect(retention.shouldRun("front"), "Its view is still up")
        #expect(retention.disappear("front") == .stop)
        #expect(retention.appear("front", isRunning: false) == .start, "The next view starts fresh")
    }

    @Test func releasingAStreamNoViewShowsStopsItAndTheNextViewStartsFresh() {
        var retention = CameraStreamRetention()
        _ = retention.appear("front", isRunning: false)
        #expect(retention.disappear("front") == .none)
        #expect(retention.release("front") == .stop)
        #expect(!retention.shouldRun("front"))
        #expect(retention.wanted.isEmpty, "A released stream is not restarted on return from the background")
        #expect(retention.appear("front", isRunning: false) == .start)
        #expect(retention.shouldRun("front"))
    }

    @Test func releasingAStreamAViewStillShowsLeavesItRunning() {
        var retention = CameraStreamRetention()
        _ = retention.appear("front", isRunning: false)
        #expect(retention.release("front") == .none)
        #expect(retention.shouldRun("front"))
    }

    @Test func retryRetainsAgain() {
        var retention = CameraStreamRetention()
        retention.failed("front")
        retention.retry("front")
        #expect(retention.shouldRun("front"))
        var unretained = CameraStreamRetention(retainsShownStreams: false)
        unretained.retry("front")
        #expect(!unretained.shouldRun("front"))
    }

    @Test func backgroundStopsEverythingAndForegroundRestartsShownStreams() {
        var retention = CameraStreamRetention()
        _ = retention.appear("front", isRunning: false)
        _ = retention.appear("drive", isRunning: false)
        _ = retention.disappear("drive")
        #expect(retention.enterBackground() == ["front", "drive"])
        #expect(!retention.shouldRun("front"))
        #expect(retention.appear("deck", isRunning: false) == .none, "Nothing starts in the background")
        #expect(retention.enterForeground() == ["front", "drive", "deck"])
        #expect(retention.shouldRun("drive"))
    }

    @Test func wantedStreamsAreTheShownAndRetainedOnesWhileInTheForeground() {
        var retention = CameraStreamRetention()
        #expect(retention.wanted.isEmpty)
        _ = retention.appear("front", isRunning: false)
        _ = retention.appear("drive", isRunning: false)
        _ = retention.disappear("drive")
        #expect(retention.wanted == ["front", "drive"])
        retention.failed("drive")
        #expect(retention.wanted == ["front"], "A failed stream nobody shows is not wanted")
        _ = retention.enterBackground()
        #expect(retention.wanted.isEmpty, "Nothing is wanted behind a backgrounded app")
        #expect(retention.enterForeground() == ["front"])
        #expect(retention.wanted == ["front"])
    }
}

@Suite(.demoHouse)
struct CameraConfigTests {
    @Test func everyHomeCameraRecordsThroughItsScript() {
        for camera in HomeConfig.cameras {
            #expect(camera.recordingEntityId?.hasPrefix("input_boolean.") == true)
            let call = camera.recordCall
            #expect(call?.domain == "script")
            #expect(call?.service == "turn_on")
            #expect(call?.target == camera.recordingScriptEntityId)
        }
        let plain = HomeConfig.Camera(title: "Test", entityId: "camera.test", rtcStreamId: "test", aspectRatio: 1)
        #expect(plain.recordCall == nil)
    }
}
