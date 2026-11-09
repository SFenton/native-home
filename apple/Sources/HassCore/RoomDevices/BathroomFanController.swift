import Foundation
import Observation

/// Drives one bathroom fan (web `useBathroomFanCommand.ts`, `bathroomFanState.ts`, `BathroomFanModalContent.tsx`).
///
/// Every command goes through the fan's script with a `command` field; Home Assistant runs the timer, lock and
/// auto-unlock logic. Power, lock, timer-pending and auto-unlock show optimistically and clear on any live change
/// or after 2 s, like the web.
///
/// **No auto-unlock choice** (owner, 2026-10-17): the fan always unlocks when its timer ends, so a timer starts with
/// `auto_unlock: true` and the web's "Auto-disable lock" checkbox is not ported. The script's `timer_auto_unlock`
/// command is left in Home Assistant untouched; the app just never sends it.
@MainActor
@Observable
public final class BathroomFanController {
    /// Timer lengths offered, in minutes (`BATHROOM_FAN_TIMER_MINUTES`).
    public static let timerMinutes = [5, 10, 15, 20, 30, 60]
    /// The timer picker's starting value.
    public static let defaultTimerMinutes = 30
    /// Web `DEFAULT_OPTIMISTIC_REVERT_MS`.
    public static let revert: Duration = .seconds(2)

    public let config: BathroomFanConfig
    public let commands: RoomDeviceCommands

    /// The timer length picked in the sheet (local until Set).
    public var selectedMinutes = BathroomFanController.defaultTimerMinutes
    /// Creates a controller.
    public init(config: BathroomFanConfig, store: EntityStore, caller: any HassServiceCalling,
                scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.config = config
        var rules: [String: OptimisticOverlay.ClearRule] = [:]
        for id in config.optimisticEntityIds { rules[id] = .liveChange }
        commands = RoomDeviceCommands(store: store, caller: caller, rules: rules, scheduler: scheduler) { [store] id in
            DeviceState.binaryFlag(store.entity(id).state?.state)
        }
    }

    // MARK: - State

    private func flag(_ id: String) -> String { commands.displayed(id) ?? "unavailable" }

    /// A power or lock command was rejected and the tile still shows its failed face (4 s).
    public var commandFailed: Bool { commands.isFailed(config.powerEntityId) || commands.isFailed(config.lockEntityId) }

    public var powerAvailable: Bool { commands.live(config.powerEntityId) != "unavailable" }
    public var lockAvailable: Bool { commands.live(config.lockEntityId) != "unavailable" }
    public var timerAvailable: Bool { commands.live(config.pendingEntityId) != "unavailable" }

    public var powerOn: Bool { flag(config.powerEntityId) == "on" }
    public var locked: Bool { flag(config.lockEntityId) == "on" }
    public var timerPending: Bool { flag(config.pendingEntityId) == "on" }
    /// Home Assistant's auto-unlock flag (set while a timer runs on a locked fan); read only to clear it optimistically.
    public var autoUnlock: Bool { flag(config.autoUnlockEntityId) == "on" }

    /// A timer can start whenever the fan and the timer helper are available: starting one turns the fan on if it is
    /// off (the script's `timer_start` ends with `switch.turn_on`, verified in `scripts.yaml` 2026-10-17).
    public var canStartTimer: Bool { powerAvailable && timerAvailable }

    /// The subtitle for the power tile and the room tile: On, Off or Unavailable.
    public var powerStateText: String { powerAvailable ? (powerOn ? "On" : "Off") : "Unavailable" }

    /// Locked, Unlocked or Unavailable.
    public var lockStateText: String { lockAvailable ? (locked ? "Locked" : "Unlocked") : "Unavailable" }

    // MARK: - Room tile text

