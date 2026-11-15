#if os(iOS)
import HassDesign
import UIKit

// MARK: - Content

/// One cell of a record collection: a record by its stable key, or one of the auxiliary cells around the records.
enum UKRecordCollectionItem: Hashable, Sendable {
    /// A one-line message above the records (a load failure, a command error).
    case notice
    /// The Try Again button under a failure.
    case retry
    /// The summary line above the records ("Sorted by Ingredients Available").
    case summary
    /// A group's title.
    case header(String)
    /// One record, by its key.
    case record(String)
    /// The next-page spinner under a grid.
    case footer
}

/// What a record collection shows once: the auxiliary cells above the records, the groups of record keys, and the footer.
struct UKRecordCollectionContent: Equatable {
    /// One group of records, drawn as one module (a list) or one grid, under an optional title.
    struct Group: Equatable {
        let id: String
        let title: String?
        let keys: [String]
        /// Whether the group's rows use the dense module density.
        let dense: Bool
    }

    /// The auxiliary cells above the records, in order.
    var leading: [UKRecordCollectionItem] = []
    var groups: [Group] = []
    var showsFooter = false
}

// MARK: - Owner

/// Supplies and answers for the cells of a ``UKRecordCollectionController``.
///
/// The controller owns scrolling, the data source, the layout and cell reuse; the owner owns what a record looks like and what
/// it does. A cell asks the owner for the view of one key each time it is configured, handing back the view it already holds so a
/// row of the same kind is reconfigured in place.
@MainActor
protocol UKRecordCollectionOwner: AnyObject {
    /// The view for `key`, configured for the current record. `old` is the view the reused cell holds, or nil.
    func recordView(for key: String, reusing old: UIView?) -> UIView?
    /// The swipe actions of a list row.
    func recordSwipe(for key: String, leading: Bool) -> UISwipeActionsConfiguration?
    /// The context menu of a list row.
    func recordMenu(for key: String) -> UIMenu?
    /// A card or row came into view; the model decides whether that asks for the next page.
    func recordDisplayed(_ key: String)
    /// The image a grid card will show, which scrolling ahead of the card prefetches.
    func recordImageURL(for key: String) -> URL?
    /// The view an auxiliary cell hosts.
    func auxiliaryView(for item: UKRecordCollectionItem) -> UIView?
}

// MARK: - Controller

