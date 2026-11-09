import Foundation
@testable import FentonActivityModel
import Testing

struct ActivityCardTests {
    private let now = ActivityFixtures.now

    private func card(_ name: String, stale: Bool = false) throws -> ActivityCard {
        let fixture = try #require(HomeActivityFixtures.fixture(name, now: now))
        return ActivityCard(attributes: fixture.attributes, state: fixture.state, isStale: stale || fixture.isStale, now: now)
    }

    // MARK: Titles

    @Test func aCardWithNoValueShowsItsHeadlineAsTheBigLineUnderTheDeviceTitle() throws {
        let vacuum = try card("vacuum")
        #expect(vacuum.state.value == nil && vacuum.state.progress == nil, "the engine sends no time and no progress for a vacuum")
        #expect(vacuum.title == "Main Floor Vacuum" && vacuum.deviceTitle == "Main Floor Vacuum")
        #expect(vacuum.bigLine == "Vacuuming Kitchen" && vacuum.figure == .none)
        #expect(try card("vacuum-paused").bigLine == "Paused in Kitchen", "paused shows the word, not a dimmed time")
        #expect(try card("fan").bigLine == nil && (try card("fan")).title == "Guest Bath Fan")
        var empty = vacuum.state
        empty.headline = ""
        #expect(ActivityCard(attributes: vacuum.attributes, state: empty).bigLine == nil)
        empty.headline = nil
        #expect(ActivityCard(attributes: vacuum.attributes, state: empty).bigLine == nil && ActivityCard(attributes: vacuum.attributes, state: empty).title == "Main Floor Vacuum")
        // An older engine's card with both a time and a headline is still named by the headline.
        var legacy = vacuum.state
        legacy.value = .countup(start: now.addingTimeInterval(-60))
        let old = ActivityCard(attributes: vacuum.attributes, state: legacy, now: now)
        #expect(old.title == "Vacuuming Kitchen" && old.bigLine == nil)
        // A finished card shows Complete, never a headline.
        legacy.phase = .done
        #expect(ActivityCard(attributes: vacuum.attributes, state: legacy, now: now).bigLine == nil)
    }

    @Test func theHeaderLineAddsTheDetailAfterTheTitle() throws {
        #expect(try card("hotflash-bysam").detail == "Your side · by Sam")
        #expect(try card("hotflash-bysam").headerLine == "Hot Flash · Your side · by Sam")
        #expect(try card("hotflash-alex-bysam").headerLine == "Hot Flash · Alex's side · started by Samuel")
        #expect(try card("fan").detail == nil && (try card("fan")).headerLine == "Guest Bath Fan")
        #expect(try card("fan-xlong").headerLine == "Bedroom 1 Washroom Wardrobe Fans")
        var blank = try card("fan").state
        blank.detail = ""
        #expect(ActivityCard(attributes: try card("fan").attributes, state: blank).detail == nil)
    }

    // MARK: Figure

    @Test func countdownsCountToTheEndAndShowHoursOnlyFromAnHour() throws {
        guard case let .countdown(range, showsHours, estimated) = try card("fan").figure else { Issue.record("not a countdown"); return }
        #expect(range.upperBound == now.addingTimeInterval(282) && !showsHours && !estimated)
        guard case let .countdown(_, longHours, _) = try card("fan-long").figure else { Issue.record("not a countdown"); return }
        #expect(longHours, "1:04:42 shows hours")
        guard case let .countdown(_, dishwasherHours, _) = try card("dishwasher-long").figure else { Issue.record("not a countdown"); return }
        #expect(dishwasherHours, "the H:MM:SS dishwasher shows hours")
        guard case let .countdown(_, _, guess) = try card("dryer-estimated").figure else { Issue.record("not a countdown"); return }
        #expect(guess)
    }

