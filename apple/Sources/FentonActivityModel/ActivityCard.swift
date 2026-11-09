import Foundation

/// What one activity shows, decided once from its attributes and content so every surface (Lock Screen, the three
/// island presentations, StandBy, the Smart Stack) agrees and the rules are tested without drawing
/// (`.agents/platforms/apple/live-activities-per-job.md` §8).
///
/// The views only translate a card into pixels. They add no rule of their own.
public struct ActivityCard: Equatable, Sendable {
    // MARK: - Types

    /// The card's layout.
    public enum Style: Equatable, Sendable {
        /// The job card: a ring, the title, the big figure and up to two buttons.
        case job
        /// The problem card: a severity circle, the problem and an instruction, and up to three buttons.
        case problem(ActivityProblem.Severity)
    }

    /// The big figure.
    public enum Figure: Equatable, Sendable {
        /// A live countdown (`Text(timerInterval:)`). `showsHours` is `H:MM:SS` rather than `MM:SS`.
        case countdown(ClosedRange<Date>, showsHours: Bool, estimated: Bool)
        /// A live count-up from the date (`Text(_:style: .timer)`).
        case countup(Date)
        /// A paused count-up, frozen at this many seconds.
        case frozen(seconds: Int)
        /// A percentage.
        case percent(Int)
        /// A word or two ("Cooling", "Starts 5:10 PM").
        case text(String)
        /// A finished job: **Complete**.
        case complete
        /// Nothing to show.
        case none
    }

    /// The ring around the glyph.
    public enum Ring: Equatable, Sendable {
        /// Fills itself as time passes (`ProgressView(timerInterval:)`).
        case timer(ClosedRange<Date>)
        /// A reported fraction, 0…1.
        case fraction(Double)
        /// A full ring that does not move (count-ups).
        case steady
        /// The empty track alone (no time range and no progress).
        case track
        /// A finished job: a filled ring with a check.
        case complete
    }

    /// One button, with the order and role the card draws it in.
    public struct Button: Equatable, Identifiable, Sendable {
        /// The control.
        public var control: ActivityControl
        /// A white pill (the first control, or one the engine marked primary) rather than a dark one.
        public var isPrimary: Bool
        /// What VoiceOver reads: "Stop Guest Bath Fan".
        public var accessibilityLabel: String
        /// The glyph of a vacuum's 44 pt round icon button (Pause, Resume, Dock); nil for a text pill.
        public var icon: Icon?

        public var id: String { control.id }

        /// A round icon button's glyph.
        public enum Icon: Equatable, Sendable {
            case pause, play, dock
        }
    }

    /// The thin bar under the value: a time range that fills itself, a reported fraction, or a finished job's full bar.
    public enum Bar: Equatable, Sendable {
        case timer(ClosedRange<Date>)
        case fraction(Double)
        case full
    }

    /// What the compact island's trailing side holds (spec §8a). A time gets a rigid width (``compactTemplate(hours:)``) so
    /// the island stays compact; a word is capped at ``compactLabelWidth``.
    public enum CompactTrailing: Equatable, Sendable {
        /// A live time, drawn over a hidden template of this text ("00:00" or "0:00:00").
        case timer(template: String)
        /// A word: the card's `short`, a percentage, or a text value.
        case label(String)
        /// A problem's one word ("Stuck").
        case problem(String)
        /// A finished job's check.
        case complete
        /// Nothing.
        case none
    }

    /// The widest a compact word grows, in points.
    public static let compactLabelWidth: Double = 56

    /// The hidden text whose width the compact island's time takes: "0:00:00" from an hour on, else "00:00".
    public static func compactTemplate(hours: Bool) -> String { hours ? "0:00:00" : "00:00" }

    // MARK: - Inputs

    /// The activity's static attributes.
    public let attributes: HomeActivityAttributes
    /// Its content.
    public let state: HomeActivityState
    /// Past its stale date (`context.isStale`). A stale pending state gives the buttons back.
    public let isStale: Bool
    /// Where "left" and "for" count from; the views pass `Date()`.
    public let now: Date

    /// Creates a card.
    public init(attributes: HomeActivityAttributes, state: HomeActivityState, isStale: Bool = false, now: Date = Date()) {
        self.attributes = attributes
        self.state = state
        self.isStale = isStale
        self.now = now
    }

    // MARK: - Identity

