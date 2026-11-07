import SwiftUI

/// Pure column math for ``DynamicGridLayout``, separated so it can be unit tested.
public struct DynamicGridMetrics: Equatable, Sendable {
    /// Number of tracks.
    public var columns: Int
    /// Width of one track (the leading side's, where a hinge band splits the grid into two regions).
    public var cellWidth: CGFloat
    /// Every track's x offset and width, in order. Equal tracks and one gutter between neighbours, except across a
    /// hinge band (``init(width:minCellWidth:maxColumns:spacing:evenColumns:band:)``), where the tracks on each side of the
    /// band share that side's width and the gap between the two middle tracks is the band.
    public var tracks: [Track]
    /// While a hinge band splits the grid, the tracks on each side of it (`columns / 2`); nil otherwise. A tile sized from its
    /// content never spans more than this, so it never crosses the band (``spanCap``).
    public var sideColumns: Int?

    /// One track's position within the grid.
    public struct Track: Equatable, Sendable {
        /// Offset from the grid's leading edge.
        public var x: CGFloat
        /// The track's width.
        public var width: CGFloat
    }

    /// The narrowest a tile may be (owner, 2026-10-30): one minimum for every tile grid, scaled by the caller with its text style
    /// (`@ScaledMetric(relativeTo: .subheadline)`). 44 pt target plus a 30 pt glyph column, 12 pt insets and about 80 pt of title
    /// fit in it (HIG Layout, Buttons).
    public static let tileMinWidth: CGFloat = 150
    /// The most tiles in a row (owner, 2026-10-30), whatever the width. Grids of controls narrower than ``controlMaxWidth`` (colour
    /// swatches, alarm modes, day pickers) are not tiles and keep their own caps.
    public static let maxTileColumns = 4
    /// A grid whose minimum is below this is a grid of small controls, not tiles.
    public static let controlMaxWidth: CGFloat = 100

    /// The least width of one section column on a page (room pages, Media, Sprinklers, Vacation: every 340 pt section grid). A section
    /// grid scales its minimum with `.body` but never below this, so text size removes section columns and never adds them
    /// (duo-widths rule 5, `.agents/design/duo-widths.md`): two columns need 704 pt of content at every size.
    public static let sectionMinWidth: CGFloat = 340

    /// The column cap a grid actually uses: its `maxColumns`, never more than ``maxTileColumns`` unless it is a grid of small controls.
    public static func effectiveMaxColumns(_ maxColumns: Int, minCellWidth: CGFloat) -> Int {
        minCellWidth < controlMaxWidth ? max(maxColumns, 1) : min(max(maxColumns, 1), maxTileColumns)
    }

    /// Computes tracks for a width.
    ///
    /// Columns are `floor((width + spacing) / (minCellWidth + spacing))`, clamped to `1...maxColumns` (and to four for tiles,
    /// ``effectiveMaxColumns(_:minCellWidth:)``); leftover width is shared equally by every track, and a short last row keeps the
    /// same tracks from the leading edge (web `dynamicGridLayout.ts`).
    /// A non-finite width (an unbounded `.infinity` size probe) gets every column at the minimum width.
    ///
    /// With `evenColumns` (a window with a hinge, the unfolded iPhone Duo) a count of two or more rounds down to
    /// an even number (``evenRounded(_:)``), so the fold falls between tracks rather than through a tile; a single
    /// track stays single.
    ///
    /// With a `band` (the hinge, in the grid's local x offsets; `.agents/patterns/hinge-avoidance.md`) the grid is laid out
    /// as two regions, the part before the band and the part after it. Each side gets the same number of tracks, as many as fit
    /// in the narrower side (at most half of `maxColumns`), sharing that side's width; the gap between the two middle tracks is
    /// the band itself, so no tile starts under the fold and the fold falls where the grid's own centre does not have to be.
    /// A side narrower than one `minCellWidth`, or a grid limited to one column, ignores the band and lays out as above.
    public init(width: CGFloat, minCellWidth: CGFloat, maxColumns: Int, spacing: CGFloat, evenColumns: Bool = false,
                band: ClosedRange<CGFloat>? = nil) {
        let maxColumns = Self.effectiveMaxColumns(maxColumns, minCellWidth: minCellWidth)
        guard width.isFinite else {
            columns = max(maxColumns, 1)
            cellWidth = minCellWidth
            tracks = (0..<columns).map { Track(x: CGFloat($0) * (minCellWidth + spacing), width: minCellWidth) }
            sideColumns = nil
            return
        }
        if evenColumns, maxColumns >= 2, let band, band.lowerBound > 0, band.upperBound < width {
            let leading = band.lowerBound
            let trailing = width - band.upperBound
            let fitLeading = Int(((leading + spacing) / (minCellWidth + spacing)).rounded(.down))
            let fitTrailing = Int(((trailing + spacing) / (minCellWidth + spacing)).rounded(.down))
            let perSide = min(fitLeading, fitTrailing, maxColumns / 2)
            if perSide >= 1 {
                let count = CGFloat(perSide)
                let leadingCell = max(0, (leading - spacing * (count - 1)) / count)
                let trailingCell = max(0, (trailing - spacing * (count - 1)) / count)
                columns = perSide * 2
                sideColumns = perSide
                cellWidth = leadingCell
                tracks = (0..<perSide).map { Track(x: CGFloat($0) * (leadingCell + spacing), width: leadingCell) }
                    + (0..<perSide).map { Track(x: band.upperBound + CGFloat($0) * (trailingCell + spacing), width: trailingCell) }
                return
            }
        }
        let fit = Int(((width + spacing) / (minCellWidth + spacing)).rounded(.down))
        var columns = min(max(fit, 1), max(maxColumns, 1))
        if evenColumns { columns = Self.evenRounded(columns) }
        self.columns = columns
        let cell = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        self.cellWidth = cell
        tracks = (0..<columns).map { Track(x: CGFloat($0) * (cell + spacing), width: cell) }
        sideColumns = nil
    }

