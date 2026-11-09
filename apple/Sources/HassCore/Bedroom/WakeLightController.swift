import Foundation
import Observation

/// Drives a room's wake light: reads the status sensor, shows edits at once, and sends response-checked
/// `wake_light.command` calls (web `useWakeLightController.ts`).
///
/// Configuration commands run one at a time in order; stopping an episode jumps the queue. Each edit shows
/// immediately and gives way to Home Assistant after ``revert`` or when the command is refused.
@MainActor
@Observable
public final class WakeLightController {
    // MARK: - Properties

    public let config: WakeLightConfig
    public let store: EntityStore
    /// Only Home Assistant administrators may edit (web `canEdit`).
    public var canEdit: Bool

    /// The last refused command's error code, until cleared or the next command.
    public private(set) var errorCode: String?
    /// The editor's alarm changed elsewhere; offer to reload it.
    public private(set) var requiresAlarmReload = false
    /// Commands in flight, by ``WakeLight/Command/pendingKeys``.
    public private(set) var pending: Set<String> = []

    private var alarmIntents: [String: WakeLight.Alarm?] = [:]
    private var linkIntents: [String: Bool] = [:]
    private var defaultsIntent: WakeLight.Defaults?
    private var occurrencesCleared = false

    @ObservationIgnored private let caller: any HassServiceResponding
    @ObservationIgnored private let scheduler: any RevertScheduler
    @ObservationIgnored private let makeRequestId: @MainActor () -> String
    @ObservationIgnored private var timers: [String: any ScheduledWork] = [:]
    @ObservationIgnored private var revisionFloor = 0
    @ObservationIgnored private var queueTail: Task<Void, Never>?
    @ObservationIgnored private var errorEpoch = 0

    /// How long an edit shows before Home Assistant's state wins again (web `REVERT_MS`).
    public static let revert: Duration = .seconds(8)
    /// How long a command may take before it counts as a transport failure.
    public static let timeout: Duration = .seconds(10)

    // MARK: - Init

    /// Creates a controller.
    /// - Parameters:
    ///   - config: The room's wake light.
    ///   - store: Live state.
    ///   - caller: Sends response-checked commands (the connection, or a recorder).
    ///   - canEdit: Whether the signed-in user may change alarms.
    ///   - scheduler: Runs revert timers.
    ///   - requestId: Makes each command's `request_id`.
    public init(config: WakeLightConfig, store: EntityStore, caller: any HassServiceResponding, canEdit: Bool = true,
                scheduler: any RevertScheduler = TaskRevertScheduler(),
                requestId: @escaping @MainActor () -> String = { UUID().uuidString.lowercased() }) {
        self.config = config
        self.store = store
        self.caller = caller
        self.canEdit = canEdit
        self.scheduler = scheduler
        makeRequestId = requestId
    }

    // MARK: - Reading

    /// What Home Assistant reports.
    public var live: WakeLight.Snapshot {
        WakeLight.snapshot(store.entity(config.statusEntityId).state, profileId: config.id)
    }

    /// What to show: the live snapshot with pending edits applied.
    public var snapshot: WakeLight.Snapshot {
        var snapshot = live
        var alarms = snapshot.alarms.compactMap { alarm in alarmIntents.keys.contains(alarm.id) ? alarmIntents[alarm.id]! : alarm }
        for (id, intent) in alarmIntents.sorted(by: { $0.key < $1.key }) where !snapshot.alarms.contains(where: { $0.id == id }) {
            if let intent { alarms.append(intent) }
        }
        snapshot.alarms = alarms
        for (key, linked) in linkIntents {
            if linked { snapshot.unlinkedKeys.remove(key) } else { snapshot.unlinkedKeys.insert(key) }
        }
        if let defaultsIntent { snapshot.defaults = defaultsIntent }
        if occurrencesCleared { snapshot.activeOccurrences = [] }
        return snapshot
    }

    /// The error to show, if any.
    public var error: String? { errorCode.map(WakeLight.errorMessage) }

    /// A configuration command is in flight (editing is locked meanwhile).
    public var configurationPending: Bool { pending.contains { $0 != "end_episode" } }

    /// Stopping the episode is in flight.
    public var stopping: Bool { pending.contains("end_episode") }

    /// Whether an alarm's save or delete is in flight.
    public func isPending(alarmId: String) -> Bool { pending.contains("alarm:\(alarmId)") }

    /// Whether any of these link keys is changing.
    public func arePending(linkKeys: [String]) -> Bool { linkKeys.contains { pending.contains("link:\($0)") } }

    /// Clears the error and any reload prompt.
    public func clearError() {
        errorEpoch += 1
        errorCode = nil
        requiresAlarmReload = false
    }

    // MARK: - Commands

    /// Saves (creates or updates) an alarm.
    @discardableResult
    public func save(_ alarm: WakeLight.Alarm) async -> Bool {
        var shown = alarm
        shown.revision += 1
        return await send(.upsert(alarm), optimistic: { $0.commitAlarm(alarm.id, shown) }, rollback: { $0.clearIntent("alarm:\(alarm.id)") })
    }

    /// Deletes an alarm.
    @discardableResult
    public func delete(alarmId: String) async -> Bool {
        await send(.delete(alarmId: alarmId), optimistic: { $0.commitAlarm(alarmId, nil) }, rollback: { $0.clearIntent("alarm:\(alarmId)") })
    }

