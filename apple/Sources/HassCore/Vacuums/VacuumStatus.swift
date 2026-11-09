import Foundation

// MARK: - Status contract

/// The typed status contract the Valetudo coordinator publishes as the status sensor's attributes
/// (web `vacuumStatus.ts`). Anything that fails validation falls back to the dashboard's own reading.
public struct VacuumStatusContract: Equatable, Sendable {
    public enum Availability: String, Sendable { case available, missing, unavailable, unknown }
    public enum PolicyMode: String, Sendable, Comparable {
        case normal, restricted, none

        /// `normal` < `restricted` < `none` (web `COMMAND_POLICY_RANK`).
        var rank: Int { self == .normal ? 0 : self == .restricted ? 1 : 2 }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
    }
    public enum IssueStatus: String, Sendable { case clear, present, unknown }

    /// The error the vacuum is reporting now.
    public struct Issue: Equatable, Sendable {
        public var code: String?
        public var raw: String?
        public var reportedAt: Date?
        public var status: IssueStatus

        public static let unknown = Issue(code: nil, raw: nil, reportedAt: nil, status: .unknown)
        public static let clear = Issue(code: nil, raw: nil, reportedAt: nil, status: .clear)
    }

    /// A Home Assistant condition that restricts commands (resume pending, vacuum-only fallback, …).
    public struct Condition: Equatable, Sendable {
        public enum Source: String, Sendable { case automation, coordinator, derived }
        public var code: String
        public var since: Date
        public var source: Source
    }

    /// The last error, kept after contact is lost.
    public struct LastIssue: Equatable, Sendable {
        public var clearedAt: Date?
        public var code: String
        public var raw: String
        public var reportedAt: Date
    }

    public var activeConditions: [Condition]
    public var availability: Availability
    public var policyMode: PolicyMode
    public var policyReason: String?
    public var currentIssue: Issue
    public var lastIssue: LastIssue?
    public var observedVacuumState: String?
    public var vacuumEntityId: String

    /// Parses and cross-checks the contract (`parseVacuumStatusContract`); `nil` when anything is off.
    public static func parse(_ attributes: [String: JSONValue]) -> VacuumStatusContract? {
        guard attributes["version"]?.number == 1,
              let vacuumId = attributes["vacuum_entity_id"]?.string, !vacuumId.trimmed.isEmpty else { return nil }
        let observed: String?
        switch attributes["observed_vacuum_state"] {
        case .null?: observed = nil
        case let .string(value)? where !value.trimmed.isEmpty: observed = value
        default: return nil
        }
        guard let availabilityObject = attributes["availability"],
              let availability = availabilityObject["status"]?.string.flatMap(Availability.init(rawValue:)),
              Self.nullableTimestamp(availabilityObject["since"]) != nil,
              let issue = parseIssue(attributes["current_issue"]),
              let conditionValues = attributes["active_conditions"]?.array,
              let policy = attributes["command_policy"],
              let mode = policy["mode"]?.string.flatMap(PolicyMode.init(rawValue:))
        else { return nil }
        let reason: String?
        switch policy["reason"] {
        case .null?: reason = nil
        case let .string(value)?: reason = value
        default: return nil
        }
        var conditions: [Condition] = []
        for value in conditionValues {
            guard let code = value["code"]?.string, !code.trimmed.isEmpty,
                  let source = value["source"]?.string.flatMap(Condition.Source.init(rawValue:)),
                  let since = value["since"]?.string.flatMap(VacuumDates.parse) else { return nil }
            conditions.append(.init(code: code, since: since, source: source))
        }
        var lastIssue: LastIssue?
        switch attributes["last_issue"] {
        case .null?: lastIssue = nil
        case let value?:
            guard let code = value["code"]?.string, !code.trimmed.isEmpty,
                  let raw = value["raw"]?.string, !raw.trimmed.isEmpty,
                  let reported = value["reported_at"]?.string.flatMap(VacuumDates.parse),
                  ["observed", "recorder_backfill"].contains(value["provenance"]?.string ?? "") else { return nil }
            var cleared: Date?
            if let clearedValue = value["cleared_at"], clearedValue != .null {
                guard let date = clearedValue.string.flatMap(VacuumDates.parse) else { return nil }
                cleared = date
            }
            lastIssue = .init(clearedAt: cleared, code: code, raw: raw, reportedAt: reported)
        case nil: return nil
        }

        // Cross-field rules.
        guard availability == VacuumStatusResolver.availability(observed, exists: observed != nil) else { return nil }
        if availability != .available && issue.status == .present { return nil }
        if availability != .available && mode != .none { return nil }
        if issue.status != .clear && mode == .normal { return nil }
        if !conditions.isEmpty && mode == .normal { return nil }

        return VacuumStatusContract(activeConditions: conditions, availability: availability, policyMode: mode,
                                    policyReason: reason, currentIssue: issue, lastIssue: lastIssue,
                                    observedVacuumState: observed, vacuumEntityId: vacuumId)
    }

