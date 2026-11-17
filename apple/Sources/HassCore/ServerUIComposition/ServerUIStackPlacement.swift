import Foundation

// MARK: - Stack placement (`sh.stack@1`)

/// Where the children of a stack go once ``ServerUIStackLayout`` has chosen the arrangement: pure geometry over measured sizes, so the draw
/// is a thin layer over a rule the tests can run on any host.
///
/// Frames are in the stack's content box (inside its padding) from its leading top corner; a right-to-left draw mirrors them. A group is a
/// column when the stack runs horizontally and a row when it is collapsed. A group's `distribution` runs along its own axis and its `align`
/// across it; the stack's `align` places each group across the stack's axis and its `distribution` spreads the groups along it. A line
/// between groups takes the stack's spacing on each side.
public enum ServerUIStackPlacement {
    /// One child as measured.
    public struct Item: Equatable, Sendable {
        /// The id of the child.
        public var id: String
        /// The natural width, in points.
        public var width: Double
        /// Whether the child takes the width of its column (a text that wraps) instead of its natural width.
        public var fillsWidth: Bool
        /// Whether the child can give room (a text cut with an ellipsis or slid as a ticker).
        public var shrinks: Bool

        /// Creates an item.
        public init(id: String, width: Double, fillsWidth: Bool = false, shrinks: Bool = false) {
            self.id = id
            self.width = width
            self.fillsWidth = fillsWidth
            self.shrinks = shrinks
        }
    }

    /// A rectangle in points.
    public struct Frame: Equatable, Sendable {
        /// The distance from the leading edge, in points.
        public var x: Double
        /// The distance from the top, in points.
        public var y: Double
        /// The width, in points.
        public var width: Double
        /// The height, in points.
        public var height: Double

        /// Creates a frame.
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// The placement: each child's frame, the lines between groups and the content size.
    public struct Result: Equatable, Sendable {
        /// The frame of each child, by id.
        public var frames: [String: Frame] = [:]
        /// The frames of the lines between groups.
        public var dividers: [Frame] = []
        /// The width of the content, in points.
        public var width = 0.0
        /// The height of the content, in points.
        public var height = 0.0

        /// An empty placement.
        public init() {}
    }

    /// Places the children of an arrangement.
    /// - Parameters:
    ///   - layout: The arrangement ``ServerUIStackLayout/arrange(_:)`` chose.
    ///   - items: The children that are shown, as measured. A group names children by id; one that is not shown is skipped.
    ///   - align: The stack's `align`, across its axis.
    ///   - distribution: The stack's `distribution`, along its axis.
    ///   - dividerWidth: The width of the line between groups, or `nil` for none.
    ///   - width: The width of the content box.
    ///   - height: A child's height at a width.
    public static func place(_ layout: ServerUIStackLayout.Result, items: [Item], align: ServerUIStack.Align,
                             distribution: ServerUIStack.Distribution, dividerWidth: Double?, width: Double,
                             height: (String, Double) -> Double) -> Result {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = layout.groups.compactMap { group -> (ServerUIStackLayout.GroupLayout, [Item])? in
            let members = group.children.compactMap { byID[$0] }
            return members.isEmpty ? nil : (group, members)
        }
        guard !groups.isEmpty else { return Result() }
        let between = layout.spacing + (dividerWidth.map { layout.spacing + $0 } ?? 0)
        return layout.axis == .horizontal
            ? columns(groups, between: between, spacing: layout.spacing, align: align, distribution: distribution, dividerWidth: dividerWidth,
                      width: width, height: height)
            : rows(groups, between: between, spacing: layout.spacing, align: align, dividerWidth: dividerWidth, width: width, height: height)
    }

    // MARK: Columns side by side (the arrangement a horizontal stack is written in)

