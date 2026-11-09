#if os(iOS)
import HassDesign
import UIKit

// MARK: - Cell protocol

/// What a row's `configure` closure draws into: the collection list's cell (``UKSettingsCell``) or the stack's (``UKSettingsStackCell``).
@MainActor
protocol UKSettingsRowCell: UIView {
    /// Draws `view` as the row's content, inside `insets` (the stack uses its own row padding).
    func showRow(_ view: UIView, insets: NSDirectionalEdgeInsets, minHeight: CGFloat)
    /// The cell is one element that VoiceOver reads as `label`.
    func makeRowElement(label: String, value: String?, hint: String?, traits: UIAccessibilityTraits, identifier: String?)
    var contentConfiguration: UIContentConfiguration? { get set }
    var accessories: [UICellAccessory] { get set }
    /// A view at the row's trailing edge (the switch of a toggle row, a spinner).
    func addTrailing(_ view: UIView)
    /// A row with no cell of its own (the setup notice): no fill, so the view in it is the row.
    var isTransparent: Bool { get set }
}

extension UKSettingsRowCell {
    func show(_ view: UIView, insets: NSDirectionalEdgeInsets = UKSettingsCell.defaultInsets, minHeight: CGFloat = 0) {
        showRow(view, insets: insets, minHeight: minHeight)
    }

    func makeElement(label: String, value: String? = nil, hint: String? = nil, traits: UIAccessibilityTraits = [], identifier: String? = nil) {
        makeRowElement(label: label, value: value, hint: hint, traits: traits, identifier: identifier)
    }
}

// MARK: - Model

/// One row of a ``UKSettingsListDriver``: how to draw it (`configure`, run each time its cell is configured), what it does when
/// tapped, and a signature so a change reconfigures just that cell. A SwiftUI `List` row in the Settings tab and the sheets
/// built from the same list style (Home Assistant settings, the feedback form).
struct UKSettingsListRow {
    var id: String
    /// What the row shows; a different signature reconfigures the cell in place. Typed-into rows keep one stable signature.
    var signature: String
    var isEnabled = true
    var action: (() -> Void)?
    /// What the row is in an ``InsetGroupedStack`` (padding, hairline, press highlight): ``InsetGroupedRowKind``.
    var kind: UKSettingsRowKind
    var configure: (any UKSettingsRowCell) -> Void

    init(id: String, signature: String, isEnabled: Bool = true, kind: UKSettingsRowKind = .link, action: (() -> Void)? = nil,
         configure: @escaping (any UKSettingsRowCell) -> Void) {
        self.id = id
        self.signature = signature
        self.isEnabled = isEnabled
        self.kind = kind
        self.action = action
        self.configure = configure
    }
}

/// ``InsetGroupedRowKind``.
enum UKSettingsRowKind {
    /// A button or link row with a leading glyph and text.
    case link
    /// A button of text alone ("Reset to Default").
    case textButton
    /// A row that holds its own control (a toggle, a slider) or says something without an action.
    case control
}

/// A section of a settings list: an optional header, its rows and an optional footer.
struct UKSettingsListSection {
    enum Header {
        /// ``SettingsSectionHeader``: 15 pt semibold, no uppercasing, the surface's secondary ink.
        case title(String)
        /// A plain `Section { } header: { FormHeader(...) }`: the system's grouped header in the secondary ink (the wallpaper's 85% on a page).
        case system(String)
        /// Any view (`FeedbackFieldHeader`); `label` is what VoiceOver reads, as one heading.
        case view(label: String, signature: String, build: () -> UIView)
    }

    var id: String
    var header: Header?
    var footer: String?
    var footerIdentifier: String?
    /// The footer's ink; nil for the system's secondary label.
    var footerInk: UIColor?
    var rows: [UKSettingsListRow]

    init(id: String, header: Header? = nil, footer: String? = nil, footerIdentifier: String? = nil, footerInk: UIColor? = nil,
         rows: [UKSettingsListRow]) {
        self.id = id
        self.header = header
        self.footer = footer
        self.footerIdentifier = footerIdentifier
        self.footerInk = footerInk
        self.rows = rows
    }
}

