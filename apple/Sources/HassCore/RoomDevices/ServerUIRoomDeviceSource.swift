import Foundation
import Observation

// MARK: - Typed source and intent adapter

/// One injected device model. It retains canonical controllers rather than approximating their calls.
@MainActor
@Observable
public final class ServerUIRoomDeviceSource {
    /// The authored controller choices.
    public enum Controller {
        case purifier(AirPurifierController), fan(BathroomFanController), grill(GrillController), humidifier(HumidifierController)
    }
    /// The authored intent choices.
    public enum Intent: Equatable, Sendable {
        case choose(String), number(Double), setOn(Bool), startTimer(Int), cancelTimer
    }
    /// The authored failure choices.
    public enum Failure: Error, Equatable { case unavailable, busy, invalidIntent, scheduleUnavailable, notAdministrator, staleConfirmation }

    public let descriptor: ServerUIRoomDeviceDescriptor
    public let controller: Controller
    public let schedules: HumidifierScheduleController?
    public private(set) var schedulesLoadRequested = false
    private var schedulesLoading = false
    @ObservationIgnored private let store: EntityStore

    /// Creates a server uiroom device source.
    public init(descriptor: ServerUIRoomDeviceDescriptor, store: EntityStore, caller: any HassServiceCalling,
                storage: (any HassScheduleStoring)? = nil, scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.descriptor = descriptor
        self.store = store
        switch descriptor {
        case .purifier(let config):
            controller = .purifier(AirPurifierController(config: config, store: store, caller: caller, scheduler: scheduler))
            schedules = nil
        case .fan(let config):
            controller = .fan(BathroomFanController(config: config, store: store, caller: caller, scheduler: scheduler))
            schedules = nil
        case .grill(let config):
            controller = .grill(GrillController(config: config, store: store, caller: caller, scheduler: scheduler))
            schedules = nil
        case .humidifier(let config):
            controller = .humidifier(HumidifierController(config: config, store: store, caller: caller, scheduler: scheduler))
            schedules = storage.map { HumidifierScheduleController(config: config, store: store, caller: caller, storage: $0, scheduler: scheduler) }
        }
    }

    public var commands: RoomDeviceCommands {
        switch controller {
        case .purifier(let model): model.commands
        case .fan(let model): model.commands
        case .grill(let model): model.commands
        case .humidifier(let model): model.commands
        }
    }
    public var hasPendingIntent: Bool {
        commands.hasPendingIntent || schedules?.saving == true || schedules?.commands.hasPendingIntent == true
    }
    /// Domain formatting only; the owning status atom supplies its authored appearance and unavailable copy.
    public var stateText: String {
        switch controller {
        case .purifier(let model): model.summary
        case .fan(let model): model.tileStatusText(at: Date())
        case .grill(let model): model.stateText
        case .humidifier(let model): model.subtitle
        }
    }
    public var isUnavailable: Bool {
        switch controller {
        case .purifier(let model): model.modeUnavailable && model.fanUnavailable && model.autoModeUnavailable
        case .fan(let model): !model.powerAvailable
        case .grill(let model): EntityState.isUnavailable(model.commands.entity(model.config.stateEntityId)?.state)
        case .humidifier(let model): model.isUnavailable
        }
    }

    /// Missing individual sensors must not inherit the controller's legacy OK/Off display defaults.
    public func infoItem(_ info: ServerUIRoomDeviceControl.Info) -> HumidifierController.InfoItem? {
        guard case .humidifier(let model) = controller else { return nil }
        let targets: [String]
        let numeric: Bool
        switch info {
        case .output: targets = [model.config.powerEntityId, model.config.humidifyingEntityId, model.config.tankRemovedEntityId, model.config.waterLowEntityId]; numeric = false
        case .water: targets = [model.config.waterLowEntityId]; numeric = false
        case .tank: targets = [model.config.tankRemovedEntityId]; numeric = false
        case .mode: targets = [model.config.modeEntityId]; numeric = false
        case .display: targets = [model.config.displayEntityId]; numeric = false
        case .warm: targets = [model.config.warmLevelEntityId]; numeric = true
        case .humidity: targets = [model.config.currentHumidityEntityId]; numeric = true
        case .temperature: targets = [model.config.currentTemperatureEntityId]; numeric = true
        case .mist: targets = [model.config.mistLevelEntityId, model.config.powerEntityId]; numeric = false
        case .timer: targets = [model.config.timerRemainingEntityId]; numeric = true
        }
        guard targets.allSatisfy({ !EntityState.isUnavailable(commands.entity($0)?.state) }),
              !numeric || targets.allSatisfy({ DeviceState.number(commands.entity($0)) != nil }) else { return nil }
        if info == .mist, DeviceState.number(commands.entity(model.config.mistLevelEntityId)) == nil { return nil }
        if info == .mode, commands.entity(model.config.modeEntityId).flatMap({ HumidifierMode(rawValue: $0.state) }) == nil { return nil }
        let items = model.deviceItems + model.environmentItems
        guard let index = ServerUIRoomDeviceControl.Info.allCases.firstIndex(of: info), items.indices.contains(index) else { return nil }
        return items[index]
    }

