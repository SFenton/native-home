import Foundation
import Observation

/// One sprinkler controller's state and commands (web `SprinklerController.tsx`).
///
/// Reads come from ``SprinklerSnapshot`` with optimistic values layered on top, the way the web's
/// `useOptimisticState(..., { clearOn: 'confirmation', revertMs: 10_000 })` does: a command shows at once and
/// gives way when Home Assistant confirms it, when the call fails, or after ten seconds.
@MainActor
@Observable
public final class SprinklerController: Identifiable {
    /// The controller.
    public let config: SprinklersConfig.Controller
    /// The last failed call's message (web `serviceError`), cleared by the next command.
    public private(set) var errorMessage: String?

    @ObservationIgnored private let store: EntityStore
    @ObservationIgnored private let caller: any HassServiceCalling
    /// Optimistic values (web `useOptimisticState` per value).
    @ObservationIgnored let overlay: OptimisticOverlay
    @ObservationIgnored private var inFlight: [Task<Void, Never>] = []

    public nonisolated var id: String { config.id }

    // MARK: - Keys

    enum Key {
        static let activeValve = "activeValve"
        static let rainDelay = "rainDelay"
        static let smartWatering = "smartWatering"
        static func enabled(_ program: String) -> String { "enabled:\(program)" }
        static func budget(_ program: String) -> String { "budget:\(program)" }
        static func days(_ program: String) -> String { "days:\(program)" }
        static func startTimes(_ program: String) -> String { "startTimes:\(program)" }
    }

    /// Creates a controller.
    /// - Parameters:
    ///   - config: The controller.
    ///   - store: Live state.
    ///   - caller: Where service calls go: the connection in the app, a recorder in tests.
    ///   - scheduler: Runs revert timers.
    public init(config: SprinklersConfig.Controller, store: EntityStore, caller: any HassServiceCalling,
                scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.config = config
        self.store = store
        self.caller = caller
        var rules: [String: OptimisticOverlay.ClearRule] = [
            Key.activeValve: .confirmation, Key.rainDelay: .confirmation, Key.smartWatering: .confirmation,
        ]
        for program in Set(config.zones.map(\.programEntityId)) {
            for key in [Key.enabled(program), Key.budget(program), Key.days(program), Key.startTimes(program)] {
                rules[key] = .confirmation
            }
        }
        overlay = OptimisticOverlay(rules: rules, scheduler: scheduler)
        liveDidChange()
        observeLive()
    }

    // MARK: - Reading

    /// The live snapshot (observes every entity it reads).
    public var snapshot: SprinklerSnapshot { SprinklerSnapshot(config: config, store: store) }

    /// The valve shown watering: optimistic, else live; `nil` when none.
    public var activeValve: String? {
        let shown = overlay.displayed(Key.activeValve, live: snapshot.activeValveEntityId ?? "") ?? ""
        return shown.isEmpty ? nil : shown
    }

    /// A zone is shown watering.
    public var isWatering: Bool { snapshot.available && activeValve != nil }

    /// Watering can start: available, not in `off` mode, nothing running.
    public var canStartWatering: Bool { snapshot.available && snapshot.mode != "off" && !isWatering }

    /// Rain delay as shown.
    public var rainDelay: Bool { overlay.displayed(Key.rainDelay, live: Self.flag(snapshot.rainDelay)) == "on" }

    /// Smart watering as shown.
    public var smartWatering: Bool { overlay.displayed(Key.smartWatering, live: Self.flag(snapshot.smartWatering)) == "on" }

    /// A zone's program as shown (enabled, budget, days and start times may be optimistic).
    public func program(_ index: Int) -> SprinklerSnapshot.Program? {
        guard snapshot.zones.indices.contains(index) else { return nil }
        var program = snapshot.zones[index].program
        let id = program.entityId
        program.enabled = overlay.displayed(Key.enabled(id), live: Self.flag(program.enabled)) == "on"
        program.budget = overlay.displayed(Key.budget(id), live: String(program.budget)).flatMap(Int.init) ?? program.budget
        program.days = Self.days(overlay.displayed(Key.days(id), live: Self.dayKey(program.days)) ?? "")
        program.startTimes = Self.times(overlay.displayed(Key.startTimes(id), live: Self.timeKey(program.startTimes)) ?? "")
        return program
    }

    // MARK: - Commands

    /// Waters a zone for `minutes` (web `startWatering`). Returns whether the call succeeded.
    @discardableResult
    public func startWatering(zone index: Int, minutes: Int) async -> Bool {
        guard snapshot.zones.indices.contains(index) else { return false }
        let valve = snapshot.zones[index].config.valveEntityId
        return await run(SprinklersConfig.startWatering(valve: valve, minutes: minutes),
                         intents: [(Key.activeValve, valve, snapshot.activeValveEntityId ?? "")])
    }

    /// Stops the running valve, else the first zone's (web `stopWatering`).
    public func stopWatering() {
        guard let valve = activeValve ?? snapshot.zones.first?.config.valveEntityId else { return }
        start(SprinklersConfig.stopWatering(valve: valve), intents: [(Key.activeValve, "", snapshot.activeValveEntityId ?? "")])
    }