    /// The activity's tag, which the buttons carry.
    public var tag: String { attributes.tag }
    /// The device ("Main Floor Vacuum").
    public var deviceTitle: String { attributes.title }
    /// The title line. It is the device ("Main Floor Vacuum"), except for an older engine's card that has both a time and a
    /// headline, which the headline still names.
    public var title: String {
        guard let headline = state.headline, !headline.isEmpty, figure != .none else { return attributes.title }
        return headline
    }
    /// A card with no `value` shows its `headline` as the big line under the title ("Vacuuming Kitchen", "Paused in
    /// Kitchen"), in white even when paused (spec §8a). nil when the card has a figure, is complete, or sent no headline.
    public var bigLine: String? {
        guard figure == .none, let headline = state.headline, !headline.isEmpty else { return nil }
        return headline
    }
    /// The small line beside the title (the hot flash card), or nil.
    public var detail: String? { state.detail.flatMap { $0.isEmpty ? nil : $0 } }
    /// The Lock Screen's first line: the title, then ` · ` and the detail when there is one ("Hot Flash · Your side").
    public var headerLine: String {
        guard let detail else { return title }
        return "\(title) · \(detail)"
    }
    /// The one word the compact island shows when the card has no time, or nil.
    public var short: String? { state.short.flatMap { $0.isEmpty ? nil : $0 } }
    /// The device glyph.
    public var glyph: ActivityGlyph { attributes.glyph }
    /// The `ColorFamily` raw value that tints the card.
    public var tint: String { attributes.tint }
    /// The layout.
    public var style: Style {
        if state.phase == .problem, let problem = state.problem { return .problem(problem.severity) }
        return .job
    }
    /// The problem, when the card is a problem card.
    public var problem: ActivityProblem? {
        if case .problem = style { return state.problem }
        return nil
    }
    /// Paused: the ring dims and the time stops.
    public var isPaused: Bool { state.phase == .paused }
    /// Finished: a filled ring, a check and **Complete**.
    public var isComplete: Bool { state.phase == .done }

    // MARK: - Pending

    /// "Stopping…" in place of the buttons while a press waits for Home Assistant; nil once the state is stale.
    public var pendingLabel: String? {
        guard let pending = state.pending, !isStale else { return nil }
        return pending.label
    }

    /// A press that never got an answer: the stale date passed with a pending state, so the buttons are back with
    /// "Not confirmed" (§7.4).
    public var isUnconfirmed: Bool { state.pending != nil && isStale }

    /// The line shown in place of the figure for one update ("Couldn't reach Home", "Couldn't stop. Try again."), or nil.
    public var notice: String? { state.notice.flatMap { $0.isEmpty ? nil : $0 } }

    /// The small line beside the buttons when a press is unconfirmed.
    public static let unconfirmedText = "Not confirmed"

    // MARK: - Controls

    /// The buttons to draw, in order. None while a press is pending, none on a finished card, and at most two on a job
    /// card (three on a problem card, whose last is Done).
    public var buttons: [Button] {
        if pendingLabel != nil || isComplete { return [] }
        let limit = problem == nil ? HomeActivityState.maxControls : HomeActivityState.maxProblemControls
        return state.controls.prefix(limit).enumerated().map { index, control in
            Button(control: control, isPrimary: index == 0 || control.role == .primary,
                   accessibilityLabel: "\(control.title) \(attributes.title)", icon: icon(for: control))
        }
    }

    /// A vacuum's job card draws Pause, Resume and Dock as round icon buttons; everything else is a text pill.
    private func icon(for control: ActivityControl) -> Button.Icon? {
        guard style == .job, glyph == .vacuum else { return nil }
        switch control.id {
        case "pause": return .pause
        case "resume": return .play
        case "dock": return .dock
        default: return nil
        }
    }

    /// The buttons the island's bottom region shows: the first two.
    public var islandButtons: [Button] { Array(buttons.prefix(HomeActivityState.maxControls)) }

    // MARK: - Figure and ring

    /// The big figure.
    public var figure: Figure {
        if isComplete { return .complete }
        guard let value = state.value else { return .none }
        switch value.kind {
        case .countdown:
            guard let range = value.countdownRange(now: now) else { return .none }
            return .countdown(range, showsHours: range.upperBound.timeIntervalSince(now) >= 3600, estimated: value.estimated)
        case .countup:
            if isPaused {
                // The engine freezes the time with `paused_elapsed_s`; without it the time so far stands in.
                let elapsed = value.pausedElapsedS ?? value.startDate.map { now.timeIntervalSince($0) }
                return elapsed.map { .frozen(seconds: Int(max(0, $0).rounded(.down))) } ?? .none
            }
            guard let start = value.startDate else { return .none }
            return .countup(start)
        case .percent:
            guard let progress = state.progress else { return .none }
            return .percent(Int((min(max(progress, 0), 1) * 100).rounded()))
        case .text:
            guard let text = value.text, !text.isEmpty else { return .none }
            return .text(text)
        }
    }

    /// The ring.
    public var ring: Ring {
        if isComplete { return .complete }
        let value = state.value
        if !isPaused, let range = value?.ringRange { return .timer(range) }
        if value?.kind == .countup { return .steady }
        if let progress = state.progress { return .fraction(min(max(progress, 0), 1)) }
        return .track
    }