    /// The count rounded down to an even number, never below two: 5 becomes 4, 3 becomes 2. One track (a window
    /// too narrow for two) stays one. Hinge-aware grids use it (`.agents/patterns/dynamic-grid.md`).
    public static func evenRounded(_ columns: Int) -> Int {
        guard columns >= 2 else { return max(columns, 1) }
        return columns - columns % 2
    }

    /// Width of an item spanning `span` tracks (clamped to the track count), as if it started at the first track.
    public func width(span: Int, spacing: CGFloat) -> CGFloat {
        frame(column: 0, span: span).width
    }

    /// The x offset and width of an item that starts at `column` and spans `span` tracks (both clamped to the grid). An
    /// item spanning the hinge band takes the band's width too.
    public func frame(column: Int, span: Int) -> (x: CGFloat, width: CGFloat) {
        let first = min(max(column, 0), columns - 1)
        let last = min(first + max(span, 1) - 1, columns - 1)
        let start = tracks[first], end = tracks[last]
        return (start.x, end.x + end.width - start.x)
    }

    /// Row/column placement for items with the given spans. Rows fill left to right; an item that does
    /// not fit on the current row starts the next. Incomplete rows stay leading-aligned.
    ///
    /// - Parameter sized: Which items are sized from their content (``spans(minimums:spacing:)``), or empty for none. Those
    ///   items never straddle a hinge band (one that would moves to the first track after it) and, in every row but the last,
    ///   share the tracks the row leaves over, so a row of widened tiles fills its width like the web's
    ///   `fillRows: 'except-last'`. Other items (a heading, an explicit `.gridSpan`) place exactly as before.
    public func placements(spans: [Int], sized: [Bool] = []) -> [(row: Int, column: Int, span: Int)] {
        let clamped = spans.map { min(max($0, 1), columns) }
        let sized = sized.count == spans.count ? sized : Array(repeating: false, count: spans.count)
        // Pack once to find the rows, then give each non-last row's spare tracks to its sized items.
        var rows = pack(clamped, sized: sized)
        var spans = clamped
        for row in rows.indices.dropLast() {
            let members = rows[row]
            let eligible = members.filter { sized[$0] && spans[$0] < spanCap }
            guard !eligible.isEmpty else { continue }
            var grew = true
            while grew {
                grew = false
                for index in eligible where spans[index] < spanCap {
                    spans[index] += 1
                    if Self.fits(members.map { spans[$0] }, sized: members.map { sized[$0] }, columns: columns, side: sideColumns) {
                        grew = true
                    } else {
                        spans[index] -= 1
                    }
                }
            }
        }
        rows = pack(spans, sized: sized)
        var result = [(row: Int, column: Int, span: Int)](repeating: (0, 0, 1), count: spans.count)
        for (row, members) in rows.enumerated() {
            var column = 0
            for index in members {
                column = Self.start(column, span: spans[index], sized: sized[index], columns: columns, side: sideColumns)
                result[index] = (row, column, spans[index])
                column += spans[index]
            }
        }
        return result
    }

