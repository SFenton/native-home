import Foundation

/// One job's content (`aps.content-state`, contract v2, `.agents/platforms/apple/live-activities-per-job.md` §3). Home
/// Assistant's `fenton_home` engine composes it; the app writes it locally only for the optimistic pending state after a
/// button, and for a failure notice.
///
/// Keys are snake_case through explicit `CodingKeys`, and times are Unix seconds as doubles. A Phase 1 payload
/// (`"v": 1`, a `jobs` list) still decodes, by taking its focused job (``init(from:)``).
public struct HomeActivityState: Codable, Hashable, Sendable {
    /// The content-state schema this build writes.
    public static let currentVersion = 2
    /// Buttons at most on a job card (HIG: one or two essential controls).
    public static let maxControls = 2
    /// Buttons at most on a problem card (Resume, Dock, Done).
    public static let maxProblemControls = 3
    /// `headline` at most.
    public static let maxHeadlineLength = 32
    /// `detail` at most.
    public static let maxDetailLength = 32
    /// `notice` at most.
    public static let maxNoticeLength = 60
    /// `short` at most: the one word the compact island shows when a card has no time.
    public static let maxShortLength = 10
    /// Apple's limit for the whole push, static and dynamic attributes together.
    public static let maxPayloadBytes = 4096

    /// The schema version (`v`).
    public var version: Int
    /// Where the job is.
    public var phase: JobPhase
    /// Overrides the title line ("Vacuuming Kitchen"); nil shows the attribute `title`.
    public var headline: String?
    /// The small line under the title (the hot flash card: "Your side", "Whole bed", "Your side · by Sam"). nil for every
    /// other job.
    public var detail: String?
    /// The big figure. nil on a vacuum card, whose big line is the ``headline``.
    public var value: ActivityValue?
    /// The compact island's trailing word when the card has no time ("Kitchen", "Paused", "Area"), at most
    /// ``maxShortLength`` characters. nil when the card has a time.
    public var short: String?
    /// 0…1; drives the ring when there is no time range, and a ``ActivityValue/Kind/percent`` value.
    public var progress: Double?
    /// Up to ``maxControls`` buttons (``maxProblemControls`` on a problem card).
    public var controls: [ActivityControl]
    /// The problem, present exactly when ``phase`` is ``JobPhase/problem``.
    public var problem: ActivityProblem?
    /// A pressed control Home Assistant has not confirmed. Written only by the app.
    public var pending: ActivityPending?
    /// A one-update message in place of the value ("Couldn't reach Home").
    public var notice: String?
    /// Where a tap goes: a dashboard path read like a notification's `url` (`PushLink`).
    public var url: String?

    /// Creates a state.
    public init(version: Int = HomeActivityState.currentVersion, phase: JobPhase = .running, headline: String? = nil,
                detail: String? = nil, value: ActivityValue? = nil, short: String? = nil, progress: Double? = nil,
                controls: [ActivityControl] = [], problem: ActivityProblem? = nil, pending: ActivityPending? = nil,
                notice: String? = nil, url: String? = nil) {
        self.version = version
        self.phase = phase
        self.headline = headline
        self.detail = detail
        self.value = value
        self.short = short
        self.progress = progress
        self.controls = controls
        self.problem = problem
        self.pending = pending
        self.notice = notice
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case phase, headline, detail, value, short, progress, controls, problem, pending, notice, url
        // Phase 1 (v1) only.
        case jobs, focus
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let declared = try container.decodeIfPresent(Int.self, forKey: .version)
        if declared == 1 || (declared == nil && container.contains(.jobs)) {
            let jobs = try container.decodeIfPresent([LegacyJob].self, forKey: .jobs) ?? []
            let focus = try container.decodeIfPresent(String.self, forKey: .focus)
            let url = try container.decodeIfPresent(String.self, forKey: .url)
            self = LegacyJob.state(focusing: focus, in: jobs, url: url)
            return
        }
        version = declared ?? Self.currentVersion
        phase = try container.decodeIfPresent(JobPhase.self, forKey: .phase) ?? .running
        headline = try container.decodeIfPresent(String.self, forKey: .headline)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        value = try container.decodeIfPresent(ActivityValue.self, forKey: .value)
        short = try container.decodeIfPresent(String.self, forKey: .short)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        controls = try container.decodeIfPresent([ActivityControl].self, forKey: .controls) ?? []
        problem = try container.decodeIfPresent(ActivityProblem.self, forKey: .problem)
        pending = try container.decodeIfPresent(ActivityPending.self, forKey: .pending)
        notice = try container.decodeIfPresent(String.self, forKey: .notice)
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(phase, forKey: .phase)
        try container.encodeIfPresent(headline, forKey: .headline)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(short, forKey: .short)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encode(controls, forKey: .controls)
        try container.encodeIfPresent(problem, forKey: .problem)
        try container.encodeIfPresent(pending, forKey: .pending)
        try container.encodeIfPresent(notice, forKey: .notice)
        try container.encodeIfPresent(url, forKey: .url)
    }

    // MARK: - Changing (the app's own writes)

    /// The state right after a control press: the buttons give way to `label` ("Stopping…") until Home Assistant
    /// confirms. `sinceTs` is whole seconds (``ActivityClock/wholeSecond(_:)``).
    public func awaiting(control: String, now: Date) -> HomeActivityState {
        var copy = self
        copy.notice = nil
        copy.pending = ActivityPending(control: control, label: ActivityPending.label(forControl: control),
                                       sinceTs: ActivityClock.wholeSecond(now).timeIntervalSince1970)
        return copy
    }

    /// The state with no pending press and a one-update message, after a press that could not reach Home Assistant.
    public func failing(notice: String) -> HomeActivityState {
        var copy = self
        copy.pending = nil
        copy.notice = notice
        return copy
    }

    /// Whether the state offers a control with this id.
    public func offers(control id: String) -> Bool { controls.contains { $0.id == id } }

    // MARK: - Budget

    /// The state trimmed to the wire budget: strings capped (headline 32, short 10, problem 40, message 90, chip 20, value text 16),
    /// controls at most 2 (3 on a problem card), chips at most 1.
    public func fitted() -> HomeActivityState {
        var copy = self
        copy.headline = headline.map { Self.truncated($0, to: Self.maxHeadlineLength) }
        copy.detail = detail.map { Self.truncated($0, to: Self.maxDetailLength) }
        copy.notice = notice.map { Self.truncated($0, to: Self.maxNoticeLength) }
        copy.short = short.map { Self.truncated($0, to: Self.maxShortLength) }
        if var value = copy.value {
            value.text = value.text.map { Self.truncated($0, to: ActivityValue.maxTextLength) }
            copy.value = value
        }
        if var problem = copy.problem {
            problem.problem = Self.truncated(problem.problem, to: ActivityProblem.maxProblemLength)
            problem.message = Self.truncated(problem.message, to: ActivityProblem.maxMessageLength)
            problem.chips = problem.chips.prefix(ActivityProblem.maxChips).map { Self.truncated($0, to: ActivityProblem.maxChipLength) }
            copy.problem = problem
        }
        copy.controls = Array(controls.prefix(problem == nil ? Self.maxControls : Self.maxProblemControls))
        return copy
    }

    /// `text` cut to `limit` characters, ending in an ellipsis when it was cut.
    public static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }

    /// The JSON bytes of this state, as ActivityKit sends it.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Decodes a state the way ActivityKit does (a default `JSONDecoder`, no custom strategies).
    public static func decode(_ data: Data) throws -> HomeActivityState {
        try JSONDecoder().decode(HomeActivityState.self, from: data)
    }
}
