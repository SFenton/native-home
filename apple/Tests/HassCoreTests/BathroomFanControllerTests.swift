import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The bathroom fan's command matrix and optimistic rules (web `bathroomFanState.test.ts`,
/// `BathroomFanModalContent.test.tsx`).
@MainActor
@Suite(.demoHouse)
struct BathroomFanControllerTests {
    let fan = BathroomFanConfig.all[0]

    func controller(power: String = "on", locked: Bool = false, pending: Bool = false, autoUnlock: Bool = false,
                    deadline: [String: JSONValue] = [:], deadlineState: String = "2026-10-11 12:00:00",
                    timer: [String: JSONValue] = [:], lockState: String? = nil)
        -> (BathroomFanController, EntityStore, RecordingCaller, ManualScheduler)
    {
        let store = makeStore([
            fan.powerEntityId: power,
            fan.lockEntityId: lockState ?? (locked ? "on" : "off"),
            fan.pendingEntityId: pending ? "on" : "off",
            fan.autoUnlockEntityId: autoUnlock ? "on" : "off",
            fan.deadlineEntityId: deadlineState,
            fan.timerEntityId: pending ? "active" : "idle",
        ], attributes: [fan.deadlineEntityId: deadline, fan.timerEntityId: timer])
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        return (BathroomFanController(config: fan, store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    func script(_ data: [String: String]) -> RecordingCaller.Call {
        .init(domain: "script", service: fan.scriptService, data: data)
    }

    // MARK: Contract

    @Test func keepsTheExactEntityContract() {
        #expect(BathroomFanConfig.all[1].powerEntityId == "switch.demo_bathroom_1_fan_1")
        #expect(BathroomFanConfig.all[1].scriptService == "demo_bathroom_1_fan_command")
        #expect(BathroomFanConfig.all[0].deadlineEntityId == "input_datetime.demo_fan_1")
        #expect(BathroomFanConfig.forPowerEntity("switch.demo_fan_1") == BathroomFanConfig.all[0])
        #expect(BathroomFanConfig.forPowerEntity("switch.demo_other") == nil)
    }

    @Test func timerMinutesSnapToTheOfferedLengths() {
        #expect(BathroomFanController.normalizedMinutes(5) == 5)
        #expect(BathroomFanController.normalizedMinutes(7) == 5)
        #expect(BathroomFanController.normalizedMinutes(44) == 30)
        #expect(BathroomFanController.normalizedMinutes(46) == 60)
        #expect(BathroomFanController.normalizedMinutes(500) == 60)
        #expect(BathroomFanController.durationTitle(60) == "1 hour")
        #expect(BathroomFanController.durationTitle(15) == "15 minutes")
    }

    // MARK: Commands

    @Test func powerOffAlsoShowsTimerLockAndAutoUnlockCleared() async {
        let (fanController, _, caller, _) = controller(power: "on", locked: true, pending: true, autoUnlock: true)
        fanController.setPower(false)
        #expect(!fanController.powerOn && !fanController.timerPending && !fanController.locked && !fanController.autoUnlock)
        await fanController.commands.waitForCalls()
        #expect(caller.calls == [script(["command": "power", "target_power": "off"])])
    }

    @Test func unchangedOrUnavailableCommandsAreSkipped() async {
        let (onFan, _, caller, _) = controller(power: "on")
        onFan.setPower(true)
        onFan.setLocked(false)
        onFan.cancelTimer()
        await onFan.commands.waitForCalls()
        #expect(caller.calls.isEmpty)

        let (missing, _, missingCaller, _) = controller(power: "unavailable")
        #expect(!missing.powerAvailable)
        #expect(missing.powerStateText == "Unavailable")
        missing.setPower(true)
        missing.startTimer()
        await missing.commands.waitForCalls()
        #expect(missingCaller.calls.isEmpty)
    }

    @Test func lockingDuringATimerTurnsAutoUnlockOn() async {
        let (fanController, _, caller, _) = controller(pending: true)
        fanController.setLocked(true)
        #expect(fanController.locked && fanController.autoUnlock)
        #expect(fanController.lockStateText == "Locked")
        await fanController.commands.waitForCalls()
        #expect(caller.calls == [script(["command": "lock", "locked": "true"])])
    }

    @Test func startTimerAlwaysAutoUnlocksAndKeepsTheFanOn() async {
        // The owner removed the "Auto-disable lock" choice (2026-10-17): every timer releases the lock when it ends.
        let (unlocked, _, caller, _) = controller()
        unlocked.selectedMinutes = 20
        #expect(unlocked.canStartTimer)
        unlocked.startTimer()
        #expect(unlocked.timerPending)
        await unlocked.commands.waitForCalls()
        #expect(caller.calls == [script(["auto_unlock": "true", "command": "timer_start", "minutes": "20"])])

        let (locked, _, lockedCaller, _) = controller(locked: true)
        locked.startTimer()
        #expect(locked.autoUnlock, "A locked fan shows auto-unlock on at once")
        await locked.commands.waitForCalls()
        #expect(lockedCaller.calls == [script(["auto_unlock": "true", "command": "timer_start", "minutes": "30"])])
    }

    @Test func startingATimerOnAnOffFanTurnsItOn() async {
        // The script's timer_start ends with switch.turn_on (verified in scripts.yaml), so the button works while off.
        let (off, _, caller, _) = controller(power: "off")
        #expect(off.canStartTimer)
        off.startTimer()
        #expect(off.powerOn && off.timerPending, "Both show at once")
        await off.commands.waitForCalls()
        #expect(caller.calls == [script(["auto_unlock": "true", "command": "timer_start", "minutes": "30"])])

        let (gone, _, goneCaller, _) = controller(power: "unavailable")
        #expect(!gone.canStartTimer)
        gone.startTimer()
        await gone.commands.waitForCalls()
        #expect(goneCaller.calls.isEmpty)
    }

    @Test func cancelGoesToTheServerWhilePending() async {
        let (fanController, _, caller, _) = controller(locked: true, pending: true, autoUnlock: true)
        fanController.cancelTimer()
        #expect(!fanController.timerPending && !fanController.autoUnlock)
        await fanController.commands.waitForCalls()
        #expect(caller.calls == [script(["command": "timer_cancel"])])
    }

    // MARK: Optimistic values

    @Test func optimisticValuesClearOnLiveChangeOrAfterTwoSeconds() async {
        let (fanController, store, _, scheduler) = controller(power: "off")
        fanController.setPower(true)
        #expect(fanController.powerOn)
        scheduler.fireAll()
        #expect(!fanController.powerOn, "Reverts when Home Assistant never confirms")

        fanController.setPower(true)
        set(store, fan.powerEntityId, "on")
        for _ in 0..<20 where !fanController.commands.overlay.pending.isEmpty { await Task.yield() }
        #expect(fanController.powerOn)
        #expect(fanController.commands.overlay.pending.isEmpty)
    }

    @Test func aFailedCallDropsItsOptimisticValues() async {
        let (fanController, _, caller, _) = controller(power: "off")
        caller.failNext = true
        fanController.setPower(true)
        await fanController.commands.waitForCalls()
        #expect(!fanController.powerOn)
        #expect(fanController.commandFailed)
        #expect(fanController.tileStatusText(at: Date(timeIntervalSince1970: 0)) == "Didn't Respond")
    }

    // MARK: Timer

    @Test func remainingTimeComesFromTheTimestampAttribute() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let (fanController, _, _, _) = controller(pending: true, deadline: ["timestamp": .number(1_000_000 + 754.2)])
        #expect(fanController.remainingSeconds(at: now) == 755)
        #expect(fanController.remainingSeconds(at: now.addingTimeInterval(10_000)) == 0)
        #expect(BathroomFanController.formatRemaining(755) == "12:35")
        #expect(BathroomFanController.formatRemaining(3_725) == "01:02:05")
        #expect(BathroomFanController.formatRemaining(-3) == "00:00")
    }

    @Test func remainingTimeFallsBackToTheLocalDateTimeState() throws {
        let (fanController, _, _, _) = controller(pending: true, deadlineState: "2026-10-11 12:30:00")
        let deadline = try #require(fanController.deadline)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: deadline)
        #expect(parts.hour == 12 && parts.minute == 30)
        #expect(BathroomFanController.parseLocalDateTime("2026-10-11T12:30:00") == deadline)
        #expect(BathroomFanController.parseLocalDateTime("soon") == nil)
    }

    @Test func noRemainingTimeWithoutATimerOrDeadline() {
        let (idle, _, _, _) = controller(pending: false, deadline: ["timestamp": .number(2_000_000_000)])
        #expect(idle.remainingSeconds(at: Date()) == nil)
        let (unknown, _, _, _) = controller(pending: true, deadlineState: "unknown")
        #expect(unknown.remainingSeconds(at: Date()) == nil)
    }
}

// MARK: - Room tile text and timer copy

@MainActor
@Suite(.demoHouse)
struct BathroomFanTileTextTests {
    let fan = BathroomFanConfig.all[0]
    let now = Date(timeIntervalSince1970: 1_000_000)

    func controller(power: String = "on", locked: Bool = false, pending: Bool = false, lockState: String? = nil,
                    secondsLeft: Double = 754.2, timer: [String: JSONValue] = [:]) -> BathroomFanController {
        let store = makeStore([
            fan.powerEntityId: power,
            fan.lockEntityId: lockState ?? (locked ? "on" : "off"),
            fan.pendingEntityId: pending ? "on" : "off",
            fan.autoUnlockEntityId: "off",
            fan.deadlineEntityId: "2026-10-11 12:00:00",
            fan.timerEntityId: pending ? "active" : "idle",
        ], attributes: [fan.deadlineEntityId: ["timestamp": .number(1_000_000 + secondsLeft)], fan.timerEntityId: timer])
        return BathroomFanController(config: fan, store: store, caller: RecordingCaller(), scheduler: ManualScheduler())
    }

    @Test func statusIsOneShortLine() {
        #expect(controller(power: "on").tileStatusText(at: now) == "On")
        #expect(controller(power: "off").tileStatusText(at: now) == "Off")
        #expect(controller(power: "unavailable").tileStatusText(at: now) == "Unavailable")
        #expect(controller(power: "on", pending: true).tileStatusText(at: now) == "Off in 12:35")
        #expect(controller(power: "on", pending: true, secondsLeft: 3_725).tileStatusText(at: now) == "Off in 01:02:05")
    }

    @Test func lockIsNeverInTheText() {
        #expect(controller(power: "on", locked: true).tileStatusText(at: now) == "On")
        #expect(controller(power: "off", locked: true).tileStatusText(at: now) == "Off")
        #expect(controller(power: "on", locked: true, pending: true).tileStatusText(at: now) == "Off in 12:35")
    }

    @Test func aTimerThatHasRunOutFallsBackToOn() {
        let spent = controller(power: "on", pending: true, secondsLeft: -5)
        #expect(spent.tileStatusText(at: now) == "On")
        #expect(spent.tileSpokenValue(at: now) == "on")
    }

    @Test func voiceOverSpeaksPowerTimerAndLock() {
        #expect(controller(power: "on", locked: true, pending: true).tileSpokenValue(at: now) == "on, off in 12 minutes, locked")
        #expect(controller(power: "off", locked: true).tileSpokenValue(at: now) == "off, locked")
        #expect(controller(power: "on").tileSpokenValue(at: now) == "on")
        #expect(controller(power: "on", pending: true, secondsLeft: 40).tileSpokenValue(at: now) == "on, off in 40 seconds")
        #expect(controller(power: "off", pending: true).tileSpokenValue(at: now) == "off", "A stale timer on an off fan is not spoken")
        #expect(controller(power: "unavailable", locked: true).tileSpokenValue(at: now) == "Unavailable")
        #expect(controller(power: "on", locked: true, lockState: "unavailable").tileSpokenValue(at: now) == "on",
                "An unavailable lock is not claimed as locked")
    }

    @Test func spokenDurations() {
        #expect(BathroomFanController.spokenRoughly(754) == "12 minutes")
        #expect(BathroomFanController.spokenRoughly(60) == "1 minute")
        #expect(BathroomFanController.spokenRoughly(3_900) == "1 hour, 5 minutes")
        #expect(BathroomFanController.spokenRoughly(59) == "59 seconds")
        #expect(BathroomFanController.spokenRoughly(-4) == "0 seconds")
        // The sheet's running timer changes at most once a minute for VoiceOver; the digits still count seconds.
        #expect(BathroomFanController.spokenCountdown(754) == "12 minutes")
        #expect(BathroomFanController.spokenCountdown(59) == "less than a minute")
        #expect(BathroomFanController.spokenCountdown(1) == BathroomFanController.spokenCountdown(40))
        #expect(BathroomFanController.spokenCountdown(-4) == "less than a minute")
        #expect(BathroomFanController.spokenRemaining(65).contains("1 minute"))
    }

    @Test func countdownShowsOnlyWhileTheFanIsOnAndTimed() {
        #expect(controller(power: "on", pending: true).showsCountdown)
        #expect(!controller(power: "on").showsCountdown)
        #expect(!controller(power: "off", pending: true).showsCountdown)
        #expect(!controller(power: "unavailable", pending: true).showsCountdown)
    }

    @Test func timerButtonAndSegmentTitles() {
        #expect(BathroomFanController.timerMinutes.map(BathroomFanController.segmentTitle) == ["5m", "10m", "15m", "20m", "30m", "1h"])
        #expect(BathroomFanController.startButtonTitle(10) == "Turn Off in 10 Minutes")
        #expect(BathroomFanController.startButtonTitle(30) == "Turn Off in 30 Minutes")
        #expect(BathroomFanController.startButtonTitle(60) == "Turn Off in 1 Hour")
    }

    @Test func progressUsesTheTimersDurationAttribute() {
        let timed = controller(pending: true, secondsLeft: 450, timer: ["duration": .string("0:15:00")])
        #expect(timed.totalSeconds(at: now) == 900)
        #expect(timed.remainingFraction(at: now) == 0.5)
        // Without the attribute, the shortest offered length that still covers what is left.
        let guessed = controller(pending: true, secondsLeft: 754)
        #expect(guessed.totalSeconds(at: now) == 900)
        let long = controller(pending: true, secondsLeft: 4_000)
        #expect(long.totalSeconds(at: now) == 3_600, "Beyond the longest offered length it caps there")
        #expect(long.remainingFraction(at: now) == 1)
        // An attribute shorter than what is left is stale; ignore it.
        let stale = controller(pending: true, secondsLeft: 700, timer: ["duration": .string("0:05:00")])
        #expect(stale.totalSeconds(at: now) == 900)
        #expect(controller(pending: false).remainingFraction(at: now) == nil)
    }

    @Test func parsesHomeAssistantDurations() {
        #expect(BathroomFanController.parseDuration("0:30:00") == 1_800)
        #expect(BathroomFanController.parseDuration("1:00:00") == 3_600)
        #expect(BathroomFanController.parseDuration("05:00") == 300)
        #expect(BathroomFanController.parseDuration("0:00:05.5") == 5)
        #expect(BathroomFanController.parseDuration("soon") == nil)
        #expect(BathroomFanController.parseDuration("") == nil)
        #expect(BathroomFanController.parseDuration("1:2:3:4") == nil)
    }
}
