import Foundation

// MARK: - Predicates

/// A closed condition over entity state and the signed-in person, shaped after Home Assistant's own card visibility
/// conditions (`state`, `numeric_state`, `user`, `and`, `or`, `not`). It answers yes, no, or unknown when the data is not there.
///
/// One predicate belongs to one node (``ServerUIVisibility``) or one option (`selectedWhen`), and is evaluated inside that
/// node's own observation, so a change to one entity touches only the nodes that read it (``sourceIds``).
public indirect enum ServerUIPredicate: Hashable, Sendable {
    /// The state at `path` is one of `values` (compared as text).
    case state(sourceId: String, path: [String], values: [String])
    /// The number at `path` is above and/or below the given operands (either may read another entity).
    case numeric(sourceId: String, path: [String], above: ServerUIOperand?, below: ServerUIOperand?)
    /// The signed-in user is an administrator and/or one of `userIds` (both must hold when both are given).
    case viewer(isAdmin: Bool?, userIds: [String]?)
    /// The state of the signed-in user's `person.*` entity is one of `values`.
    case viewerPerson(values: [String])
    case all([ServerUIPredicate])
    case any([ServerUIPredicate])
    case not(ServerUIPredicate)
    /// Two operands compared (`sh.conditions@1`).
    case compare(CompareOp, left: ServerUIOperand, right: ServerUIOperand)
    /// The value is one of the options (`sh.conditions@1`).
    case `in`(value: ServerUIOperand, options: [ServerUIOperand])
    /// The operand has a value that is not `null` (`sh.conditions@1`).
    case exists(ServerUIOperand)

    /// How a ``compare(_:left:right:)`` relates its two operands.
    public enum CompareOp: String, Sendable, CaseIterable {
        /// Equal scalars (numbers and booleans by value, text by canonical equivalence, `1` and `"1"` alike).
        case eq
        /// Both scalars and not equal (a `null` or a structure is neither equal nor unequal: no).
        case ne
        /// Both numbers, left greater.
        case above
        /// Both numbers, left smaller.
        case below
        /// Both dates or dates and times, left earlier.
        case before
        /// Both dates or dates and times, left later.
        case after
    }

    /// The source ids this predicate reads.
    public var sourceIds: Set<String> {
        switch self {
        case .state(let id, _, _): [id]
        case .numeric(let id, _, let above, let below):
            Set([id]).union(above?.sourceIds ?? []).union(below?.sourceIds ?? [])
        case .viewer, .viewerPerson: []
        case .all(let items), .any(let items): items.reduce(into: Set<String>()) { $0.formUnion($1.sourceIds) }
        case .not(let item): item.sourceIds
        case .compare(_, let left, let right): left.sourceIds.union(right.sourceIds)
        case .in(let value, let options): options.reduce(value.sourceIds) { $0.union($1.sourceIds) }
        case .exists(let value): value.sourceIds
        }
    }

    /// Whether the predicate depends on the signed-in person.
    public var readsViewer: Bool {
        switch self {
        case .viewer, .viewerPerson: true
        case .state: false
        case .numeric(_, _, let above, let below): above?.readsViewer == true || below?.readsViewer == true
        case .all(let items), .any(let items): items.contains { $0.readsViewer }
        case .not(let item): item.readsViewer
        case .compare(_, let left, let right): left.readsViewer || right.readsViewer
        case .in(let value, let options): value.readsViewer || options.contains { $0.readsViewer }
        case .exists(let value): value.readsViewer
        }
    }

    /// Whether the predicate reads the clock anywhere, so the app ticks it once a minute only while something does.
    public var readsClock: Bool {
        switch self {
        case .state, .viewer, .viewerPerson: false
        case .numeric(_, _, let above, let below): above?.readsClock == true || below?.readsClock == true
        case .all(let items), .any(let items): items.contains { $0.readsClock }
        case .not(let item): item.readsClock
        case .compare(_, let left, let right): left.readsClock || right.readsClock
        case .in(let value, let options): value.readsClock || options.contains { $0.readsClock }
        case .exists(let value): value.readsClock
        }
    }

    /// Evaluates against `environment`. Total: missing data is ``ServerUITri/unknown``, never an error.
    ///
    /// In flow mode (``ServerUIReading/isFlow``) an answer that cannot be given is `no`.
    public func evaluate(_ environment: some ServerUIReading) -> ServerUITri {
        environment.spend()
        let answer = outcome(environment)
        return environment.isFlow && answer == .unknown ? .no : answer
    }

    private func outcome(_ environment: some ServerUIReading) -> ServerUITri {
        switch self {
        case .state(let sourceId, let path, let values):
            guard let value = environment.read(sourceId: sourceId, path: path).json,
                  let text = ServerUIOperand.scalarText(value) else { return .unknown }
            return values.contains(text) ? .yes : .no
        case .numeric(let sourceId, let path, let above, let below):
            guard let number = environment.read(sourceId: sourceId, path: path).json?.finiteNumber else { return .unknown }
            var parts: [ServerUITri] = []
            for (bound, isAbove) in [(above, true), (below, false)] {
                guard let bound else { continue }
                guard let limit = bound.evaluate(environment).json?.finiteNumber else { parts.append(.unknown); continue }
                parts.append((isAbove ? number > limit : number < limit) ? .yes : .no)
            }
            return ServerUITri.all(parts)
        case .viewer(let isAdmin, let userIds):
            guard let viewer = environment.viewer else { return .unknown }
            var parts: [ServerUITri] = []
            if let isAdmin { parts.append(viewer.isAdmin.map { $0 == isAdmin ? .yes : .no } ?? .unknown) }
            if let userIds { parts.append(viewer.userId.map { userIds.contains($0) ? .yes : .no } ?? .unknown) }
            return ServerUITri.all(parts)
        case .viewerPerson(let values):
            guard let value = environment.viewerPersonState().json, let text = ServerUIOperand.scalarText(value) else { return .unknown }
            return values.contains(text) ? .yes : .no
        case .all(let items): return ServerUITri.all(items.map { $0.evaluate(environment) })
        case .any(let items): return ServerUITri.any(items.map { $0.evaluate(environment) })
        case .not(let item): return item.evaluate(environment).negated
        case .exists(let value):
            guard case .value(let found) = value.evaluate(environment) else { return .unknown }
            return found == .null ? .no : .yes
        case .in(let value, let options):
            let subject = value.evaluate(environment)
            let evaluated = options.map { $0.evaluate(environment) }
            guard case .value(let found) = subject else { return .unknown }
            guard Self.isScalar(found) else { return .no }
            let matched = evaluated.contains { option in
                guard case .value(let candidate) = option, Self.isScalar(candidate) else { return false }
                return ServerUIOperand.matches(found, candidate)
            }
            if matched { return .yes }
            return evaluated.contains { $0.json == nil } ? .unknown : .no
        case .compare(let op, let leftOperand, let rightOperand):
            let left = leftOperand.evaluate(environment), right = rightOperand.evaluate(environment)
            guard case .value(let a) = left, case .value(let b) = right else { return .unknown }
            switch op {
            case .eq, .ne:
                guard Self.isScalar(a), Self.isScalar(b) else { return .no }
                return ServerUIOperand.matches(a, b) == (op == .eq) ? .yes : .no
            case .above, .below:
                guard case .number(let x) = a, case .number(let y) = b else { return .no }
                return (op == .above ? x > y : x < y) ? .yes : .no
            case .before, .after:
                guard let x = Self.instant(a, environment), let y = Self.instant(b, environment) else { return .no }
                return (op == .before ? x < y : x > y) ? .yes : .no
            }
        }
    }

    /// A string, number or boolean: the only values that compare as equal or unequal.
    private static func isScalar(_ value: JSONValue) -> Bool {
        switch value {
        case .string, .number, .bool: true
        default: false
        }
    }

    /// The ordering key of a date or date and time text on the environment's clock, or `nil`.
    private static func instant(_ value: JSONValue, _ environment: some ServerUIReading) -> Int? {
        guard case .string(let text) = value else { return nil }
        return ServerUIDates.wallTime(text, utcOffsetMinutes: environment.clock?.utcOffsetMinutes ?? 0)?.instant
    }
}