    /// A run of one row that a fill spreads over: the whole row, or one side of a hinge band.
    public struct FillSegment: Equatable, Sendable {
        /// Positions, in the array passed to ``fillSegments(of:)``, of the items in this run.
        public var items: [Int]
        /// The first track of the run.
        public var first: Int
        /// The last track of the run.
        public var last: Int
    }

    /// Splits one row's items (`column`, `span`) into the runs a fill works within: the whole row, or, while a hinge band splits the
    /// grid, each side of it (a fill never crosses a band). Nil when an item itself spans the band: that row is left as placed.
    public func fillSegments(of row: [(column: Int, span: Int)]) -> [FillSegment]? {
        guard let side = sideColumns else {
            return row.isEmpty ? [] : [FillSegment(items: Array(row.indices), first: 0, last: columns - 1)]
        }
        if row.contains(where: { $0.column < side && $0.column + $0.span > side }) { return nil }
        let leading = row.indices.filter { row[$0].column < side }
        let trailing = row.indices.filter { row[$0].column >= side }
        var result: [FillSegment] = []
        if !leading.isEmpty { result.append(FillSegment(items: leading, first: 0, last: side - 1)) }
        if !trailing.isEmpty { result.append(FillSegment(items: trailing, first: side, last: columns - 1)) }
        return result
    }

    /// The x offset and width of the run of tracks `first...last`.
    public func extent(first: Int, last: Int) -> (x: CGFloat, width: CGFloat) {
        let start = tracks[min(max(first, 0), columns - 1)], end = tracks[min(max(last, 0), columns - 1)]
        return (start.x, end.x + end.width - start.x)
    }

    /// Widths that share a row (or one side of a hinge band): every item gets at least its `base` width, and the width the row
    /// leaves over is shared so the smaller items grow to one common level while the larger ones keep theirs (max-min fair
    /// share). One 150 pt tile fills the whole row; three 150 pt tiles in a 637 pt row become three equal tiles; a 150 pt Vent
    /// beside a 312 pt purifier become two equal halves.
    ///
    /// Never narrower than `base`. Their sum plus the gaps equals `available`, unless the bases already need more, in which case
    /// they are returned unchanged.
    /// - Parameters:
    ///   - base: Each item's width before the fill, in order.
    ///   - available: The row's (or side's) width.
    ///   - spacing: The gutter between neighbours.
    public static func sharedWidths(base: [CGFloat], available: CGFloat, spacing: CGFloat) -> [CGFloat] {
        guard !base.isEmpty, available.isFinite else { return base }
        let total = available - spacing * CGFloat(base.count - 1)
        guard total > base.reduce(0, +) else { return base }
        // Water-fill: find the level `L` where the sum of max(base, L) is `total`. Items wider than the equal share of what is left keep
        // their width and leave the pool, widest first; the rest share what remains.
        var remaining = total
        var left = base.count
        for value in base.sorted(by: >) where left > 1 {
            guard value > remaining / CGFloat(left) else { break }
            remaining -= value
            left -= 1
        }
        let level = remaining / CGFloat(left)
        return base.map { max($0, level) }
    }

    /// Like ``placements(spans:sized:)``, but every row, the last included, hands its spare tracks to its items as whole tracks, so each
    /// edge stays on the track lines of the other rows (duo-widths rule 1, grids of more than one row). Starting from each item's span,
    /// the spare tracks go one at a time to the item with the smallest span, ties to the later item in reading order: three tiles in four
    /// tracks become 1, 1, 2; a 1 and a 2 in four become 2, 2; a lone tile spans the row. A band is a wall: each side of a row is filled
    /// within its own tracks, and a row with an item that spans the band is left as placed.
    public func fillingPlacements(spans: [Int]) -> [(row: Int, column: Int, span: Int)] {
        var placed = placements(spans: spans)
        let rowCount = (placed.map(\.row).max() ?? -1) + 1
        for row in 0..<rowCount {
            let members = placed.indices.filter { placed[$0].row == row }
            guard let segments = fillSegments(of: members.map { (placed[$0].column, placed[$0].span) }) else { continue }
            for segment in segments {
                let ids = segment.items.map { members[$0] }
                var spare = segment.last - segment.first + 1 - ids.reduce(0) { $0 + placed[$1].span }
                while spare > 0 {
                    // The narrowest item; `>=` makes a tie go to the later one.
                    var target = ids[0]
                    for id in ids where placed[id].span <= placed[target].span { target = id }
                    placed[target].span += 1
                    spare -= 1
                }
                var column = segment.first
                for id in ids {
                    placed[id].column = column
                    column += placed[id].span
                }
            }
        }
        return placed
    }