    /// Rechecks the current entity boxes, capability and value at gesture time.
    public func perform(_ kind: ServerUIRoomDeviceControl.Kind, intent: Intent, detailEntityId: String? = nil) throws {
        guard kind.model == descriptor.model else { throw Failure.invalidIntent }
        guard !hasPendingIntent else { throw Failure.busy }
        func available(_ id: String) throws {
            guard !EntityState.isUnavailable(store.entity(id).state?.state) else { throw Failure.unavailable }
        }
        switch (controller, kind, intent) {
        case let (.purifier(model), .purifierMode, .choose(value)),
             let (.purifier(model), .purifierAuto, .choose(value)):
            let auto = kind == .purifierAuto
            let target = auto ? model.config.autoModeEntityId : model.config.modeEntityId
            try available(target)
            guard !auto || model.showsAutoModes,
                  let option = (auto ? AirPurifierController.autoModes : AirPurifierController.fanModes).first(where: { $0.value == value }) else {
                throw Failure.invalidIntent
            }
            if let values = store.entity(target).state?.attributes["options"]?.array,
               !values.contains(.string(value)) { throw Failure.unavailable }
            if auto { model.selectAutoMode(option) } else { model.selectMode(option) }
        case let (.purifier(model), .purifierSpeed, .choose(value)):
            try available(model.config.fanEntityId)
            guard model.showsSpeeds, let option = AirPurifierController.speeds.first(where: { $0.value == value }) else { throw Failure.invalidIntent }
            model.selectSpeed(option)
        case let (.fan(model), .fanPower, .setOn(on)):
            try available(model.config.powerEntityId); model.setPower(on)
        case let (.fan(model), .fanLock, .setOn(on)):
            guard model.lockAvailable else { throw Failure.unavailable }
            model.setLocked(on)
        case let (.fan(model), .fanTimer, .startTimer(minutes)):
            guard model.canStartTimer else { throw Failure.unavailable }
            guard BathroomFanController.timerMinutes.contains(minutes) else { throw Failure.invalidIntent }
            model.selectedMinutes = minutes
            model.startTimer()
        case let (.fan(model), .fanTimer, .cancelTimer):
            guard model.timerAvailable, model.timerPending else { throw Failure.unavailable }
            model.cancelTimer()
        case let (.grill(model), .grillDetail, .setOn(on)):
            guard let detail = model.config.details.first(where: { $0.entityId == detailEntityId }), detail.isSwitch else { throw Failure.invalidIntent }
            guard model.display(detail).isActionable else { throw Failure.unavailable }
            if model.display(detail).isActive != on { model.toggle(detail) }
        case let (.humidifier(model), .humidifierPower, .setOn(on)):
            guard model.canTogglePower else { throw Failure.unavailable }
            if model.powerOn != on { model.togglePower() }
        case let (.humidifier(model), .humidifierDisplay, .setOn(on)):
            try available(model.config.displayEntityId)
            guard !model.isBlocked, !model.isSleep, model.powerOn else { throw Failure.unavailable }
            model.setDisplay(on)
        case let (.humidifier(model), .humidifierMode, .choose(value)):
            try available(model.config.modeEntityId)
            guard !model.isBlocked else { throw Failure.unavailable }
            guard let mode = HumidifierMode(rawValue: value) else { throw Failure.invalidIntent }
            if let values = store.entity(model.config.modeEntityId).state?.attributes["options"]?.array,
               !values.contains(.string(value)) { throw Failure.unavailable }
            model.setMode(mode)
        case let (.humidifier(model), .humidifierPresets, .choose(value)):
            guard let level = Int(value), (1...9).contains(level), String(level) == value else { throw Failure.invalidIntent }
            try available(model.config.mistLevelEntityId)
            guard model.canSetLevel else { throw Failure.unavailable }
            model.setLevel(level)
        case let (.humidifier(model), .humidifierWarm, .choose(value)):
            guard let level = Int(value), (0...3).contains(level), String(level) == value else { throw Failure.invalidIntent }
            try available(model.config.warmLevelEntityId)
            guard !model.isBlocked, !model.isSleep else { throw Failure.unavailable }
            model.setWarmLevel(level)
        case let (.humidifier(model), .humidifierMist, .number(value)):
            guard value.isFinite, (0...9).contains(value) else { throw Failure.invalidIntent }
            try available(model.config.mistLevelEntityId)
            guard model.canSetLevel else { throw Failure.unavailable }
            model.setLevel(Int(value.rounded()))
        case let (.humidifier(model), .humidifierTarget, .number(value)):
            guard value.isFinite, (40...80).contains(value) else { throw Failure.invalidIntent }
            try available(model.config.targetHumidityEntityId)
            guard !model.isBlocked, model.mode == .targetHumidity else { throw Failure.unavailable }
            model.setTargetHumidity(value)
        case let (.humidifier(model), .humidifierTimer, .number(value)):
            guard value.isFinite, (0...720).contains(value) else { throw Failure.invalidIntent }
            try available(model.config.timerMinutesEntityId)
            guard !model.isBlocked, model.powerOn else { throw Failure.unavailable }
            model.setTimerMinutes(Int(value.rounded()))
        case let (.humidifier, .humidifierScheduling, .setOn(on)):
            guard let schedules, !schedules.loading, schedules.ready, !schedules.toggleDisabled else { throw Failure.scheduleUnavailable }
            if schedules.enabled != on { schedules.toggleEnabled() }
        default: throw Failure.invalidIntent
        }
    }

