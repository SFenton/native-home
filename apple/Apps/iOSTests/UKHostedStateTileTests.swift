import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

private func look(_ stateClass: StateTileLook.Class, _ text: String, icon: String = "stop.fill", indicator: StateTileLook.Indicator = .none,
                  active: Bool = false, action: Bool = false) -> StateTileLook {
    StateTileLook(icon: icon, colour: .init(stateClass, active: active), indicator: indicator, text: text, hasAction: action)
}

/// ``UKStateTileTransition``: the flap guard, once-only effects, the three announcements, and no transition on a first render or a reapply
/// (`.agents/design/state-styled-tile.md`, Transitions and Flap guard).
@MainActor
final class UKHostedStateTileTransitionTests: XCTestCase {
    private var scheduler = HandScheduler()
    private var transition: UKStateTileTransition!
    private var plans: [UKStateTilePlan] = []
    private var spoken: [String] = []
    private var effects: [StateTileLook.Indicator] = []
    private var haptics = 0
    private var clock: TimeInterval = 100
    private var visible = true
    private var begun: [Bool] = []
    private var ended = 0
    private var settles: [(seconds: TimeInterval, work: @MainActor () -> Void)] = []

    override func setUp() async throws {
        try await super.setUp()
        UKMotion.reduceMotionOverride = false
        scheduler = HandScheduler()
        plans = []; spoken = []; effects = []; haptics = 0; clock = 100; visible = true
        begun = []; ended = 0; settles = []
        transition = UKStateTileTransition(scheduler: scheduler, title: { "Door" })
        transition.render = { [unowned self] in plans.append($0) }
        transition.announce = { [unowned self] in spoken.append($0) }
        transition.playEffect = { [unowned self] in effects.append($0) }
        transition.errorHaptic = { [unowned self] in haptics += 1 }
        transition.isPageVisible = { [unowned self] in visible }
        transition.now = { [unowned self] in clock }
        transition.beginSignpost = { [unowned self] reduced in
            begun.append(reduced)
            return { [unowned self] in ended += 1 }
        }
        transition.afterSettle = { [unowned self] seconds, work in settles.append((seconds, work)) }
    }

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        try await super.tearDown()
    }

    // MARK: Signpost

    func testAnAnimatedChangeOpensOneLayoutChangeIntervalAndEndsItWhenTheFadeSettles() {
        transition.apply(look(.resting, "Closed", action: true))
        XCTAssertTrue(begun.isEmpty, "a first render is instant: no interval")
        transition.apply(look(.resting, "Open", active: true, action: true))
        XCTAssertEqual(begun, [false])
        XCTAssertEqual(ended, 0, "open while the fade runs")
        XCTAssertEqual(settles.first?.seconds, MotionTokens.stateDuration)
        settles[0].work()
        XCTAssertEqual(ended, 1)
        settles[0].work()
        XCTAssertEqual(ended, 1, "a settle fires once; a second call ends nothing")
    }

    func testTheIntervalSpansTheLongerOfTheColourFadeAndTheDiscFade() {
        transition.apply(look(.resting, "Closed", action: true))
        transition.apply(look(.resting, "Closed", icon: "b", action: true))
        XCTAssertEqual(settles.last?.seconds ?? 0, 1.0 / 60, accuracy: 0.0001, "a glyph-only change settles in one frame")
        transition.apply(look(.inProgress, "Opening", indicator: .arc))
        XCTAssertGreaterThanOrEqual(settles.last?.seconds ?? 0, MotionTokens.quickDuration)
    }

    func testReduceMotionOpensTheReducedIntervalOnTheShorterFade() {
        UKMotion.reduceMotionOverride = true
        transition.apply(look(.resting, "Closed", action: true))
        transition.apply(look(.resting, "Open", active: true, action: true))
        XCTAssertEqual(begun, [true])
        XCTAssertEqual(settles.first?.seconds, MotionTokens.stateReducedDuration)
        settles[0].work()
        XCTAssertEqual(ended, 1)
    }

    func testAChangeMidFadeEndsTheOpenIntervalFirstAndAReapplyEndsIt() {
        transition.apply(look(.resting, "Closed", action: true))
        transition.apply(look(.resting, "Open", active: true, action: true))
        transition.apply(look(.warning, "Ajar", indicator: .pulse, active: true, action: true))
        XCTAssertEqual(begun.count, 2)
        XCTAssertEqual(ended, 1, "intervals never nest")
        settles[0].work()
        XCTAssertEqual(ended, 1, "the first interval's late settle does not end the second")
        transition.apply(look(.resting, "Closed", action: true), reapply: true)
        XCTAssertEqual(ended, 2, "a reapply is instant and closes what was open")
        XCTAssertEqual(begun.count, 2)
    }

    func testAnUnchangedLookOpensNoInterval() {
        transition.apply(look(.resting, "Closed", action: true))
        transition.apply(look(.resting, "Closed", action: true))
        XCTAssertTrue(begun.isEmpty)
    }

    func testAFirstRenderAndAReapplySetEveryLayerAtOnceWithNothingSaid() {
        transition.apply(look(.inProgress, "Opening", indicator: .arc))
        XCTAssertEqual(plans.count, 1)
        XCTAssertTrue(plans[0].isInstant)
        XCTAssertNil(plans[0].colourFade)
        XCTAssertEqual(plans[0].slot, .none)
        transition.noteOwnRequest()
        transition.apply(look(.error, "Error", indicator: .wiggle), reapply: true)
        XCTAssertTrue(plans[1].isInstant, "a reconnect or a cold launch sets the layers at once")
        XCTAssertTrue(spoken.isEmpty && effects.isEmpty && haptics == 0 && scheduler.pending.isEmpty, "no announcement, effect, haptic or guard")
        // A reapply into in-progress starts no flap guard either: the next state shows at once.
        transition.apply(look(.inProgress, "Opening", indicator: .arc), reapply: true)
        transition.apply(look(.resting, "Open", active: true, action: true))
        XCTAssertEqual(plans.count, 4)
        XCTAssertFalse(plans[3].isInstant)
    }

    func testTheInProgressLookIsHeldForASecondAndTheLatestStateWins() {
        transition.apply(look(.resting, "Closed", action: true))
        clock = 100
        transition.apply(look(.inProgress, "Sending Open…", indicator: .arc))
        XCTAssertEqual(plans.count, 2)
        clock = 100.3
        transition.apply(look(.resting, "Open", active: true, action: true))
        clock = 100.5
        transition.apply(look(.error, "Error", indicator: .wiggle, action: true))
        XCTAssertEqual(plans.count, 2, "states that arrive during the hold are coalesced, an error waits too")
        XCTAssertEqual(transition.shown?.text, "Sending Open…", "the whole look is held, words included")
        XCTAssertEqual(scheduler.pending.count, 1, "one release")
        let remaining = scheduler.pending[0].delay
        XCTAssertLessThan(abs(remaining / .seconds(1) - 0.7), 0.001, "the rest of MotionTokens.StateTile.minimumInProgress")
        scheduler.fire()
        XCTAssertEqual(plans.count, 3)
        XCTAssertEqual(plans[2].look.text, "Error", "the latest is applied when the hold ends")
    }

    func testALitFaceInProgressLookHoldsTheFlapGuardAndAnnouncesNothingOnAFaceOnlyChange() {
        transition.apply(look(.resting, "Docked"))
        transition.noteOwnRequest()
        transition.apply(look(.inProgress, "Returning", indicator: .arc))
        let spokenAtStart = spoken.count, rendered = plans.count
        clock = 100.2
        // A colour token lit on the in-progress state changes the face only: the class stays in-progress, so the guard still holds.
        transition.apply(look(.inProgress, "Returning", indicator: .arc, active: true))
        XCTAssertEqual(plans.count, rendered, "held by the flap guard like any in-progress look")
        XCTAssertEqual(scheduler.pending.count, 1)
        scheduler.fire()
        XCTAssertEqual(plans.last?.changes, .colour, "only the face changes")
        XCTAssertEqual(spoken.count, spokenAtStart, "a face-only change announces nothing")
        XCTAssertEqual(transition.shown?.stateClass, .inProgress)
    }

    func testAfterTheHoldTheNextStateShowsAtOnce() {
        transition.apply(look(.resting, "Closed", action: true))
        transition.apply(look(.inProgress, "Opening", indicator: .arc))
        clock = 101.2
        transition.apply(look(.resting, "Open", active: true, action: true))
        XCTAssertEqual(plans.count, 3)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testInProgressToInProgressKeepsTheArcAndOnlyTheTextChanges() {
        transition.apply(look(.inProgress, "Opening", indicator: .arc))
        clock = 102
        transition.apply(look(.inProgress, "Closing", indicator: .arc))
        XCTAssertEqual(plans.last?.changes, .text)
        XCTAssertEqual(plans.last?.slot, SlotNone.value, "the same arc keeps turning")
        XCTAssertTrue(spoken.isEmpty, "one in-progress state to another is not spoken")
    }

    func testTheWiggleStartsAfterTheDiscHasFadedIn() {
        transition.apply(look(.inProgress, "Opening", indicator: .arc))
        clock = 102
        transition.apply(look(.error, "Error", icon: "door.garage.closed", indicator: .wiggle, action: true))
        XCTAssertEqual(plans.last?.slot, .arcOut)
        XCTAssertEqual(plans.last?.effectDelay, MotionTokens.quickDuration)
        XCTAssertTrue(effects.isEmpty, "not while the disc is still fading in")
        XCTAssertEqual(scheduler.pending.first?.delay, .seconds(MotionTokens.quickDuration))
        scheduler.fire()
        XCTAssertEqual(effects, [.wiggle])
    }

    func testAWarningPulsesAtOnceAndAgainWhenItsPageBecomesVisible() {
        transition.apply(look(.resting, "Closed", action: true))
        transition.apply(look(.warning, "Open", indicator: .pulse, active: true, action: true))
        XCTAssertEqual(effects, [.pulse])
        XCTAssertTrue(spoken.isEmpty && haptics == 0, "no haptic and no announcement for a warning")
        transition.pageDidBecomeVisible()
        XCTAssertEqual(effects, [.pulse, .pulse])
        transition.apply(look(.resting, "Closed", action: true))
        transition.pageDidBecomeVisible()
        XCTAssertEqual(effects.count, 2, "a resting tile plays nothing when its page appears")
    }

    func testReduceMotionPlaysNoEffectAndSwapsTheIconWithNone() {
        UKMotion.reduceMotionOverride = true
        transition.apply(look(.resting, "Closed", icon: "a", action: true))
        transition.apply(look(.error, "Error", icon: "b", indicator: .wiggle, action: true))
        XCTAssertEqual(plans.last?.icon, .silent, "the icon swaps with no effect")
        XCTAssertEqual(plans.last?.colourFade, .stateReduced, "colour cross-fades on stateReduced")
        XCTAssertNil(plans.last?.effect)
        scheduler.fire()
        XCTAssertTrue(effects.isEmpty)
        transition.pageDidBecomeVisible()
        XCTAssertTrue(effects.isEmpty)
    }

    func testColourFadesOnStateAndTheIconReplacesOnAVisibleDisc() {
        transition.apply(look(.resting, "Closed", icon: "a", action: true))
        transition.apply(look(.resting, "Open", icon: "b", active: true, action: true))
        XCTAssertEqual(plans.last?.colourFade, .state)
        XCTAssertEqual(plans.last?.icon, .replace)
    }

    func testTheThreeAnnouncementsAndNoOthers() {
        transition.apply(look(.resting, "Closed", action: true))
        transition.noteOwnRequest()
        transition.apply(look(.inProgress, "Sending Open…", indicator: .arc))
        XCTAssertEqual(spoken, ["Door, Sending Open…"], "the start of the person's own request")
        clock = 102
        transition.apply(look(.resting, "Open", active: true, action: true))
        XCTAssertEqual(spoken.last, "Door, Open", "arrival at resting after in-progress")
        transition.apply(look(.error, "Error", indicator: .wiggle, action: true))
        XCTAssertEqual(spoken.last, "Door, Error", "arrival at error")
        transition.apply(look(.resting, "Closed", action: true))
        XCTAssertEqual(spoken.last, "Door, Closed", "arrival at resting after error")
        transition.apply(look(.unknown, "Unavailable"))
        transition.apply(look(.warning, "Open", indicator: .pulse, action: true))
        XCTAssertEqual(spoken.count, 4, "unknown and warning say nothing")
        XCTAssertEqual(haptics, 0, "the error was not the person's own request")
    }

    func testAnExternalChangeStartsNoAnnouncementAndAnOffscreenTileIsSilent() {
        transition.apply(look(.resting, "Closed", action: true))
        transition.apply(look(.inProgress, "Opening", indicator: .arc))
        XCTAssertTrue(spoken.isEmpty, "someone else's request is not announced at its start")
        visible = false
        clock = 102
        transition.apply(look(.resting, "Open", active: true, action: true))
        XCTAssertTrue(spoken.isEmpty, "a tile on a page that is not visible announces nothing")
    }

    func testTheErrorHapticFollowsTheOwnRequest() {
        transition.apply(look(.resting, "Closed", action: true))
        transition.noteOwnRequest()
        transition.apply(look(.inProgress, "Sending Open…", indicator: .arc))
        clock = 102
        transition.apply(look(.error, "Error", indicator: .wiggle, action: true))
        XCTAssertEqual(haptics, 1)
    }
}