    /// The item indices of each row, packed left to right.
    private func pack(_ spans: [Int], sized: [Bool]) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var column = 0
        for index in spans.indices {
            var start = Self.start(column, span: spans[index], sized: sized[index], columns: columns, side: sideColumns)
            if start + spans[index] > columns, !rows[rows.count - 1].isEmpty {
                rows.append([])
                column = 0
                start = Self.start(0, span: spans[index], sized: sized[index], columns: columns, side: sideColumns)
            }
            rows[rows.count - 1].append(index)
            column = start + spans[index]
        }
        return rows
    }

    /// Where an item that would start at `column` actually starts: a sized item that would straddle the band starts after it.
    private static func start(_ column: Int, span: Int, sized: Bool, columns: Int, side: Int?) -> Int {
        guard sized, let side, span <= side, column < side, column + span > side else { return column }
        return side
    }

    /// Whether one row's items, in order, fit within `columns` tracks.
    private static func fits(_ spans: [Int], sized: [Bool], columns: Int, side: Int?) -> Bool {
        var column = 0
        for (span, isSized) in zip(spans, sized) {
            column = start(column, span: span, sized: isSized, columns: columns, side: side) + span
            if column > columns { return false }
        }
        return true
    }

    // MARK: Content-aware spans

    /// How many tracks a tile sized from its content takes.
    public struct TileSpan: Hashable, Sendable {
        /// Tracks claimed, at least 1 and at most ``DynamicGridMetrics/spanCap``.
        public var span: Int
        /// The tile spans its whole row (or its side of a hinge band) and its minimum still exceeds that width: it cannot widen
        /// any more, so an overflowing line becomes a ticker.
        public var isCapped: Bool
    }

    /// The most tracks a tile sized from its content may take: the whole row, or one side of a hinge band (a span never crosses it).
    public var spanCap: Int { max(sideColumns ?? columns, 1) }

    /// The narrowest track, which spans are measured against.
    public var narrowestTrack: CGFloat { tracks.map(\.width).min() ?? cellWidth }

    /// Each tile's span for its minimum width, against this grid's tracks and cap.
    public func spans(minimums: [CGFloat], spacing: CGFloat) -> [TileSpan] {
        Self.spans(minimums: minimums, trackWidth: narrowestTrack, columns: spanCap, spacing: spacing)
    }

    /// Whether a tile with this minimum width spans its whole row (or its side of a hinge band): the same rule the grid resolves
    /// spans with (``spans(minimums:spacing:)``), asked of one tile. A tile with no minimum takes one track, so it is full row only
    /// in a one-column grid.
    public func spansFullRow(minimum: CGFloat, spacing: CGFloat) -> Bool {
        (spans(minimums: [minimum], spacing: spacing).first?.span ?? 1) >= spanCap
    }

    /// Each tile takes `ceil(minimum / trackWidth)` tracks, counting the gutters it spans (`n` tracks are
    /// `n * trackWidth + (n - 1) * spacing` wide, so with no spacing it is the plain ceiling), capped at `columns`.
    /// A tile with no minimum (0 or less) takes one track.
    ///
    /// Pure: the grid calls it in its second resolve step, after the columns and track width follow from `minCellWidth`, so
    /// nothing is circular (`.agents/patterns/dynamic-grid.md`, content-aware spans).
    /// - Parameters:
    ///   - minimums: Each tile's minimum width, from ``TileMinimumWidth``.
    ///   - trackWidth: One track's width.
    ///   - columns: The most tracks a tile may take (the row, or one side of a hinge band).
    ///   - spacing: The gutter between tracks.
    public static func spans(minimums: [CGFloat], trackWidth: CGFloat, columns: Int, spacing: CGFloat = 0) -> [TileSpan] {
        let cap = max(columns, 1)
        let capWidth = CGFloat(cap) * trackWidth + CGFloat(cap - 1) * spacing
        return minimums.map { minimum in
            guard minimum > 0 else { return TileSpan(span: 1, isCapped: false) }
            guard trackWidth > 0, trackWidth.isFinite, minimum.isFinite else { return TileSpan(span: cap, isCapped: minimum > 0) }
            // Small tolerance: a minimum measured to a hundredth must not push a tile that fits exactly onto another track.
            let needed = ((minimum - 0.01 + spacing) / (trackWidth + spacing)).rounded(.up)
            let span = Int(min(max(needed, 1), CGFloat(cap)))
            return TileSpan(span: span, isCapped: minimum - 0.01 > capWidth)
        }
    }
}

