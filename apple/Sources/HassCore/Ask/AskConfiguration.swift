import Foundation

// MARK: - Configuration

/// The rules the house answerer runs by, as data.
///
/// The answerable universe is what the *configuration* names: the entities the house document references, plus whatever the
/// overlay (``entityNames``, ``groups``, ``sameAs``, ``scopeRecords``) adds. Home Assistant's registries supply names, areas
/// and floors for those entities only. Something that exists in Home Assistant and is not configured is answered with a
/// fixed "not set up" sentence and never its state.
///
/// Every generic rule has a default here (which domains are never subjects, which kinds the document defines house-wide
/// sets for, generic synonyms, the token budget). Anything specific to one house, such as the platform names of its custom
/// integrations, its room nicknames or a spoken name for one entity, is *never* a literal in code: the caller loads it into
/// the matching field (from the house document, a Studio record or a private file) before building an ``AskableIndex``.
///
/// Decoding is forgiving: a missing key keeps its default, so a stored configuration survives a field added later.
public struct AskConfiguration: Codable, Sendable, Equatable {
    // MARK: Scope

    /// Domains that are never subjects, configured or not (helpers and tuning knobs nobody asks about).
    public var neverDomains: Set<String>
    /// Integration platforms whose entities are never subjects (annotators, plumbing).
    public var excludedPlatforms: Set<String>
    /// Domains a platform's entities are *not* subjects in, with the platform's other domains kept (a camera integration's motion sensors).
    public var excludedPlatformDomains: [String: Set<String>]
    /// Regular expressions; an entity whose name matches one is not a subject.
    public var excludedNamePatterns: [String]
    /// Kinds for which the configuration defines a house-wide set ("the lights", "the cameras", "the locks"). A plural question
    /// about any other kind across the house ("the motion sensors", "the batteries") is a set nobody has configured, and gets
    /// the "not set up" answer. A room or floor set is defined by what the configuration places there.
    public var houseSetKinds: Set<AskKind>
    /// Nouns that name a subset of a kind ("TV" and "speaker" are media players): a house-wide set under one of these nouns
    /// is not the kind's set, so it needs a group of its own.
    public var subsetNouns: Set<String>
    /// Words that narrow a kind to a place no room names ("outdoor lights"): such a set needs a group of its own.
    public var qualifierWords: Set<String>

    // MARK: Names and rooms

    /// Generic synonyms, applied word for word to the question and to names (`telly` reads `tv`).
    public var synonyms: [String: String]
    /// Extra phrases per room title (case-insensitive), for household nicknames. House specific: loaded, never built in.
    public var roomNicknames: [String: [String]]
    /// Extra phrases per floor name.
    public var floorNicknames: [String: [String]]
    /// Extra spoken names per entity id. House specific. An entity named here is configured.
    public var entityNames: [String: [String]]
    /// Named sets the configuration defines by listing their members ("outdoor lights"). House specific. Members are configured.
    public var groups: [AskGroup]
    /// Sets of entity ids that report one thing (a garage door's cover and its contact sensor): the first present counts, the
    /// rest are the same thing. House specific.
    public var sameAs: [[String]]
    /// Entity ids the configuration brings into scope without giving them a name.
    public var scopeRecords: [String]

    // MARK: Ranking

    /// How many name words closer the best match must be than the next one to be "found" rather than "which one?".
    public var nameMargin: Int
    /// The same margin for lock, garage, alarm and presence answers. A match that rests on a name with another candidate
    /// closer than this is answered "which one?" with the candidates instead of picking.
    public var securityNameMargin: Int
    /// Whether the security margin applies at all.
    public var securityGuard: Bool
    /// The kinds the security margin protects: a wrong confident answer about one of these is worse than asking.
    public var guardedKinds: Set<AskKind>

    // MARK: Annotators