// MARK: - Visibility

/// A node's `visibleWhen`: a predicate and what to do while it cannot be answered.
public struct ServerUIVisibility: Equatable, Sendable {
    /// What a node does while its predicate is unknown (an entity missing or unavailable, first sign-in before any state).
    public enum WhenUnknown: String, Sendable, CaseIterable {
        /// Show the node.
        case show
        /// Hide the node (the behaviour of today's room visibility for an unavailable entity).
        case hide
        /// Keep whatever the node was doing, so a reconnect or a cold launch never blanks or reorders a screen. A node that
        /// has never been answered is shown. The default.
        case keep
    }

    public let predicate: ServerUIPredicate
    public let whenUnknown: WhenUnknown

    /// Creates a visibility rule.
    public init(predicate: ServerUIPredicate, whenUnknown: WhenUnknown = .keep) {
        self.predicate = predicate
        self.whenUnknown = whenUnknown
    }

    /// Whether the node is shown now.
    /// - Parameter previous: What it was showing before, for ``WhenUnknown/keep``.
    public func isShown(_ environment: some ServerUIReading, previous: Bool?) -> Bool {
        switch predicate.evaluate(environment) {
        case .yes: true
        case .no: false
        case .unknown:
            switch whenUnknown {
            case .show: true
            case .hide: false
            case .keep: previous ?? true
            }
        }
    }
}

/// One `selectedWhen` rule: the option it names is selected while the predicate holds.
public struct ServerUISelection: Equatable, Sendable {
    public let predicate: ServerUIPredicate

    /// Creates a selection rule.
    public init(_ predicate: ServerUIPredicate) { self.predicate = predicate }

    /// Whether the option is selected now; unknown counts as not selected.
    public func isSelected(_ environment: some ServerUIReading) -> Bool { predicate.evaluate(environment) == .yes }
}