    @Test func countUpsRunFromTheStartAndFreezeWhilePaused() throws {
        #expect(try card("dryer").figure == .countup(now.addingTimeInterval(-1_930)))
        let attributes = try card("dryer").attributes
        var paused = try card("dryer").state
        paused.phase = .paused
        paused.value = ActivityValue(kind: .countup, startTs: now.timeIntervalSince1970 - 1_000, pausedElapsedS: 760)
        #expect(ActivityCard(attributes: attributes, state: paused, now: now).figure == .frozen(seconds: 760))
        // Paused with no frozen time: the time so far stands in.
        paused.value?.pausedElapsedS = nil
        #expect(ActivityCard(attributes: attributes, state: paused, now: now).figure == .frozen(seconds: 1_000))
        // Paused with neither.
        paused.value = ActivityValue(kind: .countup)
        #expect(ActivityCard(attributes: attributes, state: paused, now: now).figure == .none)
        // Running with no start shows nothing.
        var running = try card("dryer").state
        running.value = ActivityValue(kind: .countup)
        #expect(ActivityCard(attributes: attributes, state: running, now: now).figure == .none)
    }

    @Test func percentsTextAndNothing() throws {
        #expect(try card("dishwasher-percent").figure == .percent(62))
        #expect(try card("hotflash-cooling").figure == .text("Cooling"))
        #expect(try card("dishwasher-waiting").figure == .text("Starts 5:10 PM"))
        let attributes = try card("fan").attributes
        func figure(_ state: HomeActivityState) -> ActivityCard.Figure { ActivityCard(attributes: attributes, state: state, now: now).figure }
        #expect(figure(HomeActivityState(value: .percent)) == .none, "percent needs progress")
        #expect(figure(HomeActivityState(value: .percent, progress: 3)) == .percent(100), "clamped")
        #expect(figure(HomeActivityState(value: .percent, progress: -1)) == .percent(0))
        #expect(figure(HomeActivityState(value: ActivityValue(kind: .text))) == .none)
        #expect(figure(HomeActivityState(value: .text(""))) == .none)
        #expect(figure(HomeActivityState(value: ActivityValue(kind: .countdown))) == .none, "a countdown needs an end")
        #expect(figure(HomeActivityState()) == .none)
    }

    @Test func aFinishedJobIsComplete() throws {
        for name in HomeActivityFixtures.completeNames {
            let complete = try card(name)
            #expect(complete.isComplete && complete.figure == .complete && complete.ring == .complete, Comment(rawValue: name))
            #expect(complete.buttons.isEmpty, "a finished card has no buttons")
            #expect(complete.spokenFigure == "complete")
        }
    }

    // MARK: Ring

    @Test func theRingFollowsTheKindOfFigure() throws {
        guard case .timer = try card("fan").ring else { Issue.record("a fan timer fills its ring with time"); return }
        #expect(try card("dryer").ring == .steady)
        #expect(try card("vacuum").ring == .track, "a vacuum has no time and no progress")
        #expect(try card("dishwasher-percent").ring == .fraction(0.62))
        #expect(try card("hotflash-cooling").ring == .fraction(0.45))
        #expect(try card("dishwasher-waiting").ring == .track)
        #expect(try card("vacuum-paused").ring == .track)
        #expect(try card("vacuum-paused").isPaused)
        #expect(try card("dryer-estimated").ring == .track, "an estimate has no start, so no ring range")
        var paused = try card("fan").state
        paused.phase = .paused
        #expect(ActivityCard(attributes: try card("fan").attributes, state: paused, now: now).ring == .track, "a paused countdown stops filling")
        var over = try card("fan").state
        over.progress = 7
        over.value = nil
        #expect(ActivityCard(attributes: try card("fan").attributes, state: over, now: now).ring == .fraction(1))
    }

    // MARK: Style

    @Test func aProblemPhaseMakesAProblemCard() throws {
        let stuck = try card("problem-navigation-stuck")
        #expect(stuck.style == .problem(.critical) && stuck.problem?.code == "navigation.stuck")
        #expect(try card("problem-mop-clean_water_empty").style == .problem(.warning))
        #expect(try card("fan").style == .job && (try card("fan")).problem == nil)
        // A problem phase with no problem is a job card (a malformed push never blanks the card).
        var broken = stuck.state
        broken.problem = nil
        #expect(ActivityCard(attributes: stuck.attributes, state: broken, now: now).style == .job)
    }

    // MARK: Buttons

