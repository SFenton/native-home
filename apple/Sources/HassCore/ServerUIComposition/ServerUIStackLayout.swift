import Foundation

// MARK: - Stack arrangement (`sh.stack@1`)

/// How a `stack` chooses between its two arrangements: the one it is written in, and the collapsed one a horizontal stack falls back to
/// at an accessibility text size or when the children that must fit beside each other do not.
///
/// The rules are the ones the hand-laid weather card header follows (`UKWeatherCard.layout`): it stacks when the text size is an
/// accessibility size, or when the range text is wider than the room left beside the reading, measured from natural widths that do not
/// depend on the layout chosen, with half a point of tolerance. The shared evaluation corpus (`ContractCorpus/evaluation/stack-reflow-*`)
/// pins them, so the Studio's preview and the app's draw agree. This type only decides; the draw measures and places.
public enum ServerUIStackLayout {

    /// Half a point: a header whose natural widths fit within it does not collapse (the app's rounding tolerance).
    public static let overflowTolerance = 0.5

    /// One child as measured: its natural width in points, and whether it can give room (a text cut with an ellipsis or slid as a ticker).
    public struct Measure: Equatable, Sendable {
        /// The id the groups name the child by.
        public var id: String
        /// The width the child wants, in points.
        public var width: Double
        /// Whether the child can give up width (a truncating text).
        public var shrinks: Bool

        /// Creates a measure.
        public init(id: String, width: Double, shrinks: Bool = false) {
            self.id = id
            self.width = width
            self.shrinks = shrinks
        }
    }

    /// What a stack needs to choose: its rules, its children as measured, the width inside its padding and the text size class.
    public struct Input: Equatable, Sendable {
        /// The axis the stack runs along.
        public var axis: ServerUIStack.Axis
        /// The points between groups.
        public var spacing: ServerUICompositionDocument.Space
        /// The groups, or `nil` for each child on its own.
        public var groups: [ServerUIStack.Group]?
        /// The collapse rule, or `nil`.
        public var collapse: ServerUIStack.Collapse?
        /// The children that are shown, as measured.
        public var children: [Measure]
        /// The width the stack has, in points.
        public var width: Double
        /// Whether the person's text size is an accessibility size.
        public var accessibilitySize: Bool

        /// Creates an input.
        public init(axis: ServerUIStack.Axis, spacing: ServerUICompositionDocument.Space, groups: [ServerUIStack.Group]? = nil, collapse: ServerUIStack.Collapse? = nil,
                    children: [Measure], width: Double, accessibilitySize: Bool) {
            self.axis = axis
            self.spacing = spacing
            self.groups = groups
            self.collapse = collapse
            self.children = children
            self.width = width
            self.accessibilitySize = accessibilitySize
        }
    }

    /// One group of the chosen arrangement, with the defaults filled in.
    public struct GroupLayout: Equatable, Sendable {
        /// The ids of the group's children.
        public var children: [String]
        /// The points between the group's children.
        public var spacing: Double
        /// How the children spread along the group's axis.
        public var distribution: ServerUIStack.Distribution
        /// How the children line up across the group's axis.
        public var align: ServerUIStack.Align
        /// Whether the group takes the room the others leave.
        public var grow: Bool
    }

    /// The arrangement chosen.
    public struct Result: Equatable, Sendable {
        /// Whether the stack changed to a column.
        public var collapsed: Bool
        /// Why it collapsed, or `nil`. When both hold, the text size is named first.
        public var reason: ServerUIStack.Trigger?
        /// The axis the groups run along now.
        public var axis: ServerUIStack.Axis
        /// The points between groups.
        public var spacing: Double
        /// The groups, as arranged.
        public var groups: [GroupLayout]
    }

    /// The arrangement a stack draws now.
    public static func arrange(_ input: Input) -> Result {
        let spacing = input.spacing.points
        let collapse = input.axis == .horizontal ? input.collapse : nil
        var reason: ServerUIStack.Trigger?
        if let collapse {
            if collapse.when.contains(.accessibilitySize), input.accessibilitySize { reason = .accessibilitySize }
            else if collapse.when.contains(.overflow), overflows(input) { reason = .overflow }
        }
        guard let collapse, let reason else {
            return Result(collapsed: false, reason: nil, axis: input.axis, spacing: spacing,
                          groups: resolve(input.groups, children: input.children, spacing: spacing))
        }
        let next = collapse.spacing?.points ?? spacing
        return Result(collapsed: true, reason: reason, axis: .vertical, spacing: next,
                      groups: resolve(collapse.groups ?? input.groups, children: input.children, spacing: next))
    }

    /// Whether the children that must fit do not, side by side.
    ///
    /// A group needs the widest of the children it counts: the ones `fits` names, or, in a group that names none, the ones that cannot give
    /// room. The groups need their widths plus the spacing between them. If `fits` is named and every named width is 0 there is no overflow.
    public static func overflows(_ input: Input) -> Bool {
        let named = Set(input.collapse?.fits ?? [])
        let byID = Dictionary(input.children.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let base = input.groups ?? input.children.map { ServerUIStack.Group(children: [$0.id]) }
        if !named.isEmpty, !named.contains(where: { (byID[$0]?.width ?? 0) > 0 }) { return false }
        var need = 0.0
        for group in base {
            let members = group.children.compactMap { byID[$0] }
            let hasNamed = members.contains { named.contains($0.id) }
            let counted = members.filter { named.contains($0.id) || (!hasNamed && !$0.shrinks) }
            need += max(0, counted.map(\.width).max() ?? 0)
        }
        need += input.spacing.points * Double(max(0, base.count - 1))
        return need > input.width + overflowTolerance
    }

    private static func resolve(_ groups: [ServerUIStack.Group]?, children: [Measure], spacing: Double) -> [GroupLayout] {
        let own = groups ?? children.map { ServerUIStack.Group(children: [$0.id]) }
        return own.map {
            GroupLayout(children: $0.children, spacing: $0.spacing?.points ?? spacing, distribution: $0.distribution, align: $0.align, grow: $0.grow)
        }
    }
}