// MARK: - Cell

/// A settings row's cell: the system inset grouped cell, on the module tint over the wallpaper or the system cell in a sheet.
/// A row's `configure` puts a view in it (``show(_:insets:minHeight:)``) and says what VoiceOver reads (``makeElement(label:value:hint:traits:identifier:)``).
final class UKSettingsCell: UICollectionViewListCell, UKSettingsRowCell {
    /// How the cell is drawn: the wallpaper's module tint, or the system's grouped cell.
    var style: UKSettingsListDriver.Style = .wallpaper {
        didSet { setNeedsUpdateConfiguration() }
    }
    var showsDisabled = false
    /// A row with no cell of its own (the setup notice): no fill, so the view in it is the row.
    var isTransparent = false {
        didSet { setNeedsUpdateConfiguration() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configurationUpdateHandler = { [weak self] cell, state in
            guard let self else { return }
            var background = UIBackgroundConfiguration.listGroupedCell()
            if self.isTransparent {
                background.backgroundColor = .clear
            } else if self.style == .wallpaper {
                let tint = UKDesignSurface.moduleTint(.thin, reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)
                // The system's pressed row: a light wash over the module.
                background.backgroundColor = state.isHighlighted || state.isSelected ? tint.ukBlend(with: UIColor.white.withAlphaComponent(0.22)) : tint
            }
            cell.backgroundConfiguration = background
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        ukFitted(layoutAttributes)
    }

    /// Clears what the last row left.
    func reset() {
        contentConfiguration = nil
        removeHosted()
        accessories = []
        isAccessibilityElement = false
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityHint = nil
        accessibilityIdentifier = nil
        accessibilityTraits = []
        accessibilityElements = nil
        alpha = 1
        showsDisabled = false
        isTransparent = false
    }

    /// A `List` row's default insets on iPhone: 20 pt either side.
    static let defaultInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    private var hosted: UIView?
    private var hostedConstraints: [NSLayoutConstraint] = []

    /// Draws `view` as the row's content, pinned inside `insets` (added to the content view directly, as the module rows do).
    func addTrailing(_ view: UIView) {
        accessories.append(.customView(configuration: .init(customView: view, placement: .trailing())))
    }

    func showRow(_ view: UIView, insets: NSDirectionalEdgeInsets, minHeight: CGFloat) {
        contentConfiguration = nil
        removeHosted()
        var insets = insets
        // A `List` row's side inset is 20 pt at regular width (iPad), 16 pt on a phone; the standard 14 pt above and below grows to 16.
        if insets == Self.defaultInsets, traitCollection.horizontalSizeClass == .regular {
            insets = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        hosted = view
        hostedConstraints = [
            view.topAnchor.constraint(equalTo: contentView.topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -insets.bottom),
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: insets.leading),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -insets.trailing),
        ]
        if minHeight > 0 { hostedConstraints.append(view.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight)) }
        NSLayoutConstraint.activate(hostedConstraints)
    }

    private func removeHosted() {
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedConstraints = []
        hosted?.removeFromSuperview()
        hosted = nil
    }

    /// The cell is one element (a button, a row of values) that VoiceOver reads as `label`.
    func makeRowElement(label: String, value: String?, hint: String?, traits: UIAccessibilityTraits, identifier: String?) {
        // The view the row put in the cell is the element when there is one, so a button reads as a button (a cell reads as a cell).
        let target: UIView = hosted ?? self
        target.isAccessibilityElement = true
        target.accessibilityLabel = label
        target.accessibilityValue = value
        target.accessibilityHint = hint
        target.accessibilityTraits = traits
        target.accessibilityIdentifier = identifier
        if let hosted {
            isAccessibilityElement = false
            accessibilityElements = [hosted]
        }
    }
}

/// A row view that picks its arrangement from the width it is given (`ViewThatFits`).
@MainActor
protocol UKWidthAdapting: UIView {
    /// Chooses the arrangement for `width`; returns whether it changed (the list then measures the row again).
    func adapt(toWidth width: CGFloat) -> Bool
}

