#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Specs

/// One row of a ``UKGroupedFormController``: a view the row builds when its cell is made, what a tap does, and how the cell
/// is dressed (a `Form` row; `.listRowBackground(Color.clear)` and `.listRowInsets(EdgeInsets())` are ``isClear`` and ``fullBleed``).
struct UKFormRowSpec {
    var id: String
    /// Makes the row's content (called each time the cell is configured, so a row view owns its own bindings).
    var build: () -> UIView
    /// Runs when the row is tapped; nil for a row that is not selectable.
    var action: (() -> Void)?
    var accessories: [UICellAccessory] = []
    /// No cell background and no separators.
    var isClear = false
    /// The content takes the cell's whole width, with no margin.
    var fullBleed = false
}

/// A titled form section (`Section { } header: { FormHeader } footer: { FormFooter }`).
struct UKFormSectionSpec {
    var id: String
    var header: String?
    var footer: String?
    var rows: [UKFormRowSpec]
}

// MARK: - Controller

/// A SwiftUI `Form` with `.formStyle(.grouped)` as UIKit draws it: an inset grouped list on the sheet's ground, capped at a
/// readable width and centred (`ClimateForm`), headers and footers in the readable secondary ink (`FormHeader`, `FormFooter`).
/// Rows build their own content; call ``setSections(_:)`` again when the *shape* of the form changes (rows come and go), never
/// for a value, which each row binds for itself.
@MainActor
class UKGroupedFormController: UKPageViewController, UICollectionViewDelegate, UKSheetFitting {
    private(set) var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<String, String>!
    private var sections: [UKFormSectionSpec] = []
    private var rows: [String: UKFormRowSpec] = [:]
    private let maxWidth: CGFloat
    private var applyScheduled = false

    var sheetFitScrollView: UIScrollView? { collectionView }

    init(maxWidth: CGFloat = 720, context: UKContext = .sheetPlaceholder) {
        self.maxWidth = maxWidth
        super.init(context: context.with { $0.surface = .sheet }, title: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.backgroundColor = .clear
            let section = self?.sections[safe: index]
            configuration.headerMode = section?.header != nil ? .supplementary : .none
            configuration.footerMode = section?.footer != nil ? .supplementary : .none
            configuration.itemSeparatorHandler = { [weak self] path, base in
                var separators = base
                if let id = self?.dataSource.itemIdentifier(for: path), self?.rows[id]?.isClear == true {
                    separators.topSeparatorVisibility = .hidden
                    separators.bottomSeparatorVisibility = .hidden
                }
                return separators
            }
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
        collectionView = UKWidthAwareCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        install(scrollView: collectionView)

        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            guard let row = self?.rows[id] else { return }
            cell.accessibilityIdentifier = nil
            cell.contentConfiguration = UKFormRowContent(view: row.build(), fullBleed: row.fullBleed, accessoryWidth: row.accessories.isEmpty ? 0 : 36)
            cell.accessories = row.accessories
            cell.backgroundConfiguration = row.isClear ? .clear() : nil
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] cell, _, path in
            guard let text = self?.sections[safe: path.section]?.header else { return }
            var content = UIListContentConfiguration.groupedHeader()
            content.text = text
            content.textProperties.color = UKDesignInk.secondary
            cell.contentConfiguration = content
            cell.accessibilityTraits = .header
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { [weak self] cell, _, path in
            guard let text = self?.sections[safe: path.section]?.footer else { return }
            var content = UIListContentConfiguration.groupedFooter()
            content.text = text
            content.textProperties.color = UKDesignInk.secondary
            cell.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, path, id in
            collectionView.dequeueConfiguredReusableCell(using: cell, for: path, item: id)
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, path in
            kind == UICollectionView.elementKindSectionHeader
                ? collectionView.dequeueConfiguredReusableSupplementary(using: header, for: path)
                : collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: path)
        }
        applySnapshot()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(view.bounds.width, maxWidth)
        collectionView.frame = CGRect(x: (view.bounds.width - width) / 2, y: 0, width: width, height: view.bounds.height)
    }

    /// Shows `newSections`; rows and sections diff by id.
    func setSections(_ newSections: [UKFormSectionSpec]) {
        sections = newSections
        rows = [:]
        for section in newSections { for row in section.rows { rows[row.id] = row } }
        // Applied on the next turn: the rows' initial reads must not be tracked by the observation that decided the shape.
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            applyScheduled = false
            if isViewLoaded { applySnapshot() }
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections(sections.map(\.id))
        for section in sections { snapshot.appendItems(section.rows.map(\.id), toSection: section.id) }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: Selection

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        sections[safe: indexPath.section]?.rows[safe: indexPath.item]?.action != nil
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        sections[safe: indexPath.section]?.rows[safe: indexPath.item]?.action?()
    }
}

/// Hosts a row's view in a list cell: inside the cell's margins, or edge to edge.
struct UKFormRowContent: UIContentConfiguration {
    var view: UIView
    var fullBleed: Bool
    /// What the cell's accessories (a disclosure chevron) take from the row's width.
    var accessoryWidth: CGFloat = 0

