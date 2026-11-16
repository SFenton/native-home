import Foundation
import Observation

// MARK: - Retained editor session

/// Domain-owned alarm draft. Shell owns routing/focus/discard UI; canonical controllers own every command.
@MainActor
@Observable
public final class ServerUIBedroomDraft {
    /// The authored value choices.
    public enum Value: Equatable, Sendable {
        case bed(BedSideController.AlarmDraft)
        case wake(WakeLight.Alarm)
    }

    public private(set) var value: Value
    public private(set) var busy = false
    public private(set) var completed = false
    public private(set) var error: String?
    private var initial: Value
    /// Whether this visit creates a new alarm; controls use it for creation-only fields.
    public let isNew: Bool
    @ObservationIgnored private let validate: (Value) -> [String]
    @ObservationIgnored private let available: () -> Bool
    @ObservationIgnored private let deleteAllowed: (Value) -> Bool
    @ObservationIgnored private let saveCommand: (Value) async -> Bool
    @ObservationIgnored private let deleteCommand: (Value) async -> Bool
    @ObservationIgnored private let latest: () -> Value?
    @ObservationIgnored private let pending: () -> Bool
    @ObservationIgnored private let commandError: () -> String?
    @ObservationIgnored private let reloadRequired: (Value) -> Bool
    @ObservationIgnored private var targetProvider: () -> [BedroomDevices.BedTarget] = { [] }
    public var bedTargets: [BedroomDevices.BedTarget] { targetProvider() }

    public var dirty: Bool {
        if case .wake(let current) = value, case .wake(let opened) = initial { return !current.sameEdits(as: opened) }
        return value != initial
    }
    public var protectsPublication: Bool { busy || dirty || (isNew && !completed) || pending() }
    /// An untouched creation pins publication while open, but leaving it discards no user edits.
    public var blocksExit: Bool { !completed && (busy || dirty || pending()) }
    public var canDiscard: Bool { !busy && !pending() }
    public var problems: [String] { validate(value) }
    public var canSave: Bool { !busy && !completed && available() && problems.isEmpty && (dirty || isNew) }
    public var canDelete: Bool { !busy && !completed && !isNew && available() && deleteAllowed(value) }
    /// Explicit draft failures take precedence over the canonical controller's current error.
    public var feedbackError: String? { error ?? commandError() }
    /// An explicit replacement must remain reachable whenever stale-state validation blocks saving.
    public var needsReload: Bool { reloadRequired(value) }

    /// Destructive wake copy describes the opened alarm, not unsaved field edits.
    public var openedWakeAlarm: WakeLight.Alarm? {
        if case .wake(let alarm) = initial { return alarm }
        return nil
    }

    /// The opened alarm's title, unchanged by typing; an explicit reload adopts the latest name.
    public var presentationTitle: String {
        switch initial {
        case .bed(let alarm): alarm.title
        case .wake(let alarm): isNew ? "Add Wake Alarm" : alarm.label
        }
    }

    private init(value: Value, isNew: Bool, validate: @escaping (Value) -> [String],
                 available: @escaping () -> Bool, deleteAllowed: @escaping (Value) -> Bool, save: @escaping (Value) async -> Bool,
                 delete: @escaping (Value) async -> Bool, latest: @escaping () -> Value?, pending: @escaping () -> Bool,
                 commandError: @escaping () -> String? = { nil }, reloadRequired: @escaping (Value) -> Bool = { _ in false }) {
        self.value = value
        initial = value
        self.isNew = isNew
        self.validate = validate
        self.available = available
        self.deleteAllowed = deleteAllowed
        saveCommand = save
        deleteCommand = delete
        self.latest = latest
        self.pending = pending
        self.commandError = commandError
        self.reloadRequired = reloadRequired
    }

    /// A bed editor preserves wake-link-first saving and the side controller's full schedule ownership.
    public static func bed(controller: BedSideController, wake: WakeLightController,
                           draft: BedSideController.AlarmDraft) -> ServerUIBedroomDraft {
        .init(value: .bed(draft), isNew: draft.editingId == nil, validate: {
            guard case .bed(let draft) = $0 else { return ["Wrong alarm draft type."] }
            return controller.problems(draft)
        }, available: { controller.alarmsEditable && !wake.configurationPending }, deleteAllowed: {
            guard case .bed(let draft) = $0 else { return false }
            return draft.editingId != nil && !controller.isStale(draft)
        }, save: {
            guard case .bed(let draft) = $0 else { return false }
            return await controller.save(draft, wakeLight: wake)
        }, delete: {
            guard case .bed(let draft) = $0 else { return false }
            return await controller.delete(draft, wakeLight: wake)
        }, latest: { nil }, pending: { controller.hasPendingCommands || wake.hasPendingCommands })
    }

