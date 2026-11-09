import Foundation
import HassCore
@testable import HassUI
import Testing
import HassTestSupport

/// The pool's lifecycle with fake stream sessions: what restarts when the app returns or the socket comes back,
/// and what is left alone (owner report 2026-10-16: cameras did not reconnect after the app was backgrounded).
@MainActor
@Suite(.demoHouse)
struct CameraStreamPoolTests {
    /// Records every open and answers like the network would.
    @MainActor
    final class FakeStreams {
        /// Opens per camera stream id, across modes.
        var opens: [String: Int] = [:]
        /// Throwing makes every mode fail, as an unreachable server does.
        var fails = false
        /// Calls to the connection check, and the gate holding it open.
        var checks = 0
        var gate: CheckedContinuation<Void, Never>?
        var holdsCheck = false
        /// The fake frame source: the count every live stream reports, and whether it advances on each read.
        var frames = 0
        var advancing = true

        var opener: CameraStreamOpener {
            { [self] model, _, _, _ in
                opens[model.camera.rtcStreamId, default: 0] += 1
                if fails { throw URLError(.cannotConnectToHost) }
            }
        }

        func check(_ connection: HassConnection) async {
            checks += 1
            guard holdsCheck else { return }
            await withCheckedContinuation { gate = $0 }
        }

        func release() {
            gate?.resume()
            gate = nil
        }
    }

    private let front = HomeConfig.cameras[0]
    private let driveway = HomeConfig.cameras[1]

    private func makePool(_ streams: FakeStreams, retryDelays: [Duration] = [], pauseAfterHidden: Duration = .seconds(60),
                          stallAfter: Duration = .seconds(60)) -> (CameraStreamPool, HassConnection) {
        let pool = CameraStreamPool(
            modes: [.webRTC, .hls], observesApp: false, opener: streams.opener, retryDelays: retryDelays,
            pauseAfterHidden: pauseAfterHidden, stallAfter: stallAfter, stallCheckInterval: .milliseconds(10),
            frameCounter: { [streams] _ in
                if streams.advancing { streams.frames += 1 }
                return streams.frames
            },
            prepareConnection: { [streams] connection in await streams.check(connection) }
        )
        let connection = HassConnection(server: .example, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
        return (pool, connection)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func goLive(_ model: CameraLiveModel) {
        model.firstFrame(.webRTC)
        #expect(model.state.phase == .live)
    }

    // MARK: - Background and return

    @Test func aStreamStoppedInTheBackgroundIsRebuiltOnceOnReturn() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)

        pool.enterBackground()
        #expect(!model.isRunning)
        #expect(model.state.phase == .connecting, "The snapshot is back over the empty player; nothing reads Live over a black frame")

        pool.enterForeground()
        await waitUntil { streams.opens["front_door"] == 2 }
        #expect(streams.opens["front_door"] == 2)
        #expect(model.isRunning)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(streams.opens["front_door"] == 2, "Rebuilt once, not once per trigger")
        #expect(streams.checks == 1, "The connection was checked before the streams restarted")
    }