    /// Explicit load; the parent injects the shared connection as schedule storage.
    public func loadSchedules() async throws {
        guard let schedules else { throw Failure.scheduleUnavailable }
        guard !schedulesLoading else { throw Failure.busy }
        schedulesLoadRequested = true
        schedulesLoading = true
        defer { schedulesLoading = false }
        await schedules.load()
        guard schedules.error == nil else { throw Failure.scheduleUnavailable }
    }

    /// The immutable deletion question is tied to a source and exact rule, not a row index.
    public struct DeleteTicket: Equatable, Sendable {
        public let descriptor: ServerUIRoomDeviceDescriptor
        public let rule: HumidifierScheduleRule
    }
    /// A ticket that confirms deleting the entry with this id.
    public func deletion(for id: String) throws -> DeleteTicket {
        guard let schedules, schedules.ready, !schedules.loading else { throw Failure.scheduleUnavailable }
        guard schedules.roleVerified, schedules.canEdit else { throw Failure.notAdministrator }
        guard !hasPendingIntent else { throw Failure.busy }
        guard let rule = schedules.rules.first(where: { $0.id == id }) else { throw Failure.staleConfirmation }
        return DeleteTicket(descriptor: descriptor, rule: rule)
    }
    /// Deletes the entry the ticket names.
    public func delete(_ ticket: DeleteTicket) async throws {
        guard descriptor == ticket.descriptor, try deletion(for: ticket.rule.id) == ticket else { throw Failure.staleConfirmation }
        guard let schedules, await schedules.delete(ticket.rule.id) else { throw Failure.scheduleUnavailable }
    }
}

// MARK: - Domain draft (Shell owns focus, route and dismissal)

/// An activity edit bound to one retained source. Save failure leaves the draft and last-good rules intact.
@MainActor
@Observable
public final class ServerUIHumidifierActivityDraft {
    public let source: ServerUIRoomDeviceSource
    public let initial: HumidifierScheduleRule
    public let isNew: Bool
    public var value: HumidifierScheduleRule {
        didSet {
            if value.mode == .sleep, value.display { value.display = false }
        }
    }
    public private(set) var error: String?

    init(source: ServerUIRoomDeviceSource, rule: HumidifierScheduleRule, isNew: Bool) {
        self.source = source
        initial = rule
        value = rule
        self.isNew = isNew
    }

    public var isDirty: Bool { value != initial }
    public var isBusy: Bool { source.hasPendingIntent }
    public var conflict: ScheduleConflict? { source.schedules?.conflict(for: value) }
    public var canSave: Bool {
        guard let schedules = source.schedules, schedules.ready, !schedules.loading, schedules.roleVerified, schedules.canEdit else { return false }
        let current = schedules.rules.first { $0.id == initial.id }
        return !isBusy && value.id == initial.id && (isNew ? current == nil : current == initial)
            && value.isComplete && value.label.count <= 40 && Set(value.days).count == value.days.count
            && (1...9).contains(value.mistLevel) && (40...80).contains(value.targetHumidity)
            && value.targetHumidity % 5 == 0 && (0...3).contains(value.warmLevel) && conflict == nil
    }

    /// Saves the draft to Home Assistant.
    @discardableResult
    public func save() async -> Bool {
        guard canSave, let schedules = source.schedules else {
            error = "This activity cannot be saved. Check permissions, fields and schedule conflicts."
            return false
        }
        let snapshot = value
        guard await schedules.save(snapshot) else {
            error = schedules.error ?? "Could not save scheduled activities."
            return false
        }
        error = nil
        return true
    }
}