    /// Integration annotators: where to find a "why" or "since" for the entities they control. House specific.
    public var annotators: [AskAnnotatorRule]
    /// Whether a group member with no cause of its own takes the group's logbook row from the same two seconds.
    public var inheritGroupCause: Bool
    /// The window around a state change inside which a logbook row counts as that change, in seconds.
    public var causeWindowSeconds: Double
    /// The tolerance for a group's row to explain a member, in seconds.
    public var groupInheritanceSeconds: Double

    // MARK: History

    /// The shortest cluster of identical `lastChanged` values that marks a Home Assistant restart.
    public var restartClusterMinimum: Int
    /// The width of the restart cluster, in seconds.
    public var restartClusterSeconds: Double
    /// The history window for "how long", in days.
    public var durationWindowDays: Double
    /// The history window for "when last", narrow first, in hours, then widened once to ``lastTimeWideDays``.
    public var lastTimeNarrowHours: Double
    /// The widened history window for "when last", in days.
    public var lastTimeWideDays: Double
    /// The deadline for one history or logbook call, in seconds.
    public var callDeadlineSeconds: Double

    // MARK: Slice

    /// The token budget for the slice a model sees.
    public var budget: AskBudget
    /// Which answers go through the phrasing closure, and so through the model. **Empty by default: code writes every answer.**
    ///
    /// The model never decides what is true; at most it rewords a sentence code already wrote. It stays off until a path is
    /// listed here and an ``AskAnswerer`` is given a phrasing closure. Leaving the set empty is the whole switch: nothing
    /// else needs removing.
    public var modelPaths: Set<AskModelPath>

    // MARK: Sensitivity

    /// Rules that classify an entity as security (`S2`) or home and location (`S1`).
    public var sensitivity: AskSensitivityRules
    /// Whether answers about the highest sensitivity class (locks, alarm, cameras, doors, windows, garage) are withheld.
    ///
    /// **On by default.** While on, a question whose answer would read security state gets the fixed sentence "Open the app to
    /// check that." whatever the lock state of the phone, and a "why" answer whose cause is security state gets it too. No
    /// state of that class is spoken until someone sets this to `false` on purpose.
    public var withholdSecurityState: Bool

