#if os(iOS)
import HassCore
import HassDesign
import UIKit

// The list the Sprinklers sheet's pages are built on: a SwiftUI `List` (inset grouped, on the sheet's ground) as UIKit draws it.
// Rows hold a content view that is made once per row id and updated in place when state changes, so a stepper being held or a
// switch being flipped is never rebuilt under the finger; the cell only changes for its own properties (disclosure, selectable,
// edge to edge).

// MARK: - Model

/// One row of a ``UKSprinklerListController``.
struct UKSprinklerRow {
    var id: String
    /// Builds the row's content. Called once per id; the view is kept.
    var make: @MainActor () -> UIView
    /// Shows the current state in the content. Called every time the sections are set, so reads inside it are observed.
    var update: @MainActor (UIView) -> Void = { _ in }
    /// The content runs the full width of the cell, no margins, and the cell draws no background or separator (a row with
    /// `listRowBackground(Color.clear)` and `listRowInsets(EdgeInsets())`).
    var edgeToEdge = false
    var insets = NSDirectionalEdgeInsets(top: 11, leading: 0, bottom: 11, trailing: 0)
    /// A trailing chevron: a `NavigationLink` that is the row's root.
    var disclosure = false
    /// Run when the row is selected (a button or navigation row).
    var action: (() -> Void)?
    /// A row that is not enabled does not highlight or select.
    var isEnabled = true

    /// What the cell draws apart from the content, so only a change here reconfigures it.
    fileprivate var signature: String { "\(edgeToEdge)|\(disclosure)|\(action != nil)|\(isEnabled)" }
}

/// A section: an optional header and footer in the readable secondary ink, and its rows.
struct UKSprinklerSection {
    var id: String
    var header: String?
    var footer: String?
    /// The footer's accessibility identifier.
    var footerIdentifier: String?
    var rows: [UKSprinklerRow]

    init(id: String, header: String? = nil, footer: String? = nil, footerIdentifier: String? = nil, rows: [UKSprinklerRow]) {
        self.id = id
        self.header = header
        self.footer = footer
        self.footerIdentifier = footerIdentifier
        self.rows = rows
    }

    fileprivate var textSignature: String { "\(header ?? "")|\(footer ?? "")|\(footerIdentifier ?? "")" }
}

// MARK: - Controller

/// An inset grouped list on the sheet's ground (a `List` in a sheet). Doubles as the fit scroller of its modal.
@MainActor
class UKSprinklerListController: UKPaneViewController, UICollectionViewDelegate, UKSheetFitting {
    private(set) var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<String, String>!
    private var sections: [UKSprinklerSection] = []
    private var rows: [String: UKSprinklerRow] = [:]
    private var contents: [String: UIView] = [:]
    private var drawnRows: [String: String] = [:]
    private var drawnText: [String: String] = [:]

    var sheetFitScrollView: UIScrollView? { collectionView }