extension UKWidthAdapting {
    /// Call from `layoutSubviews`: adapts to the width the row was given and asks the list to measure again when that changed it.
    func adaptToBounds() {
        guard adapt(toWidth: bounds.width) else { return }
        var view = superview
        while let current = view, !(current is UICollectionView) { view = current.superview }
        guard let list = view as? UICollectionView else {
            // In the stack the row measures through Auto Layout.
            invalidateIntrinsicContentSize()
            DispatchQueue.main.async { [weak self] in self?.superview?.setNeedsLayout() }
            return
        }
        DispatchQueue.main.async { UIView.performWithoutAnimation { list.collectionViewLayout.invalidateLayout() } }
    }
}

extension UIColor {
    /// `overlay` drawn over this colour (both resolved in the current traits): the pressed wash over a module tint.
    func ukBlend(with overlay: UIColor) -> UIColor {
        UIColor { traits in
            let base = self.resolvedColor(with: traits).ukRGBA
            let top = overlay.resolvedColor(with: traits).ukRGBA
            let alpha = top.a + base.a * (1 - top.a)
            guard alpha > 0 else { return .clear }
            func mix(_ over: CGFloat, _ under: CGFloat) -> CGFloat { (over * top.a + under * base.a * (1 - top.a)) / alpha }
            return UIColor(red: mix(top.r, base.r), green: mix(top.g, base.g), blue: mix(top.b, base.b), alpha: alpha)
        }
    }
}

// MARK: - Driver

/// The list under the Settings tab and the sheets that share its look: a `UICollectionView` in the system inset grouped list
/// layout (what a SwiftUI `List` is made of), a diffable data source keyed by row id, in-place reconfiguration by signature, and
/// headers and footers in the Settings text styles. The owner hosts ``collectionView``.
@MainActor
final class UKSettingsListDriver: NSObject, UICollectionViewDelegate {
    enum Style {
        /// Rows are modules over the wallpaper; header and footer text in the fixed light ink.
        case wallpaper
        /// The system's grouped list in a sheet.
        case sheet
    }

    let style: Style
    private(set) var collectionView: UICollectionView!
    private(set) var sections: [UKSettingsListSection] = []
    private var dataSource: UICollectionViewDiffableDataSource<String, String>!
    private var drawn: [String: String] = [:]
    private var drawnHeaders: [String: String] = [:]