    private static func parseIssue(_ value: JSONValue?) -> Issue? {
        guard let value, let status = value["status"]?.string.flatMap(IssueStatus.init(rawValue:)) else { return nil }
        if status == .present {
            guard let code = value["code"]?.string, !code.trimmed.isEmpty,
                  let raw = value["raw"]?.string, !raw.trimmed.isEmpty,
                  let reported = value["reported_at"]?.string.flatMap(VacuumDates.parse) else { return nil }
            return Issue(code: code, raw: raw, reportedAt: reported, status: .present)
        }
        for key in ["code", "raw", "reported_at"] where !(value[key] == nil || value[key] == .null) { return nil }
        return Issue(code: nil, raw: nil, reportedAt: nil, status: status)
    }

    /// `.some(nil)` for null, `.some(date)` for a timestamp, `nil` when invalid.
    private static func nullableTimestamp(_ value: JSONValue?) -> Date?? {
        switch value {
        case .null?: return .some(nil)
        case let .string(text)?: return VacuumDates.parse(text).map { .some($0) }
        default: return nil
        }
    }
}

// MARK: - Resolved status

/// What the dashboard believes about a vacuum after merging the contract with live entities
/// (web `useResolvedVacuumDetails`).
public struct ResolvedVacuumStatus: Equatable, Sendable {
    public var activeConditions: [VacuumStatusContract.Condition]
    public var availability: VacuumStatusContract.Availability
    public var policyMode: VacuumStatusContract.PolicyMode
    public var policyReason: String?
    public var currentIssue: VacuumStatusContract.Issue
    public var lastIssue: VacuumStatusContract.LastIssue?

    /// The vacuum entity reports a real state.
    public var primaryAvailable: Bool { availability == .available }
}

/// Pure status rules shared by the controller and tests.
public enum VacuumStatusResolver {
    /// Reason used when an entity the commands depend on is unreadable.
    public static let sourceUnreadableReason = "source_unreadable"

    static let normalCommandStates: Set<String> = ["docked", "idle"]
    static let busyDockStates: Set<String> = ["cleaning", "drying", "emptying", "error", "pause", "paused"]
    static let clearErrorStates: Set<String> = ["", "no error", "none", "ok"]

    /// `vacuumAvailabilityStatus`.
    public static func availability(_ state: String?, exists: Bool = true) -> VacuumStatusContract.Availability {
        guard exists else { return .missing }
        guard let state, !state.isEmpty, state != "unknown" else { return .unknown }
        return state == "unavailable" ? .unavailable : .available
    }

    /// The error sensor read as an issue (`nativeVacuumIssue`).
    public static func nativeIssue(_ state: String?) -> VacuumStatusContract.Issue {
        guard let state else { return .unknown }
        let raw = state.trimmed
        let normalized = raw.lowercased()
        if normalized == "unknown" || normalized == "unavailable" { return .unknown }
        if clearErrorStates.contains(normalized) { return .clear }
        let code = normalized.replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return .init(code: code, raw: raw, reportedAt: nil, status: .present)
    }

    /// Unknown, unavailable or missing.
    public static func isUnavailable(_ state: String?) -> Bool {
        let normalized = state?.trimmed.lowercased() ?? ""
        return normalized.isEmpty || normalized == "unavailable" || normalized == "unknown"
    }

