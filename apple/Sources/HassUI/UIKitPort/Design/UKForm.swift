#if os(iOS)
import HassDesign
import UIKit

// MARK: - Rows

/// One row of a ``UKFormViewController`` (a SwiftUI `Form` row).
enum UKFormRowKind {
    /// A `Toggle`: the row's title and the system switch.
    case toggle(title: String, isOn: Bool, onChange: (Bool) -> Void)
    /// A `Slider` named for VoiceOver by `label`.
    case slider(label: String, value: Float, range: ClosedRange<Float>, onChange: (Float) -> Void)
    /// A single-choice row (``FilterOptionRow``): title, optional subtitle, optional colour swatch, a checkmark when selected.
    case option(title: String, subtitle: String?, swatch: [UIColor], isSelected: Bool, action: () -> Void)
    /// A text field.
    case text(placeholder: String, text: String, onChange: (String) -> Void)
    /// A text button in the action tint (the Reset row): `title` wraps and the row grows with the text.
    case button(title: String, action: () -> Void)
    /// Any view, as the row's content. A custom row is only redrawn when its row id changes, so content that depends on state either
    /// lives in a view the form keeps and updates in place, or puts that state in the row id (`id: items.isEmpty ? "pick" : "pick-change"`).
    case custom(() -> UIView)
    /// Any view on the bare ground: no cell background, no insets (`.listRowBackground(Color.clear)` + `.listRowInsets(EdgeInsets())`),
    /// for the camera of Add Item and the step's instructions.
    case clear(() -> UIView)
}

struct UKFormRow {
    var id: String
    var kind: UKFormRowKind
    /// The accessibility identifier of the row's control (the switch, the slider, the field) or of the row.
    var identifier: String?

    init(id: String, identifier: String? = nil, _ kind: UKFormRowKind) {
        self.id = id
        self.identifier = identifier
        self.kind = kind
    }
}

/// A titled form section (`FilterSection` + `Section`): the header in the readable secondary ink at section-title size.
struct UKFormSection {
    /// How the header is drawn.
    enum HeaderStyle {
        /// `FilterSection`: section-title size, bold, readable secondary ink, no uppercasing.
        case sectionTitle
        /// A plain `Section { } header: { Text(…) }`: the system's small uppercase header.
        case system
        /// `RecipeSectionHeader`: 15 Semibold in the readable secondary ink, no uppercasing (the Food and Inventory sheets' sections).
        case subheadline
        /// The same, in the regular weight (a generated heading).
        case subheadlineQuiet
    }

    var id: String
    var header: String?
    var footer: String?
    var headerStyle: HeaderStyle
    var rows: [UKFormRow]
    /// The accessibility identifier of the footer (`FormFooter(…).accessibilityIdentifier(…)`).
    var footerIdentifier: String?

    init(id: String, header: String? = nil, footer: String? = nil, headerStyle: HeaderStyle = .sectionTitle, footerIdentifier: String? = nil,
         rows: [UKFormRow]) {
        self.id = id
        self.header = header
        self.footer = footer
        self.headerStyle = headerStyle
        self.footerIdentifier = footerIdentifier
        self.rows = rows
    }
}

// MARK: - Controller

/// A SwiftUI `Form` as UIKit draws it: an inset grouped list on the sheet's ground with the system cells (white in light,
/// `#2C2C2E` in dark), switches, sliders, option rows and text fields, diffable and self-sizing. The page of an edit sheet, a
/// filter sheet or an option picker. Doubles as the fit scroller of its ``UKHassModalController``.
///
/// ```swift
/// let form = UKFormViewController()
/// form.setSections([UKFormSection(id: "main", rows: [UKFormRow(id: "name", identifier: "sizing.edit.name", .text(placeholder: "Task Name", text: name) { name = $0 })])])
/// ```
class UKFormViewController: UKPageViewController, UICollectionViewDelegate, UKSheetFitting {
    private(set) var sections: [UKFormSection] = []
    private(set) var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<String, String>!
    private var updater: UKListUpdater<String, String>!
    private var drawn: [String: String] = [:]
    private var drawnTexts: [String: String] = [:]

    var sheetFitScrollView: UIScrollView? { collectionView }

    init() { super.init(sheetTitle: nil) }

