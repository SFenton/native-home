#if os(iOS)
import HassDesign
import UIKit

// MARK: - Solver

/// How a grid is laid out (the inputs of `DynamicGridLayout`).
struct UKGridConfiguration: Equatable {
    var minCellWidth: CGFloat = DynamicGridMetrics.tileMinWidth
    var maxColumns = 4
    var spacing: CGFloat = HassTokens.Spacing.m
    /// Gives every tile row the height of the tallest tile in the grid; heading rows keep their own.
    var equalRowHeights = false
    /// Rounds the column count down to an even number (a window with a hinge).
    var evenColumns = false
    /// The hinge band across the grid, as x offsets from its leading edge.
    var hingeBand: ClosedRange<CGFloat>?
    /// How a row that leaves tracks unused is filled (duo-widths rule 1, `.agents/design/duo-widths.md`).
    var fill = UKGridFill.share
}

/// How a grid fills a row whose items leave tracks unused (a lone tile, a short last row).
enum UKGridFill: Equatable {
    /// The row's width (one side's, while a hinge band crosses the grid) is filled. A grid of one row shares it equally among its items,
    /// never below the width each already has (``DynamicGridMetrics/sharedWidths(base:available:spacing:)``); a grid of more than one row
    /// fills in whole tracks so every edge stays on the other rows' track lines (``DynamicGridMetrics/fillingPlacements(spans:)``). The default.
    case share
    /// Short rows stay leading-aligned at the track width: aspect-ratio media, choice chips, dials, small controls.
    case none
}

/// Where every item of a grid goes.
struct UKGridSolution {
    var metrics: DynamicGridMetrics
    var frames: [CGRect]
    var rowTops: [CGFloat]
    var rowHeights: [CGFloat]
    var height: CGFloat
    /// Which items span their whole row (or their side of a hinge band): the tiles' animation gate (`TileGridGeometry.isFullRow`).
    var fullRow: [Bool]
}

