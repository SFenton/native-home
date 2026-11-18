import Foundation

// MARK: - The count operand

/// One entry of a ``ServerUIOperand/count(_:)`` (`sh.count@1`): a condition over some entities, counted once when it holds, and an optional list
/// of people it is counted for.
public struct ServerUICountEntry: Hashable, Sendable {
    /// The most entries a count has, and the most people one entry lists.
    public static let maximumEntries = 32

    /// The condition; it is the grammar of a `visibleWhen`, with the budget of a rule's case.
    public let test: ServerUIPredicate
    /// The `person.*` entities this entry is counted for; `nil` counts it for everyone. A viewer who is not listed, or who has no person entity,
    /// is not in the entry, and the entry's entities are not read.
    public let personEntityIds: [String]?

    init(test: ServerUIPredicate, personEntityIds: [String]?) {
        self.test = test
        self.personEntityIds = personEntityIds
    }
}

extension ServerUIOperand {
    /// Evaluates a ``count(_:)``: how many entries' conditions hold, as a number from 0 to the number of entries.
    ///
    /// Each entry is read once, in order, and costs one read of its entities and no pattern match. An entry whose answer is `unknown` (no state, still
    /// loading, a `numeric` test over text) is not counted and the count goes on. Only when every entry in play is unanswerable is there nothing to
    /// say: `loading` when any read of any kind was "not yet" (a read, a raw state, a last change, the viewer's person state, a viewer not known),
    /// else `unavailable`. An entry the viewer is not in is not in play; a count with none in play is 0. A filtered entry, before the viewer is
    /// known, makes the whole count `loading`. A flow reads no document source: there a count is a gap.
    func evaluateCount(_ entries: [ServerUICountEntry], _ environment: some ServerUIReading) -> ServerUIReadResult {
        if environment.isFlow { return .unavailable }
        var waiting = false
        return withUnsafeMutablePointer(to: &waiting) { flag in
            let watched = ServerUIWatchedReader(base: environment, waiting: flag)
            var held = 0, considered = 0, unknown = 0
            // The viewer is asked for once, on the first filtered entry: it is a lookup the app has cached, but 32 filtered entries ask once, not 32 times.
            var viewer: ServerUIViewer?
            var askedForViewer = false
            for entry in entries {
                if let people = entry.personEntityIds {
                    if !askedForViewer { viewer = environment.viewer; askedForViewer = true }
                    guard let viewer else { return .loading }
                    guard let person = viewer.personEntityId, people.contains(person) else { continue }
                }
                considered += 1
                switch entry.test.evaluate(watched) {
                case .yes: held += 1
                case .unknown: unknown += 1
                case .no: break
                }
            }
            if considered > 0, unknown == considered { return flag.pointee ? .loading : .unavailable }
            return .value(.number(Double(held)))
        }
    }
}

// MARK: - Watching what a count reads

/// A reader that passes every read through and notes when any of them was "not yet", so a count nobody can answer says `loading` rather than
/// `unavailable`. The note is one flag the count owns; the reader holds a pointer to it, so a count allocates nothing.
struct ServerUIWatchedReader<Base: ServerUIReading>: ServerUIReading {
    let base: Base
    let waiting: UnsafeMutablePointer<Bool>

    private func seen(_ result: ServerUIReadResult) -> ServerUIReadResult {
        if result == .loading { waiting.pointee = true }
        return result
    }

    /// A count's entries read an entity whose state is `unavailable` as that text, so a test can ask for it and a house of them is a known 0.
    func read(sourceId: String, path: [String]) -> ServerUIReadResult { seen(base.readStateText(sourceId: sourceId, path: path)) }
    func readStateText(sourceId: String, path: [String]) -> ServerUIReadResult { seen(base.readStateText(sourceId: sourceId, path: path)) }
    func readRaw(sourceId: String) -> ServerUIReadResult { seen(base.readRaw(sourceId: sourceId)) }
    func readChanged(sourceId: String) -> ServerUIReadResult { seen(base.readChanged(sourceId: sourceId)) }
    func viewerPersonState() -> ServerUIReadResult { seen(base.viewerPersonState()) }
    var viewer: ServerUIViewer? {
        let viewer = base.viewer
        if viewer == nil { waiting.pointee = true }
        return viewer
    }
    var controlValue: JSONValue? { base.controlValue }
    var clock: ServerUIClock? { base.clock }
    var secondClock: ServerUIClock? { base.secondClock }
    var item: JSONValue? { base.item }
    var index: Int? { base.index }
    func parameter(_ name: String) -> JSONValue? { base.parameter(name) }
    var isFlow: Bool { base.isFlow }
    var locale: Locale? { base.locale }
    func drawsSymbol(_ name: String) -> Bool { base.drawsSymbol(name) }
    func spend() { base.spend() }
}