    /// A form page that keeps its caller's environment (the sheet surface, avatars, the navigator).
    init(context: UKContext) { super.init(context: context.with { $0.surface = .sheet }, title: nil) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
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
        install(scrollView: collectionView)

        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            guard let row = self?.row(id) else { return }
            Self.configure(cell, row: row)
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] cell, _, path in
            guard let section = self?.sections[safe: path.section], let text = section.header else { return }
            var content = UIListContentConfiguration.groupedHeader()
            content.text = text
            if section.headerStyle == .sectionTitle {
                // `FilterSection`: the section title weight in FormHeader's readable secondary ink, with no uppercasing.
                content.textProperties.font = .ukFont(.title3, weight: .bold)
                content.textProperties.color = UKDesignInk.secondary
                content.textProperties.transform = .none
            } else if section.headerStyle == .subheadline || section.headerStyle == .subheadlineQuiet {
                content.textProperties.font = .ukFont(.subheadline, weight: section.headerStyle == .subheadline ? .semibold : .regular)
                content.textProperties.color = UKDesignInk.secondary
                content.textProperties.transform = .none
            } else {
                content.textProperties.color = UKDesignInk.secondary
            }
            cell.contentConfiguration = content
            cell.accessibilityTraits = .header
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { [weak self] cell, _, path in
            guard let section = self?.sections[safe: path.section], let text = section.footer else { return }
            var content = UIListContentConfiguration.groupedFooter()
            content.text = text
            content.textProperties.color = UKDesignInk.secondary
            cell.contentConfiguration = content
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
        updater = UKListUpdater(surface: "Form", collectionView: collectionView, dataSource: dataSource, holdsOnlyForRemovals: true)
        applySnapshot(cause: .reset)
    }

    /// Shows `newSections`. A row whose state changed is reconfigured in place; rows and sections diff by id, through ``UKListUpdater``.
    /// - Parameters:
    ///   - animated: `false` replaces the sections at once (``ListUpdateCause/reset``).
    ///   - cause: Overrides `animated`: `.person` for a change the person just made (see ``expectRemoval(of:title:)``), `.live` otherwise.
    func setSections(_ newSections: [UKFormSection], animated: Bool = true, cause: ListUpdateCause? = nil) {
        sections = newSections
        if isViewLoaded { applySnapshot(cause: cause ?? (animated ? .live : .reset)) }
    }

    /// A person is removing the rows `ids`; the sections that hold them leave with the system animation and are announced as
    /// "<title> deleted" when the next ``setSections(_:animated:cause:)`` drops them.
    func expectRemoval(of ids: [String], title: String? = nil) { updater?.expectRemoval(of: ids, title: title) }

    /// The removal failed: the rows stay and nothing moves.
    func cancelExpectation(of ids: [String]) { updater?.cancelExpectation(of: ids) }

    private func row(_ id: String) -> UKFormRow? {
        for section in sections { if let row = section.rows.first(where: { $0.id == id }) { return row } }
        return nil
    }

    private func applySnapshot(cause: ListUpdateCause) {
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections(sections.map(\.id))
        var changed: [String] = []
        var seen: [String: String] = [:]
        for section in sections {
            snapshot.appendItems(section.rows.map(\.id), toSection: section.id)
            for row in section.rows {
                let signature = Self.signature(row.kind)
                seen[row.id] = signature
                if let before = drawn[row.id], before != signature { changed.append(row.id) }
            }
        }
        drawn = seen
        snapshot.reconfigureItems(changed.filter { snapshot.indexOfItem($0) != nil })
        // A header or footer whose words changed (a footer that explains the draft) is drawn again.
        var texts: [String: String] = [:]
        var reloaded: [String] = []
        for section in sections {
            let text = "\(section.header ?? "")|\(section.footer ?? "")"
            texts[section.id] = text
            if let before = drawnTexts[section.id], before != text { reloaded.append(section.id) }
        }
        drawnTexts = texts
        snapshot.reloadSections(reloaded.filter { snapshot.indexOfSection($0) != nil })
        updater.apply(snapshot, cause: cause)
    }

    /// What a row shows, so a state change reconfigures it and nothing else does.
    private static func signature(_ kind: UKFormRowKind) -> String {
        switch kind {
        case let .toggle(title, isOn, _): "toggle|\(title)|\(isOn)"
        case let .slider(label, value, range, _): "slider|\(label)|\(value)|\(range)"
        case let .option(title, subtitle, swatch, isSelected, _): "option|\(title)|\(subtitle ?? "")|\(swatch.count)|\(isSelected)"
        case let .text(placeholder, text, _): "text|\(placeholder)|\(text)"
        case let .button(title, _): "button|\(title)"
        case .custom: "custom"
        case .clear: "clear"
        }
    }