/// `DynamicGridLayout`'s arithmetic: the column rules come from ``DynamicGridMetrics``, the row heights from the items.
enum UKGridSolver {
    /// Lays out `spans.count` items `width` wide.
    /// - Parameters:
    ///   - spans: How many tracks each item claims (`Int.max` for a heading).
    ///   - headers: Which items are full-width headings, which equal row heights skip.
    ///   - minimums: Each item's least width (``TileMinimumWidth``; 0 for none). A tile whose content does not fit its tracks takes more of
    ///     them, up to the row (owner, 2026-11-01, content-aware span): `max(explicit span, ceil(minimum / track))`. Tracks stay equal
    ///     and a short row stays leading-aligned (the 2026-10-30 rule); only the tile that cannot fit widens.
    ///   - height: The height an item wants at the width its tracks give it.
    static func solve(width: CGFloat, configuration: UKGridConfiguration, spans: [Int], headers: [Bool], minimums: [CGFloat] = [],
                      height: (Int, CGFloat) -> CGFloat) -> UKGridSolution {
        // Unbounded: the ideal width, as `sizeThatFits` does for an unspecified proposal.
        let width = width.isFinite ? width
            : configuration.minCellWidth * CGFloat(DynamicGridMetrics.effectiveMaxColumns(configuration.maxColumns, minCellWidth: configuration.minCellWidth))
        let metrics = DynamicGridMetrics(width: width, minCellWidth: configuration.minCellWidth, maxColumns: configuration.maxColumns,
                                         spacing: configuration.spacing, evenColumns: configuration.evenColumns, band: configuration.hingeBand)
        // Owner, 2026-11-01: a tile that declared a minimum takes the tracks its content needs (Quick Links' Security System, the Air
        // Purifier); every other tile keeps its explicit span. A tile is full row when its span is the cap.
        let content = metrics.spans(minimums: minimums.count == spans.count ? minimums : spans.map { _ in 0 }, spacing: configuration.spacing)
        let wanted = spans.indices.map { index -> Int in
            let minimum = index < minimums.count ? minimums[index] : 0
            return minimum > 0 && !headers[index] ? max(spans[index], content[index].span) : spans[index]
        }
        // Grids of small controls never fill (duo-widths rule 4).
        let fill = configuration.minCellWidth < DynamicGridMetrics.controlMaxWidth ? UKGridFill.none : configuration.fill
        var placements = metrics.placements(spans: wanted)
        // A grid of more than one row of tiles snaps each short row to whole tracks; a grid of one row shares the width equally.
        let tileRows = Set(placements.indices.filter { !headers[$0] }.map { placements[$0].row }).count
        let wholeTracks = fill == .share && tileRows > 1
        if wholeTracks { placements = metrics.fillingPlacements(spans: wanted) }
        var xs = placements.map { metrics.frame(column: $0.column, span: $0.span).x }
        var widths = placements.map { metrics.frame(column: $0.column, span: $0.span).width }
        var fullRow = placements.map { metrics.spanCap <= 1 || $0.span >= metrics.spanCap }
        if fill == .share {
            // Each row's items, in run segments (the row, or each side of a band): a fill never crosses a band.
            let rowCount = (placements.map(\.row).max() ?? -1) + 1
            for row in 0..<rowCount {
                let members = placements.indices.filter { placements[$0].row == row && !headers[$0] }
                guard let segments = metrics.fillSegments(of: members.map { (placements[$0].column, placements[$0].span) }) else { continue }
                for segment in segments {
                    let ids = segment.items.map { members[$0] }
                    let extent = metrics.extent(first: segment.first, last: segment.last)
                    if !wholeTracks {
                        let shared = DynamicGridMetrics.sharedWidths(base: ids.map { widths[$0] }, available: extent.width, spacing: configuration.spacing)
                        var x = extent.x
                        for (id, width) in zip(ids, shared) {
                            xs[id] = x
                            widths[id] = width
                            x += width + configuration.spacing
                        }
                    }
                    for id in ids { fullRow[id] = metrics.spanCap <= 1 || widths[id] >= extent.width - 0.5 }
                }
            }
        }
        var rows: [CGFloat] = []
        var headerRows = Set<Int>()
        for (index, place) in placements.enumerated() {
            if place.row >= rows.count { rows.append(0) }
            rows[place.row] = max(rows[place.row], height(index, widths[index]))
            if headers[index] { headerRows.insert(place.row) }
        }
        if configuration.equalRowHeights { rows = DynamicGridLayout.equalized(rows, headerRows: headerRows) }
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for row in rows {
            tops.append(y)
            y += row + configuration.spacing
        }
        let frames = placements.indices.map { index in
            CGRect(x: xs[index], y: tops[placements[index].row], width: widths[index], height: rows[placements[index].row])
        }
        return UKGridSolution(metrics: metrics, frames: frames, rowTops: tops, rowHeights: rows,
                              height: rows.reduce(0, +) + configuration.spacing * CGFloat(max(rows.count - 1, 0)), fullRow: fullRow)
    }
}

/// A view a grid can ask for its height at a width.
@MainActor
protocol UKGridMeasuring: AnyObject {
    func gridHeight(forWidth width: CGFloat) -> CGFloat
    /// The least width the item needs to show its text on one line beside its controls (`TileMinimumWidth`); 0 for no opinion.
    var gridMinimumWidth: CGFloat { get }
}

extension UKGridMeasuring {
    var gridMinimumWidth: CGFloat { 0 }
}

@MainActor
private func ukMinimum(_ view: UIView) -> CGFloat { (view as? UKGridMeasuring)?.gridMinimumWidth ?? 0 }

@MainActor
private func ukMeasure(_ view: UIView, width: CGFloat) -> CGFloat {
    if let measuring = view as? UKGridMeasuring { return measuring.gridHeight(forWidth: width) }
    let fitted = view.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
    if fitted > 0 { return fitted }
    return view.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                        withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
}

