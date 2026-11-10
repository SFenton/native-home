@testable import HassDesign
import Testing

/// A scripted clock and sleeper for ``ContentGateModel``: every sleep is logged and advances the clock, unless the script cancels it.
@MainActor
private final class GateScript {
    let base = ContinuousClock.now
    var offset: Duration = .zero
    var sleeps: [Duration] = []
    /// Sleeps (by index) that come back cancelled, as when a newer `advance` supersedes the one waiting.
    var cancelled: Set<Int> = []
    /// Sees the model at each sleep, to check what is on screen while the gate waits.
    var onSleep: (@MainActor (Duration) -> Void)?

    var now: ContinuousClock.Instant { base + offset }

    func sleep(_ duration: Duration) async -> Bool {
        let index = sleeps.count
        sleeps.append(duration)
        onSleep?(duration)
        if cancelled.contains(index) { return false }
        offset += duration
        return true
    }

    func model(isReady: Bool, profile: ContentGateModel.Profile = .sheet) -> ContentGateModel {
        ContentGateModel(page: "Test", isReady: isReady, firstLoad: profile, sleep: { [self] in await sleep($0) }, now: { [self] in now })
    }
}

@MainActor
struct ContentGateTests {
    // MARK: Profiles

    @Test func sheetProfileHoldsTheDesignedValues() {
        let sheet = ContentGateModel.Profile.sheet
        #expect(ContentGateModel.Timing.sheetFade.seconds == MotionTokens.quickDuration)
        #expect(ContentGateModel.Timing.sheetFade == .milliseconds(200))
        #expect(sheet.spinnerDelay == .milliseconds(150))
        #expect(sheet.spinnerEnter == .milliseconds(200))
        #expect(sheet.spinnerExit == ContentGateModel.Timing.sheetFade)
        #expect(sheet.contentEnter == ContentGateModel.Timing.sheetFade)
        #expect(sheet.childTimeout == ContentGateModel.Timing.childTimeout)
        #expect(sheet.minimumLoading == .zero)
        #expect(sheet.loadTimeout == .seconds(10))
        #expect(sheet.contentRise == 0)
        #expect(sheet.waitsForPresentation)
        #expect(sheet.spinnerMinimumShown == .milliseconds(500))
        #expect(sheet.revealsOnce)
    }

    @Test func pageAndResultsKeepTheirWebValues() {
        let page = ContentGateModel.Profile.page
        #expect(page.spinnerDelay == .zero)
        #expect(page.spinnerExit == .milliseconds(500))
        #expect(page.contentEnter == .milliseconds(170))
        #expect(page.minimumLoading == .milliseconds(1000))
        #expect(page.loadTimeout == ContentGateModel.Timing.loadTimeout)
        #expect(ContentGateModel.Timing.loadTimeout == .milliseconds(10_000))
        let results = ContentGateModel.Profile.results
        #expect(results.spinnerExit == .milliseconds(140))
        #expect(results.contentEnter == .milliseconds(170))
        #expect(results.loadTimeout == nil)
        for profile in [page, results] {
            #expect(profile.contentRise == 4)
            #expect(!profile.waitsForPresentation)
            #expect(profile.spinnerMinimumShown == .zero)
            #expect(!profile.revealsOnce)
        }
    }

    // MARK: Before the presentation

    @Test func contentIsHiddenUntilPresentedAndNothingSleeps() async {
        let script = GateScript()
        let model = script.model(isReady: true)
        #expect(model.phase == .loading, "ready content still waits for the slide")
        #expect(!model.isPresented)
        await model.advance(isReady: true)
        #expect(model.phase == .loading)
        #expect(script.sleeps.isEmpty)
    }

    @Test func noArcBeforePresentationEvenAfterTheDelay() async {
        let script = GateScript()
        let model = script.model(isReady: false)
        script.offset = .seconds(2)
        await model.advance(isReady: false)
        #expect(!model.spinnerShown)
        #expect(script.sleeps.isEmpty, "no arc timer and no load timeout run before the presentation")
    }

    @Test func presentationCompletedIsIdempotentAndStartsTheClock() async {
        let script = GateScript()
        let model = script.model(isReady: false)
        script.offset = .seconds(3)
        model.presentationCompleted()
        script.offset = .seconds(4)
        model.presentationCompleted()
        #expect(model.isPresented)
        await model.advance(isReady: false)
        // The timeout counts from the first completion at +3 s: 10 s - (the 150 ms grace) is left once the arc is up.
        #expect(script.sleeps.first == .milliseconds(150))
        #expect(script.sleeps.count > 1)
        #expect(script.sleeps[1] == .milliseconds(10_000) - .seconds(1) - .milliseconds(150))
    }