    // MARK: Cells

    private static func configure(_ cell: UICollectionViewListCell, row: UKFormRow) {
        cell.backgroundConfiguration = nil
        cell.contentConfiguration = nil
        cell.accessories = []
        cell.accessibilityElements = nil
        cell.isAccessibilityElement = false
        cell.accessibilityIdentifier = nil
        cell.accessibilityTraits = []
        switch row.kind {
        case let .toggle(title, isOn, onChange):
            var content = UIListContentConfiguration.cell()
            content.text = title
            content.textProperties.font = .ukFont(.body)
            content.textProperties.color = UKDesignInk.primary
            cell.contentConfiguration = content
            let toggle = UISwitch()
            toggle.isOn = isOn
            toggle.accessibilityLabel = title
            toggle.accessibilityIdentifier = row.identifier
            toggle.addAction(UIAction { action in onChange((action.sender as? UISwitch)?.isOn ?? false) }, for: .valueChanged)
            cell.accessories = [.customView(configuration: .init(customView: toggle, placement: .trailing()))]
            cell.accessibilityElements = [toggle]
        case let .slider(label, value, range, onChange):
            let slider = UISlider()
            slider.minimumValue = range.lowerBound
            slider.maximumValue = range.upperBound
            slider.value = value
            slider.accessibilityLabel = label
            slider.accessibilityIdentifier = row.identifier
            slider.addAction(UIAction { action in onChange((action.sender as? UISlider)?.value ?? 0) }, for: .valueChanged)
            cell.contentConfiguration = UKCellContent(view: slider, insets: NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0), minHeight: HassTokens.minTarget)
            cell.accessibilityElements = [slider]
        case let .option(title, subtitle, swatch, isSelected, _):
            let content = UKFilterOptionContent(title: title, subtitle: subtitle, swatch: swatch, isSelected: isSelected)
            cell.contentConfiguration = UKCellContent(view: content, insets: NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0), minHeight: HassTokens.minTarget)
            // The row's content is the element, so it reads as a button (a cell reads as a cell to UI tests).
            content.isAccessibilityElement = true
            content.accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
            content.accessibilityTraits = isSelected ? [.button, .selected] : .button
            content.accessibilityIdentifier = row.identifier
        case let .text(placeholder, text, onChange):
            let field = UITextField()
            field.placeholder = placeholder
            field.text = text
            field.font = .ukFont(.body)
            field.adjustsFontForContentSizeCategory = true
            field.textColor = UKDesignInk.primary
            field.accessibilityIdentifier = row.identifier
            field.accessibilityLabel = placeholder
            field.addAction(UIAction { action in onChange((action.sender as? UITextField)?.text ?? "") }, for: .editingChanged)
            cell.contentConfiguration = UKCellContent(view: field, insets: NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0), minHeight: HassTokens.minTarget)
            cell.accessibilityElements = [field]
        case let .button(title, _):
            // The label wraps and the row grows at AX5, with padding that scales with the text (12 pt either side of the line).
            let label = UILabel.uk(.body, ink: UKDesignInk.action)
            label.text = title
            let pad = UIFontMetrics(forTextStyle: .body).scaledValue(for: 12)
            // The row's content is the element (a cell reads as a cell to UI tests, as the option rows do): it is the whole row, so
            // the target is the row.
            let content = UIView()
            label.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: content.topAnchor, constant: pad), label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -pad),
                label.leadingAnchor.constraint(equalTo: content.leadingAnchor), label.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ])
            cell.contentConfiguration = UKCellContent(view: content, insets: .zero, minHeight: 0)
            content.isAccessibilityElement = true
            content.accessibilityLabel = title
            content.accessibilityTraits = .button
            content.accessibilityIdentifier = row.identifier
        case let .custom(build):
            // A grouped `Form` row is 52 pt at least (the toggles and pickers beside it are).
            cell.contentConfiguration = UKCellContent(view: build(), insets: .zero, minHeight: 52)
        case let .clear(build):
            cell.backgroundConfiguration = .clear()
            cell.contentConfiguration = UKCellContent(view: build(), insets: .zero, minHeight: 0, ignoresMargins: true)
        }
    }

    // MARK: Selection

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        switch sections[safe: indexPath.section]?.rows[safe: indexPath.item]?.kind {
        case .option, .button: true
        default: false
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch sections[safe: indexPath.section]?.rows[safe: indexPath.item]?.kind {
        case let .option(_, _, _, _, action): action()
        case let .button(_, action): action()
        default: break
        }
    }
}

