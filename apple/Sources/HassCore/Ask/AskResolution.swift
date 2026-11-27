import Foundation

// MARK: - Route

/// Where a question goes, decided in code. The raw values are the names the eval scorer reads.
public enum AskRoute: String, Codable, Sendable, CaseIterable {
    /// One entity.
    case found
    /// A clear set of entities answered together (a room, a plural, a floor, a pair).
    case group
    /// A singular name that matches several things: ask which.
    case several
    /// Nothing in the home matches what was named.
    case none
    /// The thing or set exists in Home Assistant, or is a set no one has defined, but the configuration does not cover it.
    /// Answered with a fixed "not set up" sentence; its state is never read.
    case notConfigured = "not_configured"
    /// An action request: the answerer only reads.
    case declineAction = "decline_action"
    /// Not about the home.
    case declineOfftopic = "decline_offtopic"
    /// The one entity asked about reports unavailable or unknown.
    case unavailable
}

/// What a question asks about.
public enum AskQuestionType: String, Codable, Sendable, CaseIterable {
    case state, value
    case howLong = "how_long"
    case why
    case lastTime = "last_time"
    case room, aggregate, comparison, people, automation, media, compound
}

// MARK: - Intent

/// The state a yes/no question asks about ("is it *on*", "is it *open*").
public enum AskPredicate: String, Codable, Sendable {
    case on, off, open, closed, locked, unlocked, home, away, playing, notPlaying, occupied, clear, running, recording, detected, enabled, disabled
}

/// How a comparison ranks its subjects.
public enum AskComparisonKind: String, Codable, Sendable {
    /// Higher temperature wins ("warmer", "hotter", "warmest").
    case warmer
    /// Lower temperature wins.
    case colder
    /// Higher humidity wins.
    case humid
    /// Lower humidity wins.
    case dry
    /// The longest time in the current state.
    case longest
    /// The difference between two readings.
    case difference
}

/// What the words of a question ask for, apart from which entities they name.
public struct AskIntent: Sendable, Equatable {
    /// "why", "who turned", "what caused".
    public var wantsWhy = false
    /// "how long", "since when".
    public var wantsHowLong = false
    /// "when ... last".
    public var wantsLast = false
    /// "how many".
    public var wantsCount = false
    /// "which", "what is on", "list".
    public var wantsWhich = false
    /// "any", "is there".
    public var wantsAny = false
    /// "all", "both", "everything", "every".
    public var wantsAll = false
    /// "today".
    public var today = false
    /// A reading rather than a state ("how warm", "what is the humidity").
    public var wantsValue = false
    /// A ranking or a pair.
    public var comparison: AskComparisonKind?
    /// A ranking over every room ("the coolest room"), not a pair.
    public var superlative = false
    /// "in" against "out" in a comparison ("warmer inside than outside").
    public var inOut = false
    /// The state a yes/no question asks about.
    public var predicate: AskPredicate?
    /// Whether the question reads as a yes/no question.
    public var yesNo = false
    /// A question about a person ("who is home", "when did Sam leave").
    public var leaving = false
    /// "What is on in the office": the answer is the entities that are on, not the whole room.
    public var whatsOn = false
    /// An indefinite article before the kind ("did I leave a door open"): any of them.
    public var indefinite = false
    /// Whether the speaker said the state was negative ("is it still off", "isn't it closed").
    public var negated = false
    /// The quantity a reading or ranking is about ("how warm" is temperature).
    public var valueKind: AskKind?
    /// Whether the question asks about the people of the household ("who is home", "are we all home").
    public var household = false

    /// Creates an empty intent.
    public init() {}
}

// MARK: - Parts and resolution

/// What one noun phrase of the question resolved to.
public struct AskPart: Sendable, Equatable {
    /// How the phrase resolved.
    public enum Kind: String, Sendable { case found, group, several, none, notConfigured }

    /// The speaker's words for it.
    public var phrase: String
    /// How it resolved.
    public var kind: Kind
    /// The entities it resolved to (found, group), in a stable order.
    public var entityIds: [String]
    /// The candidates a `several` part asks the speaker to choose between.
    public var candidateIds: [String]
    /// The scope a group came from, with its title for speech.
    public var scope: AskScope?
    /// The title of the room or floor the scope names.
    public var scopeTitle: String?
    /// The kind of entity a group collects.
    public var entityKind: AskKind?
    /// The ids to report as the answer's targets when they differ from ``entityIds`` (a "what is on" question reports only what is on).
    public var reportedIds: [String]?
    /// The entity the name ranking would have picked had the security margin not asked "which one?" instead (for evaluation only).
    public var guardedPick: String?

    /// Creates a part.
    public init(
        phrase: String, kind: Kind, entityIds: [String] = [], candidateIds: [String] = [], scope: AskScope? = nil,
        scopeTitle: String? = nil, entityKind: AskKind? = nil
    ) {
        self.phrase = phrase
        self.kind = kind
        self.entityIds = entityIds
        self.candidateIds = candidateIds
        self.scope = scope
        self.scopeTitle = scopeTitle
        self.entityKind = entityKind
    }
}

/// The deterministic reading of one question. No model ran.
public struct AskResolution: Sendable, Equatable {
    /// Where the question goes.
    public var route: AskRoute
    /// What it asks about.
    public var type: AskQuestionType
    /// The entity ids the answer is about (found, group, unavailable).
    public var entityIds: [String]
    /// The candidates a `several` route lists.
    public var candidateIds: [String]
    /// One entry per noun phrase.
    public var parts: [AskPart]
    /// What the words ask for.
    public var intent: AskIntent
    /// The words of the question that matched nothing (a `none` route).
    public var unmatchedPhrase: String?

    /// Creates a resolution.
    public init(
        route: AskRoute, type: AskQuestionType, entityIds: [String] = [], candidateIds: [String] = [], parts: [AskPart] = [],
        intent: AskIntent = AskIntent(), unmatchedPhrase: String? = nil
    ) {
        self.route = route
        self.type = type
        self.entityIds = entityIds
        self.candidateIds = candidateIds
        self.parts = parts
        self.intent = intent
        self.unmatchedPhrase = unmatchedPhrase
    }
}