    /// The live facts the resolver reads.
    public struct Inputs: Sendable {
        public var vacuumEntityId: String
        public var vacuumState: String?
        public var vacuumExists: Bool
        public var batteryState: String?
        public var errorState: String?
        public var statusFlagState: String?
        public var statusFlagChanged: Date?
        public var hasDockControls: Bool
        public var dockState: String?
        public var statusAttributes: [String: JSONValue]?

        public init(vacuumEntityId: String, vacuumState: String?, vacuumExists: Bool, batteryState: String?, errorState: String?,
                    statusFlagState: String?, statusFlagChanged: Date? = nil, hasDockControls: Bool, dockState: String?,
                    statusAttributes: [String: JSONValue]?) {
            self.vacuumEntityId = vacuumEntityId
            self.vacuumState = vacuumState
            self.vacuumExists = vacuumExists
            self.batteryState = batteryState
            self.errorState = errorState
            self.statusFlagState = statusFlagState
            self.statusFlagChanged = statusFlagChanged
            self.hasDockControls = hasDockControls
            self.dockState = dockState
            self.statusAttributes = statusAttributes
        }
    }

    /// Merges the contract with live entities; the most restrictive command policy wins.
    public static func resolve(_ input: Inputs) -> ResolvedVacuumStatus {
        let availability = availability(input.vacuumState, exists: input.vacuumExists)
        let primaryAvailable = availability == .available
        let native = nativeIssue(input.errorState)
        var contract = input.statusAttributes.flatMap(VacuumStatusContract.parse)
        if let parsed = contract, parsed.vacuumEntityId != input.vacuumEntityId || parsed.observedVacuumState != input.vacuumState {
            contract = nil // invalid or stale
        }
        let issue: VacuumStatusContract.Issue
        if !primaryAvailable { issue = .unknown }
        else if let contract { issue = coherentIssue(contract.currentIssue, native) }
        else { issue = native }

        var conditions = contract?.activeConditions ?? []
        if input.statusFlagState == "resumable", !conditions.contains(where: { $0.code == "vacuum.task_resume_pending" }) {
            conditions.append(.init(code: "vacuum.task_resume_pending", since: input.statusFlagChanged ?? .distantPast, source: .derived))
        }

        let readable = !isUnavailable(input.errorState) && !isUnavailable(input.statusFlagState)
            && !isUnavailable(input.batteryState) && Double(input.batteryState ?? "") != nil
            && (!input.hasDockControls || !isUnavailable(input.dockState))
        var mode = VacuumStatusContract.PolicyMode.normal
        var reason: String?
        if !primaryAvailable {
            mode = .none; reason = "primary_\(availability.rawValue)"
        } else if !readable {
            mode = .restricted; reason = sourceUnreadableReason
        } else if issue.status != .clear {
            mode = .restricted; reason = "current_issue"
        } else if let first = conditions.first {
            mode = .restricted; reason = first.code
        } else if !normalCommandStates.contains(input.vacuumState ?? "") {
            mode = .restricted; reason = "vacuum_\(input.vacuumState ?? "unknown")"
        } else if busyDockStates.contains(input.dockState ?? "") {
            mode = .restricted; reason = "dock_\(input.dockState ?? "")"
        }
        let contractMode = contract?.policyMode ?? .normal
        let finalMode = max(mode, contractMode)
        let finalReason = mode >= contractMode ? reason : contract?.policyReason

        let lastIssue = contract?.lastIssue.flatMap { $0.clearedAt == nil ? $0 : nil }
        return ResolvedVacuumStatus(activeConditions: conditions, availability: availability, policyMode: finalMode,
                                    policyReason: finalReason, currentIssue: issue, lastIssue: lastIssue)
    }

    static func coherentIssue(_ contract: VacuumStatusContract.Issue, _ native: VacuumStatusContract.Issue) -> VacuumStatusContract.Issue {
        if native.status == .unknown { return native }
        if contract.status == .present {
            return native.status == .present && contract.raw == native.raw ? contract : native
        }
        return contract.status == native.status ? contract : native
    }

