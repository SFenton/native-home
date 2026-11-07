import Foundation
@preconcurrency import HAKit
import Observation

/// Reads and writes Home Assistant `schedule` helpers. ``HassConnection`` is the app's implementation; the gallery
/// and tests use in-memory ones.
@MainActor
public protocol HassScheduleStoring: AnyObject {
    /// `schedule/list`.
    func listSchedules() async throws -> [HassSchedule]
    /// `schedule/update` with `message` (its `type` is ignored); returns the saved schedule.
    func updateSchedule(_ message: [String: JSONValue]) async throws -> HassSchedule
    /// Whether the signed-in user is an administrator (only they may edit helpers).
    func userIsAdmin() async throws -> Bool
}

/// The humidifier's Schedules tab (web `useHumidifierScheduleController`): loads the activities from the
/// `schedule` helper, saves edits back, and turns scheduling on or off through its `input_boolean`.
@MainActor
@Observable
public final class HumidifierScheduleController {
    public let config: HumidifierConfig
    public let commands: RoomDeviceCommands

    public private(set) var rules: [HumidifierScheduleRule] = []
    public private(set) var loading = true
    public private(set) var saving = false
    public private(set) var error: String?
    /// Only administrators edit (web: `is_admin !== false`, so unknown counts as allowed).
    public private(set) var canEdit = true
    private var schedule: HassSchedule?

    @ObservationIgnored private let storage: any HassScheduleStoring

    /// Creates the controller and starts loading.
    public init(config: HumidifierConfig, store: EntityStore, caller: any HassServiceCalling, storage: any HassScheduleStoring,
                scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.config = config
        self.storage = storage
        commands = RoomDeviceCommands(store: store, caller: caller, rules: [config.scheduleEnabledEntityId: .confirmation],
                                      scheduler: scheduler)
    }

    // MARK: - State

    /// The helper was loaded, so activities can be added and saved.
    public var ready: Bool { schedule != nil }
    public var masterAvailable: Bool { !EntityState.isUnavailable(commands.entity(config.scheduleEnabledEntityId)?.state) }
    public var enabled: Bool { commands.displayed(config.scheduleEnabledEntityId) == "on" }
    public var scheduleActive: Bool { commands.entity(config.scheduleEntityId)?.state == "on" }
    public var vacationActive: Bool { commands.entity(config.vacationModeEntityId)?.state == "on" }
    public var activeRuleId: String? { commands.entity(config.scheduleEntityId)?.attributes["rule_id"]?.string }

    /// The rule running now, if any.
    public func isRunning(_ rule: HumidifierScheduleRule) -> Bool { scheduleActive && activeRuleId == rule.id }

    /// The scheduling switch's title.
    public var toggleTitle: String {
        if !masterAvailable { return "Scheduling Unavailable" }
        if vacationActive { return "Paused for Vacation" }
        return enabled ? "Scheduling On" : "Scheduling Paused"
    }

    /// The scheduling switch's subtitle.
    public var toggleSubtitle: String {
        if !masterAvailable { return "Home Assistant schedule control is unavailable" }
        if vacationActive { return "Vacation mode disables scheduled runs" }
        if scheduleActive { return "Activity running now" }
        if rules.isEmpty { return "Add an activity to enable scheduling" }
        return "\(rules.count) \(rules.count == 1 ? "activity" : "activities") configured"
    }

    /// The switch is locked: nothing to schedule, vacation, or no helper.
    public var toggleDisabled: Bool { !masterAvailable || rules.isEmpty || vacationActive }

    /// The rules the editor would save: `draft` replacing its original, or appended when new.
    public func rules(saving draft: HumidifierScheduleRule) -> [HumidifierScheduleRule] {
        rules.contains { $0.id == draft.id } ? rules.map { $0.id == draft.id ? draft : $0 } : rules + [draft]
    }

    /// The first overlap `draft` would cause.
    public func conflict(for draft: HumidifierScheduleRule) -> ScheduleConflict? {
        HumidifierSchedule.conflicts(in: rules(saving: draft)).first
    }

    // MARK: - Loading

    /// Loads the helper and the user's role. Safe to call again (pull to refresh).
    public func load() async {
        loading = true
        defer { loading = false }
        if let admin = try? await storage.userIsAdmin() { canEdit = admin }
        do {
            guard let found = try await storage.listSchedules().first(where: { $0.id == config.scheduleId }) else {
                error = "The humidifier schedule helper was not found."
                return
            }
            schedule = found
            rules = HumidifierSchedule.rules(from: found)
            error = nil
        } catch {
            self.error = "Could not load scheduled activities."
        }
    }

    // MARK: - Actions

    /// Turns scheduling on or off.
    public func toggleEnabled() {
        guard masterAvailable else { return }
        setEnabled(!enabled)
    }

    private func setEnabled(_ on: Bool) {
        commands.perform(ServiceCall("input_boolean", on ? "turn_on" : "turn_off", target: config.scheduleEnabledEntityId),
                         intents: [OptimisticIntent(config.scheduleEnabledEntityId, on ? "on" : "off", revertAfter: HumidifierController.revert)])
    }

    /// Saves `draft` (new or edited). Returns whether it saved.
    @discardableResult
    public func save(_ draft: HumidifierScheduleRule) async -> Bool {
        var draft = draft
        draft.label = draft.label.trimmingCharacters(in: .whitespaces)
        return await save(rules: rules(saving: draft))
    }

    /// Deletes the rule with `id`. Returns whether it saved.
    @discardableResult
    public func delete(_ id: String) async -> Bool {
        await save(rules: rules.filter { $0.id != id })
    }

    /// Clears the error line (opening the editor).
    public func clearError() { error = nil }

    /// Writes `next`, then turns scheduling on for the first activity or off when the last is removed (web `saveRules`).
    func save(rules next: [HumidifierScheduleRule]) async -> Bool {
        guard let schedule else { return false }
        if let conflict = HumidifierSchedule.conflicts(in: next).first {
            error = conflict.message
            return false
        }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let updated = try await storage.updateSchedule(HumidifierSchedule.updateMessage(schedule, rules: next))
            let hadRules = !rules.isEmpty
            self.schedule = updated
            rules = HumidifierSchedule.rules(from: updated)
            if !hadRules, !next.isEmpty, !enabled, !vacationActive, masterAvailable {
                setEnabled(true)
            } else if next.isEmpty, enabled, masterAvailable {
                setEnabled(false)
            }
            return true
        } catch {
            self.error = "Could not save scheduled activities."
            return false
        }
    }

    /// Waits for scheduling-switch calls (tests).
    public func waitForCalls() async { await commands.waitForCalls() }
}

// MARK: - Home Assistant

extension HassConnection: HassScheduleStoring {
    /// Error for a schedule response that isn't a schedule.
    public struct UnexpectedSchedule: Error, Equatable {}

    public func listSchedules() async throws -> [HassSchedule] {
        let result = try await requestJSON("schedule/list", data: [:])
        return (result.array ?? []).compactMap(HassSchedule.init(json:))
    }

    public func updateSchedule(_ message: [String: JSONValue]) async throws -> HassSchedule {
        var data = message
        data["type"] = nil
        guard let schedule = HassSchedule(json: try await requestJSON("schedule/update", data: data.mapValues(\.foundationValue))) else {
            throw UnexpectedSchedule()
        }
        return schedule
    }

    public func userIsAdmin() async throws -> Bool { try await currentUser().isAdmin }
}
