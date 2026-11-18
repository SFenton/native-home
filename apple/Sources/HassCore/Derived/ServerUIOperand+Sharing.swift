import Foundation

// MARK: - Which authored logic can be shared

public extension ServerUIOperand {
    /// Whether the operand's answer depends only on entities and the signed-in person, so every use of an identical tree gets the same
    /// answer and one ``DerivedValue`` can serve them all.
    ///
    /// A repeat cell's `item` and `index`, a flow's `param` and the `control` of an action are different in each place the tree is
    /// used, and the clock's ticks start and stop with the node that reads them (and with its page being on screen), so a tree that
    /// reads one of those is evaluated where it is used.
    var isShareable: Bool { !readsClock && isScopeFree }

    /// The fewest distinct sources a tree reads for sharing it to pay.
    static let sharingThreshold = 3

    /// Whether the tree has at least ``sharingThreshold`` places that read a source. A walk that allocates nothing and stops at the
    /// threshold, so the app can rule a small expression out on every run for the price of a few visits, before it hashes the tree.
    var hasManyReads: Bool { readSites(upTo: Self.sharingThreshold) >= Self.sharingThreshold }

    fileprivate func readSites(upTo cap: Int) -> Int {
        var total = 0
        func add(_ operand: ServerUIOperand) { if total < cap { total += operand.readSites(upTo: cap - total) } }
        switch self {
        case .read, .rawState, .lastChanged, .listCount: return 1
        case .literal, .control, .viewer, .item, .index, .param, .clock: return 0
        case .listIncludes(_, _, let value): return 1 + value.readSites(upTo: cap)
        case .date(let from, let to), .progress(let from, let to), .secondsBetween(let from, let to): add(from); add(to)
        case .choose(let cases, let otherwise):
            for item in cases where total < cap { total += item.when.readSites(upTo: cap - total); add(item.then) }
            add(otherwise)
        case .format(_, let args, _): for value in args.values { add(value) }
        case .map(let of, let cases, let otherwise): add(of); add(otherwise); for item in cases { add(item.then) }
        case .math(_, let args), .list(let args): for value in args { add(value) }
        case .object(let fields): for value in fields.values { add(value) }
        }
        return total
    }

    /// Whether sharing pays: the tree is shareable and reads several sources. A derived value is an extra run, so it saves only
    /// what the many reads of one evaluation cost: a literal, a single read or a rule over one or two entities is cheaper
    /// evaluated where it is used, and its readers redraw whenever it changes anyway.
    var isWorthSharing: Bool {
        isShareable && sourceIds.count >= Self.sharingThreshold
    }

    fileprivate var isScopeFree: Bool {
        switch self {
        case .item, .index, .param, .control: false
        case .literal, .read, .viewer, .clock, .rawState, .lastChanged, .listCount: true
        case .listIncludes(_, _, let value): value.isScopeFree
        case .date(let from, let to), .progress(let from, let to), .secondsBetween(let from, let to): from.isScopeFree && to.isScopeFree
        case .choose(let cases, let otherwise): otherwise.isScopeFree && cases.allSatisfy { $0.when.isScopeFree && $0.then.isScopeFree }
        case .format(_, let args, _): args.values.allSatisfy(\.isScopeFree)
        case .map(let of, let cases, let otherwise): of.isScopeFree && otherwise.isScopeFree && cases.allSatisfy { $0.then.isScopeFree }
        case .math(_, let args), .list(let args): args.allSatisfy(\.isScopeFree)
        case .object(let fields): fields.values.allSatisfy(\.isScopeFree)
        }
    }
}

public extension ServerUIPredicate {
    fileprivate func readSites(upTo cap: Int) -> Int {
        var total = 0
        func add(_ operand: ServerUIOperand) { if total < cap { total += operand.readSites(upTo: cap - total) } }
        switch self {
        case .state: return 1
        case .viewer, .viewerPerson: return 0
        case .numeric(_, _, let above, let below): total = 1; if let above { add(above) }; if let below { add(below) }
        case .all(let items), .any(let items): for item in items where total < cap { total += item.readSites(upTo: cap - total) }
        case .not(let item): return item.readSites(upTo: cap)
        case .compare(_, let left, let right): add(left); add(right)
        case .in(let value, let options): add(value); for option in options { add(option) }
        case .exists(let value): add(value)
        }
        return total
    }

    /// Whether the predicate's answer is the same wherever it is used (see ``ServerUIOperand/isShareable``).
    var isShareable: Bool { !readsClock && isScopeFree }

    fileprivate var isScopeFree: Bool {
        switch self {
        case .state, .viewer, .viewerPerson: true
        case .numeric(_, _, let above, let below): (above?.isScopeFree ?? true) && (below?.isScopeFree ?? true)
        case .all(let items), .any(let items): items.allSatisfy(\.isScopeFree)
        case .not(let item): item.isScopeFree
        case .compare(_, let left, let right): left.isScopeFree && right.isScopeFree
        case .in(let value, let options): value.isScopeFree && options.allSatisfy(\.isScopeFree)
        case .exists(let value): value.isScopeFree
        }
    }
}