    /// The defaults.
    public init(
        neverDomains: Set<String> = [
            "number", "select", "button", "text", "update", "image", "datetime", "time", "input_text", "input_number",
            "input_datetime", "input_button", "counter", "notify", "tts", "stt", "conversation", "zone", "ai_task", "group",
            "event", "remote", "device_tracker",
        ],
        excludedPlatforms: Set<String> = [],
        excludedPlatformDomains: [String: Set<String>] = [:],
        excludedNamePatterns: [String] = [],
        houseSetKinds: Set<AskKind> = [
            .light, .window, .door, .garage, .lock, .alarm, .camera, .vent, .occupancy, .temperature, .climate, .mediaPlayer,
            .fan, .vacuum, .person, .valve, .weather,
        ],
        subsetNouns: Set<String> = ["tv", "speaker"],
        qualifierWords: Set<String> = ["outdoor", "outside", "exterior", "external"],
        synonyms: [String: String] = [
            "telly": "tv", "television": "tv", "tele": "tv", "lounge": "living room", "hall": "hallway", "temp": "temperature",
            "heating": "thermostat", "heat": "thermostat", "ac": "thermostat", "aircon": "thermostat", "lamp": "light",
            "bulb": "light", "bulbs": "light", "loo": "bathroom", "bath": "bathroom", "washroom": "bathroom",
            "doorlock": "lock", "deadbolt": "lock", "cleaned": "clean", "vacuumed": "vacuum", "mopped": "mop",
        ],
        roomNicknames: [String: [String]] = [:],
        floorNicknames: [String: [String]] = [:],
        entityNames: [String: [String]] = [:],
        groups: [AskGroup] = [],
        sameAs: [[String]] = [],
        scopeRecords: [String] = [],
        nameMargin: Int = 1,
        securityNameMargin: Int = 2,
        securityGuard: Bool = true,
        guardedKinds: Set<AskKind> = [.lock, .garage, .alarm, .occupancy, .person],
        annotators: [AskAnnotatorRule] = [],
        inheritGroupCause: Bool = true,
        causeWindowSeconds: Double = 5,
        groupInheritanceSeconds: Double = 2,
        restartClusterMinimum: Int = 200,
        restartClusterSeconds: Double = 300,
        durationWindowDays: Double = 7,
        lastTimeNarrowHours: Double = 24,
        lastTimeWideDays: Double = 7,
        callDeadlineSeconds: Double = 1.5,
        budget: AskBudget = AskBudget(),
        modelPaths: Set<AskModelPath> = [],
        sensitivity: AskSensitivityRules = AskSensitivityRules(),
        withholdSecurityState: Bool = true
    ) {
        self.neverDomains = neverDomains
        self.excludedPlatforms = excludedPlatforms
        self.excludedPlatformDomains = excludedPlatformDomains
        self.excludedNamePatterns = excludedNamePatterns
        self.houseSetKinds = houseSetKinds
        self.subsetNouns = subsetNouns
        self.qualifierWords = qualifierWords
        self.synonyms = synonyms
        self.roomNicknames = roomNicknames
        self.floorNicknames = floorNicknames
        self.entityNames = entityNames
        self.groups = groups
        self.sameAs = sameAs
        self.scopeRecords = scopeRecords
        self.nameMargin = nameMargin
        self.securityNameMargin = securityNameMargin
        self.securityGuard = securityGuard
        self.guardedKinds = guardedKinds
        self.annotators = annotators
        self.inheritGroupCause = inheritGroupCause
        self.causeWindowSeconds = causeWindowSeconds
        self.groupInheritanceSeconds = groupInheritanceSeconds
        self.restartClusterMinimum = restartClusterMinimum
        self.restartClusterSeconds = restartClusterSeconds
        self.durationWindowDays = durationWindowDays
        self.lastTimeNarrowHours = lastTimeNarrowHours
        self.lastTimeWideDays = lastTimeWideDays
        self.callDeadlineSeconds = callDeadlineSeconds
        self.budget = budget
        self.modelPaths = modelPaths
        self.withholdSecurityState = withholdSecurityState
        self.sensitivity = sensitivity
    }