// MARK: - View grid

/// One child of a ``UKDynamicGridView``.
struct UKGridItem {
    var view: UIView
    /// How many tracks it claims (`gridSpan(_:)`).
    var span = 1
    /// A heading that takes a whole row (`gridHeader()`).
    var isHeader = false

    init(_ view: UIView, span: Int = 1, isHeader: Bool = false) {
        self.view = view
        self.span = isHeader ? Int.max : span
        self.isHeader = isHeader
    }
}

/// The shared responsive grid (`DynamicGridLayout`, pattern: `.agents/patterns/dynamic-grid.md`) over a list of views, for pages of a
/// few dozen tiles inside a scrolling column. For hundreds of items use ``UKDynamicGridLayout`` on a collection view, which
/// reuses cells.
///
/// Columns are `floor((width + spacing) / (minCellWidth + spacing))` clamped to `1...maxColumns`, leftover width shared equally; with a
/// hinge the count rounds down to an even number and the tracks split around the band (``DynamicGridMetrics``). Size it with
/// ``sizeThatFits(_:)``; it draws nothing itself.
@MainActor
class UKDynamicGridView: UIView, UKGridMeasuring {
    var configuration: UKGridConfiguration { didSet { if configuration != oldValue { invalidate() } } }
    private(set) var items: [UKGridItem] = []
    /// The window's hinge in window coordinates, if any (the unfolded iPhone Duo): the grid rounds to an even column count and keeps
    /// every tile off the band (`HingeAwareGrid`).
    var hinge: CGRect? { didSet { if hinge != oldValue { invalidate() } } }

