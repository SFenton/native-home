import Foundation

// MARK: - Fold sides (sh.fold-sides@1)

/// The side of the hinge a page's top-level component takes while the iPhone Duo is partly folded sideways (`layout.foldSide`).
public enum ServerUIFoldSide: String, Sendable, Equatable, CaseIterable {
    /// Across the top of both sides.
    case span
    /// The side before the hinge.
    case leading
    /// The side after the hinge.
    case trailing
}

/// The one rule of `sh.fold-sides@1`, equal to the Studio's `resolveFoldSides` (`src/shared/composition/fold-sides.ts`).
///
/// It reads a page's top-level components, in order, and answers each one's side. The rule is pure: it never sees a view, a hinge or a
/// device. `HassUI` lays the answer out (`FoldColumns`, `UKFoldColumns`); the shared evaluation corpus (`evaluation/fold-sides-*`) pins it
/// byte for byte on both sides.
///
/// The page is counted after static filtering and before any rule hides a component:
/// 1. A notification banner and a pinned bar hold no slot and take no side.
/// 2. The run of status strips at the top spans, and so does any component that says `span` inside that run.
/// 3. The rest alternate by position among the rest: the first leads, the next trails, and so on.
/// 4. A written side wins and still holds its position in the count.
/// 5. One placed component leads and the trailing side stays empty.
public enum ServerUIFoldSides {
    /// What the rule reads of a top-level component.
    public enum Kind: Sendable, Equatable {
        /// A status strip (the chip rail): it spans the top of the page while it is split.
        case strip
        /// Any other component that is drawn in the page's column.
        case section
        /// A component the app leaves out before counting (the notification banner): it holds no slot.
        case staticallyHidden
        /// A component drawn outside the scrolling column (the pinned bar): it holds no slot.
        case pinned
    }

    /// One top-level component as the rule reads it: its kind, and the side its `layout.foldSide` writes, if any.
    public struct Input: Sendable, Equatable {
        public var kind: Kind
        public var said: ServerUIFoldSide?

        public init(kind: Kind, said: ServerUIFoldSide? = nil) {
            self.kind = kind
            self.said = said
        }

        /// Whether it holds a slot: not filtered out statically and not pinned. A rule that hides it while the app runs does not matter,
        /// since it keeps its slot.
        public var holdsSlot: Bool { kind != .staticallyHidden && kind != .pinned }
    }

    /// The side of each component, in the page's order; nil for one that holds no slot.
    public static func resolve(_ items: [Input]) -> [ServerUIFoldSide?] {
        var run = true
        var position = 0
        return items.map { item in
            guard item.holdsSlot else { return nil }
            if item.said == .span { return .span }
            if item.said == nil, run, item.kind == .strip { return .span }
            run = false
            defer { position += 1 }
            return item.said ?? (position % 2 == 0 ? .leading : .trailing)
        }
    }

    /// Whether a page lays its sections out in two sides: the switch is on, or a component is pinned to a side.
    /// - Parameters:
    ///   - switchedOn: The page's `layout.foldSides` is `auto`.
    ///   - items: The page's top-level components.
    public static func usesFoldSides(switchedOn: Bool, items: [Input]) -> Bool {
        switchedOn || items.contains { $0.holdsSlot && ($0.said == .leading || $0.said == .trailing) }
    }

    /// The indices of the components whose `span` comes too late: `span` is Across the Top, so it has to come before the first
    /// component that takes a side (a status strip, another `span`, or nothing at all).
    public static func lateSpans(_ items: [Input]) -> [Int] {
        var late: [Int] = []
        var run = true
        for (index, item) in items.enumerated() where item.holdsSlot {
            if item.said == .span {
                if !run { late.append(index) }
                continue
            }
            if !(item.said == nil && item.kind == .strip) { run = false }
        }
        return late
    }

    /// The width a component takes while split, as the corpus records it: the page's width for a spanning one, else its side's region,
    /// each less the page's padding at both of its edges.
    /// - Parameters:
    ///   - side: The component's side.
    ///   - leading: The region before the band.
    ///   - band: The band between the regions.
    ///   - trailing: The region after the band.
    ///   - inset: The page's leading and trailing padding.
    public static func width(of side: ServerUIFoldSide, leading: Double, band: Double, trailing: Double, inset: Double) -> Double {
        let region = switch side {
        case .span: leading + band + trailing
        case .leading: leading
        case .trailing: trailing
        }
        return region - 2 * inset
    }
}

// MARK: - Reading the compiled page

extension ServerUICompositionDocument.Component {
    /// What the fold-sides rule reads of this top-level component.
    public var foldKind: ServerUIFoldSides.Kind {
        switch self {
        case .statusRail: .strip
        case .notificationBanner: .staticallyHidden
        case .pinnedActions: .pinned
        default: .section
        }
    }
}

extension ServerUICompositionDocument.Surface {
    /// The fold-sides input of each top-level component, in order.
    public var foldInputs: [ServerUIFoldSides.Input] {
        components.map { ServerUIFoldSides.Input(kind: $0.foldKind, said: $0.node.foldSide) }
    }

    /// Whether the page lays its sections out in two sides while partly folded (`sh.fold-sides@1`).
    public var usesFoldSides: Bool { ServerUIFoldSides.usesFoldSides(switchedOn: layout.foldSides, items: foldInputs) }

    /// The side of each top-level component, in order; nil for one that holds no slot.
    public var foldSides: [ServerUIFoldSide?] { ServerUIFoldSides.resolve(foldInputs) }
}
