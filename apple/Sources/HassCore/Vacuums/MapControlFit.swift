import Foundation

// MARK: - Corner groups and the fit rule

/// One of the four corners a group of map buttons sits in. They are leading and trailing, so a right-to-left language swaps sides.
public enum MapControlCorner: String, CaseIterable, Sendable {
    case topLeading = "top-leading", topTrailing = "top-trailing", bottomLeading = "bottom-leading", bottomTrailing = "bottom-trailing"

    /// Whether the corner is on the top edge.
    public var isTop: Bool { self == .topLeading || self == .topTrailing }
    /// Whether the corner is on the leading edge.
    public var isLeading: Bool { self == .topLeading || self == .bottomLeading }
}

/// The way a group runs: a row reads leading to trailing, a column top to bottom.
public enum MapControlAxis: String, Sendable { case row, column }

/// The fit rule for corner button groups (`build/design/vacuum-map-ctl.md`, "Fit"), as a pure function over points.
///
/// The Studio holds the same rule in `surface-controls-fit.ts`; both are tested with the same inputs and must give the same counts. The rule
/// never reads a device: a card is a width and a height, so an iPhone, a folded Duo and an iPad are one rule.
public enum MapControlFit {
    /// A button's side: its visible and its hit region (HIG, Buttons: at least 44 by 44 points).
    public static let controlSize = 44.0
    /// The inset from the two card edges of a corner.
    public static let inset = 8.0
    /// The least space between two groups on one edge.
    public static let gap = 12.0

    /// A group as the rule takes it: where it sits, how it runs, and how many buttons it holds.
    public struct Group: Equatable, Sendable {
        public let corner: MapControlCorner
        public let axis: MapControlAxis
        public let count: Int
        public init(corner: MapControlCorner, axis: MapControlAxis, count: Int) {
            self.corner = corner
            self.axis = axis
            self.count = count
        }
    }

    /// What the rule gives one group.
    public struct Result: Equatable, Sendable {
        public let corner: MapControlCorner
        /// The buttons drawn before More (all of them when there is no More).
        public let shown: Int
        /// Whether the last slot is the More button.
        public let more: Bool
        /// The buttons that moved into More.
        public let hidden: Int
    }

    private enum Edge { case top, bottom, leading, trailing }

    /// A group of one has no axis to draw: it counts as a column.
    private static func axis(_ group: Group) -> MapControlAxis { group.count == 1 ? .column : group.axis }

    private static func edge(_ group: Group) -> Edge {
        axis(group) == .row ? (group.corner.isTop ? .top : .bottom) : (group.corner.isLeading ? .leading : .trailing)
    }

    /// The corner at the other end of the edge a group runs along.
    private static func across(_ group: Group) -> MapControlCorner {
        let top = group.corner.isTop, leading = group.corner.isLeading
        switch axis(group) {
        case .row: return top ? (leading ? .topTrailing : .topLeading) : (leading ? .bottomTrailing : .bottomLeading)
        case .column: return top ? (leading ? .bottomLeading : .bottomTrailing) : (leading ? .topLeading : .topTrailing)
        }
    }

    /// How many buttons of each group show on a card of `width` by `height`, and whether More shows, in the order of `groups`.
    ///
    /// A group's length is the card edge its axis runs along; its neighbour is the group at the other end of that edge, which needs its full
    /// length when it runs along the same edge and one button when it crosses it. When both do not fit, a crossing neighbour takes its one
    /// button, two groups on one edge each get at least half, and a group that needs less than half gives the remainder to the other. A
    /// group with more buttons than `k = floor(available / 44)` (at least 1) shows its first `k - 1` and then More.
    public static func fit(width: Double, height: Double, groups: [Group]) -> [Result] {
        groups.map { group in
            let thisEdge = edge(group)
            let length = axis(group) == .row ? width : height
            let neighbour = groups.first { $0.corner == across(group) }
            let along = neighbour.map { edge($0) == thisEdge } ?? false
            let own = controlSize * Double(group.count)
            let theirs = neighbour.map { along ? controlSize * Double($0.count) : controlSize } ?? 0
            let total = length - 2 * inset - (neighbour == nil ? 0 : gap)
            var available = total
            if own + theirs > total {
                if !along {
                    available = total - theirs
                } else {
                    let half = total / 2
                    available = own <= half ? own : theirs < half ? total - theirs : half
                }
            }
            let room = max(1, Int((available / controlSize).rounded(.down)))
            return group.count > room
                ? Result(corner: group.corner, shown: room - 1, more: true, hidden: group.count - (room - 1))
                : Result(corner: group.corner, shown: group.count, more: false, hidden: 0)
        }
    }
}