/// How many tracks a child of ``DynamicGridLayout`` claims.
public struct GridSpanKey: LayoutValueKey {
    public static let defaultValue = 1
}

/// The least width a tile needs to show its text on one line beside its controls, declared by the tile from its content
/// (``GlassTile``) and read by ``DynamicGridLayout``, which gives the tile `ceil(minimum / track)` tracks
/// (``DynamicGridMetrics/spans(minimums:trackWidth:columns:spacing:)``). Zero (the default) means the tile has no
/// opinion and takes the span it was given.
public struct TileMinimumWidth: LayoutValueKey {
    public static let defaultValue: CGFloat = 0
}

/// Marks a full-width heading row in a ``DynamicGridLayout``; equal row heights skip it.
public struct GridHeaderKey: LayoutValueKey {
    public static let defaultValue = false
}


/// The shared responsive grid (pattern: `.agents/patterns/dynamic-grid.md`).
public struct DynamicGridLayout: Layout {
    public var minCellWidth: CGFloat
    public var maxColumns: Int
    public var spacing: CGFloat
    /// Gives every tile row the height of the tallest tile in the grid, so a title that wraps to two lines (Master
    /// Bedroom Closet on an iPhone) lifts every tile to match. Heading rows (``View/gridHeader()``) keep their own
    /// height. Measured on every layout pass, so it follows Dynamic Type and rotation. Tiles fill the height they
    /// are offered inside ``View/equalHeightTiles()``.
    public var equalRowHeights: Bool
    /// Rounds the column count down to an even number (``DynamicGridMetrics/evenRounded(_:)``). Set for you from the
    /// environment: grids called as `DynamicGridLayout(...) { }` turn it on while ``SwiftUICore/EnvironmentValues/windowHinge``
    /// is set (the unfolded iPhone Duo), so no tile straddles the fold.
    public var evenColumns = false
    /// The hinge band across this grid, as x offsets from its leading edge (``DynamicGridMetrics/init(width:minCellWidth:maxColumns:spacing:evenColumns:band:)``).
    /// Set for you with `evenColumns`, from the environment's hinge and the grid's own frame.
    public var hingeBand: ClosedRange<CGFloat>?

    /// Creates a grid.
    public init(minCellWidth: CGFloat = 150, maxColumns: Int = 4, spacing: CGFloat = HassTokens.Spacing.m,
                equalRowHeights: Bool = false) {
        self.minCellWidth = minCellWidth
        self.maxColumns = maxColumns
        self.spacing = spacing
        self.equalRowHeights = equalRowHeights
    }

