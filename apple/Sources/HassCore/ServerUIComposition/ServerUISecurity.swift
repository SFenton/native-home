import Foundation

// MARK: - Configured security values

extension ServerUICompositionDocument {
    /// Ordered, authored mode buttons. Services and mandatory Disarm confirmation are not authorable.
    public struct AlarmModeControl: Equatable, Sendable {
        public let state: String
        public let label: String
        public let hint: String
        public let icon: Symbol
        public let fill: TileFill
    }

    /// The authored security confirmation.
    public struct SecurityConfirmation: Equatable, Sendable {
        public let title: String
        public let message: String
        public let confirmLabel: String
        public let cancelLabel: String

        public var spec: TileActionSpec.Confirmation {
            .init(title: title, message: message, confirmVerb: confirmLabel)
        }
    }

    /// Pure panel composition, shared by a page, a sheet and a modal-local pushed page.
    public struct AlarmPanel: Equatable, Sendable {
        public let node: Node
        public let sourceId: String
        public let modes: [AlarmModeControl]
        public let states: [AlarmStateAppearance]
        public let fallback: AlarmAppearance
        public let subtitle: String
        public let sincePrefix: String
        public let separator: String
        public let loadingText: String
        public let unavailableText: String
        public let hiddenText: String
        public let errorText: String
        public let pendingText: String
        public let confirmation: SecurityConfirmation
        public let triggeredWash: TileFill
    }

    /// The authored door kind choices.
    public enum DoorKind: String, Sendable { case lock, garage }
    /// The authored door state appearance.
    public struct DoorStateAppearance: Equatable, Sendable {
        public let state: String
        public let appearance: AlarmAppearance
        public let active: Bool
        public let error: Bool
    }
}

// MARK: - Non-authorable command policy

/// Canonical alarm commands with injected targets. Downloaded copy cannot weaken confirmation or select a service.
public enum ServerUISecurity {
    public static let modeServices = [
        "disarmed": "alarm_disarm", "armed_home": "alarm_arm_home",
        "armed_away": "alarm_arm_away", "armed_night": "alarm_arm_night"
    ]

    /// The alarm mode to show for the live entity and the selected mode.
    public static func alarmMode(entityID: String, live: EntityState?, selected: String,
                                 confirmation: TileActionSpec.Confirmation) -> TileActionSpec? {
        guard let service = modeServices[selected] else { return nil }
        let unavailable = EntityState.isUnavailable(live?.state)
        return .init(id: selected, verb: selected, symbol: "shield",
                     phase: unavailable ? .unavailable : .ready, feedback: .optimistic,
                     call: ServiceCall("alarm_control_panel", service, target: entityID),
                     optimistic: [OptimisticIntent(entityID, value: selected)],
                     confirmation: selected == "disarmed" ? confirmation : nil)
    }
}