    override func viewDidLoad() {
        super.viewDidLoad()
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.backgroundColor = .clear
            let section = self?.sections[safe: index]
            configuration.headerMode = section?.header != nil ? .supplementary : .none
            configuration.footerMode = section?.footer != nil ? .supplementary : .none
            configuration.itemSeparatorHandler = { [weak self] indexPath, separators in
                nonisolated(unsafe) var result = separators
                MainActor.assumeIsolated {
                    if let id = self?.dataSource.itemIdentifier(for: indexPath), self?.rows[id]?.edgeToEdge == true {
                        result.topSeparatorVisibility = .hidden
                        result.bottomSeparatorVisibility = .hidden
                    }
                }
                return result
            }
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
        collectionView = UKWidthAwareCollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        // Rows whose height follows their width (the pill grid, the day buttons) grow after layout.
        collectionView.selfSizingInvalidation = .enabledIncludingConstraints
        view.addSubview(collectionView)

        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            guard let self, let row = self.rows[id] else { return }
            self.configure(cell, row: row)
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] cell, _, path in
            guard let text = self?.sections[safe: path.section]?.header else { return }
            var content = UIListContentConfiguration.groupedHeader()
            content.text = text
            // `FormHeader`: the readable secondary ink, in the system's small uppercase header.
            content.textProperties.color = UKDesignInk.secondary
            cell.contentConfiguration = content
            cell.accessibilityTraits = .header
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { [weak self] cell, _, path in
            guard let section = self?.sections[safe: path.section], let text = section.footer else { return }
            var content = UIListContentConfiguration.groupedFooter()
            content.text = text
            content.textProperties.color = UKDesignInk.secondary
            cell.contentConfiguration = content
            cell.isAccessibilityElement = section.footerIdentifier != nil
            cell.accessibilityLabel = text
            cell.accessibilityIdentifier = section.footerIdentifier
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, path in
            kind == UICollectionView.elementKindSectionHeader
                ? collectionView.dequeueConfiguredReusableSupplementary(using: header, for: path)
                : collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: path)
        }
        applySnapshot(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // An inset grouped cell is the list's width less its 16 pt side insets: the width a row estimates before it is laid out.
        UKSprinklerWidthDrivenView.estimatedWidth = max(1, collectionView.bounds.width - 2 * HassTokens.Spacing.l)
    }

    /// Shows `newSections`: rows diff by id, their content updates in place, a cell is reconfigured only when its own properties
    /// changed, and a section reloads only when its header or footer text did.
    func setSections(_ newSections: [UKSprinklerSection], animated: Bool = true) {
        sections = newSections
        var newRows: [String: UKSprinklerRow] = [:]
        for section in newSections { for row in section.rows { newRows[row.id] = row } }
        rows = newRows
        for id in contents.keys where newRows[id] == nil { contents.removeValue(forKey: id) }
        for (id, row) in newRows { if let view = contents[id] { row.update(view) } }
        if isViewLoaded { applySnapshot(animated: animated) }
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections(sections.map(\.id))
        var changedRows: [String] = []
        var reloaded: [String] = []
        var seenRows: [String: String] = [:]
        var seenText: [String: String] = [:]
        for section in sections {
            snapshot.appendItems(section.rows.map(\.id), toSection: section.id)
            seenText[section.id] = section.textSignature
            if let before = drawnText[section.id], before != section.textSignature { reloaded.append(section.id) }
            for row in section.rows {
                seenRows[row.id] = row.signature
                if let before = drawnRows[row.id], before != row.signature { changedRows.append(row.id) }
            }
        }
        drawnRows = seenRows
        drawnText = seenText
        snapshot.reconfigureItems(changedRows.filter { snapshot.indexOfItem($0) != nil })
        snapshot.reloadSections(reloaded.filter { snapshot.indexOfSection($0) != nil })
        dataSource.apply(snapshot, animatingDifferences: animated && view.window != nil)
    }

    // MARK: Cells

    private func configure(_ cell: UICollectionViewListCell, row: UKSprinklerRow) {
        let content: UIView
        if let existing = contents[row.id] {
            content = existing
        } else {
            content = row.make()
            contents[row.id] = content
            row.update(content)
        }
        cell.contentConfiguration = UKSprinklerCellContent(view: content, insets: row.insets, edgeToEdge: row.edgeToEdge)
        cell.accessories = row.disclosure ? [.disclosureIndicator()] : []
        cell.backgroundConfiguration = row.edgeToEdge ? UIBackgroundConfiguration.clear() : UIBackgroundConfiguration.listGroupedCell()
        cell.isAccessibilityElement = false
    }

    // MARK: Selection

    private func selectableRow(at indexPath: IndexPath) -> UKSprinklerRow? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id], row.action != nil, row.isEnabled else { return nil }
        return row
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        selectableRow(at: indexPath) != nil
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        selectableRow(at: indexPath) != nil
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        selectableRow(at: indexPath)?.action?()
    }
}

// MARK: - Cell content

/// Hosts a row's content view in a list cell, with the row's insets (relative to the cell's margins, or to its edges).
struct UKSprinklerCellContent: UIContentConfiguration {
    var view: UIView
    var insets: NSDirectionalEdgeInsets
    var edgeToEdge: Bool

    func makeContentView() -> UIView & UIContentView { UKSprinklerCellContentView(self) }
    func updated(for state: UIConfigurationState) -> UKSprinklerCellContent { self }
}

