import Foundation

// MARK: - Evaluation environment

/// What an authored operand or predicate reads: a value, "not yet" or "not available".
///
/// Evaluation is total. A missing entity, a path that is not there, a value of the wrong kind and a division by zero all
/// become ``unavailable`` (or ``loading`` while the first states are still arriving); nothing throws.
public enum ServerUIReadResult: Equatable, Sendable {
    case value(JSONValue)
    case loading
    case unavailable

    /// The value, if there is one.
    public var json: JSONValue? { if case .value(let value) = self { value } else { nil } }

    /// Combines the results of several parts of one expression: `loading` outranks `unavailable`, so a node waits instead of
    /// giving up. `nil` when every part has a value.
    static func combine(_ parts: [Self]) -> Self? {
        var sawLoading = false, sawUnavailable = false
        for part in parts {
            switch part {
            case .value: break
            case .loading: sawLoading = true
            case .unavailable: sawUnavailable = true
            }
        }
        if sawLoading { return .loading }
        return sawUnavailable ? .unavailable : nil
    }
}

/// The signed-in person an authored expression can ask about.
public struct ServerUIViewer: Equatable, Sendable {
    /// Home Assistant's user id.
    public var userId: String?
    /// Whether the user is an administrator; `nil` until the connection has said.
    public var isAdmin: Bool?
    /// The `person.*` entity whose `user_id` is ``userId``, when one is known.
    public var personEntityId: String?

    /// Creates a viewer.
    public init(userId: String? = nil, isAdmin: Bool? = nil, personEntityId: String? = nil) {
        self.userId = userId
        self.isAdmin = isAdmin
        self.personEntityId = personEntityId
    }
}

/// The values an operand or predicate is evaluated against. The app implements it over `EntityStore` boxes, so the entities an
/// evaluation reads are exactly the ones an observation tracks.
public protocol ServerUIReading {
    /// The value at `path` of a declared source (`["state"]` or `["attributes", ...]` for a Home Assistant entity).
    func read(sourceId: String, path: [String]) -> ServerUIReadResult
    /// The signed-in person; `nil` before the connection knows them.
    var viewer: ServerUIViewer? { get }
    /// The state text of an `ha-entity` source exactly as Home Assistant reports it: `unknown` and `unavailable` are values
    /// (`raw-state`, `sh.raw-state@1`). `.unavailable` only when the source has no entity; `.loading` before the first states arrive.
    func readRaw(sourceId: String) -> ServerUIReadResult
    /// When the state of an `ha-entity` source last changed, as `YYYY-MM-DDTHH:MM:SS.sssZ` (`last-changed`, `sh.entity-time@1`). `.unavailable` when the
    /// source has no entity or no time, `.loading` before the first states arrive. Reading it is reading the entity's box, so a change re-runs the reader.
    func readChanged(sourceId: String) -> ServerUIReadResult
    /// The state of the viewer's person entity.
    func viewerPersonState() -> ServerUIReadResult
    /// The new value of the control that sent the action being resolved; `nil` outside an action.
    var controlValue: JSONValue? { get }
    /// The clock the `clock` and `date` operands and the relative date styles use; `nil` makes them unavailable.
    var clock: ServerUIClock? { get }
    /// The clock `now-second` reads (`sh.countdown@1`): the wall time to the second. The app publishes it once a second, and only from the first read until one
    /// tick after the last; the default is ``clock``, so a reader with one pinned clock gives both.
    var secondClock: ServerUIClock? { get }
    /// The item a flow step is looking at (`item` operands); `nil` outside a flow step.
    var item: JSONValue? { get }
    /// The 0-based position of that item (`index` operands, `sh.repeat@1`); `nil` outside a flow step and a repeat cell.
    var index: Int? { get }
    /// The evaluated value of the flow parameter `name` (`param` operands); `nil` when the flow has no such parameter.
    func parameter(_ name: String) -> JSONValue?
    /// Flow mode: there is no `loading` or `unavailable`, a gap is `null` and a condition is yes or no.
    var isFlow: Bool { get }
    /// The language and region date styles are drawn in; `nil` draws United States English (``ServerUIDateFormat``).
    var locale: Locale? { get }
    /// Whether the app draws an SF Symbol of this name (`UIImage(systemName:)`); the default draws every name.
    func drawsSymbol(_ name: String) -> Bool
    /// Called once for every operand and condition node evaluated, so a flow can meter its work. The default does nothing.
    func spend()
}

public extension ServerUIReading {
    func readRaw(sourceId: String) -> ServerUIReadResult { .unavailable }
    func readChanged(sourceId: String) -> ServerUIReadResult { .unavailable }
    var controlValue: JSONValue? { nil }
    var clock: ServerUIClock? { nil }
    var secondClock: ServerUIClock? { clock }
    var item: JSONValue? { nil }
    var index: Int? { nil }
    func parameter(_ name: String) -> JSONValue? { nil }
    var isFlow: Bool { false }
    var locale: Locale? { nil }
    func drawsSymbol(_ name: String) -> Bool { true }
    func spend() {}
}

// MARK: - Three-valued truth

/// The outcome of a predicate: it holds, it does not, or the data to say is not there.
public enum ServerUITri: Equatable, Sendable {
    case yes, no, unknown

    /// Kleene conjunction: one `no` settles it, otherwise any `unknown` keeps it unknown.
    static func all(_ values: [Self]) -> Self {
        if values.contains(.no) { return .no }
        return values.contains(.unknown) ? .unknown : .yes
    }
    /// Kleene disjunction: one `yes` settles it, otherwise any `unknown` keeps it unknown.
    static func any(_ values: [Self]) -> Self {
        if values.contains(.yes) { return .yes }
        return values.contains(.unknown) ? .unknown : .no
    }
    var negated: Self {
        switch self {
        case .yes: .no
        case .no: .yes
        case .unknown: .unknown
        }
    }
}