    @Test func streamsWaitForTheConnectionCheckBeforeRestarting() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)
        pool.enterBackground()

        streams.holdsCheck = true
        pool.enterForeground()
        await waitUntil { streams.checks == 1 }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(streams.opens["front_door"] == 1, "No stream is asked for while the socket is unconfirmed")
        #expect(model.state.phase == .connecting)

        streams.release()
        await waitUntil { streams.opens["front_door"] == 2 }
        #expect(streams.opens["front_door"] == 2)
    }

    @Test func aViewAppearingDuringTheCheckDoesNotStartAheadOfIt() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        _ = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        pool.enterBackground()
        streams.holdsCheck = true
        pool.enterForeground()
        await waitUntil { streams.checks == 1 }

        _ = pool.appear(driveway, connection: connection)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(streams.opens["garage_camera"] == nil, "Held for the connection check with the rest")

        streams.release()
        await waitUntil { streams.opens["garage_camera"] == 1 && streams.opens["front_door"] == 2 }
        #expect(streams.opens["garage_camera"] == 1)
        #expect(streams.opens["front_door"] == 2)
    }

    @Test func leavingAgainBeforeTheCheckEndsCancelsTheRestart() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        _ = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        pool.enterBackground()
        streams.holdsCheck = true
        pool.enterForeground()
        await waitUntil { streams.checks == 1 }
        pool.enterBackground()
        streams.release()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(streams.opens["front_door"] == 1, "A stream is never started behind a backgrounded app")
    }

    @Test func retainedStreamsWithNoViewRestartOnReturnAndUnshownOnesStayOff() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        _ = pool.appear(front, connection: connection)
        pool.disappear(front) // Retained for the session.
        _ = pool.model(for: driveway) // Never shown.
        await waitUntil { streams.opens["front_door"] == 1 }
        pool.enterBackground()
        pool.enterForeground()
        await waitUntil { streams.opens["front_door"] == 2 }
        #expect(streams.opens["front_door"] == 2)
        #expect(streams.opens["garage_camera"] == nil)
    }

    // MARK: - Socket reconnects

    @Test func aHealthyStreamIsUntouchedWhenTheSocketReconnects() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)

        pool.connectionBecameReady()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(streams.opens["front_door"] == 1)
        #expect(model.state.phase == .live)
    }

    @Test func aStreamStillConnectingIsLeftToFinishWhenTheSocketBecomesReady() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        #expect(model.state.phase == .connecting)

        pool.connectionBecameReady() // The first connect at launch.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(streams.opens["front_door"] == 1)
    }

    @Test func aStreamThatGaveUpWhileTheSocketWasDownRestartsWhenItReturns() async {
        let streams = FakeStreams()
        streams.fails = true
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        await waitUntil { model.state.phase == .failed }
        #expect(model.state.phase == .failed)
        #expect(streams.opens["front_door"] == 2, "WebRTC, then HLS")

        streams.fails = false
        pool.connectionBecameReady()
        await waitUntil { streams.opens["front_door"] == 3 }
        #expect(streams.opens["front_door"] == 3)
        #expect(model.isRunning)
        #expect(model.state.phase == .connecting)
    }

    @Test func aFailedStreamNobodyIsShowingStaysOffWhenTheSocketReturns() async {
        let streams = FakeStreams()
        streams.fails = true
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        await waitUntil { model.state.phase == .failed }
        pool.disappear(front)
        streams.fails = false

        pool.connectionBecameReady()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(streams.opens["front_door"] == 2, "Failed streams drop their retention; no view wants it")
    }

    @Test func noRestartsWhileTheAppIsInTheBackground() async {
        let streams = FakeStreams()
        streams.fails = true
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        await waitUntil { model.state.phase == .failed }
        pool.enterBackground()
        pool.connectionBecameReady()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(streams.opens["front_door"] == 2)
    }

    // MARK: - Sharing across surfaces

    @Test func homeAndSecurityShareOneStreamPerCamera() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let home = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(home)

        let security = pool.appear(front, connection: connection) // Security's tile for the same camera
        #expect(security === home, "One model per camera, whichever page shows it")
        #expect(security.state.phase == .live, "Security's tile is live on its first read")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(streams.opens["front_door"] == 1, "No second stream was opened")
        #expect(pool.model(for: front) === home)
    }

    @Test func leavingOneSurfaceKeepsTheStreamForTheOther() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection) // Home
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)
        _ = pool.appear(front, connection: connection) // Security
        pool.disappear(front) // Home's tile leaves with the tab switch

        #expect(model.isRunning)
        #expect(model.state.phase == .live)
        #expect(pool.shouldRun(front))
        pool.disappear(front) // Security's too: still retained for the session
        #expect(model.isRunning)
        #expect(model.state.phase == .live)

        _ = pool.appear(front, connection: connection) // Back on Home
        try? await Task.sleep(for: .milliseconds(100))
        #expect(streams.opens["front_door"] == 1, "Returning to a page attaches to the running stream")
        #expect(model.state.phase == .live)
    }

    @Test func theViewerOpenedFromEitherPageSharesTheTilesStream() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let tile = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(tile)
        let viewer = pool.appear(front, connection: connection)
        #expect(viewer === tile)
        pool.disappear(front) // The viewer closes
        #expect(tile.isRunning)
        #expect(streams.opens["front_door"] == 1)
    }

    // MARK: - Live after returning

    @Test func theLiveStateReturnsAfterAForegroundRestart() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)
        pool.enterBackground()
        #expect(model.state.phase == .connecting)
        pool.enterForeground()
        await waitUntil { streams.opens["front_door"] == 2 }
        model.firstFrame(.webRTC)
        #expect(model.state.phase == .live, "The tile reads Live again once the restarted stream shows a frame")
    }

    // MARK: - Automatic retries

    @Test func aStreamThatFailedEveryModeIsRetriedWhileAViewWantsIt() async {
        let streams = FakeStreams()
        streams.fails = true
        let (pool, connection) = makePool(streams, retryDelays: [.milliseconds(30), .milliseconds(30)])
        let model = pool.appear(front, connection: connection)
        await waitUntil { model.state.phase == .failed }
        #expect(streams.opens["front_door"] == 2, "WebRTC, then HLS")

        streams.fails = false
        await waitUntil { streams.opens["front_door"] == 3 }
        #expect(streams.opens["front_door"] == 3, "Retried with no socket event and no new view")
        #expect(model.isRunning)
        model.firstFrame(.webRTC)
        #expect(model.state.phase == .live)
    }

    @Test func retriesStopAfterTheLastDelayAndAViewAppearingStartsOver() async {
        let streams = FakeStreams()
        streams.fails = true
        let (pool, connection) = makePool(streams, retryDelays: [.milliseconds(20)])
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 4 } // Two modes, then one retry of two modes.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(streams.opens["front_door"] == 4, "One retry, then it waits for a trigger")
        #expect(model.state.phase == .failed)

        streams.fails = false
        _ = pool.appear(front, connection: connection) // The next view that shows it tries again.
        await waitUntil { streams.opens["front_door"] == 5 }
        #expect(streams.opens["front_door"] == 5)
    }

    @Test func noRetryForAStreamNobodyShowsOrBehindABackgroundedApp() async {
        let streams = FakeStreams()
        streams.fails = true
        let (pool, connection) = makePool(streams, retryDelays: [.milliseconds(30)])
        let model = pool.appear(front, connection: connection)
        pool.disappear(front)
        await waitUntil { model.state.phase == .failed }
        try? await Task.sleep(for: .milliseconds(120))
        #expect(streams.opens["front_door"] == 2, "No view wants a failed stream, so it stays down")

        _ = pool.appear(driveway, connection: connection)
        await waitUntil { streams.opens["garage_camera"] == 2 }
        pool.enterBackground()
        try? await Task.sleep(for: .milliseconds(120))
        #expect(streams.opens["garage_camera"] == 2, "Retries are cancelled when the app leaves the foreground")
    }

    // MARK: - Frame stalls

    @Test func aLiveStreamWhoseFramesStopIsTakenDownAndRestartedOnce() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams, retryDelays: [.milliseconds(20)], stallAfter: .milliseconds(80))
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)
        streams.advancing = false // The camera stops sending.

        await waitUntil { model.state.phase != .live }
        #expect(model.state.phase == .connecting, "Back on the snapshot: the tile's dot goes")
        #expect(model.lastLiveAt != nil, "The viewer's pill can say when it was last live")
        #expect(!model.isRunning || streams.opens["front_door"] == 2)

        streams.advancing = true // The restarted stream delivers frames.
        await waitUntil { streams.opens["front_door"] == 2 }
        #expect(streams.opens["front_door"] == 2, "Restarted through the pool's retry")
        goLive(model)
        #expect(model.lastLiveAt == nil)
        try? await Task.sleep(for: .milliseconds(250))
        #expect(streams.opens["front_door"] == 2, "Restarted once, not once per check")
        #expect(model.state.phase == .live)
    }

    @Test func framesThatKeepComingNeverRestartAStream() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams, retryDelays: [.milliseconds(20)], stallAfter: .milliseconds(80))
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(streams.opens["front_door"] == 1)
        #expect(model.state.phase == .live)
    }

    @Test func aBriefPauseUnderTheLimitIsNotAStall() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams, retryDelays: [.milliseconds(20)], stallAfter: .milliseconds(200))
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)
        streams.advancing = false
        try? await Task.sleep(for: .milliseconds(80))
        streams.advancing = true
        try? await Task.sleep(for: .milliseconds(300))
        #expect(streams.opens["front_door"] == 1)
        #expect(model.state.phase == .live)
    }

    @Test func theWatchdogIsPausedInTheBackgroundAndAfterTheStreamStops() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams, retryDelays: [.milliseconds(20)], stallAfter: .milliseconds(60))
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)
        #expect(model.liveResources["Camera.watchdogs"] == 1)

        streams.advancing = false
        pool.enterBackground()
        #expect(model.liveResources["Camera.watchdogs"] == 0, "No watchdog behind a backgrounded app")
        try? await Task.sleep(for: .milliseconds(250))
        #expect(streams.opens["front_door"] == 1, "A frozen count in the background restarts nothing")
        #expect(model.state.phase == .connecting)
    }

    @Test func theCensusStaysFlatOverRepeatedStallsAndResumes() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams, retryDelays: [.milliseconds(10)], stallAfter: .milliseconds(60))
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        for cycle in 1...4 {
            goLive(model)
            #expect(model.liveResources["Camera.watchdogs"] == 1, "Cycle \(cycle)")
            streams.advancing = false
            await waitUntil { model.state.phase != .live }
            streams.advancing = true
            await waitUntil { streams.opens["front_door"] == cycle + 1 }
            #expect(streams.opens["front_door"] == cycle + 1)
            #expect(model.liveResources["Camera.watchdogs"] == 0, "Cycle \(cycle): none while connecting")
        }
        goLive(model)
        pool.enterBackground()
        pool.enterForeground()
        await waitUntil { streams.opens["front_door"] == 6 }
        goLive(model)
        #expect(model.liveResources["Camera.watchdogs"] == 1)
        #expect(pool.liveResources["CameraPool.running"] == 1)
    }

    // MARK: - Model

    @Test func suspendingPutsTheSnapshotBackAndStartingGoesLiveAgain() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        goLive(model)
        model.suspend()
        #expect(model.state.phase == .connecting)
        #expect(!model.isRunning)
        model.start(connection: connection)
        #expect(model.isRunning)
        model.firstFrame(.webRTC)
        #expect(model.state.phase == .live)
    }

    // MARK: - Resume cycles

    @Test func manyBackgroundAndForegroundCyclesLeaveTheFirstLaunchSet() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        _ = pool.appear(driveway, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 && streams.opens["garage_camera"] == 1 }
        goLive(model)
        let launch = pool.liveResources
        let launchModel = model.liveResources
        for cycle in 2...7 {
            pool.enterBackground()
            #expect(pool.liveResources["CameraPool.running"] == 0, "Nothing streams in the background")
            pool.enterForeground()
            await waitUntil { streams.opens["front_door"] == cycle && pool.liveResources["CameraPool.resumeTask"] == 0 }
            goLive(model)
        }
        #expect(pool.liveResources == launch, "A resume registers nothing the next background does not take away")
        #expect(model.liveResources == launchModel)
        #expect(streams.opens["front_door"] == 7, "One restart per resume")
    }

    @Test func aPoolHoldsItsAppObserversOnceAcrossResumes() {
        // macOS has no UIKit scene notifications; the ready notification is always observed.
        let pool = CameraStreamPool(modes: [.hls], observesApp: true)
        let held = pool.liveResources["CameraPool.observers"] ?? 0
        #expect(held >= 1)
        for _ in 0..<5 {
            pool.enterBackground()
            pool.enterForeground()
        }
        #expect(pool.liveResources["CameraPool.observers"] == held, "Resuming adds no observers")
    }

    @Test func restartingAModelDropsTheOldAttempt() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams)
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        for _ in 0..<5 { model.start(connection: connection) }
        #expect(model.liveResources["Camera.attempts"] == 1, "One attempt task, however many starts")
        model.stop()
        #expect(model.liveResources["Camera.attempts"] == 0)
        #expect(model.liveResources["Camera.players"] == 0)
    }

    // MARK: - Pausing with no view

    @Test func aStreamNoViewShowsIsPausedAndTheNextViewRestartsIt() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams, pauseAfterHidden: .milliseconds(40))
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)
        pool.disappear(front)
        #expect(model.isRunning, "Still running through the pause delay: Home to Security must not stop it")
        await waitUntil { !model.isRunning }

        #expect(!model.isRunning, "Paused: nothing decodes behind a page with no camera")
        #expect(!pool.shouldRun(front), "No longer retained or wanted")
        #expect(model.state.phase == .connecting, "The snapshot (and the last frame) covers the player")
        #expect(pool.liveResources["CameraPool.pauseTasks"] == 0)

        _ = pool.appear(front, connection: connection)
        #expect(model.isRunning, "A view showing it again restarts it at once")
        await waitUntil { streams.opens["front_door"] == 2 }
        #expect(streams.opens["front_door"] == 2)
    }

    @Test func aViewReturningInsideTheDelayKeepsTheStreamRunning() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams, pauseAfterHidden: .milliseconds(150))
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)
        pool.disappear(front) // Home's tile leaves with the tab switch
        #expect(pool.liveResources["CameraPool.pauseTasks"] == 1)
        _ = pool.appear(front, connection: connection) // Security's arrives
        #expect(pool.liveResources["CameraPool.pauseTasks"] == 0, "The pending pause is cancelled")
        try? await Task.sleep(for: .milliseconds(250))
        #expect(model.isRunning)
        #expect(model.state.phase == .live)
        #expect(streams.opens["front_door"] == 1, "The same stream throughout")
    }

    @Test func backgroundingCancelsPendingPauses() async {
        let streams = FakeStreams()
        let (pool, connection) = makePool(streams, pauseAfterHidden: .seconds(30))
        let model = pool.appear(front, connection: connection)
        await waitUntil { streams.opens["front_door"] == 1 }
        goLive(model)
        pool.disappear(front)
        #expect(pool.liveResources["CameraPool.pauseTasks"] == 1)
        pool.enterBackground()
        #expect(pool.liveResources["CameraPool.pauseTasks"] == 0)
    }
}