    /// Calls the grid as a view, reading the window's hinge so the column count rounds to an even number across a
    /// fold. A `Layout` cannot read the environment itself, so the call goes through a small wrapper view.
    @MainActor
    public func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HingeAwareGrid(layout: self, content: content())
    }

    /// What one layout pass resolves for a width: the tracks, where each tile goes, and the row heights. Scroll views and
    /// stacks propose the same width several times per pass, and nested grids multiply that; resolving once per width
    /// instead of once per call cut layout work on room pages (`.agents/patterns/dynamic-grid.md`).
    public struct Cache {
        var resolutions: [Key: Resolution] = [:]

        /// What a resolution depends on: the width, the hinge band (which changes the tracks) and the tiles' minimums
        /// (a text-size or action-count change moves them, so no stale rows are served).
        struct Key: Hashable {
            var width: CGFloat
            var bandLower: CGFloat?
            var bandUpper: CGFloat?
            var minimums: Int
        }
    }

    /// The outcome of resolving the grid at one width.
    struct Resolution {
        var metrics: DynamicGridMetrics
        var placements: [(row: Int, column: Int, span: Int)]
        var rows: [CGFloat]
    }

    public func makeCache(subviews: Subviews) -> Cache { Cache() }

    /// Any change to the subviews (or their content) invalidates every measurement.
    public func updateCache(_ cache: inout Cache, subviews: Subviews) { cache.resolutions.removeAll(keepingCapacity: true) }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        // Unspecified or unbounded (`.infinity`, e.g. a hosting view's maximum-size probe): the ideal width.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minCellWidth * CGFloat(maxColumns)
        let rows = resolution(width: width, subviews: subviews, cache: &cache).rows
        let height = rows.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let resolved = resolution(width: bounds.width, subviews: subviews, cache: &cache)
        var rowTops: [CGFloat] = []
        var y = bounds.minY
        for height in resolved.rows {
            rowTops.append(y)
            y += height + spacing
        }
        for (index, subview) in subviews.enumerated() {
            let place = resolved.placements[index]
            let frame = resolved.metrics.frame(column: place.column, span: place.span)
            subview.place(
                at: CGPoint(x: bounds.minX + frame.x, y: rowTops[place.row]),
                proposal: ProposedViewSize(width: frame.width, height: resolved.rows[place.row])
            )
        }
    }

    private func resolution(width: CGFloat, subviews: Subviews, cache: inout Cache) -> Resolution {
        let minimums = subviews.map { $0[TileMinimumWidth.self] }
        let key = Cache.Key(width: width, bandLower: hingeBand?.lowerBound, bandUpper: hingeBand?.upperBound,
                            minimums: Self.minimumsHash(minimums))
        if let resolution = cache.resolutions[key] { return resolution }
        let resolution = resolve(width: width, subviews: subviews, minimums: minimums)
        cache.resolutions[key] = resolution
        return resolution
    }

    /// The columns and track width follow from `minCellWidth` alone; each tile takes its explicit `.gridSpan` (one track by default);
    /// then rows are packed leading-aligned.
    private func resolve(width: CGFloat, subviews: Subviews, minimums: [CGFloat]) -> Resolution {
        let metrics = DynamicGridMetrics(width: width, minCellWidth: minCellWidth, maxColumns: maxColumns, spacing: spacing,
                                         evenColumns: evenColumns, band: hingeBand)
        // Owner, 2026-10-30: tiles never widen to their content. Every track is the same width and a short last row keeps it, so rows
        // line up; text that does not fit wraps or runs as a ticker. `TileMinimumWidth` no longer changes a span.
        let spans = subviews.map { $0[GridSpanKey.self] }
        let placements = metrics.placements(spans: spans)
        var heights: [CGFloat] = []
        var headerRows = Set<Int>()
        for (index, subview) in subviews.enumerated() {
            let place = placements[index]
            let size = subview.sizeThatFits(ProposedViewSize(width: metrics.frame(column: place.column, span: place.span).width, height: nil))
            if place.row >= heights.count { heights.append(0) }
            heights[place.row] = max(heights[place.row], size.height)
            if subview[GridHeaderKey.self] { headerRows.insert(place.row) }
        }
        let rows = equalRowHeights ? Self.equalized(heights, headerRows: headerRows) : heights
        return Resolution(metrics: metrics, placements: placements, rows: rows)
    }

    /// Each tile's span: its explicit `.gridSpan` is a floor, and a tile that declared a minimum takes at least what its content needs
    /// (`max(explicit, content)`).
    static func spans(explicit: [Int], minimums: [CGFloat], metrics: DynamicGridMetrics, spacing: CGFloat) -> [Int] {
        let content = metrics.spans(minimums: minimums, spacing: spacing)
        return explicit.indices.map { minimums[$0] > 0 ? max(explicit[$0], content[$0].span) : explicit[$0] }
    }

    /// A hash of the minimums for the cache key: tenths of a point, so a changed text size or action count misses and noise does not.
    static func minimumsHash(_ minimums: [CGFloat]) -> Int {
        var hasher = Hasher()
        for minimum in minimums { hasher.combine((minimum * 10).rounded()) }
        return hasher.finalize()
    }

    /// Raises every non-heading row to the tallest non-heading row.
    public static func equalized(_ heights: [CGFloat], headerRows: Set<Int>) -> [CGFloat] {
        let tallest = heights.indices.filter { !headerRows.contains($0) }.map { heights[$0] }.max() ?? 0
        return heights.indices.map { headerRows.contains($0) ? heights[$0] : tallest }
    }
}