    private static func columns(_ groups: [(ServerUIStackLayout.GroupLayout, [Item])], between: Double, spacing: Double,
                                align: ServerUIStack.Align, distribution: ServerUIStack.Distribution, dividerWidth: Double?,
                                width: Double, height: (String, Double) -> Double) -> Result {
        var widths = groups.map { $0.1.map(\.width).max() ?? 0 }
        let gaps = between * Double(groups.count - 1)
        let total = widths.reduce(0, +) + gaps
        var extraGap = 0.0
        if total > width {
            var over = total - width
            // The groups that can give room do, then the rest, each down to nothing.
            for pass in 0..<2 {
                let indices = groups.indices.filter { pass == 0 ? groups[$0].1.contains(where: \.shrinks) : true }
                for index in indices where over > 0 {
                    let give = min(over, widths[index])
                    widths[index] -= give
                    over -= give
                }
            }
        } else {
            let leftover = width - total
            let growers = groups.indices.filter { groups[$0].0.grow }
            if !growers.isEmpty {
                for index in growers { widths[index] += leftover / Double(growers.count) }
            } else if distribution == .spread, groups.count > 1 {
                extraGap = leftover / Double(groups.count - 1)
            }
        }
        // Each group's content height at its width.
        let heights: [[Double]] = groups.indices.map { index in
            groups[index].1.map { height($0.id, $0.fillsWidth ? widths[index] : min($0.width, widths[index])) }
        }
        let content = groups.indices.map { index in
            heights[index].reduce(0, +) + groups[index].0.spacing * Double(max(0, heights[index].count - 1))
        }
        let rowHeight = content.max() ?? 0
        var result = Result()
        var x = 0.0
        for index in groups.indices {
            let (group, members) = groups[index]
            let groupHeight = group.distribution == .spread ? rowHeight : content[index]
            let top: Double = switch align {
            case .start: 0
            case .center: (rowHeight - groupHeight) / 2
            case .end: rowHeight - groupHeight
            }
            let gap = group.distribution == .spread && members.count > 1
                ? (groupHeight - heights[index].reduce(0, +)) / Double(members.count - 1) : group.spacing
            var y = top
            for (member, memberHeight) in zip(members, heights[index]) {
                let memberWidth = member.fillsWidth ? widths[index] : min(member.width, widths[index])
                let left: Double = switch group.align {
                case .start: 0
                case .center: (widths[index] - memberWidth) / 2
                case .end: widths[index] - memberWidth
                }
                result.frames[member.id] = Frame(x: x + left, y: y, width: memberWidth, height: memberHeight)
                y += memberHeight + gap
            }
            x += widths[index]
            if index < groups.count - 1, let dividerWidth {
                result.dividers.append(Frame(x: x + spacing + extraGap / 2, y: 0, width: dividerWidth, height: rowHeight))
            }
            x += between + extraGap
        }
        result.width = max(0, x - between - extraGap)
        result.height = rowHeight
        return result
    }

    // MARK: Rows stacked (the collapsed arrangement)

    private static func rows(_ groups: [(ServerUIStackLayout.GroupLayout, [Item])], between: Double, spacing: Double, align: ServerUIStack.Align,
                             dividerWidth: Double?, width: Double, height: (String, Double) -> Double) -> Result {
        var result = Result()
        var y = 0.0
        for (index, (group, members)) in groups.enumerated() {
            var widths = members.map(\.width)
            var over = widths.reduce(0, +) + group.spacing * Double(members.count - 1) - width
            for pass in 0..<2 {
                for (position, member) in members.enumerated() where over > 0 && (pass == 1 || member.shrinks) {
                    let give = min(over, widths[position])
                    widths[position] -= give
                    over -= give
                }
            }
            let heights = zip(members, widths).map { height($0.id, $1) }
            let rowHeight = heights.max() ?? 0
            let used = widths.reduce(0, +)
            let rowWidth = group.distribution == .spread ? width : used + group.spacing * Double(members.count - 1)
            let gap = group.distribution == .spread && members.count > 1 ? (width - used) / Double(members.count - 1) : group.spacing
            let origin: Double = switch align {
            case .start: 0
            case .center: (width - rowWidth) / 2
            case .end: width - rowWidth
            }
            var x = origin
            for (position, member) in members.enumerated() {
                let top: Double = switch group.align {
                case .start: 0
                case .center: (rowHeight - heights[position]) / 2
                case .end: rowHeight - heights[position]
                }
                result.frames[member.id] = Frame(x: x, y: y + top, width: widths[position], height: heights[position])
                x += widths[position] + gap
            }
            result.width = max(result.width, rowWidth)
            y += rowHeight
            if index < groups.count - 1 {
                if let dividerWidth { result.dividers.append(Frame(x: 0, y: y + spacing, width: width, height: dividerWidth)) }
                y += between
            }
        }
        result.height = y
        return result
    }
}