    /// Decodes with every missing key falling back to its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AskConfiguration()
        neverDomains = try c.decodeIfPresent(Set<String>.self, forKey: .neverDomains) ?? d.neverDomains
        excludedPlatforms = try c.decodeIfPresent(Set<String>.self, forKey: .excludedPlatforms) ?? d.excludedPlatforms
        excludedPlatformDomains = try c.decodeIfPresent([String: Set<String>].self, forKey: .excludedPlatformDomains) ?? d.excludedPlatformDomains
        excludedNamePatterns = try c.decodeIfPresent([String].self, forKey: .excludedNamePatterns) ?? d.excludedNamePatterns
        houseSetKinds = try c.decodeIfPresent(Set<AskKind>.self, forKey: .houseSetKinds) ?? d.houseSetKinds
        subsetNouns = try c.decodeIfPresent(Set<String>.self, forKey: .subsetNouns) ?? d.subsetNouns
        qualifierWords = try c.decodeIfPresent(Set<String>.self, forKey: .qualifierWords) ?? d.qualifierWords
        synonyms = try c.decodeIfPresent([String: String].self, forKey: .synonyms) ?? d.synonyms
        roomNicknames = try c.decodeIfPresent([String: [String]].self, forKey: .roomNicknames) ?? d.roomNicknames
        floorNicknames = try c.decodeIfPresent([String: [String]].self, forKey: .floorNicknames) ?? d.floorNicknames
        entityNames = try c.decodeIfPresent([String: [String]].self, forKey: .entityNames) ?? d.entityNames
        groups = try c.decodeIfPresent([AskGroup].self, forKey: .groups) ?? d.groups
        sameAs = try c.decodeIfPresent([[String]].self, forKey: .sameAs) ?? d.sameAs
        scopeRecords = try c.decodeIfPresent([String].self, forKey: .scopeRecords) ?? d.scopeRecords
        nameMargin = try c.decodeIfPresent(Int.self, forKey: .nameMargin) ?? d.nameMargin
        securityNameMargin = try c.decodeIfPresent(Int.self, forKey: .securityNameMargin) ?? d.securityNameMargin
        securityGuard = try c.decodeIfPresent(Bool.self, forKey: .securityGuard) ?? d.securityGuard
        guardedKinds = try c.decodeIfPresent(Set<AskKind>.self, forKey: .guardedKinds) ?? d.guardedKinds
        annotators = try c.decodeIfPresent([AskAnnotatorRule].self, forKey: .annotators) ?? d.annotators
        inheritGroupCause = try c.decodeIfPresent(Bool.self, forKey: .inheritGroupCause) ?? d.inheritGroupCause
        causeWindowSeconds = try c.decodeIfPresent(Double.self, forKey: .causeWindowSeconds) ?? d.causeWindowSeconds
        groupInheritanceSeconds = try c.decodeIfPresent(Double.self, forKey: .groupInheritanceSeconds) ?? d.groupInheritanceSeconds
        restartClusterMinimum = try c.decodeIfPresent(Int.self, forKey: .restartClusterMinimum) ?? d.restartClusterMinimum
        restartClusterSeconds = try c.decodeIfPresent(Double.self, forKey: .restartClusterSeconds) ?? d.restartClusterSeconds
        durationWindowDays = try c.decodeIfPresent(Double.self, forKey: .durationWindowDays) ?? d.durationWindowDays
        lastTimeNarrowHours = try c.decodeIfPresent(Double.self, forKey: .lastTimeNarrowHours) ?? d.lastTimeNarrowHours
        lastTimeWideDays = try c.decodeIfPresent(Double.self, forKey: .lastTimeWideDays) ?? d.lastTimeWideDays
        callDeadlineSeconds = try c.decodeIfPresent(Double.self, forKey: .callDeadlineSeconds) ?? d.callDeadlineSeconds
        budget = try c.decodeIfPresent(AskBudget.self, forKey: .budget) ?? d.budget
        modelPaths = try c.decodeIfPresent(Set<AskModelPath>.self, forKey: .modelPaths) ?? d.modelPaths
        sensitivity = try c.decodeIfPresent(AskSensitivityRules.self, forKey: .sensitivity) ?? d.sensitivity
        withholdSecurityState = try c.decodeIfPresent(Bool.self, forKey: .withholdSecurityState) ?? d.withholdSecurityState
    }

    /// Entity ids the overlay brings into scope: named ones, group members, same-as members and bare scope records.
    public var overlayEntityIds: Set<String> {
        var ids = Set(entityNames.keys).union(scopeRecords)
        for g in groups { ids.formUnion(g.entityIds) }
        for list in sameAs { ids.formUnion(list) }
        return ids
    }
}

// MARK: - Groups

/// A named set the configuration defines by listing its members ("outdoor lights", "cameras").
///
/// A set is valid only because the configuration says so: a question about a set that no group, document list or room
/// defines is answered "not set up", never from whatever matches in Home Assistant.
public struct AskGroup: Codable, Sendable, Equatable, Hashable {
    /// A stable id for logs.
    public var id: String
    /// The phrases people say for the set ("outdoor lights", "outside lights").
    public var say: [String]
    /// What the members are, when the set is one kind. Unknown kind names in a stored group decode as nil.
    public var kind: AskKind?
    /// The members, in order.
    public var entityIds: [String]