    /// `save` is the canonical room's saveWakeAlarm closure, including Add-to-bed provisioning.
    public static func wake(controller: WakeLightController, alarm: WakeLight.Alarm, isNew: Bool,
                            bedTargets: @escaping () -> [BedroomDevices.BedTarget] = { [] },
                            save: @escaping (WakeLight.Alarm) async -> Bool) -> ServerUIBedroomDraft {
        let draft = ServerUIBedroomDraft(value: .wake(alarm), isNew: isNew, validate: {
            guard case .wake(let alarm) = $0 else { return ["Wrong alarm draft type."] }
            var problems = WakeLight.problems(alarm)
            if controller.requiresAlarmReload || (!isNew && !isCurrent(alarm, controller: controller)) {
                problems.append("This alarm changed. Open the latest alarm to replace the draft.")
            }
            if isNew && !Set(alarm.bedSides).isSubset(of: Set(bedTargets().filter(\.available).map(\.side))) {
                problems.append("A selected bed is unavailable. Review Add to Bed.")
            }
            return problems
        }, available: { controller.canEdit && controller.live.available && !controller.configurationPending }, deleteAllowed: {
            guard case .wake(let alarm) = $0 else { return false }
            return isCurrent(alarm, controller: controller)
        }, save: {
            guard case .wake(let alarm) = $0 else { return false }
            return await save(alarm)
        }, delete: {
            guard case .wake(let alarm) = $0 else { return false }
            return await controller.delete(alarmId: alarm.id)
        }, latest: {
            guard let latest = controller.live.alarms.first(where: { $0.id == alarm.id }) else { return nil }
            controller.clearError()
            return .wake(latest)
        }, pending: { controller.hasPendingCommands }, commandError: { controller.error }, reloadRequired: {
            guard !isNew, case .wake(let alarm) = $0 else { return false }
            return !isCurrent(alarm, controller: controller)
        })
        draft.targetProvider = bedTargets
        return draft
    }

    private static func isCurrent(_ alarm: WakeLight.Alarm, controller: WakeLightController) -> Bool {
        !controller.requiresAlarmReload && controller.live.alarms.first(where: { $0.id == alarm.id })?.revision == alarm.revision
    }

    // MARK: - Pinned commands

    /// Input changes never mutate an in-flight command or turn a provider into another draft kind.
    public func update(_ change: (inout Value) -> Void) {
        guard !busy, !completed else { error = "Wait for the current alarm operation to finish."; return }
        var next = value
        change(&next)
        switch (value, next) {
        case (.bed, .bed), (.wake, .wake): value = next; error = nil
        default: error = "Wrong alarm draft type."
        }
    }

    /// Captures the draft before suspension. Failed saves retain it rather than closing the editor.
    @discardableResult
    public func save() async -> Bool {
        guard canSave else { error = problems.first ?? "Alarm cannot be saved right now."; return false }
        let captured = value
        busy = true
        error = nil
        let result = await saveCommand(captured)
        busy = false
        if result { initial = captured; completed = true }
        else { error = commandError() ?? "Home Assistant did not save the alarm. Your draft is retained." }
        return result
    }

    /// The confirmation ticket is the complete draft, rechecked immediately before deletion.
    @discardableResult
    public func delete(confirming ticket: Value) async -> Bool {
        guard canDelete, ticket == value else { error = "The alarm changed. Review it before deleting."; return false }
        busy = true
        error = nil
        let result = await deleteCommand(ticket)
        busy = false
        if result { initial = ticket; completed = true }
        else { error = commandError() ?? "Home Assistant did not delete the alarm. Your draft is retained." }
        return result
    }

    /// Explicit replacement only; an echo or publication never overwrites a draft.
    @discardableResult
    public func reload() -> Bool {
        guard !busy, !completed, let current = latest() else { error = "The latest alarm is unavailable."; return false }
        value = current
        initial = current
        error = nil
        return true
    }

    /// Completes an untouched departure or the shell's explicit discard decision; live commands remain protected.
    @discardableResult
    public func discard() -> Bool {
        guard canDiscard else { error = "Wait for the current alarm operation to finish."; return false }
        value = initial
        completed = true
        error = nil
        return true
    }
}
