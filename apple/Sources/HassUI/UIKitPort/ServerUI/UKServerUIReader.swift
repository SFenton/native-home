#if os(iOS)
import HassCore
import Observation
import UIKit

// MARK: - The signed-in person

/// Who is signed in, for `viewer` operands and predicates.
///
/// The user comes from `auth/current_user` over the one connection (``load(from:)``). Until it arrives the cached publication's
/// recorded user id can be ``seed(userID:)``ed, so a rule on the user's id resolves at the first frame; `isAdmin` stays unknown
/// (a ``ServerUIVisibility`` then follows its `whenUnknown` policy) until the connection has said.
@MainActor
@Observable
final class UKServerUIViewerSource {
    private(set) var user: HassUser?
    private(set) var seededUserID: String?

    /// Records the user the cached publication was delivered for.
    func seed(userID: String?) { if user == nil, seededUserID != userID { seededUserID = userID } }

    /// Sets the signed-in user (a hosted test, or ``load(from:)``).
    func set(_ user: HassUser?) { if self.user != user { self.user = user } }

    /// Fetches the user once over the existing connection; a failure leaves the viewer unknown.
    func load(from connection: HassConnection) async {
        guard user == nil, let loaded = try? await connection.currentUser() else { return }
        set(loaded)
    }

    /// The viewer as an expression sees it. Reads `peopleRevision`, so an observation re-runs when the person list changes.
    ///
    /// The person entity is found by scanning the house, so it is found once per user and people revision (``PersonLookup``) and
    /// every later read is a comparison: a viewer predicate costs what it names, not the entity count.
    func viewer(in store: EntityStore) -> ServerUIViewer? {
        guard let id = user?.id ?? seededUserID else { return nil }
        let revision = store.peopleRevision
        return ServerUIViewer(userId: id, isAdmin: user?.isAdmin,
                              personEntityId: lookup.personID(forUser: id, revision: revision, in: store))
    }

    /// How many times the house was scanned for the viewer's person; tests read it to prove a read costs no scan.
    var personScans: Int { lookup.scans }

    /// The last person lookup, kept off Observation: writing it during a read must not wake the readers.
    @ObservationIgnored private var lookup = PersonLookup()
}

// MARK: - Reading entity state for expressions

/// Evaluates operands and predicates over the entity boxes the document's `ha-entity` sources name.
///
/// Every read goes through `EntityStore` boxes and the optimistic overlay, so an observation that evaluates an expression
/// subscribes to exactly the entities that expression reads and to nothing else.
struct UKServerUIReader: ServerUIReading {
    let bindings: UKServerUIBindings
    let viewerSource: UKServerUIViewerSource
    let runner: UKServerUICallRunner?
    var controlValue: JSONValue?

    init(bindings: UKServerUIBindings, viewerSource: UKServerUIViewerSource, runner: UKServerUICallRunner?, controlValue: JSONValue? = nil) {
        self.bindings = bindings
        self.viewerSource = viewerSource
        self.runner = runner
        self.controlValue = controlValue
    }

    /// The record of the repeat cell being drawn (`item` operands, `sh.repeat@1`); `nil` outside a cell. Reading it inside an observation
    /// follows the cell's own record, so one record changing re-runs only the expressions of its cell.
    var item: JSONValue? { MainActor.assumeIsolated { bindings.cell?.record } }

    /// The position of the repeat cell being drawn (`index` operands).
    var index: Int? { MainActor.assumeIsolated { bindings.cell?.index } }

    var viewer: ServerUIViewer? {
        MainActor.assumeIsolated { viewerSource.viewer(in: bindings.context.store) }
    }

    /// The wall clock. Reading it starts the minute tick, and the tick stops once nothing reads it (``UKServerUIAppStateSource``).
    var clock: ServerUIClock? { MainActor.assumeIsolated { bindings.appState.clockForReading() } }

    /// The wall clock to the second (`now-second`, `sh.countdown@1`). Reading it starts the one-second tick, which stops one tick after the last read.
    var secondClock: ServerUIClock? { MainActor.assumeIsolated { bindings.appState.secondClockForReading() } }

    /// Dates are drawn in the phone's language and region.
    var locale: Locale? { .autoupdatingCurrent }

    func drawsSymbol(_ name: String) -> Bool { UIImage(systemName: name) != nil }

    func viewerPersonState() -> ServerUIReadResult {
        MainActor.assumeIsolated {
            guard let viewer = viewerSource.viewer(in: bindings.context.store) else { return .loading }
            guard let person = viewer.personEntityId else { return .unavailable }
            if bindings.context.valuesPending { return .loading }
            guard let state = bindings.context.store.entity(person).state, !state.isUnavailable else { return .unavailable }
            return .value(.string(state.state))
        }
    }

    /// The state text of the source's entity box, `unknown` and `unavailable` included (`raw-state`, `sh.raw-state@1`). It reads the
    /// store, not the optimistic overlay: the point is what Home Assistant says. A source that is not an `ha-entity` has no raw state.
    func readRaw(sourceId: String) -> ServerUIReadResult {
        MainActor.assumeIsolated {
            guard case .haEntity? = bindings.definitions[sourceId] else { return .unavailable }
            switch bindings.entityID(for: sourceId) {
            case .loading: return .loading
            case .unavailable: return .unavailable
            case .ready(let id):
                return .rawState(of: bindings.context.store.entity(id).state, statesLoaded: !bindings.context.valuesPending)
            }
        }
    }

    /// When the source's entity state last changed (`last-changed`, `sh.entity-time@1`). It reads the entity box, so the next change re-runs the reader.
    func readChanged(sourceId: String) -> ServerUIReadResult {
        MainActor.assumeIsolated {
            guard case .haEntity? = bindings.definitions[sourceId] else { return .unavailable }
            switch bindings.entityID(for: sourceId) {
            case .loading: return .loading
            case .unavailable: return .unavailable
            case .ready(let id):
                return .lastChanged(of: bindings.context.store.entity(id).state, statesLoaded: !bindings.context.valuesPending)
            }
        }
    }

    func read(sourceId: String, path: [String]) -> ServerUIReadResult {
        MainActor.assumeIsolated {
            guard let source = bindings.definitions[sourceId] else { return .unavailable }
            guard case .haEntity = source else {
                // Any model that has read fields reads through the one vocabulary a slot read uses (`ServerUIModelReads`).
                switch bindings.read(.init(sourceId: sourceId, path: path, kind: .string)) {
                case .ready(let value): return .value(value)
                case .loading: return .loading
                case .unavailable: return .unavailable
                }
            }
            let entity = bindings.entityID(for: sourceId)
            guard case .ready(let id) = entity else {
                if case .loading = entity { return .loading }
                return .unavailable
            }
            if bindings.context.valuesPending { return .loading }
            guard let state = bindings.context.store.entity(id).state, !state.isUnavailable else { return .unavailable }
            if path == ["state"] { return .value(.string(runner?.pendingState(id) ?? state.state)) }
            guard path.first == "attributes" else { return .unavailable }
            var value: JSONValue? = .object(state.attributes)
            for segment in path.dropFirst() { value = value?[segment] }
            return value.map { .value($0) } ?? .unavailable
        }
    }
}
#endif