    /// The room tile's one short status line (owner, 2026-10-17): `On`, `Off`, `Off in 12:30` while a timer runs, or
    /// `Unavailable`. The lock is never in the text; its button shows it.
    public func tileStatusText(at now: Date) -> String {
        if commandFailed { return "Didn't Respond" }
        guard powerAvailable else { return "Unavailable" }
        guard powerOn else { return "Off" }
        if let remaining = remainingSeconds(at: now), remaining > 0 { return "Off in \(Self.formatRemaining(remaining))" }
        return "On"
    }

    /// What VoiceOver reads for the room tile: `on, off in 12 minutes, locked`. The lock is spoken here because the
    /// text no longer carries it.
    public func tileSpokenValue(at now: Date) -> String {
        guard powerAvailable else { return "Unavailable" }
        var parts = [powerOn ? "on" : "off"]
        if powerOn, let remaining = remainingSeconds(at: now), remaining > 0 { parts.append("off in \(Self.spokenRoughly(remaining))") }
        if lockAvailable && locked { parts.append("locked") }
        return parts.joined(separator: ", ")
    }

    /// Whether the room tile shows a countdown, so the view only runs a per-second clock while one is pending.
    public var showsCountdown: Bool { powerAvailable && powerOn && timerPending && deadline != nil }

    // MARK: - Timer

    /// When the pending timer ends, from the deadline helper (`timestamp` attribute, else the local date-time state).
    public var deadline: Date? {
        guard let entity = commands.entity(config.deadlineEntityId), !EntityState.isUnavailable(entity.state) else { return nil }
        if let timestamp = entity.attributes["timestamp"]?.number { return Date(timeIntervalSince1970: timestamp) }
        return Self.parseLocalDateTime(entity.state)
    }