/// Applies the window's hinge to a ``DynamicGridLayout`` (see ``DynamicGridLayout/callAsFunction(_:)``).
private struct HingeAwareGrid<Content: View>: View {
    var layout: DynamicGridLayout
    var content: Content
    @Environment(\.windowHinge) private var hinge
    /// A hinge exists in either pose: flat, the tracks stay even (so they stay symmetric about the page's midpoint) but have no gap.
    @Environment(\.windowFold) private var fold
    /// The grid's frame in window coordinates (position and width), to tell where the hinge falls across it. Read only
    /// while a hinge is set, so the other devices pay nothing.
    @State private var frame: CGRect = .zero

    var body: some View {
        var layout = layout
        layout.evenColumns = layout.evenColumns || hinge != nil || fold.hinge != nil
        layout.hingeBand = hinge == nil ? nil : HingeAvoidance.band(in: frame, hinge: hinge)
        let geometry = frame.width > 0 && frame.width.isFinite
            ? TileGridGeometry(width: frame.width, minCellWidth: layout.minCellWidth, maxColumns: layout.maxColumns, spacing: layout.spacing,
                               evenColumns: layout.evenColumns, band: layout.hingeBand)
            : nil
        let hasHinge = hinge != nil
        return AnyLayout(layout) { content }
            .environment(\.tileGridGeometry, geometry)
            .onGeometryChange(for: CGRect.self) { proxy in
                // Position (only while a hinge is set) and width: the height follows the tracks and must not feed back.
                let frame = proxy.frame(in: .global)
                return CGRect(x: hasHinge ? frame.minX.rounded() : 0, y: 0, width: frame.width.rounded(), height: 0)
            } action: { frame = $0 }
    }
}


// MARK: - Grid geometry for tiles

/// The geometry a ``DynamicGridLayout`` resolved its tracks from, handed to the tiles inside it through the environment so a tile
/// can tell whether it spans its row (``TileGridGeometry/isFullRow(minimum:)``).
///
/// **It only gates animation.** A tile uses it to decide whether a change of action set may animate its height
/// (``TileActionSetTransition``); layout never reads it, so it cannot feed back into the spans it is computed from and nothing
/// is circular. The grid measures its width with `onGeometryChange` (width only, written when it changes), as it already did for a hinge.
public struct TileGridGeometry: Equatable, Sendable {
    /// The grid's width.
    public var width: CGFloat
    /// The grid's `minCellWidth`, `maxColumns` and `spacing`.
    public var minCellWidth: CGFloat
    public var maxColumns: Int
    public var spacing: CGFloat
    /// Whether the column count rounds to an even number (a hinge is set).
    public var evenColumns: Bool
    /// The hinge band across the grid, in its local x offsets.
    public var band: ClosedRange<CGFloat>?

    /// Creates the geometry.
    public init(width: CGFloat, minCellWidth: CGFloat, maxColumns: Int, spacing: CGFloat, evenColumns: Bool = false,
                band: ClosedRange<CGFloat>? = nil) {
        self.width = width
        self.minCellWidth = minCellWidth
        self.maxColumns = maxColumns
        self.spacing = spacing
        self.evenColumns = evenColumns
        self.band = band
    }

    /// The tracks this geometry resolves.
    public var metrics: DynamicGridMetrics {
        DynamicGridMetrics(width: width, minCellWidth: minCellWidth, maxColumns: maxColumns, spacing: spacing, evenColumns: evenColumns,
                           band: band)
    }

    /// Whether a tile with this minimum width spans its whole row, or its side of the hinge band (``DynamicGridMetrics/spansFullRow(minimum:spacing:)``).
    public func isFullRow(minimum: CGFloat) -> Bool {
        // Tiles no longer widen to their content (owner, 2026-10-30): a tile is full row only in a one-track grid.
        metrics.spanCap <= 1
    }
}

public extension EnvironmentValues {
    /// The enclosing grid's geometry, or nil outside a grid (or before its first measure). Set by ``DynamicGridLayout`` itself.
    @Entry var tileGridGeometry: TileGridGeometry?
}