    @Test func buttonsAreNamedForTheirDeviceAndTheFirstIsPrimary() throws {
        let fan = try card("fan")
        #expect(fan.buttons.map(\.accessibilityLabel) == ["Stop Guest Bath Fan"])
        #expect(fan.buttons.first?.isPrimary == true)
        let vacuum = try card("vacuum")
        #expect(vacuum.buttons.map(\.accessibilityLabel) == ["Pause Main Floor Vacuum", "Dock Main Floor Vacuum"])
        #expect(vacuum.buttons.map(\.control.title) == ["Pause", "Dock"])
        #expect(vacuum.buttons.map(\.isPrimary) == [true, false])
        #expect(vacuum.buttons.map(\.id) == ["pause", "dock"])
        var promoted = vacuum.state
        promoted.controls[1].role = .primary
        #expect(ActivityCard(attributes: vacuum.attributes, state: promoted, now: now).buttons.map(\.isPrimary) == [true, true])
    }

    @Test func aVacuumsPauseResumeAndDockAreRoundIconButtons() throws {
        #expect(try card("vacuum").buttons.map(\.icon) == [.pause, .dock])
        let paused = try card("vacuum-paused")
        #expect(paused.buttons.map(\.icon) == [.play, .dock], "Resume is a play glyph")
        #expect(paused.buttons.map(\.accessibilityLabel) == ["Resume Main Floor Vacuum", "Dock Main Floor Vacuum"])
        #expect(paused.buttons.map(\.isPrimary) == [true, false], "white circle, then dark")
        #expect(paused.islandButtons.map(\.icon) == [.play, .dock])
        // Other cards, and a vacuum's problem card, keep text pills.
        #expect(try card("fan").buttons.map(\.icon) == [nil])
        #expect(try card("dishwasher-paused").buttons.map(\.icon) == [nil, nil], "the dishwasher's Resume is a pill")
        #expect(try card("problem-navigation-stuck").buttons.map(\.icon) == [nil, nil, nil])
        var odd = try card("vacuum").state
        odd.controls = [ActivityControl(id: "spot", title: "Spot")]
        #expect(ActivityCard(attributes: try card("vacuum").attributes, state: odd, now: now).buttons.map(\.icon) == [nil], "an unknown control is a pill")
    }

    @Test func aJobCardKeepsTwoButtonsAndAProblemCardThreeWithDoneLast() throws {
        let stuck = try card("problem-navigation-stuck")
        #expect(stuck.buttons.map(\.id) == ["resume", "dock", "done"])
        #expect(stuck.islandButtons.map(\.id) == ["resume", "dock"], "the island shows two")
        var crowded = try card("fan").state
        crowded.controls = (0..<4).map { ActivityControl(id: "c\($0)", title: "C") }
        #expect(ActivityCard(attributes: try card("fan").attributes, state: crowded, now: now).buttons.count == 2)
        #expect(try card("washer").buttons.isEmpty)
    }

    // MARK: Pending

    @Test func aPendingPressReplacesTheButtonsWithItsLabel() throws {
        let pending = try card("fan-pending")
        #expect(pending.pendingLabel == "Stopping…" && pending.buttons.isEmpty && !pending.isUnconfirmed)
        let completing = try card("problem-completing")
        #expect(completing.pendingLabel == "Completing…" && completing.buttons.isEmpty)
    }

    @Test func aStalePendingPressGivesTheButtonsBackWithNotConfirmed() throws {
        let stale = try card("fan-pending-stale")
        #expect(stale.pendingLabel == nil && stale.isUnconfirmed)
        #expect(stale.buttons.map(\.id) == ["stop"], "the controls come back")
        #expect(ActivityCard.unconfirmedText == "Not confirmed")
        let plainStale = try card("fan", stale: true)
        #expect(!plainStale.isUnconfirmed && plainStale.buttons.count == 1, "stale without a press says nothing")
    }

    @Test func aNoticeIsKeptForOneUpdate() throws {
        let failed = try card("fan-notice")
        #expect(failed.notice == "Couldn't reach Home" && failed.buttons.map(\.id) == ["stop"] && failed.pendingLabel == nil)
        #expect(try card("fan").notice == nil)
        var blank = failed.state
        blank.notice = ""
        #expect(ActivityCard(attributes: failed.attributes, state: blank, now: now).notice == nil)
    }

    // MARK: Bar

