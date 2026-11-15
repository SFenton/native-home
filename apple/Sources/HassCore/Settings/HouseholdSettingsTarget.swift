import Foundation

/// One injected household command target, independent of the house configuration.
public struct HouseholdSettingsTarget: Equatable, Sendable {
    /// The authored kind choices.
    public enum Kind: Equatable, Sendable { case toggle, presence, powerRecovery, readOnly }
    /// The authored failure choices.
    public enum Failure: Error, Equatable { case invalidTarget, unavailable, stale }

    public let kind: Kind
    public let entityId: String
    public let title: String

    /// Validates a literal target before it can become a command source.
    public init(kind: Kind, entityId: String, title: String) throws {
        let pattern = "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$"
        let domain = String(entityId.prefix { $0 != "." })
        let permitted: Bool
        switch kind {
        case .toggle: permitted = ["input_boolean", "switch"].contains(domain)
        case .presence: permitted = domain == "switch"
        case .powerRecovery: permitted = domain == "automation"
        case .readOnly: permitted = true
        }
        guard entityId.utf16.count <= 160,
              entityId.range(of: pattern, options: .regularExpression) == entityId.startIndex..<entityId.endIndex,
              permitted, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf16.count <= 240 else { throw Failure.invalidTarget }
        self.kind = kind
        self.entityId = entityId
        self.title = title
    }
}

/// A bounded adapter for a single source. The controller and command remain alive while pending.
@MainActor
public final class HouseholdSettingsTargetAdapter {
    public let target: HouseholdSettingsTarget
    public let controller: HouseholdSettingsController

    /// Creates a household settings target adapter.
    public init(target: HouseholdSettingsTarget, store: EntityStore, caller: any HassServiceCalling,
                scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.target = target
        let targets = HouseholdSettingsController.Targets(
            toggleEntityIds: target.kind == .toggle ? [target.entityId] : [],
            presenceTitles: target.kind == .presence ? [target.entityId: target.title] : [:],
            powerRecoveryEntityId: target.kind == .powerRecovery ? target.entityId : nil)
        controller = HouseholdSettingsController(store: store, caller: caller, scheduler: scheduler, targets: targets)
    }

    private var key: String {
        target.kind == .presence ? HouseholdSettingsController.presenceKey(target.entityId) : target.entityId
    }

    /// Includes both the service lifetime and the optimistic confirmation lifetime.
    public var hasPendingIntent: Bool {
        controller.isExecuting(key) || controller.overlay.pending[key] != nil
    }

    /// Revalidates the face captured before a confirmation or gesture.
    public func flip(expected: HouseholdSettingsController.ToggleDisplay) throws {
        guard target.kind == .toggle else { throw HouseholdSettingsTarget.Failure.invalidTarget }
        let current = controller.toggle(target.entityId)
        guard !current.isUnavailable else { throw HouseholdSettingsTarget.Failure.unavailable }
        guard current == expected else { throw HouseholdSettingsTarget.Failure.stale }
        controller.flip(target.entityId, title: target.title)
    }

    /// Revalidates the shown presence mode before sending an explicitly selected mode.
    public func selectPresence(_ mode: PresenceOverrideState, expected: PresenceOverrideState) throws {
        guard target.kind == .presence, mode != .unavailable else { throw HouseholdSettingsTarget.Failure.invalidTarget }
        let current = controller.presence(target.entityId)
        guard current != .unavailable else { throw HouseholdSettingsTarget.Failure.unavailable }
        guard current == expected else { throw HouseholdSettingsTarget.Failure.stale }
        controller.setPresence(target.entityId, to: mode)
    }

    /// Runs the configured automation only when its entity is available.
    public func triggerPowerRecovery() throws {
        guard target.kind == .powerRecovery else { throw HouseholdSettingsTarget.Failure.invalidTarget }
        guard let entity = controller.store.entity(target.entityId).state, !entity.isUnavailable else {
            throw HouseholdSettingsTarget.Failure.unavailable
        }
        controller.triggerPowerRecovery()
    }
}
