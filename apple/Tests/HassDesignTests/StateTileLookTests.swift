@testable import HassDesign
import Testing

private typealias Look = StateTileLook

private func look(_ icon: String = "stop.fill", _ stateClass: Look.Class = .inProgress, active: Bool = true, _ indicator: Look.Indicator = .none,
                  text: String = "Opening", action: Bool = false) -> Look {
    Look(icon: icon, colour: .init(stateClass, active: active), indicator: indicator, text: text, hasAction: action)
}

// MARK: - Layers

struct StateTileLookTests {
    @Test func anArcIsDroppedForAStateThatHasAnAction() {
        #expect(look("x", .inProgress, .arc, action: true).indicator == .none)
        #expect(look("x", .inProgress, .arc, action: false).indicator == .arc)
        #expect(look("x", .warning, .pulse, action: true).indicator == .pulse, "an effect survives an action")
    }

    @Test func theArcHidesTheDiscAndStopsTaps() {
        let arc = look("x", .inProgress, .arc)
        #expect(arc.showsArc && arc.discOpacity == 0 && !arc.acceptsTaps)
        let stop = look("stop.fill", .inProgress, .none, action: true)
        #expect(!stop.showsArc && stop.discOpacity == 1 && stop.acceptsTaps, "a state that still takes a tap keeps its disc")
    }

    @Test func unknownKeepsADimmedDiscAndNoArc() {
        let unknown = look("lock.fill", .unknown, active: false, text: "Unavailable", action: true)
        #expect(!unknown.showsArc && unknown.discOpacity == 0.5 && !unknown.acceptsTaps)
    }
}

// MARK: - The per-layer diff

struct StateTileLayerDiffTests {
    @Test func openingToClosingWithNoActionChangesOnlyTheText() {
        let opening = look("blinds.horizontal.open", .inProgress, .arc, text: "Opening")
        let closing = look("blinds.horizontal.open", .inProgress, .arc, text: "Closing")
        #expect(opening.changes(to: closing) == .text)
        #expect(opening.slotChange(to: closing) == .none, "the same arc keeps its phase")
        #expect(opening.iconChange(to: closing) == .none)
    }

    @Test func anActionAppearingSwapsTheArcForTheDisc() {
        let arc = look("lock.fill", .inProgress, active: false, .arc, text: "Locking")
        let stop = look("stop.fill", .inProgress, active: false, .none, text: "Locking", action: true)
        #expect(arc.changes(to: stop).contains(.indicator))
        #expect(arc.slotChange(to: stop) == .arcOut)
        #expect(stop.slotChange(to: arc) == .arcIn, "and it swaps back when the action goes")
    }

    @Test func aHiddenDiscTakesItsNextGlyphWithNoEffect() {
        let arc = look("a", .inProgress, .arc)
        let disc = look("b", .resting, .none, action: true)
        #expect(arc.iconChange(to: disc) == .silent, "the disc fades in from behind the arc already showing its glyph")
        #expect(disc.iconChange(to: arc) == .silent, "the arc stands in before the glyph changes")
        let other = look("c", .resting, .none, action: true)
        #expect(disc.iconChange(to: other) == .replace, "a visible disc replaces its symbol")
    }

    @Test func anEqualLayerIsNotTouched() {
        let one = look("a", .resting, active: false, .none, text: "Closed", action: true)
        #expect(one.changes(to: one) == [])
        #expect(one.iconChange(to: one) == .none && one.slotChange(to: one) == .none)
        #expect(one.effectToStart(for: one) == nil && !one.stopsEffect(for: one))
    }

    @Test func colourChangesWithTheClassOrTheLitFace() {
        let rest = look("a", .resting, active: false, text: "Closed")
        #expect(rest.changes(to: look("a", .resting, active: true, text: "Closed")) == .colour)
        #expect(rest.changes(to: look("a", .warning, active: false, text: "Closed")) == .colour)
    }

    @Test func onceOnlyEffectsStartOnArrivalAndHeldEffectsStopWhenTheStateEnds() {
        let resting = look("a", .resting, .none)
        let error = look("a", .error, .wiggle)
        #expect(resting.effectToStart(for: error) == .wiggle)
        #expect(error.effectToStart(for: error) == nil, "never replayed")
        #expect(!error.stopsEffect(for: resting), "a once-only effect needs no stopping")
        let breathe = look("a", .resting, .breathe)
        #expect(breathe.stopsEffect(for: resting) && breathe.effectToStart(for: resting) == nil)
        #expect(resting.effectToStart(for: breathe) == .breathe)
    }

    @Test func aSymbolEffectNeverMeansTheArc() {
        #expect(!Look.Indicator.arc.isSymbolEffect && !Look.Indicator.none.isSymbolEffect)
        #expect([Look.Indicator.pulse, .breathe, .bounce, .wiggle].allSatisfy { $0.isSymbolEffect })
        #expect(Look.Indicator.bounce.playsOnce && Look.Indicator.wiggle.playsOnce && !Look.Indicator.pulse.playsOnce)
    }
}

// MARK: - Announcements and spoken value

struct StateTileAnnouncementTests {
    @Test func theThreeAnnouncementsAndNoOthers() {
        #expect(Look.announcement(from: .resting, to: .inProgress, ownRequest: true) == .requestStarted)
        #expect(Look.announcement(from: .inProgress, to: .resting, ownRequest: false) == .arrivedAtResting)
        #expect(Look.announcement(from: .error, to: .resting, ownRequest: false) == .arrivedAtResting)
        #expect(Look.announcement(from: .resting, to: .error, ownRequest: false) == .arrivedAtError)
        #expect(Look.announcement(from: .inProgress, to: .error, ownRequest: true) == .arrivedAtError)
    }

    @Test func nothingElseIsAnnounced() {
        #expect(Look.announcement(from: .resting, to: .inProgress, ownRequest: false) == .none, "only the person's own request")
        #expect(Look.announcement(from: .inProgress, to: .inProgress, ownRequest: true) == .none, "one in-progress to another is not spoken")
        #expect(Look.announcement(from: .resting, to: .warning, ownRequest: true) == .none)
        #expect(Look.announcement(from: .resting, to: .unknown, ownRequest: true) == .none)
        #expect(Look.announcement(from: .resting, to: .resting, ownRequest: true) == .none)
        #expect(Look.announcement(from: nil, to: .error, ownRequest: true) == .none, "a first render, reconnect or cold launch is silent")
    }

    @Test func theErrorHapticFollowsTheOwnRequestOnly() {
        #expect(Look.playsErrorHaptic(from: .inProgress, to: .error, ownRequest: true))
        #expect(!Look.playsErrorHaptic(from: .inProgress, to: .error, ownRequest: false))
        #expect(!Look.playsErrorHaptic(from: nil, to: .error, ownRequest: true))
        #expect(!Look.playsErrorHaptic(from: .error, to: .error, ownRequest: true))
    }

    @Test func theValueEndsWithTheClassUnlessTheWordsSayIt() {
        #expect(look(text: "Opening").spokenValue() == "Opening, in progress")
        #expect(look("a", .warning, text: "Open").spokenValue() == "Open, warning")
        #expect(look("a", .error, text: "Error").spokenValue() == "Error", "the words already say it")
        #expect(look("a", .error, text: "Jammed").spokenValue() == "Jammed, error")
        #expect(look("a", .resting, text: "Closed").spokenValue() == "Closed")
        #expect(look("a", .unknown, text: "Unavailable").spokenValue() == "Unavailable")
    }
}