    @Test func theBarAppearsOnlyWhenThereIsProgress() throws {
        guard case .timer = try card("fan").bar else { Issue.record("a countdown fills a bar with time"); return }
        guard case .timer = try card("hotflash-holding").bar else { Issue.record("so does the hot flash hold"); return }
        #expect(try card("dishwasher-percent").bar == .fraction(0.62))
        #expect(try card("hotflash-cooling").bar == .fraction(0.45))
        for name in HomeActivityFixtures.completeNames { #expect(try card(name).bar == .full, Comment(rawValue: name)) }
        for name in ["dryer", "washer", "vacuum", "vacuum-paused", "vacuum-long", "dishwasher-waiting", "dryer-estimated"] {
            #expect(try card(name).bar == nil, "\(name) has no progress")
        }
    }

    // MARK: Compact island

    @Test func theCompactTimeTakesARigidTemplateByRange() throws {
        #expect(ActivityCard.compactTemplate(hours: false) == "00:00" && ActivityCard.compactTemplate(hours: true) == "0:00:00")
        #expect(try card("fan").compactTrailing == .timer(template: "00:00"))
        #expect(try card("dishwasher").compactTrailing == .timer(template: "00:00"), "42 minutes left")
        #expect(try card("dishwasher-long").compactTrailing == .timer(template: "0:00:00"), "1:04:42 left")
        #expect(try card("fan-long").compactTrailing == .timer(template: "0:00:00"))
        // A count-up gets no push while it runs, so it takes the wide template from the start.
        #expect(try card("dryer").compactTrailing == .timer(template: "0:00:00"), "32 minutes, and an hour later with no push")
        var long = try card("dryer").state
        long.value = .countup(start: now.addingTimeInterval(-3_100))
        #expect(ActivityCard(attributes: try card("dryer").attributes, state: long, now: now).compactTrailing == .timer(template: "0:00:00"))
        // A frozen time.
        var frozen = long
        frozen.phase = .paused
        frozen.value = ActivityValue(kind: .countup, startTs: now.timeIntervalSince1970 - 5_000, pausedElapsedS: 4_000)
        #expect(ActivityCard(attributes: try card("dryer").attributes, state: frozen, now: now).compactTrailing == .timer(template: "0:00:00"))
        frozen.value?.pausedElapsedS = 600
        #expect(ActivityCard(attributes: try card("dryer").attributes, state: frozen, now: now).compactTrailing == .timer(template: "00:00"))
    }

    @Test func aCardWithNoTimeShowsItsShortWordInTheCompactIsland() throws {
        #expect(try card("vacuum").compactTrailing == .label("Kitchen"))
        #expect(try card("vacuum-paused").compactTrailing == .label("Paused"))
        #expect(try card("vacuum-drawn").compactTrailing == .label("Area"))
        #expect(ActivityCard.compactLabelWidth == 56)
        #expect(try card("vacuum").short == "Kitchen")
        // No `short` and no time: nothing, so the island holds the glyph alone.
        var bare = try card("vacuum").state
        bare.short = nil
        #expect(ActivityCard(attributes: try card("vacuum").attributes, state: bare, now: now).compactTrailing == .none)
        bare.short = ""
        #expect(ActivityCard(attributes: try card("vacuum").attributes, state: bare, now: now).short == nil)
        // A percentage and a word still read; `short` wins when the engine sends one.
        #expect(try card("dishwasher-percent").compactTrailing == .label("62%"))
        #expect(try card("hotflash-cooling").compactTrailing == .label("Cooling"))
        var worded = try card("hotflash-cooling").state
        worded.short = "Chill"
        #expect(ActivityCard(attributes: try card("hotflash-cooling").attributes, state: worded, now: now).compactTrailing == .label("Chill"))
        worded = try card("dishwasher-percent").state
        worded.short = "Rinse"
        #expect(ActivityCard(attributes: try card("dishwasher-percent").attributes, state: worded, now: now).compactTrailing == .label("Rinse"))
    }

    @Test func compactProblemsAndCompleteCards() throws {
        #expect(try card("problem-navigation-stuck").compactTrailing == .problem("Stuck"))
        #expect(try card("washer-complete").compactTrailing == .complete)
    }

    @Test func aRingNeedsATimeOrProgress() throws {
        for name in ["fan", "dishwasher-percent", "dryer"] { #expect(try card(name).showsRing, Comment(rawValue: name)) }
        for name in ["vacuum", "vacuum-paused"] { #expect(try !card(name).showsRing, "a vacuum draws its glyph alone") }
    }

    // MARK: Speech

    @Test func aProblemReadsAsOnePhrase() throws {
        #expect(try card("problem-navigation-stuck").spokenSummary
            == "Main Floor Vacuum, needs help: Stuck in Kitchen. Move it somewhere flat, then tap Resume.")
        #expect(try card("problem-mop-clean_water_empty").spokenSummary.hasPrefix("Main Floor Vacuum, needs attention: Clean water tank empty."))
        #expect(try card("problem-vendor-unknown_error_88").spokenSummary.hasSuffix(", Error 88"), "the chip is read too")
    }

    @Test func titlesCarryTheWordsThatMakeTheFigureASentence() throws {
        #expect(try card("dryer").spokenTitle == "Dryer, running for")
        #expect(try card("vacuum-paused").spokenTitle == "Main Floor Vacuum")
        #expect(try card("vacuum-paused").spokenSummary == "Main Floor Vacuum, Paused in Kitchen")
        #expect(try card("hotflash-bysam").spokenTitle == "Hot Flash · Your side · by Sam, time left")
        #expect(try card("dryer-estimated").spokenTitle == "Dryer, about")
        #expect(try card("fan").spokenTitle == "Guest Bath Fan, time left")
        #expect(try card("dishwasher-percent").spokenTitle == "Dishwasher")
    }

    @Test func figuresReadAsPhrases() throws {
        #expect(try card("fan").spokenFigure == "5 minutes left")
        #expect(try card("fan-long").spokenFigure == "1 hour 5 minutes left")
        #expect(try card("dryer-estimated").spokenFigure == "about 20 minutes left")
        #expect(try card("dryer").spokenFigure == "running for 32 minutes")
        #expect(try card("vacuum-paused").spokenFigure == nil, "a vacuum has no time to speak")
        var frozen = try card("dryer").state
        frozen.phase = .paused
        frozen.value = ActivityValue(kind: .countup, startTs: now.timeIntervalSince1970 - 1_000, pausedElapsedS: 760)
        let dryer = ActivityCard(attributes: try card("dryer").attributes, state: frozen, now: now)
        #expect(dryer.spokenFigure == "paused at 12 minutes" && dryer.spokenTitle == "Dryer, paused at")
        #expect(try card("dishwasher-percent").spokenFigure == "62 percent")
        #expect(try card("hotflash-cooling").spokenFigure == "Cooling")
        #expect(try card("hotflash-cooling").spokenSummary == "Hot Flash, Your side, Cooling")
        #expect(try card("washer-complete").spokenSummary == "Washing Machine, complete")
        #expect(ActivityCard(attributes: HomeActivityAttributes(), state: HomeActivityState(), now: now).spokenFigure == nil)
    }

    @Test func durationsAreSpokenInWholeUnits() {
        #expect(ActivityCard.spokenDuration(30) == "less than a minute")
        #expect(ActivityCard.spokenDuration(60) == "1 minute")
        #expect(ActivityCard.spokenDuration(125) == "2 minutes")
        #expect(ActivityCard.spokenDuration(3_600) == "1 hour")
        #expect(ActivityCard.spokenDuration(7_320) == "2 hours 2 minutes")
        #expect(ActivityCard.spokenDuration(61, roundingUp: true) == "2 minutes")
        #expect(ActivityCard.spokenRemaining(until: now, now: now) == "done")
        #expect(ActivityCard.spokenRemaining(until: now.addingTimeInterval(20), now: now) == "less than a minute left")
    }

    @Test func clocksFormatMinutesAndHours() {
        #expect(ActivityCard.clock(seconds: 760) == "12:40")
        #expect(ActivityCard.clock(seconds: 5) == "0:05")
        #expect(ActivityCard.clock(seconds: 3_882) == "1:04:42")
        #expect(ActivityCard.clock(seconds: -3) == "0:00")
    }
}