    /// The text a condition notice shows (`conditionStatusText`).
    public static func conditionText(_ condition: VacuumStatusContract.Condition) -> String {
        let code = condition.code.lowercased()
        if code.contains("resume") { return "Kept for Later" }
        if code.contains("vacuum_only") || code.contains("fallback") { return "Vacuuming Only" }
        if code.contains("dock") { return "Docking May Be Incomplete" }
        let last = condition.code.split(separator: ".").last.map(String.init) ?? condition.code
        return StateText.titleCase(last.replacingOccurrences(of: "_", with: " "), empty: "")
    }
}

// MARK: - Runtime mode and tabs

/// Full shows cleaning setup; minimal shows only runtime actions (web `vacuumModalRuntime.ts`).
public enum VacuumRuntimeMode: String, Sendable { case full, minimal }

/// A tab in the vacuum sheet (`VACUUM_MODAL_TABS`, surfaceSemantics.ts:93).
public enum VacuumTab: String, CaseIterable, Identifiable, Sendable {
    case controls, zones, autoClean, more, info
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .controls: "Controls"
        case .zones: "Rooms"
        case .autoClean: "Auto-Clean"
        case .more: "Dock"
        case .info: "Info"
        }
    }

    /// The web's icon.
    public var icon: String {
        switch self {
        case .controls: "mdi:robot-vacuum"
        case .zones: "mdi:floor-plan"
        case .autoClean: "mdi:robot-vacuum-off"
        case .more: "mdi:flash"
        case .info: "mdi:information-outline"
        }
    }
}

public enum VacuumRuntime {
    /// `vacuumRuntimeMode`: full only when commands are normal and a clean can start.
    public static func mode(policy: VacuumStatusContract.PolicyMode, displayState: String, statusFlag: String?, error: String?) -> VacuumRuntimeMode {
        guard policy == .normal, statusFlag != "resumable" else { return .minimal }
        let lowBattery = error == "Low battery"
        return displayState == "docked" || displayState == "idle" || (displayState == "error" && !lowBattery) ? .full : .minimal
    }

    /// `vacuumModalTabsForMode`.
    public static func tabs(for vacuum: VacuumConfig, mode: VacuumRuntimeMode, dockState: String?) -> [VacuumTab] {
        let activeDock = dockState == "cleaning" || dockState == "drying"
        return VacuumTab.allCases.filter { tab in
            switch tab {
            case .controls: true
            case .zones: mode == .full && !vacuum.zones.isEmpty
            case .autoClean: !vacuum.autoCleanDisabledRooms.isEmpty
            case .more: mode == .full || (vacuum.dockControls != nil && activeDock)
            case .info: !vacuum.consumables.isEmpty
            }
        }
    }
}

// MARK: - Visuals

/// Tone of a status pill or tile.
public enum VacuumTone: String, Sendable { case active, danger, neutral, ok, returning, unavailable, warning }

/// Icon and tone for a vacuum state (`vacuumStateVisual`).
public struct VacuumVisual: Equatable, Sendable {
    public var icon: String
    public var tone: VacuumTone

    public static func state(_ state: String?) -> VacuumVisual {
        if VacuumStatusResolver.isUnavailable(state) { return .init(icon: "mdi:robot-vacuum-off", tone: .unavailable) }
        switch state?.trimmed.lowercased() {
        case "cleaning": return .init(icon: "mdi:broom", tone: .active)
        case "docked": return .init(icon: "mdi:home", tone: .ok)
        case "error": return .init(icon: "mdi:alert-circle", tone: .danger)
        case "paused": return .init(icon: "mdi:pause-circle", tone: .warning)
        case "returning": return .init(icon: "mdi:home-import-outline", tone: .returning)
        default: return .init(icon: "mdi:robot-vacuum", tone: .neutral)
        }
    }

    /// Dock status (`dockStatusVisual`).
    public static func dock(_ state: String?) -> VacuumVisual {
        switch state {
        case "cleaning": .init(icon: "mdi:water", tone: .active)
        case "drying": .init(icon: "mdi:weather-windy", tone: .active)
        case "emptying": .init(icon: "mdi:delete-restore", tone: .warning)
        case "pause": .init(icon: "mdi:pause", tone: .warning)
        case "error": .init(icon: "mdi:alert-circle", tone: .danger)
        default: .init(icon: "mdi:home", tone: VacuumStatusResolver.isUnavailable(state) ? .unavailable : .neutral)
        }
    }