    /// A page grid reads the window's fold itself (owner, 2026-11-01): the band while the Duo is partly folded (``hinge``), and, in
    /// either pose, the even track count that keeps the tracks symmetric about the page's midpoint (lying flat there is no gap).
    /// It follows ``UKHinge`` and applies a change one turn after it was published, so the posture change reflows inside
    /// ``UKReflow``'s animation and nothing is written from a layout pass. Sheet grids leave it off (a sheet sits in the leading half).
    var followsFold = false {
        didSet {
            guard followsFold != oldValue else { return }
            if followsFold {
                NotificationCenter.default.addObserver(self, selector: #selector(foldChanged), name: UKHinge.didChange, object: nil)
                applyFold()
            } else {
                NotificationCenter.default.removeObserver(self, name: UKHinge.didChange, object: nil)
                hinge = nil
                foldIsPresent = false
            }
        }
    }
    /// The hinge exists in either pose (``UKHinge/hasFold``), copied while ``followsFold``.
    private var foldIsPresent = false { didSet { if foldIsPresent != oldValue { invalidate() } } }

    @objc private func foldChanged() {
        // After the observers of the same publish, before ``UKReflow`` animates (it hops twice).
        DispatchQueue.main.async { [weak self] in self?.applyFold() }
    }

    private func applyFold() {
        guard followsFold, hinge != UKHinge.frame || foldIsPresent != UKHinge.hasFold else { return }
        hinge = UKHinge.frame
        foldIsPresent = UKHinge.hasFold
        // The tracks changed, so the height did: the grids and hand-laid columns above measure again too.
        remeasure()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { applyFold() }
    }

    private var cache: (key: [CGFloat], solution: UKGridSolution)?
    /// The cache key for a set of minimums: tenths of a point, so a changed text size or action count misses and noise does not.
    private func minimumsKey(_ minimums: [CGFloat]) -> CGFloat {
        var hasher = Hasher()
        for minimum in minimums { hasher.combine((minimum * 10).rounded()) }
        return CGFloat(hasher.finalize() % 1_000_003)
    }

    init(configuration: UKGridConfiguration = UKGridConfiguration()) {
        self.configuration = configuration
        super.init(frame: .zero)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKDynamicGridView, _) in view.invalidate() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Replaces the children.
    func setItems(_ items: [UKGridItem]) {
        self.items.forEach { $0.view.removeFromSuperview() }
        self.items = items
        items.forEach { addSubview($0.view) }
        invalidate()
    }

    /// Measures again: a child's content changed, so its height may have.
    func invalidateLayout() { invalidate() }

    private func invalidate() {
        cache = nil
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    /// Forgets the measured tracks (a tile's text changed height); see `remeasure()` in the Rooms lane.
    func invalidateMeasure() { invalidate() }
    /// Measures the children again: call after a child's content changed its height (a tile whose subtitle now wraps).
    func invalidateMeasurements() { invalidate() }

    private func solution(width: CGFloat) -> UKGridSolution {
        var configuration = configuration
        let crossing = (hinge != nil || foldIsPresent) && UKHinge.crossesFold(convert(bounds, to: nil), in: window)
        configuration.evenColumns = configuration.evenColumns || crossing
        if let hinge, window != nil {
            let frame = convert(bounds, to: nil)
            // Position and width only: the height follows the tracks and must not feed back.
            configuration.hingeBand = HingeAvoidance.band(in: CGRect(x: frame.minX.rounded(), y: 0, width: width.rounded(), height: 0), hinge: hinge)
        }
        let minimums = items.map { ukMinimum($0.view) }
        let key = [width, configuration.evenColumns ? 1 : 0, configuration.hingeBand?.lowerBound ?? -1, configuration.hingeBand?.upperBound ?? -1, minimumsKey(minimums),
                   configuration.fill == .share ? 0 : 1]
        if let cache, cache.key == key { return cache.solution }
        let solution = UKGridSolver.solve(width: width, configuration: configuration, spans: items.map(\.span), headers: items.map(\.isHeader),
                                          minimums: minimums) {
            ukMeasure(items[$0].view, width: $1)
        }
        cache = (key, solution)
        return solution
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = size.width.isFinite && size.width > 0 ? size.width : configuration.minCellWidth * CGFloat(configuration.maxColumns)
        return CGSize(width: width, height: solution(width: width).height)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { sizeThatFits(CGSize(width: width, height: 0)).height }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: solution(width: max(bounds.width, 1)).height) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let solution = solution(width: bounds.width)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (index, (item, frame)) in zip(items, solution.frames).enumerated() {
            item.view.frame = mirror ? CGRect(x: bounds.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height) : frame
            if let tile = item.view as? UKGlassTileView { tile.gridFullRow = solution.fullRow[index] }
        }
    }
}

// MARK: - Collection layout

/// What a ``UKDynamicGridLayout`` asks its owner.
@MainActor
protocol UKDynamicGridLayoutDelegate: AnyObject {
    /// How many tracks the item claims; `Int.max` for a heading.
    func gridLayout(_ layout: UKDynamicGridLayout, spanAt indexPath: IndexPath) -> Int
    /// Whether the item is a full-width heading.
    func gridLayout(_ layout: UKDynamicGridLayout, isHeaderAt indexPath: IndexPath) -> Bool
    /// The height the item wants at `width`. Cheap and without side effects: the layout asks for every item once per width.
    func gridLayout(_ layout: UKDynamicGridLayout, heightAt indexPath: IndexPath, width: CGFloat) -> CGFloat
}

extension UKDynamicGridLayoutDelegate {
    func gridLayout(_ layout: UKDynamicGridLayout, spanAt indexPath: IndexPath) -> Int { 1 }
    func gridLayout(_ layout: UKDynamicGridLayout, isHeaderAt indexPath: IndexPath) -> Bool { false }
}

/// `DynamicGridLayout` for a `UICollectionView`: the same columns, spans, headings, equal row heights and hinge band, with the
/// cells reused. Items of every section flow as one grid, in order. The layout measures through its delegate (never by
/// self-sizing), so scrolling does no layout work.
@MainActor
final class UKDynamicGridLayout: UICollectionViewLayout {
    var configuration: UKGridConfiguration { didSet { if configuration != oldValue { invalidateLayout() } } }
    /// Space around the grid inside the scroll content (the SwiftUI `.padding()`).
    var contentInsets: UIEdgeInsets = .zero { didSet { if contentInsets != oldValue { invalidateLayout() } } }
    /// The window's hinge in window coordinates, if any.
    var hinge: CGRect? { didSet { if hinge != oldValue { invalidateLayout() } } }
    weak var delegate: UKDynamicGridLayoutDelegate?