    /// Creates a group.
    public init(id: String, say: [String], kind: AskKind? = nil, entityIds: [String]) {
        self.id = id
        self.say = say
        self.kind = kind
        self.entityIds = entityIds
    }

    private enum CodingKeys: String, CodingKey { case id, say, kind, entityIds }

    /// Decodes a group, ignoring keys it does not know and a kind name it cannot map.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        say = try c.decodeIfPresent([String].self, forKey: .say) ?? []
        kind = (try c.decodeIfPresent(String.self, forKey: .kind)).flatMap(AskKind.init(rawValue:))
        entityIds = try c.decodeIfPresent([String].self, forKey: .entityIds) ?? []
    }
}

// MARK: - Model paths

/// An answer path that may go through the model. A path not listed in ``AskConfiguration/modelPaths`` is answered in code.
public enum AskModelPath: String, Codable, Sendable, Hashable, CaseIterable {
    /// A "why" answer that has a cause line to explain.
    case cause
    /// A listing answer ("what is on in the office") with more items than a sentence reads well.
    case listing
    /// A compound question with several parts.
    case compound
    /// Any question about state or value (the baseline the code-only paths are measured against).
    case everything
}

// MARK: - Budget

/// How many tokens each part of a slice may use, against a 4,096-token on-device window.
public struct AskBudget: Codable, Sendable, Equatable {
    /// Characters per token for the estimate (the default is 3.8; 3.3 is the conservative figure).
    public var charactersPerToken: Double
    /// Tokens reserved for the instructions and framing.
    public var fixedTokens: Int
    /// The hard cap on the input, instructions included.
    public var inputCap: Int
    /// The most entity lines in one slice.
    public var maxEntityLines: Int
    /// The most cause lines in one slice.
    public var maxCauseLines: Int
    /// The most annotator lines in one slice.
    public var maxAnnotatorLines: Int
    /// How many names an aggregate lists before "and N more".
    public var maxListedNames: Int

    /// The defaults from the house configuration note.
    public init(
        charactersPerToken: Double = 3.8, fixedTokens: Int = 250, inputCap: Int = 1_200, maxEntityLines: Int = 20,
        maxCauseLines: Int = 4, maxAnnotatorLines: Int = 3, maxListedNames: Int = 8
    ) {
        self.charactersPerToken = charactersPerToken
        self.fixedTokens = fixedTokens
        self.inputCap = inputCap
        self.maxEntityLines = maxEntityLines
        self.maxCauseLines = maxCauseLines
        self.maxAnnotatorLines = maxAnnotatorLines
        self.maxListedNames = maxListedNames
    }
}

// MARK: - Annotators

/// One integration whose entities explain other entities.
///
/// The platform name is house data: it comes from configuration, not from code. The attribute names are read from the
/// annotator's state attributes, so the rule needs no registry call beyond the platform.
public struct AskAnnotatorRule: Codable, Sendable, Equatable {
    /// What the annotator provides.
    public enum Role: String, Codable, Sendable { case why, since }

    /// The integration platform (`registry.platform`), or a `domain.` prefix when no registry is present.
    public var platform: String
    /// The domain of the annotator entities (`switch`, `sensor`).
    public var domain: String
    /// The attribute holding the subject entity id.
    public var subjectAttribute: String
    /// What it provides.
    public var role: Role
    /// Attributes worth a line, in order. A dotted name reads into a nested object.
    public var attributes: [String]
    /// A phrase for a raw attribute value: `value_phrases[attribute][value]`.
    public var valuePhrases: [String: [String: String]]

    /// Creates a rule.
    public init(
        platform: String, domain: String, subjectAttribute: String, role: Role, attributes: [String] = [],
        valuePhrases: [String: [String: String]] = [:]
    ) {
        self.platform = platform
        self.domain = domain
        self.subjectAttribute = subjectAttribute
        self.role = role
        self.attributes = attributes
        self.valuePhrases = valuePhrases
    }
}