    /// Seconds left at `now`, or `nil` when no timer runs or the deadline is unknown.
    public func remainingSeconds(at now: Date) -> Int? {
        guard timerPending, let deadline else { return nil }
        return max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    /// The length the running timer was started with, in seconds: the `timer` entity's `duration` attribute
    /// (`0:30:00`), else the shortest offered length that still covers what is left.
    public func totalSeconds(at now: Date) -> Int? {
        guard let remaining = remainingSeconds(at: now) else { return nil }
        if let text = commands.entity(config.timerEntityId)?.attributes["duration"]?.string,
           let seconds = Self.parseDuration(text), seconds >= remaining, seconds > 0 { return seconds }
        let covering = Self.timerMinutes.first { $0 * 60 >= remaining } ?? Self.timerMinutes.last ?? 60
        return covering * 60
    }

    /// How much of the running timer is left, 1 at the start and 0 at the end, or `nil` when no timer runs.
    public func remainingFraction(at now: Date) -> Double? {
        guard let remaining = remainingSeconds(at: now), let total = totalSeconds(at: now), total > 0 else { return nil }
        return min(1, max(0, Double(remaining) / Double(total)))
    }

    /// Parses Home Assistant's `H:MM:SS` (or `MM:SS`) duration text.
    static func parseDuration(_ text: String) -> Int? {
        let parts = text.split(separator: ":").map { Int($0.split(separator: ".").first ?? "") }
        guard !parts.isEmpty, parts.count <= 3, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    /// `05:00` or `01:00:00` (web `formatTimerRemaining`).
    public static func formatRemaining(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, rest = seconds % 60
        return hours > 0 ? String(format: "%02d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }

    /// `5 minutes` … `1 hour`.
    public static func durationTitle(_ minutes: Int) -> String {
        minutes == 60 ? "1 hour" : "\(minutes) minutes"
    }

    /// A segment's title in the timer row: `5m` ... `1h`.
    public static func segmentTitle(_ minutes: Int) -> String { minutes == 60 ? "1h" : "\(minutes)m" }

    /// The timer button's title: `Turn Off in 10 Minutes`, `Turn Off in 1 Hour`.
    public static func startButtonTitle(_ minutes: Int) -> String {
        minutes == 60 ? "Turn Off in 1 Hour" : "Turn Off in \(minutes) Minutes"
    }

    /// `4 minutes 5 seconds`, for the sheet's running timer.
    public static func spokenRemaining(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: TimeInterval(max(0, seconds))) ?? formatRemaining(seconds)
    }

    /// The sheet's running timer as VoiceOver reads it: whole minutes, then "less than a minute", so the value changes
    /// at most once a minute and a focused element is not re-announced every tick (the visible digits still count seconds).
    public static func spokenCountdown(_ seconds: Int) -> String {
        seconds < 60 ? "less than a minute" : spokenRoughly(seconds)
    }

    /// `12 minutes`, `1 hour 5 minutes` or `40 seconds`: whole minutes while a minute or more is left, so the room
    /// tile's value does not change every second under VoiceOver.
    public static func spokenRoughly(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        guard seconds >= 60 else {
            formatter.allowedUnits = [.second]
            return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds) seconds"
        }
        formatter.allowedUnits = [.hour, .minute]
        return formatter.string(from: TimeInterval(seconds / 60 * 60)) ?? "\(seconds / 60) minutes"
    }

    /// Parses `2026-10-11 14:30:00` (or with a `T`) in the device's time zone, like the web's `Date.parse`.
    static func parseLocalDateTime(_ text: String) -> Date? { HassDates.localDateTime(text) }

    /// The closest offered length (web `normalizeBathroomFanTimerMinutes`; ties keep the earlier value).
    public static func normalizedMinutes(_ minutes: Int) -> Int {
        timerMinutes.reduce(defaultTimerMinutes) { closest, candidate in
            abs(candidate - minutes) < abs(closest - minutes) ? candidate : closest
        }
    }

    // MARK: - Actions

    private func script(_ data: [String: JSONValue]) -> ServiceCall {
        ServiceCall("script", config.scriptService, data: data)
    }

    private func intent(_ id: String, _ on: Bool) -> OptimisticIntent { OptimisticIntent(id, on ? "on" : "off", revertAfter: Self.revert) }

    /// Turns the fan on or off; this also clears the timer, lock and auto-unlock on the server.
    public func setPower(_ on: Bool) {
        guard powerAvailable, on != powerOn else { return }
        var intents = [intent(config.powerEntityId, on)]
        if timerPending { intents.append(intent(config.pendingEntityId, false)) }
        if locked { intents.append(intent(config.lockEntityId, false)) }
        if autoUnlock { intents.append(intent(config.autoUnlockEntityId, false)) }
        commands.perform(script(["command": .string("power"), "target_power": .string(on ? "on" : "off")]), intents: intents)
    }

    /// Locks or unlocks the fan against its automations. Locking during a timer turns auto-unlock on.
    public func setLocked(_ lock: Bool) {
        guard lockAvailable, lock != locked else { return }
        var intents = [intent(config.lockEntityId, lock)]
        if lock && timerPending { intents.append(intent(config.autoUnlockEntityId, true)) }
        commands.perform(script(["command": .string("lock"), "locked": .bool(lock)]), intents: intents)
    }

    /// Starts the off timer with ``selectedMinutes``. The script turns the fan on if it is off, and always releases the
    /// lock when the timer ends (`auto_unlock: true`; the app has no choice to turn that off).
    public func startTimer() {
        guard canStartTimer else { return }
        var intents = [intent(config.pendingEntityId, true), intent(config.autoUnlockEntityId, locked)]
        if !powerOn { intents.append(intent(config.powerEntityId, true)) }
        commands.perform(script([
            "auto_unlock": .bool(true),
            "command": .string("timer_start"),
            "minutes": .number(Double(Self.normalizedMinutes(selectedMinutes))),
        ]), intents: intents)
    }

    /// Cancels the pending timer.
    public func cancelTimer() {
        guard timerPending, timerAvailable else { return }
        commands.perform(script(["command": .string("timer_cancel")]),
                         intents: [intent(config.pendingEntityId, false), intent(config.autoUnlockEntityId, false)])
    }
}