/// The canonical scrolling list or grid of records: a page's one scroller when its body is a single record collection.
///
/// It is a diffable `UICollectionView` whose cells are reused and self-sized. A live change reconfigures only the records the owner
/// names as changed (plus the neighbours whose module corner moved), nothing draws per frame while it scrolls, and a grid pages
/// from `willDisplay`, prefetches images ahead of the cards and lays out on the iPhone Duo's hinge. The geometry is the page
/// base's: the content sits inside ``padding`` and is centred up to ``maxWidth``, so a list or grid lines up with the headings
/// and rows of every other page. Install ``collectionView`` as the page's scroll view
/// (``UKPageViewController/setPageScrollView(_:)``); a page never adds its own insets.
///
/// Rung-0 note: `UICollectionViewCompositionalLayout.list` and `UICollectionViewDiffableDataSource` are the system APIs this is
/// built on; the controller adds only the grid's hinge-aware tracks and the page-base insets, which no system layout provides
/// (precedent: the compiled lists of `UKTodoPageViewController` and `UKRecipeResultsController`, removed in 5304b1e).
@MainActor
final class UKRecordCollectionController: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    /// How the records are laid out.
    enum Shape {
        /// A module of rows (Todo, Inventory).
        case list
        /// Equal-width cards in as many columns as fit (Recipes).
        case grid
    }

    /// One section's role in the layout.
    private enum Block: Equatable {
        case auxiliary
        case header
        case records
    }

    let shape: Shape
    weak var owner: (any UKRecordCollectionOwner)?
    /// Called with a record's key each time its cell is configured; tests use it to prove only changed rows reconfigure.
    var configured: ((String) -> Void)?
    /// The page body's padding. The content is inset by it and centred up to ``maxWidth``.
    var padding = UKPageMetrics.padding { didSet { if padding != oldValue { collectionView.collectionViewLayout.invalidateLayout() } } }
    /// The widest the content runs.
    var maxWidth: CGFloat = .greatestFiniteMagnitude {
        didSet { if maxWidth != oldValue { collectionView.collectionViewLayout.invalidateLayout() } }
    }
    /// The surface the module background draws for; a change reconfigures every row.
    private(set) var surface: TileSurface = .page
    /// The collection view: the page's scroller.
    private(set) lazy var collectionView: UICollectionView = {
        let view = UKWidthAwareCollectionView(frame: .zero, collectionViewLayout: makeLayout())
        view.backgroundColor = .clear
        view.delegate = self
        view.prefetchDataSource = self
        return view
    }()

    private var content = UKRecordCollectionContent()
    private var blocks: [Block] = []
    private var hasApplied = false
    private var prefetching: [String: Task<Void, Never>] = [:]
    private var cardWidth: CGFloat = 160
    private var auxiliarySignatures: [UKRecordCollectionItem: String] = [:]
    private lazy var dataSource: UICollectionViewDiffableDataSource<Int, UKRecordCollectionItem> = makeDataSource()

    /// - Parameter shape: A module of rows or a grid of cards.
    init(shape: Shape) {
        self.shape = shape
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(foldChanged), name: UKHinge.didChange, object: nil)
    }

    // MARK: Applying

    /// Shows `content`, reconfiguring only what changed.
    ///
    /// - Parameters:
    ///   - content: The auxiliary cells, record groups and footer.
    ///   - changed: The keys whose record differs from the one last shown. A key not previously shown is configured on dequeue.
    ///   - signatures: What each auxiliary cell shows; a cell whose signature changed reconfigures (and re-measures).
    ///   - surface: The surface the module background draws for.
    ///   - animated: Whether insertions and removals animate once shown (a completed chore animates away).
    func apply(_ content: UKRecordCollectionContent, changed: Set<String>, signatures: [UKRecordCollectionItem: String] = [:],
               surface: TileSurface, animated: Bool = false) {
        let before = self.content
        let restyled = self.surface != surface
        self.surface = surface
        self.content = content
        var blocks: [Block] = []
        if !content.leading.isEmpty { blocks.append(.auxiliary) }
        for group in content.groups {
            if group.title != nil { blocks.append(.header) }
            blocks.append(.records)
        }
        if content.showsFooter { blocks.append(.auxiliary) }
        self.blocks = blocks

        var snapshot = NSDiffableDataSourceSnapshot<Int, UKRecordCollectionItem>()
        var section = 0
        func append(_ items: [UKRecordCollectionItem]) {
            snapshot.appendSections([section])
            snapshot.appendItems(items, toSection: section)
            section += 1
        }
        if !content.leading.isEmpty { append(content.leading) }
        for group in content.groups {
            if group.title != nil { append([.header(group.id)]) }
            append(group.keys.map { .record($0) })
        }
        if content.showsFooter { append([.footer]) }

        let existing = Set(dataSource.snapshot().itemIdentifiers)
        let previousCorners = Self.corners(before)
        let corners = Self.corners(content)
        let density = Dictionary(content.groups.flatMap { group in group.keys.map { ($0, group.dense) } }, uniquingKeysWith: { first, _ in first })
        let previousDensity = Dictionary(before.groups.flatMap { group in group.keys.map { ($0, group.dense) } }, uniquingKeysWith: { first, _ in first })
        var reconfigured: [UKRecordCollectionItem] = []
        for group in content.groups {
            for key in group.keys {
                let item = UKRecordCollectionItem.record(key)
                guard existing.contains(item) else { continue }
                if restyled || changed.contains(key) || previousCorners[key] != corners[key] || previousDensity[key] != density[key] {
                    reconfigured.append(item)
                }
            }
        }
        var auxiliary = content.leading
        if content.showsFooter { auxiliary.append(.footer) }
        for group in content.groups where group.title != nil { auxiliary.append(.header(group.id)) }
        for item in auxiliary where existing.contains(item) && auxiliarySignatures[item] != signatures[item] {
            reconfigured.append(item)
        }
        auxiliarySignatures = signatures
        snapshot.reconfigureItems(reconfigured)
        dataSource.apply(snapshot, animatingDifferences: animated && hasApplied && collectionView.window != nil)
        hasApplied = true
        collectionView.collectionViewLayout.invalidateLayout()
    }

    /// Each key's place in its module (first and last), the corners a row's background rounds.
    private static func corners(_ content: UKRecordCollectionContent) -> [String: [Bool]] {
        Dictionary(content.groups.flatMap { group in
            group.keys.enumerated().map { index, key in (key, [index == 0, index == group.keys.count - 1]) }
        }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Reading

    /// The views the visible cells hold, by record key.
    var visibleViews: [String: UIView] {
        var views: [String: UIView] = [:]
        for cell in collectionView.visibleCells {
            if let cell = cell as? UKRecordRowCell, let key = cell.key, let view = cell.hosted { views[key] = view }
            if let cell = cell as? UKRecordCardCell, let key = cell.key, let view = cell.hosted { views[key] = view }
        }
        return views
    }

    /// The keys of the records whose cells are on screen.
    var visibleKeys: [String] {
        collectionView.indexPathsForVisibleItems.sorted().compactMap { path in
            if case .record(let key)? = dataSource.itemIdentifier(for: path) { key } else { nil }
        }
    }

    /// Tells the owner each visible record was displayed (a window that has just been laid out shows its cards without `willDisplay`).
    func reportVisible() {
        for key in visibleKeys { owner?.recordDisplayed(key) }
    }

    /// The card width the grid last laid out, in points.
    var gridCardWidth: CGFloat { cardWidth }

    // MARK: Data source

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Int, UKRecordCollectionItem> {
        let row = UICollectionView.CellRegistration<UKRecordRowCell, UKRecordCollectionItem> { [weak self] cell, path, item in
            guard let self, case .record(let key) = item else { return }
            let group = self.group(at: path.section)
            cell.key = key
            let view = self.owner?.recordView(for: key, reusing: cell.hosted)
            cell.configure(view, first: path.item == 0, last: path.item == (group?.keys.count ?? 0) - 1, surface: self.surface,
                           density: group?.dense == true ? .dense : .thin)
            self.configured?(key)
        }
        let card = UICollectionView.CellRegistration<UKRecordCardCell, UKRecordCollectionItem> { [weak self] cell, _, item in
            guard let self, case .record(let key) = item else { return }
            cell.key = key
            cell.configure(self.owner?.recordView(for: key, reusing: cell.hosted))
            self.configured?(key)
        }
        let auxiliary = UICollectionView.CellRegistration<UKRecordAuxiliaryCell, UKRecordCollectionItem> { [weak self] cell, _, item in
            cell.configure(self?.owner?.auxiliaryView(for: item), footer: item == .footer)
        }
        return UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collection, path, item in
            guard let self else { return nil }
            switch item {
            case .record:
                return shape == .grid ? collection.dequeueConfiguredReusableCell(using: card, for: path, item: item)
                    : collection.dequeueConfiguredReusableCell(using: row, for: path, item: item)
            default:
                return collection.dequeueConfiguredReusableCell(using: auxiliary, for: path, item: item)
            }
        }
    }

    /// The record group whose records are in `section`.
    private func group(at section: Int) -> UKRecordCollectionContent.Group? {
        guard blocks.indices.contains(section), blocks[section] == .records else { return nil }
        let index = blocks[..<section].filter { $0 == .records }.count
        return content.groups.indices.contains(index) ? content.groups[index] : nil
    }

    // MARK: Layout

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            self?.section(index, environment) ?? Self.emptySection()
        }
    }

    private static func emptySection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(1))
        return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
    }

    /// The content's leading edge and width inside a container `width` wide: the page body's rule (``UKPageScrollView``).
    static func column(in width: CGFloat, padding: UIEdgeInsets, maxWidth: CGFloat) -> (leading: CGFloat, width: CGFloat) {
        let available = max(0, width)
        let inner = min(maxWidth, max(0, available - padding.left - padding.right))
        return (padding.left + max(0, (available - padding.left - padding.right - inner) / 2), inner)
    }

    private func section(_ index: Int, _ environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        guard blocks.indices.contains(index) else { return Self.emptySection() }
        let width = environment.container.effectiveContentSize.width
        let place = Self.column(in: width, padding: padding, maxWidth: maxWidth)
        let rightToLeft = environment.traitCollection.layoutDirection == .rightToLeft
        let trailing = max(0, width - place.leading - place.width)
        let top: CGFloat
        if index == 0 { top = padding.top }
        else { top = blocks[index - 1] == .auxiliary ? 0 : HassTokens.Spacing.m }
        let bottom: CGFloat = index == blocks.count - 1 ? padding.bottom : 0
        let insets = NSDirectionalEdgeInsets(top: top, leading: rightToLeft ? trailing : place.leading, bottom: bottom,
                                             trailing: rightToLeft ? place.leading : trailing)
        if shape == .grid, blocks[index] == .records {
            return gridSection(inner: place.width, leading: place.leading, insets: insets, environment: environment)
        }
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = .clear
        if blocks[index] == .records {
            configuration.leadingSwipeActionsConfigurationProvider = { [weak self] path in self?.swipe(at: path, leading: true) }
            configuration.trailingSwipeActionsConfigurationProvider = { [weak self] path in self?.swipe(at: path, leading: false) }
        }
        let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        section.contentInsets = insets
        return section
    }

    /// One grid section: the page base's cards (`RecipeGrid.columnCount` columns, `HassTokens.Spacing.m` apart), or the hinge's tracks on an
    /// iPhone Duo (an even number of equal tracks lying flat; partly folded, as many on each side of the band as fit).
    private func gridSection(inner: CGFloat, leading: CGFloat, insets: NSDirectionalEdgeInsets,
                             environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let spacing = HassTokens.Spacing.m
        let accessibility = environment.traitCollection.ukIsAccessibilitySize
        let section: NSCollectionLayoutSection
        if UKHinge.hasFold, let tracks = foldTracks(inner: inner, leading: leading, spacing: spacing, accessibility: accessibility) {
            cardWidth = tracks[0].width
            let height = tracks[0].width / ImageCard.aspectRatio
            let items = tracks.indices.map { index -> NSCollectionLayoutItem in
                let track = tracks[index]
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(track.width), heightDimension: .estimated(height)))
                let gap = index + 1 < tracks.count ? tracks[index + 1].x - (track.x + track.width) : 0
                item.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: nil, top: nil, trailing: .fixed(gap), bottom: nil)
                return item
            }
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height)), subitems: items)
            group.interItemSpacing = .fixed(0)
            section = NSCollectionLayoutSection(group: group)
        } else {
            let columns = RecipeGrid.columnCount(width: inner, accessibilitySize: accessibility)
            let each = max(1, (inner - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            cardWidth = each
            let height = each / ImageCard.aspectRatio
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                                                                                  heightDimension: .estimated(height)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height)),
                repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(spacing)
            section = NSCollectionLayoutSection(group: group)
        }
        section.interGroupSpacing = spacing
        section.contentInsets = insets
        return section
    }

    /// The card tracks on an iPhone Duo (either pose): equal tracks lying flat, so they are symmetric about the page's midpoint, and,
    /// partly folded, as many on each side of the hinge band as fit (``DynamicGridMetrics``, as the tile grids do). Nil for one track.
    private func foldTracks(inner: CGFloat, leading: CGFloat, spacing: CGFloat, accessibility: Bool) -> [DynamicGridMetrics.Track]? {
        guard inner > 0 else { return nil }
        let frame = collectionView.convert(collectionView.bounds, to: nil)
        let band = collectionView.window == nil ? nil : HingeAvoidance.band(
            in: CGRect(x: (frame.minX + leading).rounded(), y: 0, width: inner.rounded(), height: 0), hinge: UKHinge.frame)
        let metrics = DynamicGridMetrics(width: inner, minCellWidth: accessibility ? 320 : 160, maxColumns: 8, spacing: spacing,
                                         evenColumns: true, band: band)
        return metrics.tracks.count >= 2 ? metrics.tracks : nil
    }

    /// A change of fold re-tracks the cards one turn after it is published, so the reflow runs inside ``UKReflow``'s animation.
    @objc private func foldChanged() {
        DispatchQueue.main.async { [weak self] in self?.collectionView.collectionViewLayout.invalidateLayout() }
    }

    // MARK: Interaction

    private func swipe(at path: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
        guard case .record(let key)? = dataSource.itemIdentifier(for: path) else { return nil }
        return owner?.recordSwipe(for: key, leading: leading)
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool { false }
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { false }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard case .record(let key)? = dataSource.itemIdentifier(for: indexPath), let menu = owner?.recordMenu(for: key) else { return nil }
        return UIContextMenuConfiguration(identifier: key as NSString, previewProvider: nil) { _ in menu }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard case .record(let key)? = dataSource.itemIdentifier(for: indexPath) else { return }
        owner?.recordDisplayed(key)
    }

    // MARK: Prefetch

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard shape == .grid else { return }
        let pixels = Int(max(cardWidth, 1) * collectionView.traitCollection.displayScale)
        for path in indexPaths {
            guard case .record(let key)? = dataSource.itemIdentifier(for: path), prefetching[key] == nil,
                  let url = owner?.recordImageURL(for: key), ImagePipeline.shared.memoryImage(for: url) == nil else { continue }
            prefetching[key] = Task { @MainActor in
                for await _ in ImagePipeline.shared.images(for: url, maxPixel: pixels) {}
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for path in indexPaths {
            guard case .record(let key)? = dataSource.itemIdentifier(for: path) else { continue }
            prefetching.removeValue(forKey: key)?.cancel()
        }
    }
}

