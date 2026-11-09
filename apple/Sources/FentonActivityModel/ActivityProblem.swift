import Foundation

/// A device problem (`problem` on the wire, `.agents/platforms/apple/live-activities-per-job.md` §5). Present exactly
/// when the phase is ``JobPhase/problem``. The engine words every string ("problems.py"), so new wording ships with a
/// relay update and not an app release.
public struct ActivityProblem: Codable, Hashable, Sendable {
    /// Red stopped and needs a person (the update alerts with sound); amber carries on but needs attention (silent).
    public enum Severity: String, Codable, Hashable, Sendable {
        case critical, warning

        /// An unknown severity reads as ``warning``, the one that never alarms.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Severity(rawValue: raw) ?? .warning
        }

        /// What the island's trailing region says: "Needs help" or "Attention".
        public var islandLabel: String { self == .critical ? "Needs help" : "Attention" }
        /// The two-word state the problem card prints beside its shape, so severity is never colour alone:
        /// "Needs help" (stopped) or "Needs attention" (carries on).
        public var stateLabel: String { self == .critical ? "Needs help" : "Needs attention" }
        /// What VoiceOver says before the problem: "needs help" or "needs attention".
        public var spokenPhrase: String { self == .critical ? "needs help" : "needs attention" }
    }

    /// Characters kept: the problem line.
    public static let maxProblemLength = 40
    /// Characters kept: the instruction.
    public static let maxMessageLength = 90
    /// Characters kept: a chip.
    public static let maxChipLength = 20
    /// Chips at most.
    public static let maxChips = 1

    /// The severity.
    public var severity: Severity
    /// The issue code (`navigation.stuck`, `vendor.unknown_error_88`, `unmapped.wheel_suspended`).
    public var code: String
    /// The glyph id from the problem set (``ActivityGlyph/problemSet``).
    public var icon: String
    /// The problem in one short line ("Stuck in Kitchen").
    public var problem: String
    /// What to do, as an instruction ("Move it somewhere flat, then tap Resume.").
    public var message: String
    /// At most one chip ("Error 88"); never for a known code.
    public var chips: [String]
    /// The Donetick task behind the problem. Present ⇔ the card lives until the task closes and carries a Done button.
    public var taskId: String?

    /// Creates a problem.
    public init(severity: Severity, code: String, icon: String, problem: String, message: String, chips: [String] = [], taskId: String? = nil) {
        self.severity = severity
        self.code = code
        self.icon = icon
        self.problem = problem
        self.message = message
        self.chips = chips
        self.taskId = taskId
    }

    private enum CodingKeys: String, CodingKey {
        case severity, code, icon, problem, message, chips
        case taskId = "task_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .warning
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        problem = try container.decodeIfPresent(String.self, forKey: .problem) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        chips = try container.decodeIfPresent([String].self, forKey: .chips) ?? []
        // Donetick ids are numbers; the wire may carry one as a string or as a JSON integer.
        if let text = (try? container.decodeIfPresent(String.self, forKey: .taskId)) ?? nil {
            taskId = text
        } else if let number = (try? container.decodeIfPresent(Int.self, forKey: .taskId)) ?? nil {
            taskId = String(number)
        } else {
            taskId = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(severity, forKey: .severity)
        try container.encode(code, forKey: .code)
        try container.encode(icon, forKey: .icon)
        try container.encode(problem, forKey: .problem)
        try container.encode(message, forKey: .message)
        if !chips.isEmpty { try container.encode(chips, forKey: .chips) }
        try container.encodeIfPresent(taskId, forKey: .taskId)
    }

    /// The glyph in the severity circle.
    public var glyph: ActivityGlyph { ActivityGlyph(wire: icon) }

    /// The one word the compact island shows beside the severity circle ("Stuck", "Refill water"). The wire has no
    /// field for it, so a known code maps here and anything else reads "Help" (critical) or "Check" (warning).
    public var compactLabel: String {
        switch code {
        case "navigation.stuck": "Stuck"
        case "navigation.target_unreachable": "Blocked"
        case "navigation.dock_unreachable": "No dock"
        case "navigation.ramp_hazard": "Edge"
        case "maintenance.main_brush_jammed", "maintenance.side_brush_jammed": "Brush"
        case "power.critical_battery", "power.low_battery": "Battery"
        case "mop.clean_water_empty": "Refill water"
        case "mop.dirty_water_unavailable": "Empty tank"
        case "mop.attachment_missing": "No mop"
        case "dock.cover_open": "Cover open"
        case "dock.dustbag_blocked": "Dust bag"
        default: severity == .critical ? "Help" : "Check"
        }
    }

    /// Whether a person can complete the task from the card (the Done button).
    public var hasTask: Bool { taskId?.isEmpty == false }
}
