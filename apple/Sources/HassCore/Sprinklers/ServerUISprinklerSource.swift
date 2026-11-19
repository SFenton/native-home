import Foundation
import Observation

// MARK: - Authored sprinkler ownership

/// Guarded gestures and retained per-zone editors over the production controller.
@MainActor @Observable
public final class ServerUISprinklerSource {
    /// The validated authored controller.
    public let descriptor: ServerUISprinklerDescriptor
    /// The production controller the gestures drive.
    public let controller: SprinklerController
    /// Retained schedule editors by zone.
    @ObservationIgnored private let store: EntityStore
    public private(set) var drafts: [Int: ServerUISprinklerDraft] = [:]
    /// Fixed copy for the last rejected gesture, or `nil`.
    public private(set) var error: String?
    /// Manual run durations chosen per zone.
    public private(set) var durations: [Int: Int] = [:]
    private var pendingRequests = 0

    /// Creates the source over one store and transport.
    /// - Parameter scheduler: Runs the controller's optimistic-revert timers; tests inject a manual one so the ten-second
    ///   revert never races a slow test host.
    public init(descriptor: ServerUISprinklerDescriptor, store: EntityStore, caller: any HassServiceCalling,
                scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.descriptor = descriptor
        self.store = store
        controller = SprinklerController(config: descriptor.controller, store: store, caller: caller, scheduler: scheduler,
                                        lowBatteryPercent: descriptor.lowBatteryPercent)
    }
    /// Whether a gesture, command or unsaved draft forbids replacing this source.
    public var protectsPublication: Bool { pendingRequests > 0 || controller.hasPendingCommands || drafts.values.contains { $0.blocksExit } }
    /// Why a zone cannot start now, or `nil` when it can.
    public var wateringBlocker: String? {
        if !controller.snapshot.available { return "The sprinkler is unavailable." }
        if controller.snapshot.mode == "off" { return "Turn on the sprinkler before starting watering." }
        if controller.isWatering { return "Stop the current watering before starting another zone." }
        return nil
    }
    /// Pins the gesture synchronously, before the task first enters its async service method.
    public func start(_ intent: Intent) -> Task<Bool, Never> {
        pendingRequests += 1
        return Task { @MainActor [self] in
            defer { pendingRequests -= 1 }
            return await perform(intent)
        }
    }
    /// The chosen manual run time of `zone`, or the default.
    public func duration(_ zone: Int) -> Int { durations[zone] ?? SprinklersConfig.manualRunTime.default }
    /// Chooses a manual run time inside the configured range for an existing zone.
    public func setDuration(_ value: Int, zone: Int) {
        guard controller.snapshot.zones.indices.contains(zone),
              (SprinklersConfig.manualRunTime.min...SprinklersConfig.manualRunTime.max).contains(value) else {
            _ = reject(); return
        }
        durations[zone] = value
    }
    /// The retained schedule editor of `zone`, created on first use, or `nil` for an unknown zone.
    public func draft(_ zone: Int) -> ServerUISprinklerDraft? {
        if let value = drafts[zone] { return value }
        guard controller.snapshot.zones.indices.contains(zone) else { return nil }
        let value = ServerUISprinklerDraft(controller: controller, zone: zone, defaultStartTime: descriptor.defaultStartTime)
        drafts[zone] = value
        return value
    }
    /// A guarded sprinkler gesture.
    public enum Intent: Equatable, Sendable {
        case rainDelay(Bool), smartWatering(Bool), enabled(Int, Bool), startProgram(Int), stop, water(Int)
    }
    /// Runs one gesture. Returns whether it was accepted and succeeded.
    @discardableResult
    public func perform(_ intent: Intent) async -> Bool {
        let snapshot = controller.snapshot
        guard snapshot.available, !controller.hasPendingCommands else { return reject() }
        error = nil
        switch intent {
        case .rainDelay(let on):
            guard store.entity(descriptor.controller.rainDelayEntityId).state?.isUnavailable == false else { return reject() }
            controller.setRainDelay(on)
        case .smartWatering(let on):
            guard store.entity(descriptor.controller.smartWateringEntityId).state?.isUnavailable == false else { return reject() }
            controller.setSmartWatering(on)
        case .enabled(let index, let on):
            guard snapshot.zones.indices.contains(index), snapshot.zones[index].program.available else { return reject() }
            controller.setProgramEnabled(zone: index, on)
        case .startProgram(let index):
            guard snapshot.zones.indices.contains(index), snapshot.zones[index].program.available,
                  controller.canStartWatering else { return reject() }
            controller.startProgram(zone: index)
        case .stop:
            guard controller.activeValve != nil else { return reject() }
            controller.stopWatering()
        case .water(let index):
            guard snapshot.zones.indices.contains(index), controller.canStartWatering,
                  snapshot.zones[index].available else { return reject() }
            return await controller.startWatering(zone: index, minutes: duration(index))
        }
        await controller.waitForCalls()
        return controller.errorMessage == nil
    }
    private func reject() -> Bool { error = "The sprinkler changed or is unavailable. Try again."; return false }
}