    /// Minutes at or below which a consumable warns (`VACUUM_CONSUMABLE_WARNING_MINUTES`).
    public static let consumableWarningMinutes = 600.0

    /// A consumable's icon and tone (`vacuumConsumableVisual`).
    public static func consumable(_ consumable: VacuumConfig.Consumable, state: String?) -> VacuumVisual {
        if VacuumStatusResolver.isUnavailable(state) { return .init(icon: "mdi:help-circle-outline", tone: .unavailable) }
        if consumable.valueKind == .status {
            return state?.trimmed.lowercased() == "ok" ? .init(icon: consumable.icon, tone: .ok) : .init(icon: "mdi:alert-circle", tone: .warning)
        }
        guard let minutes = state.flatMap(Double.init) else { return .init(icon: consumable.icon, tone: .neutral) }
        if minutes <= 0 { return .init(icon: "mdi:wrench-clock", tone: .danger) }
        if minutes <= consumableWarningMinutes { return .init(icon: "mdi:timer-alert-outline", tone: .warning) }
        return .init(icon: consumable.icon, tone: .neutral)
    }
}

// MARK: - Formatting

public enum VacuumFormat {
    /// The robot's own error text in words a person can act on; text without a friendly form reads as it came. The
    /// Live Activity's problem card words the same codes ("Can't reach its room"), so the sheet and the card agree.
    public static func issue(_ raw: String) -> String {
        switch raw.trimmed.lowercased() {
        case "cannot reach target", "can't reach target", "unable to reach target", "target unreachable":
            "Can't reach its room. A door may be closed. Open it, then tap Resume."
        default: raw
        }
    }

    /// A state for display (`formatStateValue`).
    public static func state(_ value: String?, fallback: String = "Unavailable") -> String {
        guard let value, !value.isEmpty else { return fallback }
        if value == "unknown" { return "Unknown" }
        if value == "unavailable" { return "Unavailable" }
        return StateText.titleCase(value)
    }

    /// The tile subtitle: `Docked • 87%` (`vacuumTilePresentation`).
    public static func tileSubtitle(state: String?, battery: String?) -> String {
        let normalized = state?.trimmed.lowercased() ?? ""
        let label = StateText.titleCase(normalized.isEmpty ? "unavailable" : normalized)
        guard !VacuumStatusResolver.isUnavailable(normalized), let battery = battery?.trimmed, let value = Double(battery) else { return label }
        return "\(label) • \(number(value))%"
    }

    /// Passes as `2x` (`formatPassCount`).
    public static func passes(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "1x" }
        return Double(value).map { "\(number($0))x" } ?? state(value)
    }

    /// A consumable's value: `12h left`, `Due`, `OK` (`formatConsumableValue`).
    public static func consumable(_ consumable: VacuumConfig.Consumable, state: String?, unit: String?) -> String {
        guard let state, !VacuumStatusResolver.isUnavailable(state) else { return "Unknown" }
        if consumable.valueKind == .status {
            let value = self.state(state)
            return value.lowercased() == "ok" ? "OK" : value
        }
        guard let minutes = Double(state) else { return unit.map { "\(state) \($0)" } ?? state }
        if minutes <= 0 { return "Due" }
        if minutes < 60 { return "\(Int(minutes.rounded()))m left" }
        let hours = minutes / 60
        let rounded = hours < 10 ? (hours * 10).rounded() / 10 : hours.rounded()
        return "\(number(rounded))h left"
    }

    /// A length in metres: `1.25 m`, `2 m` (`formatAreaLength`).
    public static func metres(_ centimetres: Double) -> String {
        let metres = centimetres / 100
        if metres == metres.rounded() { return "\(Int(metres)) m" }
        var text = String(format: "%.2f", metres)
        if text.hasSuffix("0") { text.removeLast() }
        return "\(text) m"
    }

    /// An integer when whole, else one decimal.
    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// ISO 8601 parsing that accepts fractional seconds.
enum VacuumDates {
    static func parse(_ text: String) -> Date? { HassDates.iso8601(text) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