/// A cell content configuration that hosts a UIKit view with insets (the list cell's own margins apply at the sides).
struct UKCellContent: UIContentConfiguration {
    var view: UIView
    var insets: NSDirectionalEdgeInsets
    var minHeight: CGFloat
    /// The view runs edge to edge, past the cell's layout margins.
    var ignoresMargins = false

    func makeContentView() -> UIView & UIContentView { UKCellContentView(self) }
    func updated(for state: UIConfigurationState) -> UKCellContent { self }
}

final class UKCellContentView: UIView, UIContentView {
    var configuration: UIContentConfiguration { didSet { apply() } }

    init(_ configuration: UKCellContent) {
        self.configuration = configuration
        super.init(frame: .zero)
        // A `Form` row's content sits 16 pt inside the cell, as a list cell's own text does (UIView's default margin is 8; owner
        // 2026-10-30, Edit Task parity: the fields lined up 8 pt left of the toggles' titles).
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A hosted view whose height nothing pins (a hand-built row) reports an unbounded height, which UIKit refuses: measure the view with a
    /// compressed height instead, and never return less than the row's minimum.
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                          verticalFittingPriority: UILayoutPriority) -> CGSize {
        var size = super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority, verticalFittingPriority: verticalFittingPriority)
        guard let content = configuration as? UKCellContent else { return size }
        if !size.height.isFinite || size.height > 20_000 {
            let inner = content.view.systemLayoutSizeFitting(CGSize(width: targetSize.width, height: 0), withHorizontalFittingPriority: .required,
                                                             verticalFittingPriority: .fittingSizeLevel)
            let measured = inner.height.isFinite && inner.height < 20_000 ? inner.height + content.insets.top + content.insets.bottom : 0
            size.height = max(measured, content.minHeight, HassTokens.minTarget)
        }
        if !size.width.isFinite { size.width = targetSize.width }
        return size
    }

    private func apply() {
        guard let content = configuration as? UKCellContent else { return }
        subviews.forEach { $0.removeFromSuperview() }
        content.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content.view)
        let leading = content.ignoresMargins ? leadingAnchor : layoutMarginsGuide.leadingAnchor
        let trailing = content.ignoresMargins ? trailingAnchor : layoutMarginsGuide.trailingAnchor
        var constraints = [
            content.view.topAnchor.constraint(equalTo: topAnchor, constant: content.insets.top),
            content.view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -content.insets.bottom),
            content.view.leadingAnchor.constraint(equalTo: leading, constant: content.insets.leading),
            content.view.trailingAnchor.constraint(equalTo: trailing, constant: -content.insets.trailing),
        ]
        if content.minHeight > 0 { constraints.append(heightAnchor.constraint(greaterThanOrEqualToConstant: content.minHeight)) }
        NSLayoutConstraint.activate(constraints)
    }
}

/// The content of ``UKFormRowKind/option``: title and optional subtitle, an optional gradient swatch and a checkmark that
/// fades with the selection (``FilterOptionRow``). 44 pt at least.
final class UKFilterOptionContent: UIView {
    init(title: String, subtitle: String?, swatch: [UIColor], isSelected: Bool) {
        super.init(frame: .zero)
        let titleLabel = UILabel.uk(.body, ink: UKDesignInk.primary)
        titleLabel.text = title
        let texts = UIStackView(arrangedSubviews: [titleLabel])
        texts.axis = .vertical
        texts.spacing = HassTokens.Spacing.xs
        if let subtitle {
            // Secondary ink: 4.2:1 on a light sheet's rows with the system's, about 8:1 here.
            let sub = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
            sub.text = subtitle
            texts.addArrangedSubview(sub)
        }
        let check = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.body, weight: .semibold))))
        check.tintColor = UKDesignInk.action
        check.alpha = isSelected ? 1 : 0
        check.setContentHuggingPriority(.required, for: .horizontal)
        var parts: [UIView] = [texts]
        if !swatch.isEmpty { parts.append(UKGradientSwatch(colors: swatch)) }
        parts.append(check)
        let row = UIStackView(arrangedSubviews: parts)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = false
        check.isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Colors as a horizontal gradient capsule (`GradientSwatch`); 44 x 20 pt at the default size, scaled with the body text.