private enum SlotNone { static let value = StateTileLook.SlotChange.none }

/// The tile drawn: the arc standing in for the disc, its size and accessibility, a state that keeps its disc, and a tile with no disc
/// (`.agents/design/state-styled-tile.md`, Disc and arc).
@MainActor
final class UKHostedStateTileViewTests: XCTestCase {
    private func disc(in tile: UKGlassTileView) -> UKTileActionDisc? {
        HostedPage.descendants(of: tile).compactMap { $0 as? UKTileActionDisc }.first
    }

    private func arcs(in view: UIView) -> [UKArcSpinnerView] { HostedPage.descendants(of: view).compactMap { $0 as? UKArcSpinnerView } }

    private func model(_ state: StateTileLook.Class, words: String, action: Bool, phase: TileActionItem.Phase? = nil, arc: Bool = false)
        -> UKGlassTileModel {
        let item = TileActionItem(id: "door", verb: action ? "Stop" : "Reverse", symbol: action ? "stop.fill" : "arrow.uturn.down", isOn: true,
                                  phase: phase ?? (action ? .ready : .inFlight), feedback: .tracked)
        var model = UKGlassTileModel(title: "Door", subtitle: words, symbol: "door.garage.open", family: .contact, isActive: true,
                                     isUnavailable: state == .unknown, behavior: .perform("door"), actions: [item], identifier: "tile")
        model.look = StateTileLook(icon: item.symbol, colour: .init(state, active: true), indicator: arc ? .arc : .none, text: words, hasAction: action)
        return model
    }

