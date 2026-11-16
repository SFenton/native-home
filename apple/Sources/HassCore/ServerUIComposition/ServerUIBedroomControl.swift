import Foundation

// MARK: - Bedroom atoms

/// Narrow bedroom controls, composed by the shell rather than dispatching a feature screen.
public struct ServerUIBedroomControl: Equatable, Sendable {
    /// The authored mode family choices.
    public enum ModeFamily: String, Sendable { case neutral, lights, cooling, heating }
    /// The authored provider kind choices.
    public enum ProviderKind: String, CaseIterable, Sendable {
        case bed = "bed-side", wake = "wake-light"
        case bedDraft = "bed-alarm-draft", wakeDraft = "wake-alarm-draft"
    }

    /// The authored kind choices.
    public enum Kind: String, CaseIterable, Sendable {
        case target = "bed-target", power = "bed-power", stage = "bed-stage", mode = "bed-mode"
        case reading = "bed-reading", snooze = "bed-snooze", stop = "bed-stop"
        case wakeRamp = "wake-ramp", wakeHold = "wake-hold", wakeStop = "wake-stop"
        case wakeSummary = "wake-summary"
        case weekdays = "alarm-weekdays", time = "alarm-time", enabled = "alarm-enabled"
        case wakeLink = "alarm-wake-link", name = "alarm-name", alarmKind = "alarm-kind"
        case date = "alarm-date", ramp = "alarm-ramp", save = "alarm-save"
        case delete = "alarm-delete", reload = "alarm-reload"
        case bedTile = "bed-tile", wakeTile = "wake-tile", bedTarget = "alarm-bed-target"
        case addAlarm = "alarm-add"
        case feedback = "alarm-feedback"

        public var capability: String { "sh.\(rawValue)@1" }
        public var providers: [ProviderKind] {
            switch self {
            case .target, .power, .stage, .mode, .reading, .snooze, .stop, .bedTile: [.bed]
            case .wakeRamp, .wakeHold, .wakeStop, .wakeTile, .wakeSummary: [.wake]
            case .wakeLink: [.bedDraft]
            case .name, .alarmKind, .date, .ramp, .reload, .bedTarget: [.wakeDraft]
            case .weekdays, .time, .enabled, .save, .delete, .feedback: [.bedDraft, .wakeDraft]
            case .addAlarm: [.bed, .wake]
            }
        }
        public var usesOptions: Bool {
            [.wakeRamp, .wakeHold, .weekdays, .alarmKind, .ramp].contains(self)
        }
        public var usesConfirmation: Bool { self == .power || self == .delete }
        public var usesScope: Bool { self == .target || self == .stage }
        public var usesNavigation: Bool { [.bedTile, .wakeTile, .addAlarm].contains(self) }
    }

    /// The authored option.
    public struct Option: Equatable, Sendable {
        public let value: String
        public let label: String
        public var accessibilityLabel: String? = nil
    }

    /// Confirmation and scope copy is authored, but their required semantics cannot be removed.
    public struct Question: Equatable, Sendable {
        /// The authored message format choices.
        public enum MessageFormat: String, Sendable { case wakeAlarm = "wake-alarm" }
        public let title: String
        public let message: String
        public let confirmLabel: String
        public let cancelLabel: String
        public var messageFormat: MessageFormat? = nil

        /// Only negotiated wake-alarm messages substitute the two closed, presentation-only fields.
        public func message(for alarm: WakeLight.Alarm) -> String {
            guard messageFormat == .wakeAlarm else { return message }
            return message.replacingOccurrences(of: "{time}", with: WakeLight.displayTime(alarm.localTime))
                .replacingOccurrences(of: "{schedule}", with: WakeLight.scheduleLabel(alarm))
        }
    }
    /// The authored scope.
    public struct Scope: Equatable, Sendable {
        public let title: String
        public let message: String
        public let tonightLabel: String
        public let allNightsLabel: String
        public let cancelLabel: String
    }
    /// Optional complete active-episode presentation; omission retains the standalone Stop button.
    public struct Episode: Equatable, Sendable {
        public let heading: String
        public let detail: String
        public let pendingLabel: String
    }

    public let node: ServerUICompositionDocument.Node
    public let sourceId: String
    public let kind: Kind
    public let label: String
    public let unavailableText: String
    public let activeLabel: String?
    public let inactiveLabel: String?
    public let countdownSuffix: String?
    public let parameter: String?
    public let options: [Option]
    public let confirmation: Question?
    public let scope: Scope?
    public let icon: ServerUICompositionDocument.Symbol?
    public let family: ModeFamily?
    public var action: ServerUICompositionDocument.Action? = nil
    public var showsExplanation: Bool = false
    public var episode: Episode? = nil
    public var showsHeading = false

    /// Closed parameter and choice vocabularies shared with Studio's compiler.
    public static let readings = ["current-temperature", "pump-status", "loop-temperature", "pump-rpm", "heart-rate", "breathing", "hrv"]
    static func allowedOptions(_ kind: Kind) -> [String] {
        switch kind {
        case .weekdays: Weekday.allCases.map(\.rawValue)
        case .alarmKind: WakeLight.Kind.allCases.map(\.rawValue)
        case .wakeHold: WakeLight.holdMinutes.map(String.init)
        case .wakeRamp, .ramp: WakeLight.rampMinutes.map(String.init)
        default: []
        }
    }

    public static var capabilities: [String] {
        ["sh.bedroom-sources@1", "sh.wake-hold-explanation@1", "sh.wake-episode@1",
         "sh.bedroom-field-headings@1", "sh.weekday-accessibility-labels@1",
         "sh.wake-alarm-confirmation@1"] + Kind.allCases.map(\.capability)
    }
}
