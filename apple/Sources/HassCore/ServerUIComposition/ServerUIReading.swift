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
    /// The state of the viewer's person entity.
    func viewerPersonState() -> ServerUIReadResult
    /// The new value of the control that sent the action being resolved; `nil` outside an action.
    var controlValue: JSONValue? { get }
}

public extension ServerUIReading {
    var controlValue: JSONValue? { nil }
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