    /// The 5 pt bar under the value, only when the card has progress: a countdown, a percentage, a reported fraction, or a
    /// finished job's full bar. Count-ups and cards with no value have none.
    public var bar: Bar? {
        switch ring {
        case let .timer(range): .timer(range)
        case let .fraction(value): .fraction(value)
        case .complete: .full
        case .steady, .track: nil
        }
    }

    /// Whether the glyph sits in a ring (the compact and minimal island, the Smart Stack). A card with no time and no
    /// progress draws its glyph alone.
    public var showsRing: Bool { ring != .track }

    // MARK: - Island

    /// What the compact island's trailing side holds.
    public var compactTrailing: CompactTrailing {
        if let problem { return .problem(problem.compactLabel) }
        switch figure {
        case .complete: return .complete
        case let .countdown(_, showsHours, _): return .timer(template: Self.compactTemplate(hours: showsHours))
        // A count-up gets no push while it runs, so it always takes the wide template: a dryer passes an hour unseen.
        case .countup: return .timer(template: Self.compactTemplate(hours: true))
        case let .frozen(seconds): return .timer(template: Self.compactTemplate(hours: seconds >= 3600))
        case let .percent(value): return .label(short ?? "\(value)%")
        case let .text(text): return .label(short ?? text)
        case .none: return short.map { CompactTrailing.label($0) } ?? CompactTrailing.none
        }
    }

    // MARK: - Speech

    /// The title as VoiceOver reads it, with the words that make the figure beside it a sentence:
    /// "Dryer, running for" before a count-up, "Dryer, about" before an estimate, "Main Floor Vacuum, paused at" before a
    /// frozen time. The figure itself stays a live `Text`, so the combined element reads the current time.
    public var spokenTitle: String {
        switch figure {
        case .countup: "\(headerLine), running for"
        case .frozen: "\(headerLine), paused at"
        case let .countdown(_, _, estimated): estimated ? "\(headerLine), about" : "\(headerLine), time left"
        default: headerLine
        }
    }

    /// The whole card as one phrase for contexts that cannot hold a live `Text` (the island, the Smart Stack). A problem
    /// card reads "Main Floor Vacuum, needs help: Stuck in Kitchen. Move it somewhere flat, then tap Resume."
    public var spokenSummary: String {
        if let problem {
            var parts = ["\(attributes.title), \(problem.severity.spokenPhrase): \(problem.problem). \(problem.message)"]
            parts.append(contentsOf: problem.chips)
            return parts.joined(separator: ", ")
        }
        var parts = [title]
        if let detail { parts.append(detail) }
        if let bigLine { parts.append(bigLine) }
        if let phrase = spokenFigure { parts.append(phrase) }
        return parts.joined(separator: ", ")
    }

    /// The figure as a phrase: "4 minutes left", "running for 12 minutes", "62 percent", "complete".
    public var spokenFigure: String? {
        switch figure {
        case let .countdown(range, _, estimated):
            let phrase = Self.spokenRemaining(until: range.upperBound, now: now)
            return estimated ? "about " + phrase : phrase
        case let .countup(start): return "running for " + Self.spokenDuration(now.timeIntervalSince(start))
        case let .frozen(seconds): return "paused at " + Self.spokenDuration(Double(seconds))
        case let .percent(value): return "\(value) percent"
        case let .text(text): return text
        case .complete: return "complete"
        case .none: return nil
        }
    }

    /// "42 minutes left", "1 hour 5 minutes left", "less than a minute left", or "done" once past.
    public static func spokenRemaining(until end: Date, now: Date) -> String {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return "done" }
        return spokenDuration(seconds, roundingUp: true) + " left"
    }

    /// "12 minutes", "1 hour 5 minutes", "less than a minute".
    public static func spokenDuration(_ seconds: Double, roundingUp: Bool = false) -> String {
        let total = Int((roundingUp ? seconds.rounded(.up) : seconds.rounded(.down)))
        guard total >= 60 else { return "less than a minute" }
        let minutes = roundingUp ? (total + 59) / 60 : total / 60
        let hours = minutes / 60, rest = minutes % 60
        func unit(_ value: Int, _ word: String) -> String { "\(value) \(word)\(value == 1 ? "" : "s")" }
        if hours == 0 { return unit(minutes, "minute") }
        return rest == 0 ? unit(hours, "hour") : unit(hours, "hour") + " " + unit(rest, "minute")
    }

    /// `seconds` as a clock: "12:40", or "1:04:42" from an hour on.
    public static func clock(seconds: Int) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3600, minutes = seconds % 3600 / 60, rest = seconds % 60
        let pair = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "\(hours):\(pair(minutes)):\(pair(rest))" : "\(minutes):\(pair(rest))"
    }
}