    private func show(_ tile: UKGlassTileView, size: CGSize = CGSize(width: 393, height: 400),
                      traits: ((UIViewController) -> Void)? = nil) -> UIWindow {
        let controller = UIViewController()
        traits?(controller)
        let window = HostedPage.show(controller, size: size)
        controller.view.addSubview(tile)
        tile.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tile.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            tile.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 20),
            tile.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -20),
        ])
        controller.view.layoutIfNeeded()
        return window
    }

    func testWhileTheArcStandsInTheDiscFillAndGlyphAreHiddenAndTheArcIs28Points() throws {
        let tile = UKGlassTileView(model: model(.inProgress, words: "Opening", action: false, arc: true))
        let window = show(tile)
        defer { window.isHidden = true }
        let disc = try XCTUnwrap(disc(in: tile))
        let glyph = try XCTUnwrap(disc.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertEqual(glyph.alpha, 0, "the glyph is at zero opacity")
        XCTAssertEqual(disc.backgroundColor?.cgColor.alpha ?? 1, 0, accuracy: 0.001, "and so is the fill")
        let arc = try XCTUnwrap(arcs(in: disc).first)
        XCTAssertEqual(arc.alpha, 1)
        XCTAssertFalse(arc.isHidden)
        XCTAssertEqual(arc.intrinsicContentSize.width, 28, accuracy: 0.5)
        XCTAssertEqual(arc.intrinsicContentSize.width / disc.bounds.width, 7.0 / 11.0, accuracy: 0.01, "7/11 of the disc")
        XCTAssertFalse(arc.isAccessibilityElement, "the arc is not an accessibility element")
    }

    func testAtAX5TheDiscIs66PointsAndTheArc42() throws {
        let tile = UKGlassTileView(model: model(.inProgress, words: "Opening", action: false, arc: true))
        let window = show(tile, size: CGSize(width: 600, height: 600)) { $0.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge }
        defer { window.isHidden = true }
        let disc = try XCTUnwrap(disc(in: tile))
        XCTAssertEqual(disc.bounds.width, 66, accuracy: 0.5)
        let arc = try XCTUnwrap(arcs(in: disc).first)
        XCTAssertEqual(arc.intrinsicContentSize.width, 42, accuracy: 0.5)
    }

    func testTheArcStandingInReadsAsDisabledWithNoHintAndAnInProgressValue() throws {
        let tile = UKGlassTileView(model: model(.inProgress, words: "Opening", action: false, arc: true))
        let window = show(tile)
        defer { window.isHidden = true }
        let disc = try XCTUnwrap(disc(in: tile))
        XCTAssertTrue(disc.accessibilityTraits.contains(.button))
        XCTAssertTrue(disc.accessibilityTraits.contains(.notEnabled))
        XCTAssertNil(disc.accessibilityHint)
        XCTAssertFalse(disc.accessibilityRespondsToUserInteraction)
        XCTAssertTrue(disc.accessibilityValue?.hasSuffix("in progress") == true, disc.accessibilityValue ?? "nil")
        let body = try XCTUnwrap(tile.accessibilityElements?.first as? UIAccessibilityElement, "the tile's body element")
        XCTAssertTrue(body.accessibilityTraits.contains(.button), "the body keeps the button trait while the arc shows")
        XCTAssertTrue(body.accessibilityTraits.contains(.notEnabled), "and gains not-enabled")
        XCTAssertFalse(tile.accessibilityRespondsToUserInteraction, "the tile body ignores taps too")
        XCTAssertTrue(tile.accessibilityValue?.hasSuffix("in progress") == true, tile.accessibilityValue ?? "nil")
        disc.isHighlighted = true
        XCTAssertTrue(disc.subviews.allSatisfy { $0.isHidden || $0.backgroundColor == nil || $0.alpha == 0 || $0 !== disc.subviews.last }, "no press state")
        disc.isHighlighted = false
    }

    /// The tile carries a spoken subtitle, so it is a container whose first element is the body: the body keeps `.button` throughout and
    /// carries `.notEnabled` only while the arc stands in for the disc (the container itself carries only `.notEnabled`).
    func testTheBodyKeepsTheButtonTraitAndGainsNotEnabledOnlyWhileTheArcShows() throws {
        let busy = UKGlassTileView(model: model(.inProgress, words: "Opening", action: false, arc: true))
        let busyWindow = show(busy)
        defer { busyWindow.isHidden = true }
        let busyBody = try XCTUnwrap(busy.accessibilityElements?.first as? UIAccessibilityElement)
        XCTAssertTrue(busyBody.accessibilityTraits.contains(.button))
        XCTAssertTrue(busyBody.accessibilityTraits.contains(.notEnabled))
        XCTAssertTrue(busy.accessibilityTraits.contains(.notEnabled))

        let resting = UKGlassTileView(model: model(.resting, words: "Closed", action: true))
        let restingWindow = show(resting)
        defer { restingWindow.isHidden = true }
        let restingBody = try XCTUnwrap(resting.accessibilityElements?.first as? UIAccessibilityElement)
        XCTAssertTrue(restingBody.accessibilityTraits.contains(.button), "the button trait stays once the disc returns")
        XCTAssertFalse(restingBody.accessibilityTraits.contains(.notEnabled))
        XCTAssertFalse(resting.accessibilityTraits.contains(.notEnabled))
    }

    func testAStateThatStillTakesATapKeepsItsDiscAndHasNoArc() throws {
        let tile = UKGlassTileView(model: model(.inProgress, words: "Opening", action: true))
        let window = show(tile)
        defer { window.isHidden = true }
        let disc = try XCTUnwrap(disc(in: tile))
        let glyph = try XCTUnwrap(disc.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertEqual(glyph.alpha, 1)
        XCTAssertTrue(arcs(in: disc).allSatisfy { $0.isHidden || $0.alpha == 0 })
        XCTAssertTrue(disc.isEnabled)
        XCTAssertTrue(disc.accessibilityRespondsToUserInteraction)
        XCTAssertFalse(disc.accessibilityTraits.contains(.notEnabled))
    }

    func testUnknownKeepsADimmedDiscAndNoArc() throws {
        var unknown = model(.unknown, words: "Unavailable", action: true, phase: .unavailable)
        unknown.isUnavailable = true
        let tile = UKGlassTileView(model: unknown)
        let window = show(tile)
        defer { window.isHidden = true }
        let disc = try XCTUnwrap(disc(in: tile))
        let glyph = try XCTUnwrap(disc.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertEqual(glyph.alpha, 0.5, accuracy: 0.001, "a dimmed disc")
        XCTAssertTrue(arcs(in: disc).allSatisfy { $0.isHidden || $0.alpha == 0 }, "never an arc")
        XCTAssertFalse(disc.accessibilityRespondsToUserInteraction)
        XCTAssertNil(disc.accessibilityHint)
        XCTAssertFalse(disc.isEnabled)
    }

    func testInProgressToInProgressKeepsTheSameArcElement() throws {
        let tile = UKGlassTileView(model: model(.inProgress, words: "Opening", action: false, arc: true))
        let window = show(tile)
        defer { window.isHidden = true }
        let disc = try XCTUnwrap(disc(in: tile))
        let before = try XCTUnwrap(arcs(in: disc).first)
        tile.configure(model(.inProgress, words: "Closing", action: false, arc: true), animated: true)
        // The one-second hold keeps the whole look, so the words follow when it ends; the arc is never remade.
        XCTAssertTrue(HostedPage.until(3) { tile.model.subtitle == "Closing" })
        XCTAssertTrue(arcs(in: disc).first === before, "the same arc, not restarted")
        XCTAssertEqual(arcs(in: disc).count, 1)
    }

    func testAnActionAppearingSwapsTheArcForTheDisc() throws {
        let tile = UKGlassTileView(model: model(.inProgress, words: "Opening", action: false, arc: true))
        let window = show(tile)
        defer { window.isHidden = true }
        let disc = try XCTUnwrap(disc(in: tile))
        let glyph = try XCTUnwrap(disc.subviews.compactMap { $0 as? UIImageView }.first)
        tile.configure(model(.inProgress, words: "Opening", action: true), animated: true)
        XCTAssertTrue(HostedPage.until(3) { glyph.alpha == 1 })
        XCTAssertTrue(arcs(in: disc).allSatisfy { $0.alpha == 0 })
    }

    func testATileWithNoDiscSwapsItsGlyphForTheCompactArc() throws {
        var robot = UKGlassTileModel(title: "Robot", subtitle: "Returning", symbol: "fan", family: .cleaning, isActive: false, kind: .navigate, identifier: "robot")
        robot.look = StateTileLook(icon: "fan", colour: .init(.inProgress, active: false), indicator: .arc, text: "Returning", hasAction: false)
        let tile = UKGlassTileView(model: robot)
        let window = show(tile)
        defer { window.isHidden = true }
        let arc = try XCTUnwrap(arcs(in: tile.face).first)
        XCTAssertFalse(arc.isHidden)
        XCTAssertEqual(arc.alpha, 1)
        XCTAssertEqual(arc.intrinsicContentSize.width, 20, accuracy: 1, "the compact arc, scaled with the glyph")
        let glyph = try XCTUnwrap(HostedPage.descendants(of: tile.face).compactMap { $0 as? UIImageView }.first { $0.image != nil })
        XCTAssertEqual(glyph.alpha, 0)
        XCTAssertTrue(tile.accessibilityValue?.hasSuffix("in progress") == true)
        // A navigation tile's body keeps its traits.
        XCTAssertTrue(tile.accessibilityTraits.contains(.button) || tile.accessibilityElements != nil)
    }

    func testAWarningDrawsTheDenseFaceInTheWarningInk() {
        XCTAssertEqual(TileFaceStyle.resolve(family: .contact, isActive: true, isError: false, isWarning: true, isUnavailable: false), .warning)
        XCTAssertEqual(TileFaceStyle.resolve(family: .contact, isActive: true, isError: true, isWarning: true, isUnavailable: false), .error, "a fault wins")
        XCTAssertEqual(TileFaceStyle.resolve(family: .contact, isActive: true, isError: false, isWarning: true, isUnavailable: true), .off)
    }
}