final class UKSprinklerCellContentView: UIView, UIContentView {
    var configuration: UIContentConfiguration { didSet { apply() } }
    private var hosted: UIView?
    private var active: [NSLayoutConstraint] = []

    init(_ configuration: UKSprinklerCellContent) {
        self.configuration = configuration
        super.init(frame: .zero)
        // The row's margins are the list's 16 pt, stated here: a list cell's content view otherwise has none on iOS 27, which put the icon
        // and the switch at the cell's edges.
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: HassTokens.Spacing.l, bottom: 0, trailing: HassTokens.Spacing.l)
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The height is the content's smallest, never the height the list proposes: a canonical row (``UKRowView``) in the cell has no
    /// vertical slack of its own, and the list's unbounded proposal would otherwise be answered with an unbounded height.
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority h: UILayoutPriority, verticalFittingPriority v: UILayoutPriority) -> CGSize {
        super.systemLayoutSizeFitting(CGSize(width: targetSize.width, height: UIView.layoutFittingCompressedSize.height),
                                      withHorizontalFittingPriority: h, verticalFittingPriority: .fittingSizeLevel)
    }

    private func apply() {
        guard let content = configuration as? UKSprinklerCellContent else { return }
        NSLayoutConstraint.deactivate(active)
        // The row views belong to the list, not to a cell, so the list can move one into another cell while this one still holds
        // it: a configuration applied here again then constrained a row that had left, and the app ended (no common ancestor:
        // UKHostedGalleryDriveTests on the Duo, 2026-11-04). Take the row back whenever it is not here, and remove the old one only
        // from this cell, never from the cell it moved to.
        if hosted !== content.view || content.view.superview !== self {
            if let hosted, hosted !== content.view, hosted.superview === self { hosted.removeFromSuperview() }
            content.view.removeFromSuperview()
            content.view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content.view)
            hosted = content.view
        }
        let view = content.view
        // The canonical row carries its own vertical padding and 44 pt minimum; the cell adds only the side margins.
        let ownsPadding = content.edgeToEdge || view is UKRowView
        var constraints = [
            view.topAnchor.constraint(equalTo: topAnchor, constant: ownsPadding ? 0 : content.insets.top),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: ownsPadding ? 0 : -content.insets.bottom),
        ]
        if content.edgeToEdge {
            constraints += [view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor)]
        } else {
            constraints += [
                view.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: content.insets.leading),
                view.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: -content.insets.trailing),
                heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
            ]
        }
        active = constraints
        NSLayoutConstraint.activate(constraints)
    }
}

// MARK: - Width-driven rows

/// A row whose height follows its width (a grid, two rows of buttons): Auto Layout cannot ask a frame-laid view for a height at a
/// width, so the view keeps a height constraint equal to ``height(forWidth:)`` at its current width, and the list (self-sizing
/// invalidation) grows the cell when it changes. Before the first layout it assumes ``estimatedWidth``.
@MainActor
class UKSprinklerWidthDrivenView: UIView {
    /// The width a row is assumed to get before layout (the list sets it).
    static var estimatedWidth: CGFloat = 340

    private var heightConstraint: NSLayoutConstraint!
    private var measuredWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        heightConstraint = heightAnchor.constraint(equalToConstant: HassTokens.minTarget)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The height at `width`. Subclasses override.
    func height(forWidth width: CGFloat) -> CGFloat { HassTokens.minTarget }

    /// Lays the children out in `bounds`. Subclasses override.
    func layoutContent() {}

    /// The content changed in a way that changes its height: measure again.
    func invalidateHeight() {
        measuredWidth = 0
        applyHeight(width: bounds.width > 0 ? bounds.width : Self.estimatedWidth)
        setNeedsLayout()
    }

    private func applyHeight(width: CGFloat) {
        let height = ceil(height(forWidth: width))
        measuredWidth = width
        if heightConstraint.constant != height { heightConstraint.constant = height }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0, abs(bounds.width - measuredWidth) > 0.5 { applyHeight(width: bounds.width) }
        layoutContent()
    }
}
#endif