// MARK: - Cells

/// One list row: the module background for the row's place, with the owner's row view reused across records.
@MainActor
final class UKRecordRowCell: UICollectionViewListCell {
    private let background = UKModuleRowBackgroundView()
    /// The key of the record the cell shows.
    var key: String?
    /// The row view the cell holds; it survives reuse so a row of the same kind is reconfigured in place.
    private(set) var hosted: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        automaticallyUpdatesBackgroundConfiguration = false
        automaticallyUpdatesContentConfiguration = false
        backgroundConfiguration = .clear()
        backgroundView = background
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ view: UIView?, first: Bool, last: Bool, surface: TileSurface, density: ModuleDensity) {
        background.configure(density: density, surface: surface, isFirst: first, isLast: last, selected: false)
        guard let view, hosted !== view else { return }
        hosted?.removeFromSuperview()
        hosted = view
        contentView.addSubview(view)
        view.ukPin(to: contentView)
    }

    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        ukFitted(attributes)
    }
}

/// One grid card. It sizes itself from the card's own measure, so scrolling does no Auto Layout work.
@MainActor
final class UKRecordCardCell: UICollectionViewCell {
    /// The key of the record the cell shows.
    var key: String?
    /// The card the cell holds; it survives reuse.
    private(set) var hosted: UIView?

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override init(frame: CGRect) { super.init(frame: frame) }