    func makeContentView() -> UIView & UIContentView { UKFormRowContentView(self) }
    func updated(for state: UIConfigurationState) -> UKFormRowContent { self }
}

final class UKFormRowContentView: UIView, UIContentView {
    var configuration: UIContentConfiguration { didSet { apply() } }

    init(_ configuration: UKFormRowContent) {
        self.configuration = configuration
        super.init(frame: .zero)
        // A `Form` row's content sits 16 pt inside the cell (UIView's default margin is 8).
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        apply()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A list cell asserts when its content view reports an unbounded height; a row whose layout leaves the height open falls
    /// back to the content's own fitted size.
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontal: UILayoutPriority,
                                          verticalFittingPriority vertical: UILayoutPriority) -> CGSize {
        let size = super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontal, verticalFittingPriority: vertical)
        guard let child = subviews.first else { return size }
        // A hand-laid grid reports its height for a width (its Auto Layout height is a placeholder until it is laid out): the row
        // takes the height the grid needs at this row's width.
        if let host = child as? UKGridHost, targetSize.width.isFinite, targetSize.width > 1 {
            let inset = (configuration as? UKFormRowContent)?.fullBleed == true ? 0 : layoutMargins.left + layoutMargins.right
            let needed = host.sizeThatFits(CGSize(width: max(targetSize.width - inset, 1), height: .greatestFiniteMagnitude)).height
            return CGSize(width: size.width, height: max(needed + ((configuration as? UKFormRowContent)?.fullBleed == true ? 0 : 14), 1))
        }
        guard size.height > 100_000 else { return size }
        let width = targetSize.width.isFinite ? targetSize.width : size.width
        let fitted = child.systemLayoutSizeFitting(CGSize(width: max(width - layoutMargins.left - layoutMargins.right, 1), height: 0),
                                                   withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return CGSize(width: size.width, height: max(fitted.height.isFinite && fitted.height < 100_000 ? fitted.height : HassTokens.minTarget, HassTokens.minTarget))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A list cell sizes itself once; a wrapping label that measured one line before it had its width leaves the row too short.
        // When the content needs more than the cell has, the cell measures again.
        let wrapped = UKWrapSync.sync(self)
        guard bounds.width > 1 else { return }
        let needed = systemLayoutSizeFitting(CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
                                             withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let key = "\(Int(bounds.width))|\(Int(needed))"
        guard wrapped || (needed > bounds.height + 1 && key != lastRemeasure) else { return }
        lastRemeasure = key
        var ancestor = superview
        while let view = ancestor, !(view is UICollectionViewCell) { ancestor = view.superview }
        ancestor?.invalidateIntrinsicContentSize()
    }

    private var lastRemeasure = ""

    private func apply() {
        guard let content = configuration as? UKFormRowContent else { return }
        subviews.forEach { $0.removeFromSuperview() }
        content.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content.view)
        // A grouped `Form` row is 52 pt at least: the rows' own padding plus 7 pt a side.
        let vertical: CGFloat = content.fullBleed ? 0 : 7
        let leading = content.fullBleed ? leadingAnchor : layoutMarginsGuide.leadingAnchor
        let trailing = content.fullBleed ? trailingAnchor : layoutMarginsGuide.trailingAnchor
        NSLayoutConstraint.activate([
            content.view.topAnchor.constraint(equalTo: topAnchor, constant: vertical),
            content.view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
            content.view.leadingAnchor.constraint(equalTo: leading),
            content.view.trailingAnchor.constraint(equalTo: trailing),
            heightAnchor.constraint(greaterThanOrEqualToConstant: content.fullBleed ? 1 : 52),
        ])
    }
}

// MARK: - Row views

/// A form row that is one element (a navigation link, a checklist row): the canonical row (``UKRowView``, form metrics, on the sheet's
/// inks) with a glyph, a title, an optional second line, an optional value at the trailing edge (under the title when both do not fit on one
/// line, like `LabeledContent`), and the accessibility an explicit label, value, hint and identifier give it.
@MainActor
final class UKFormLinkRow: UKRowView {
    private let bag = UKObservationBag()

    init(title: String, subtitle: String? = nil, symbol: String? = nil, identifier: String?) {
        super.init(.init(title, subtitle: subtitle, symbol: symbol, style: .form), surface: .sheet)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Binds the row to state: `apply` reads observable state and calls `show`/`setEnabled`.
    func bind(_ apply: @escaping @MainActor (UKFormLinkRow) -> Void) {
        bag.observe { [weak self] in
            guard let self else { return }
            apply(self)
        }
    }

    func show(value: String?) {
        var content = rowContent
        content.value = value
        update(content, accessory: accessory)
    }

    func setSubtitle(_ text: String?) {
        var content = rowContent
        content.subtitle = text
        update(content, accessory: accessory)
    }

    func setEnabled(_ enabled: Bool) {
        alpha = enabled ? 1 : 0.4
        accessibilityTraits = enabled ? .button : [.button, .notEnabled]
    }
}
#endif