    private var attributes: [UICollectionViewLayoutAttributes] = []
    private var contentSize: CGSize = .zero
    private var solution: UKGridSolution?
    private var preparedWidth: CGFloat = 0

    init(configuration: UKGridConfiguration = UKGridConfiguration()) {
        self.configuration = configuration
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let width = collectionView.bounds.width - contentInsets.left - contentInsets.right
        var configuration = configuration
        let frame = collectionView.convert(collectionView.bounds, to: nil)
        configuration.evenColumns = configuration.evenColumns || (hinge != nil && UKHinge.crossesFold(frame, in: collectionView.window))
        if let hinge {
            configuration.hingeBand = HingeAvoidance.band(
                in: CGRect(x: (frame.minX + contentInsets.left).rounded(), y: 0, width: width.rounded(), height: 0), hinge: hinge)
        }
        var paths: [IndexPath] = []
        for section in 0..<collectionView.numberOfSections {
            for item in 0..<collectionView.numberOfItems(inSection: section) { paths.append(IndexPath(item: item, section: section)) }
        }
        let spans = paths.map { delegate?.gridLayout(self, spanAt: $0) ?? 1 }
        let headers = paths.map { delegate?.gridLayout(self, isHeaderAt: $0) ?? false }
        let solved = UKGridSolver.solve(width: width, configuration: configuration, spans: spans, headers: headers) { [weak self] index, width in
            guard let self else { return 0 }
            return delegate?.gridLayout(self, heightAt: paths[index], width: width) ?? 0
        }
        let mirror = collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        attributes = zip(paths, solved.frames).map { path, frame in
            let attributes = UICollectionViewLayoutAttributes(forCellWith: path)
            let x = mirror ? width - frame.maxX : frame.minX
            attributes.frame = CGRect(x: contentInsets.left + x, y: contentInsets.top + frame.minY, width: frame.width, height: frame.height)
            return attributes
        }
        solution = solved
        preparedWidth = width
        contentSize = CGSize(width: collectionView.bounds.width, height: contentInsets.top + solved.height + contentInsets.bottom)
    }

    override var collectionViewContentSize: CGSize { contentSize }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        // Items are in reading order, so the rows that meet `rect` are a contiguous run.
        guard let first = attributes.firstIndex(where: { $0.frame.maxY >= rect.minY }) else { return [] }
        var result: [UICollectionViewLayoutAttributes] = []
        for index in first..<attributes.count {
            let item = attributes[index]
            if item.frame.minY > rect.maxY { break }
            if item.frame.intersects(rect) { result.append(item) }
        }
        return result
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        var flat = 0
        guard let collectionView else { return nil }
        for section in 0..<indexPath.section { flat += collectionView.numberOfItems(inSection: section) }
        flat += indexPath.item
        return attributes.indices.contains(flat) ? attributes[flat] : nil
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}

// MARK: - Cell

/// A cell that hosts one view filling it: the grid has already measured it, so the cell does no sizing.
@MainActor
final class UKTileCell: UICollectionViewCell {
    static let reuseIdentifier = "UKTileCell"
    /// Bindings of the hosted view to entity boxes; ended when the cell is reused (`prepareForReuse`).
    let bag = UKObservationBag()
    private(set) var hosted: UIView?

    /// Hosts `view`, replacing any other.
    func host(_ view: UIView) {
        guard hosted !== view else { return }
        hosted?.removeFromSuperview()
        hosted = view
        view.frame = contentView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(view)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        bag.removeAll()
    }
}
#endif