final class UKGradientSwatch: UIView {
    private let gradient = CAGradientLayer()
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!

    init(colors: [UIColor]) {
        super.init(frame: .zero)
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradient)
        layer.borderWidth = 1
        layer.borderColor = UIColor.label.withAlphaComponent(0.2).cgColor
        clipsToBounds = true
        isAccessibilityElement = false
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: 44)
        heightConstraint = heightAnchor.constraint(equalToConstant: 20)
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        setContentHuggingPriority(.required, for: .horizontal)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.rescale() }
        rescale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rescale() {
        let metrics = UIFontMetrics(forTextStyle: .body)
        widthConstraint.constant = metrics.scaledValue(for: 44, compatibleWith: traitCollection)
        heightConstraint.constant = metrics.scaledValue(for: 20, compatibleWith: traitCollection)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        layer.cornerRadius = bounds.height / 2
        layer.borderColor = UIColor.label.withAlphaComponent(0.2).resolvedColor(with: traitCollection).cgColor
    }
}

// MARK: - Filter sheet

/// A sort or filter sheet that edits a draft and applies it on demand (`FilterSheet`; pattern `floating-actions.md`).
///
/// The caller owns the draft: it passes its rows as `sections`, commits the draft in `onApply` and restores defaults in
/// `onReset`, then calls ``update(subtitle:canApply:canReset:sections:)`` as the draft changes. An edit sheet (direction G,
/// Sheets): a circle-x Cancel leading drops the draft, the filled check applies it (disabled until the draft differs from what
/// is applied). The Reset row (action blue, never red) shows only when the draft differs from the defaults.
///
/// ```swift
/// let sheet = UKFilterSheet(title: "Filter Recipes", canApply: true, canReset: true, onApply: { apply() }, onReset: { reset() },
///                           sections: [UKFormSection(id: "coverage", header: "Ingredient Coverage", rows: [...])])
/// sheet.present(from: self)
/// ```
@MainActor
final class UKFilterSheet {
    let modal: UKHassModalController
    private let form: UKFormViewController
    private let confirm: UKSheetConfirmItem
    private var userSections: [UKFormSection]
    private var canReset: Bool
    private let onReset: () -> Void

    init(title: String, subtitle: String? = nil, canApply: Bool, canReset: Bool, onApply: @escaping () -> Void, onReset: @escaping () -> Void,
         height: HassSheetHeight = .fitted, sections: [UKFormSection], fitKey: String? = nil, onDismissed: (() -> Void)? = nil) {
        self.userSections = sections
        self.canReset = canReset
        self.onReset = onReset
        let form = UKFormViewController()
        var options = UKHassModalOptions(title: title, fitKey: fitKey ?? "FilterSheet.\(title)")
        options.showsClose = false
        options.height = height
        options.width = .form
        options.onDismissed = onDismissed
        let modal = UKHassModalController(root: form, options: options)
        self.form = form
        self.modal = modal
        confirm = UKSheetConfirmItem("Apply", isEnabled: canApply, identifier: "filterSheet.apply") { [weak modal] in
            onApply()
            modal?.close()
        }
        form.navigationItem.leftBarButtonItem = UKSheetItems.cancel(identifier: "filterSheet.cancel") { [weak modal] in modal?.close() }
        form.navigationItem.rightBarButtonItem = confirm.barButtonItem
        UKSheetSubtitle.apply(subtitle, to: form.navigationItem)
        refreshSections(animated: false)
    }

    /// Shows the draft's new state.
    func update(subtitle: String?, canApply: Bool, canReset: Bool, sections: [UKFormSection]? = nil) {
        UKSheetSubtitle.apply(subtitle, to: form.navigationItem)
        confirm.update(isEnabled: canApply)
        self.canReset = canReset
        if let sections { userSections = sections }
        refreshSections(animated: true)
    }

    func present(from presenter: UIViewController) { modal.present(from: presenter) }

    private func refreshSections(animated: Bool) {
        var all = userSections
        if canReset {
            all.append(UKFormSection(id: "uk.reset", rows: [UKFormRow(id: "reset", identifier: "filterSheet.reset", .button(title: "Reset to Defaults", action: onReset))]))
        }
        form.setSections(all, animated: animated)
    }
}
#endif
