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

    /// Whether sharing pays: the tree is shareable and does some work of its own. A literal or a single read costs one box lookup
    /// wherever it is used; a derived value for it would cost more than it saves.
    var isWorthSharing: Bool {
        switch self {
        case .literal, .read, .viewer, .clock, .rawState, .lastChanged, .listCount, .control, .item, .index, .param: false
        default: isShareable
        }
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