    /// Turns bed-alarm wake links on or off.
    @discardableResult
    public func setLinks(_ keys: [String], enabled: Bool) async -> Bool {
        guard !keys.isEmpty else { return true }
        return await send(.link(keys: keys, enabled: enabled),
                          optimistic: { controller in keys.forEach { controller.commitLink($0, enabled) } },
                          rollback: { controller in keys.forEach { controller.clearIntent("link:\($0)") } })
    }

    /// Changes the room defaults.
    @discardableResult
    public func updateDefaults(_ defaults: WakeLight.Defaults) async -> Bool {
        await send(.updateDefaults(defaults), optimistic: { $0.commitDefaults(defaults) }, rollback: { $0.clearIntent("defaults") })
    }

    /// Stops the running wake episode (urgent: skips the configuration queue).
    @discardableResult
    public func endEpisode() async -> Bool {
        await send(.endEpisode, optimistic: { $0.commitOccurrencesCleared() }, rollback: { $0.clearIntent("occurrences") })
    }

    // MARK: - Sending

    private func send(_ command: WakeLight.Command, optimistic: (WakeLightController) -> Void,
                      rollback: @escaping @MainActor (WakeLightController) -> Void) async -> Bool {
        let keys = command.pendingKeys
        let urgent = if case .endEpisode = command { true } else { false }
        guard !keys.contains(where: pending.contains) else { return false }
        let current = live
        guard current.available, !urgent || current.episodeRef != nil else {
            errorCode = "unavailable"
            return false
        }
        let epoch = errorEpoch
        pending.formUnion(keys)
        errorCode = nil
        optimistic(self)

        let previous = urgent ? nil : queueTail
        let work = Task { @MainActor [weak self] () -> Bool in
            await previous?.value
            guard let self else { return false }
            return await self.execute(command, epoch: epoch, rollback: rollback)
        }
        if !urgent { queueTail = Task { _ = await work.value } }
        let accepted = await work.value
        pending.subtract(keys)
        return accepted
    }

    private func execute(_ command: WakeLight.Command, epoch: Int, rollback: @MainActor (WakeLightController) -> Void) async -> Bool {
        var snapshot = live
        snapshot.revision = max(revisionFloor, snapshot.revision)
        let data = WakeLight.serviceData(command, snapshot: snapshot, requestId: makeRequestId())
        let outcome: CommandOutcome?
        do {
            let caller = caller
            outcome = CommandOutcome(response: try await withTimeout(Self.timeout) {
                try await caller.callServiceWithResponse("wake_light", "command", data: data)
            })
        } catch {
            outcome = nil
        }
        switch outcome {
        case let .accepted(noChange, revision)?:
            if let revision { revisionFloor = max(revisionFloor, revision) }
            if noChange { rollback(self) }
            return true
        case let .rejected(code, alarmConflict, revision)?:
            if let revision { revisionFloor = max(revisionFloor, revision) }
            rollback(self)
            if errorEpoch == epoch {
                errorCode = code
                requiresAlarmReload = alarmConflict
            }
            return false
        case nil:
            rollback(self)
            if errorEpoch == epoch { errorCode = "transport" }
            return false
        }
    }

    // MARK: - Intents

    private func commitAlarm(_ id: String, _ alarm: WakeLight.Alarm?) {
        alarmIntents[id] = .some(alarm)
        armTimer("alarm:\(id)")
    }

    private func commitLink(_ key: String, _ linked: Bool) {
        linkIntents[key] = linked
        armTimer("link:\(key)")
    }

    private func commitDefaults(_ defaults: WakeLight.Defaults) {
        defaultsIntent = defaults
        armTimer("defaults")
    }

    private func commitOccurrencesCleared() {
        occurrencesCleared = true
        armTimer("occurrences")
    }

    private func armTimer(_ key: String) {
        timers[key]?.cancel()
        timers[key] = scheduler.schedule(after: Self.revert) { [weak self] in self?.clearIntent(key) }
    }

    private func clearIntent(_ key: String) {
        timers[key]?.cancel()
        timers[key] = nil
        if key.hasPrefix("alarm:") { alarmIntents[String(key.dropFirst(6))] = nil }
        else if key.hasPrefix("link:") { linkIntents[String(key.dropFirst(5))] = nil }
        else if key == "defaults" { defaultsIntent = nil }
        else if key == "occurrences" { occurrencesCleared = false }
    }
}

/// Runs `operation`, throwing ``TimeoutError`` if it takes longer than `limit`.
///
/// A race between two main-actor tasks rather than a task group, which the region-based isolation checker
/// rejects for a main-actor operation. A late reply after the timeout is dropped.
@MainActor
func withTimeout<T: Sendable>(_ limit: Duration, _ operation: @escaping @MainActor () async throws -> T) async throws -> T {
    let race = TimeoutRace<T>()
    return try await withCheckedThrowingContinuation { continuation in
        race.continuation = continuation
        let work = Task { @MainActor in
            do { race.finish(.success(try await operation())) } catch { race.finish(.failure(error)) }
        }
        race.timer = Task { @MainActor in
            do { try await Task.sleep(for: limit) } catch { return }
            work.cancel()
            race.finish(.failure(TimeoutError()))
        }
    }
}

/// Resumes ``withTimeout(_:_:)`` once, with whichever of the operation or the timer finishes first.
@MainActor
private final class TimeoutRace<T: Sendable> {
    var continuation: CheckedContinuation<T, Error>?
    var timer: Task<Void, Never>?

    func finish(_ result: Result<T, Error>) {
        timer?.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}

/// A command took too long.
struct TimeoutError: Error {}