// MARK: - Schedule draft

/// Stable time rows, revision checks and pinned save values. The shared shell owns exit presentation.
@MainActor @Observable
public final class ServerUISprinklerDraft {
    /// One start-time row with a stable id.
    public struct Time: Equatable, Sendable, Identifiable {
        /// The row's stable id.
        public let id: String
        /// The `HH:mm` start time.
        public var value: String
    }
    /// The editable part of a zone's program.
    public struct Value: Equatable, Sendable {
        /// Weekdays, 0 through 6.
        public var days: Set<Int>
        /// Start times, at most four.
        public var times: [Time]
        /// The water budget percentage, in steps of five.
        public var budget: Int
    }
    /// The zone the draft edits.
    public let zone: Int
    /// The edited program.
    public private(set) var value: Value
    /// The program as last loaded or saved.
    public private(set) var initial: Value
    /// Whether a save is in flight.
    public private(set) var busy = false
    /// Fixed copy for the last failed save or reload, or `nil`.
    public private(set) var error: String?
    private var revision: SprinklerSnapshot.Program
    @ObservationIgnored private let controller: SprinklerController
    @ObservationIgnored private let defaultStartTime: String

    init(controller: SprinklerController, zone: Int, defaultStartTime: String) {
        self.controller = controller
        self.zone = zone
        self.defaultStartTime = defaultStartTime
        let program = controller.snapshot.zones[zone].program
        revision = program
        let initial = Self.value(program)
        self.initial = initial
        value = initial
    }
    /// Whether the edit differs from the loaded program.
    public var dirty: Bool { value != initial }
    /// Whether leaving would lose edits or abandon a save.
    public var blocksExit: Bool { dirty || busy }
    /// Whether the program is complete and still matches the live schedule.
    public var canSave: Bool {
        guard !busy, dirty, controller.snapshot.available, !controller.hasPendingCommands,
              controller.snapshot.zones.indices.contains(zone) else { return false }
        let program = controller.snapshot.zones[zone].program
        return program.available && sameSchedule(program, revision) && !value.days.isEmpty
            && (0...200).contains(value.budget) && value.budget.isMultiple(of: 5)
            && !value.times.isEmpty && value.times.count <= 4
            && Set(value.times.map(\.value)).count == value.times.count
            && value.days.allSatisfy { (0...6).contains($0) }
            && value.times.allSatisfy { ServerUICompositionShape.matches($0.value, #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#) }
    }
    /// Applies an edit unless a save is in flight.
    public func update(_ change: (inout Value) -> Void) {
        guard !busy else { return }
        change(&value)
        error = nil
    }
    /// Adds a start time at the default clock, up to four.
    public func addTime() {
        guard !busy, value.times.count < 4 else { return }
        update { $0.times.append(Time(id: UUID().uuidString, value: defaultStartTime)) }
    }
    /// Removes a start time, keeping at least one.
    public func removeTime(_ id: String) {
        guard !busy, value.times.count > 1 else { return }
        update { $0.times.removeAll { $0.id == id } }
    }
    /// Drops the edits.
    public func discard() {
        guard !busy else { return }
        value = initial
        error = nil
    }
    /// Adopts the live schedule when nothing is edited.
    public func reload() {
        guard !busy, !dirty, controller.snapshot.zones.indices.contains(zone) else {
            error = "Discard your changes before reloading the schedule."
            return
        }
        revision = controller.snapshot.zones[zone].program
        initial = Self.value(revision)
        value = initial
        error = nil
    }
    /// Saves the pinned values. Returns whether the controller applied them.
    @discardableResult
    public func save() async -> Bool {
        guard canSave else { error = "The schedule changed or is incomplete. Reload it before applying."; return false }
        let ticket = value
        busy = true
        defer { busy = false }
        let ok = await controller.saveSchedule(zone: zone, days: ticket.days.sorted(), startTimes: ticket.times.map(\.value), budget: ticket.budget)
        if ok {
            initial = ticket
            revision.days = ticket.days.sorted()
            revision.startTimes = ticket.times.map(\.value)
            revision.budget = ticket.budget
            error = nil
        }
        else { error = controller.errorMessage ?? "Couldn't apply the schedule. Try again." }
        return ok
    }
    private func sameSchedule(_ a: SprinklerSnapshot.Program, _ b: SprinklerSnapshot.Program) -> Bool {
        a.days == b.days && a.startTimes == b.startTimes && a.budget == b.budget
    }
    private static func value(_ program: SprinklerSnapshot.Program) -> Value {
        Value(days: Set(program.days), times: program.startTimes.enumerated().map {
            Time(id: "time-\($0.offset)", value: $0.element)
        }, budget: program.budget)
    }
}