    init(style: Style) {
        self.style = style
        super.init()
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.backgroundColor = .clear
            let section = self?.sections[safe: index]
            configuration.headerMode = section?.header != nil ? .supplementary : .none
            configuration.footerMode = section?.footer != nil ? .supplementary : .none
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
        collectionView = UKWidthAwareCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .interactive

        let cell = UICollectionView.CellRegistration<UKSettingsCell, String> { [weak self] cell, _, id in
            guard let self, let row = self.row(id) else { return }
            cell.reset()
            cell.style = self.style
            row.configure(cell)
            if !row.isEnabled && row.action != nil { cell.alpha = 0.4 }
        }
        let header = UICollectionView.SupplementaryRegistration<UKSettingsCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] cell, _, path in
            guard let self, let header = self.sections[safe: path.section]?.header else { return }
            self.configure(header: cell, header)
        }
        let footer = UICollectionView.SupplementaryRegistration<UKSettingsCell>(elementKind: UICollectionView.elementKindSectionFooter) { [weak self] cell, _, path in
            guard let self, let section = self.sections[safe: path.section] else { return }
            self.configure(footer: cell, section)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, path in
            kind == UICollectionView.elementKindSectionHeader
                ? collectionView.dequeueConfiguredReusableSupplementary(using: header, for: path)
                : collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: path)
        }
    }

    // MARK: Data

    /// Shows `newSections`. Rows diff by id; a row whose signature changed is reconfigured in place.
    func setSections(_ newSections: [UKSettingsListSection], animated: Bool = false) {
        sections = newSections
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections(newSections.map(\.id))
        var changed: [String] = []
        var seen: [String: String] = [:]
        var headers: [String: String] = [:]
        for section in newSections {
            snapshot.appendItems(section.rows.map(\.id), toSection: section.id)
            for row in section.rows {
                seen[row.id] = row.signature
                if let before = drawn[row.id], before != row.signature { changed.append(row.id) }
            }
            if case let .view(_, signature, _)? = section.header { headers[section.id] = signature }
        }
        drawn = seen
        snapshot.reconfigureItems(changed.filter { snapshot.indexOfItem($0) != nil })
        let headersChanged = headers != drawnHeaders
        drawnHeaders = headers
        dataSource.apply(snapshot, animatingDifferences: animated && collectionView.window != nil)
        // Headers and footers are not items: refresh the ones on screen when their text changed.
        if collectionView.window != nil {
            for index in newSections.indices {
                if let cell = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: IndexPath(item: 0, section: index)) as? UKSettingsCell {
                    configure(footer: cell, newSections[index])
                }
                if headersChanged, let header = newSections[index].header,
                   let cell = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: index)) as? UKSettingsCell {
                    configure(header: cell, header)
                }
            }
            UIView.performWithoutAnimation { collectionView.collectionViewLayout.invalidateLayout() }
        }
    }

    /// Changes a section's footer text where it stands (the Version footer after a copy).
    func updateFooter(sectionID: String, text: String) {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }), sections[index].footer != text else { return }
        sections[index].footer = text
        if let cell = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: IndexPath(item: 0, section: index)) as? UKSettingsCell {
            configure(footer: cell, sections[index])
            UIView.performWithoutAnimation { collectionView.collectionViewLayout.invalidateLayout() }
        }
    }

    private func row(_ id: String) -> UKSettingsListRow? {
        for section in sections { if let row = section.rows.first(where: { $0.id == id }) { return row } }
        return nil
    }

    // MARK: Headers and footers

    private var headerInk: UIColor { style == .wallpaper ? UKInk.onDarkSecondary : UKDesignInk.secondary }

    private func configure(header cell: UKSettingsCell, _ header: UKSettingsListSection.Header) {
        cell.accessibilityIdentifier = nil
        cell.reset()
        cell.isTransparent = true
        switch header {
        case let .title(title):
            var content = UIListContentConfiguration.groupedHeader()
            content.text = title
            content.textProperties.font = UKFont.rowTitle()
            content.textProperties.color = headerInk
            content.textProperties.transform = .none
            cell.contentConfiguration = content
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = title
            cell.accessibilityTraits = [.header, .staticText]
        case let .system(title):
            var content = UIListContentConfiguration.groupedHeader()
            content.text = title
            content.textProperties.color = style == .wallpaper ? UKDesignSurface.secondaryOnWallpaper : UKDesignInk.secondary
            cell.contentConfiguration = content
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = title
            cell.accessibilityTraits = [.header, .staticText]
        case let .view(label, _, build):
            cell.show(build(), insets: NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = label
            cell.accessibilityTraits = [.header, .staticText]
        }
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .clear
        cell.backgroundConfiguration = background
    }

    private func configure(footer cell: UKSettingsCell, _ section: UKSettingsListSection) {
        cell.reset()
        cell.isTransparent = true
        var content = UIListContentConfiguration.groupedFooter()
        content.text = section.footer
        // A footer on the wallpaper is white unless the section names its own ink: footer text is small, the photo behind it is
        // mid-grey in places, and the system's secondary label (3.9:1) and the 85% wallpaper ink (4.0:1) both failed the Settings
        // contrast audit on the notifications footer. Full white clears 4.5:1 there.
        if let ink = section.footerInk { content.textProperties.color = ink }
        else if style == .wallpaper { content.textProperties.color = UKSettingsInk.wallpaperFooter }
        cell.contentConfiguration = content
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .clear
        cell.backgroundConfiguration = background
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = section.footer
        cell.accessibilityTraits = .staticText
        cell.accessibilityIdentifier = section.footerIdentifier
    }

    // MARK: Delegate

    private func row(at path: IndexPath) -> UKSettingsListRow? { sections[safe: path.section]?.rows[safe: path.item] }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        guard let row = row(at: indexPath) else { return false }
        return row.action != nil && row.isEnabled
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let row = row(at: indexPath) else { return false }
        return row.action != nil && row.isEnabled
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        row(at: indexPath)?.action?()
    }
}
#endif
