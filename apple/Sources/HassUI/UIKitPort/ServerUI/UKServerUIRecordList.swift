#if os(iOS)
import HassDesign
import UIKit

// MARK: - System list interaction host

/// System swipe and context-menu behavior over keyed canonical row views.
@MainActor
final class UKServerUIRecordList: UIView, UKGridMeasuring, UICollectionViewDelegate {
    var swipe: (String, Bool) -> UISwipeActionsConfiguration? = { _, _ in nil }
    var menu: (String) -> UIMenu? = { _ in nil }
    /// Called with a row's key each time its cell is configured; tests use it to prove only changed rows reconfigure.
    var configured: ((String) -> Void)?
    private var keys: [String] = []
    private var rows: [String: UIView] = [:]
    private var surface: TileSurface = .page
    private var density: ModuleDensity = .thin
    private lazy var list: UICollectionView = {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = .clear
        configuration.leadingSwipeActionsConfigurationProvider = { [weak self] path in
            guard let self, let key = dataSource.itemIdentifier(for: path) else { return nil }
            return swipe(key, true)
        }
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] path in
            guard let self, let key = dataSource.itemIdentifier(for: path) else { return nil }
            return swipe(key, false)
        }
        let list = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
        list.backgroundColor = .clear
        list.isScrollEnabled = false
        list.contentInsetAdjustmentBehavior = .never
        list.delegate = self
        list.register(UKServerUIRecordCell.self, forCellWithReuseIdentifier: "record")
        return list
    }()
    private lazy var dataSource: UICollectionViewDiffableDataSource<String, String> = UICollectionViewDiffableDataSource(collectionView: list) { [weak self] collection, path, key in
        guard let self, let view = rows[key],
              let cell = collection.dequeueReusableCell(withReuseIdentifier: "record", for: path) as? UKServerUIRecordCell else { return nil }
        cell.configure(view, first: path.item == 0, last: path.item == keys.count - 1, surface: surface, density: density,
                       animatedCorners: updater.isAnimating)
        configured?(key)
        return cell
    }

    /// The one applier (`.agents/patterns/list-row-removal.md`).
    private lazy var updater = UKListUpdater<String, String>(
        surface: "RecordList", collectionView: list, dataSource: dataSource, generation: { [weak self] in self?.generation?() })
    /// Reads `EntityStore.reapplyGeneration` inside the observation that renders the list.
    var generation: (() -> Int?)?

    init() {
        super.init(frame: .zero)
        addSubview(list)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Applies the keyed rows, reconfiguring only the rows whose content or place on the module changed.
    ///
    /// - Parameters:
    ///   - keys: The row keys in order.
    ///   - rows: The retained row view per key.
    ///   - changed: The keys whose row view was rebuilt or reconfigured; `nil` treats every row as changed.
    ///   - surface: The surface the module background draws for.
    ///   - density: The module density.
    ///   - cause: ``ListUpdateCause/live`` (the default) animates a removal or insertion once the list is on screen; ``ListUpdateCause/reset`` replaces it at once.
    func apply(keys: [String], rows: [String: UIView], changed: Set<String>? = nil, surface: TileSurface,
               density: ModuleDensity = .thin, cause: ListUpdateCause = .live) {
        let previousKeys = self.keys
        let restyled = self.surface != surface || self.density != density
        let moved = Set(keys.indices.filter { index in
            let before = previousKeys.firstIndex(of: keys[index])
            return before.map { ($0 == 0) != (index == 0) || ($0 == previousKeys.count - 1) != (index == keys.count - 1) } ?? false
        }.map { keys[$0] })
        let replaced = Set(keys.filter { key in
            guard let old = self.rows[key], let new = rows[key] else { return false }
            return old !== new
        })
        self.keys = keys; self.rows = rows; self.surface = surface; self.density = density
        let reconfigured = restyled ? Set(keys) : (changed ?? Set(keys)).union(moved).union(replaced)
        if previousKeys != keys || !reconfigured.isDisjoint(with: keys) || dataSource.snapshot().sectionIdentifiers.isEmpty {
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            snapshot.appendSections(["rows"]); snapshot.appendItems(keys)
            let existing = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(keys.filter { existing.contains($0) && reconfigured.contains($0) })
            updater.apply(snapshot, cause: cause, cornerNeighbours: keys.filter { moved.contains($0) && !restyled && previousKeys.contains($0) })
        }
        list.collectionViewLayout.invalidateLayout()
    }

    /// A person is removing the rows `keys` (they confirmed): they animate away, "<title> deleted" is announced and focus moves on.
    func expectRemoval(of keys: [String], title: String? = nil) { updater.expectRemoval(of: keys, title: title) }

    /// The removal failed and the rows stay: no motion, no announcement.
    func cancelExpectation(of keys: [String]) { updater.cancelExpectation(of: keys) }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let key = dataSource.itemIdentifier(for: indexPath), let menu = menu(key) else { return nil }
        return UIContextMenuConfiguration(identifier: key as NSString, previewProvider: nil) { _ in menu }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        keys.reduce(0) { height, key in
            guard let row = rows[key] else { return height }
            if let measuring = row as? UKGridMeasuring { return height + measuring.gridHeight(forWidth: width) }
            return height + ceil(row.systemLayoutSizeFitting(.init(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
        }
    }
    override func layoutSubviews() { super.layoutSubviews(); list.frame = bounds }
}

@MainActor
private final class UKServerUIRecordCell: UICollectionViewListCell {
    private let background = UKModuleRowBackgroundView()
    private var hosted: UIView?
    override init(frame: CGRect) {
        super.init(frame: frame)
        automaticallyUpdatesBackgroundConfiguration = false
        automaticallyUpdatesContentConfiguration = false
        backgroundConfiguration = .clear()
        backgroundView = background
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func configure(_ view: UIView, first: Bool, last: Bool, surface: TileSurface, density: ModuleDensity, animatedCorners: Bool = false) {
        background.configure(density: density, surface: surface, isFirst: first, isLast: last, selected: false, animated: animatedCorners)
        if hosted !== view {
            hosted?.removeFromSuperview()
            hosted = view
            contentView.addSubview(view)
            view.ukPin(to: contentView)
        }
    }
    override func prepareForReuse() { super.prepareForReuse(); hosted?.removeFromSuperview(); hosted = nil }
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        ukFitted(attributes)
    }
}
#endif