    /// Runs a zone's program now (web `startProgram`).
    public func startProgram(zone index: Int) {
        guard snapshot.zones.indices.contains(index) else { return }
        let zone = snapshot.zones[index]
        start(SprinklersConfig.startProgram(zone.program.entityId),
              intents: [(Key.activeValve, zone.config.valveEntityId, snapshot.activeValveEntityId ?? "")])
    }

    /// Turns rain delay on or off.
    public func setRainDelay(_ on: Bool) {
        start(SprinklersConfig.setSwitch(config.rainDelayEntityId, on: on),
              intents: [(Key.rainDelay, Self.flag(on), Self.flag(snapshot.rainDelay))])
    }

    /// Turns smart watering on or off.
    public func setSmartWatering(_ on: Bool) {
        start(SprinklersConfig.setSwitch(config.smartWateringEntityId, on: on),
              intents: [(Key.smartWatering, Self.flag(on), Self.flag(snapshot.smartWatering))])
    }

    /// Enables or disables a zone's program.
    public func setProgramEnabled(zone index: Int, _ on: Bool) {
        guard snapshot.zones.indices.contains(index) else { return }
        let program = snapshot.zones[index].program
        start(SprinklersConfig.setSwitch(program.entityId, on: on),
              intents: [(Key.enabled(program.entityId), Self.flag(on), Self.flag(program.enabled))])
    }

    /// Saves a program's schedule (web `saveSchedule`). Blank start times are dropped. Returns whether it succeeded.
    @discardableResult
    public func saveSchedule(zone index: Int, days: [Int], startTimes: [String], budget: Int) async -> Bool {
        guard snapshot.zones.indices.contains(index) else { return false }
        let live = snapshot.zones[index].program
        let id = live.entityId
        let times = startTimes.filter { !$0.isEmpty }
        let sortedDays = days.sorted()
        return await run(SprinklersConfig.updateProgram(id, days: sortedDays, startTimes: times, budget: budget), intents: [
            (Key.budget(id), String(budget), String(live.budget)),
            (Key.days(id), Self.dayKey(sortedDays), Self.dayKey(live.days)),
            (Key.startTimes(id), Self.timeKey(times), Self.timeKey(live.startTimes)),
        ])
    }

    /// Clears the error message (opening the sheet, leaving a detail page).
    public func clearError() { errorMessage = nil }

    /// Waits for every call started so far. Tests use it to observe calls and failures.
    public func waitForCalls() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks { await task.value }
    }

    // MARK: - Calls

    private typealias Intent = (key: String, value: String, live: String)

    private func start(_ call: ServiceCall, intents: [Intent]) {
        let task = Task { @MainActor [weak self] in _ = await self?.run(call, intents: intents) }
        inFlight.append(task)
    }

    /// Commits the intents, calls the service and undoes them if it fails.
    private func run(_ call: ServiceCall, intents: [Intent]) async -> Bool {
        errorMessage = nil
        let commits = intents.compactMap { intent in
            overlay.commit(intent.key, value: intent.value, live: intent.live, revertAfter: SprinklersConfig.optimisticRevert)
                .map { (intent.key, $0) }
        }
        do {
            try await caller.call(call)
            return true
        } catch {
            for (key, generation) in commits { overlay.fail(key, generation: generation) }
            errorMessage = Self.message(for: error)
            return false
        }
    }

    static func message(for error: any Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return text.isEmpty ? "The command failed." : text
    }

    // MARK: - Live changes

    /// Each optimistic key's live value.
    private func liveValues() -> [String: String] {
        let snapshot = snapshot
        var values = [
            Key.activeValve: snapshot.activeValveEntityId ?? "",
            Key.rainDelay: Self.flag(snapshot.rainDelay),
            Key.smartWatering: Self.flag(snapshot.smartWatering),
        ]
        for zone in snapshot.zones {
            let program = zone.program
            values[Key.enabled(program.entityId)] = Self.flag(program.enabled)
            values[Key.budget(program.entityId)] = String(program.budget)
            values[Key.days(program.entityId)] = Self.dayKey(program.days)
            values[Key.startTimes(program.entityId)] = Self.timeKey(program.startTimes)
        }
        return values
    }

    /// Feeds live values to the overlay so confirmations clear pending values.
    func liveDidChange() {
        for (key, value) in liveValues() { overlay.liveChanged(key, to: value) }
    }

    private func observeLive() {
        let ids = SprinklerSnapshot.entityIds(config)
        withObservationTracking {
            for id in ids { _ = store.entity(id).state }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.liveDidChange()
                self?.observeLive()
            }
        }
    }

    // MARK: - Value keys

    static func flag(_ on: Bool) -> String { on ? "on" : "off" }
    static func dayKey(_ days: [Int]) -> String { days.map(String.init).joined(separator: ",") }
    static func days(_ key: String) -> [Int] { key.isEmpty ? [] : key.split(separator: ",").compactMap { Int($0) } }
    static func timeKey(_ times: [String]) -> String { times.joined(separator: "|") }
    static func times(_ key: String) -> [String] { key.isEmpty ? [] : key.split(separator: "|", omittingEmptySubsequences: false).map(String.init) }
}