    // MARK: Ready content

    @Test func readyAtPresentationFadesInOnceWithNoArc() async {
        let script = GateScript()
        let model = script.model(isReady: true)
        model.presentationCompleted()
        await model.advance(isReady: true)
        #expect(script.sleeps == [.milliseconds(200)], "one 200 ms content enter")
        #expect(model.phase == .idle)
        #expect(!model.spinnerShown)
    }

    @Test func readyWithinTheGraceShowsNoArc() async {
        let script = GateScript()
        script.cancelled = [0]
        let model = script.model(isReady: false)
        model.presentationCompleted()
        await model.advance(isReady: false)
        #expect(!model.spinnerShown, "the grace was cut short by the data arriving")
        await model.advance(isReady: true)
        #expect(script.sleeps == [.milliseconds(150), .milliseconds(200)])
        #expect(model.phase == .idle)
        #expect(!model.spinnerShown)
    }

    // MARK: The arc

    @Test func arcPathRunsGraceInHoldOutThenContent() async {
        let script = GateScript()
        let model = script.model(isReady: false)
        model.presentationCompleted()
        script.cancelled = [1]
        await model.advance(isReady: false)
        #expect(model.spinnerShown, "the arc starts after the 150 ms grace")
        var seen: [(Duration, ContentGateModel.Phase, Bool)] = []
        script.onSleep = { seen.append(($0, model.phase, model.spinnerShown)) }
        await model.advance(isReady: true)
        #expect(Array(script.sleeps.dropFirst(2)) == [.milliseconds(500), .milliseconds(200), .milliseconds(200)])
        #expect(seen.map(\.0) == [.milliseconds(500), .milliseconds(200), .milliseconds(200)])
        #expect(seen[0].1 == .loading && seen[0].2, "held at full arc for the minimum")
        #expect(seen[1].1 == .spinnerExiting, "then the arc fades out")
        #expect(seen[2].1 == .entering && !seen[2].2, "then the content fades in")
        #expect(model.phase == .idle)
    }

    @Test func dataArrivingDuringTheArcFadeInStillHoldsThenExits() async {
        let script = GateScript()
        let model = script.model(isReady: false)
        model.presentationCompleted()
        script.cancelled = [1]
        await model.advance(isReady: false)
        script.offset += .milliseconds(100)
        await model.advance(isReady: true)
        // 100 ms into the 500 ms hold: 400 ms remain, never cut short and never popped.
        #expect(script.sleeps.dropFirst(2).first == .milliseconds(400))
        #expect(model.phase == .idle)
    }

    @Test func anArcThatHeldLongEnoughExitsAtOnce() async {
        let script = GateScript()
        let model = script.model(isReady: false)
        model.presentationCompleted()
        script.cancelled = [1]
        await model.advance(isReady: false)
        script.offset += .seconds(2)
        await model.advance(isReady: true)
        #expect(Array(script.sleeps.dropFirst(2)) == [.milliseconds(200), .milliseconds(200)])
    }

    @Test func dataThatNeverArrivesShowsTheContentAfterTenSecondsFromPresentation() async {
        let script = GateScript()
        let model = script.model(isReady: false)
        script.offset = .seconds(5)
        model.presentationCompleted()
        await model.advance(isReady: false)
        #expect(script.sleeps.prefix(2) == [.milliseconds(150), .milliseconds(9850)])
        #expect(script.sleeps.prefix(2).reduce(.zero, +) == .seconds(10))
        #expect(model.phase == .idle, "the content shows anyway, to draw its own empty or failed state")
    }

    // MARK: Once

    @Test func aRevealIgnoresLaterNotReadyOnceIdle() async {
        let script = GateScript()
        let model = script.model(isReady: true)
        model.presentationCompleted()
        await model.advance(isReady: true)
        let before = script.sleeps.count
        await model.advance(isReady: false)
        #expect(model.phase == .idle)
        #expect(script.sleeps.count == before)
    }

    @Test func aResultsGateStillReloadsInPlace() async {
        let script = GateScript()
        let model = script.model(isReady: true, profile: .results)
        #expect(model.phase == .idle)
        script.cancelled = [1]
        await model.advance(isReady: false)
        #expect(model.phase == .loading, "a results region leaves idle when its data is reloading")
    }

    @Test func aPageGateStillStartsOpenWhenReady() {
        let script = GateScript()
        let model = script.model(isReady: true, profile: .page)
        #expect(model.phase == .idle)
        #expect(model.isPresented)
    }
}