    func configure(_ view: UIView?) {
        guard let view, hosted !== view else { return }
        hosted?.removeFromSuperview()
        hosted = view
        view.frame = contentView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(view)
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes ?? layoutAttributes
        if let card = hosted as? UKGridMeasuring { attributes.size.height = ceil(card.gridHeight(forWidth: layoutAttributes.size.width)) }
        return attributes
    }
}

/// A cell that hosts one owner-held view: a notice, the Try Again button, a summary line, a group title or the next-page spinner.
@MainActor
final class UKRecordAuxiliaryCell: UICollectionViewCell {
    private var hosted: UIView?
    private var bottomGap: CGFloat = 0

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override init(frame: CGRect) { super.init(frame: frame) }

    func configure(_ view: UIView?, footer: Bool) {
        bottomGap = footer ? HassTokens.Spacing.xl : 0
        guard let view else { hosted?.removeFromSuperview(); hosted = nil; return }
        if hosted !== view {
            hosted?.removeFromSuperview()
            hosted = view
            contentView.addSubview(view)
            view.ukPin(to: contentView, insets: UIEdgeInsets(top: 0, left: 0, bottom: bottomGap, right: 0))
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if hosted?.superview === contentView { hosted?.removeFromSuperview() }
        hosted = nil
    }

    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard let measuring = hosted as? UKGridMeasuring else { return ukFitted(attributes) }
        let sized = attributes.copy() as? UICollectionViewLayoutAttributes ?? attributes
        sized.size.height = ceil(measuring.gridHeight(forWidth: attributes.size.width)) + bottomGap
        return sized
    }
}
#endif
