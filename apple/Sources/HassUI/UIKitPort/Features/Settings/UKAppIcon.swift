#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Art

/// The app icon's art (``AppIconArtwork``, standard appearance) drawn with Core Graphics: the dusk glow, the pair's tint across the
/// whole square, a top light, and the house with the heart on its cut-out ring. The paths and the glow's numbers are the SwiftUI
/// view's own (``AppIconArtwork/house``, ``AppIconArtwork/Standard``), so a preview can never differ from the icon it stands for.
final class UKAppIconArtworkView: UIView {
    private let tint: UInt32
    private let tintOpacity: Double
    private let glyph: UInt32

    init(tint: UInt32, tintOpacity: Double, glyph: UInt32) {
        self.tint = tint
        self.tintOpacity = tintOpacity
        self.glyph = glyph
        super.init(frame: .zero)
        isOpaque = true
        backgroundColor = .black
        contentMode = .redraw
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let square = CGRect(x: 0, y: 0, width: side, height: side)
        context.saveGState()
        context.clip(to: square)

        // The 165 degree gradient: the corners take the end colours.
        let angle = 165.0 * Double.pi / 180
        let direction = CGVector(dx: sin(angle), dy: -cos(angle))
        let length = side * (abs(sin(angle)) + abs(cos(angle)))
        let middle = CGPoint(x: side / 2, y: side / 2)
        let stops = AppIconArtwork.Standard.background
        if let gradient = CGGradient(colorsSpace: space, colors: stops.map { UIColor(rgb: $0.color).cgColor } as CFArray,
                                     locations: stops.map { CGFloat($0.location) }) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: middle.x - direction.dx * length / 2, y: middle.y - direction.dy * length / 2),
                end: CGPoint(x: middle.x + direction.dx * length / 2, y: middle.y + direction.dy * length / 2),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        // The two glows: `radial-gradient(circle at X Y, colour, transparent P%)`.
        for glow in AppIconArtwork.Standard.glows {
            let color = UIColor(red: glow.red, green: glow.green, blue: glow.blue, alpha: glow.opacity)
            let reach = side * hypot(max(glow.x, 1 - glow.x), max(glow.y, 1 - glow.y)) * glow.reach
            if let gradient = CGGradient(colorsSpace: space, colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
                context.drawRadialGradient(gradient, startCenter: CGPoint(x: side * glow.x, y: side * glow.y), startRadius: 0,
                                           endCenter: CGPoint(x: side * glow.x, y: side * glow.y), endRadius: reach, options: [])
            }
        }
        // The tint across the whole square, then the top light: white at 18% fading to nothing by 46% of the height.
        context.setFillColor(UIColor(rgb: tint, alpha: tintOpacity).cgColor)
        context.fill(square)
        if let light = CGGradient(colorsSpace: space, colors: [UIColor(white: 1, alpha: 0.18).cgColor, UIColor(white: 1, alpha: 0).cgColor,
                                                              UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 0.46, 1]) {
            context.drawLinearGradient(light, start: .zero, end: CGPoint(x: 0, y: side), options: [])
        }

        // The glyph: 80% of the icon's width, centred, in 100-unit coordinates.
        let box = side * AppIconArtwork.glyphFraction
        let unit = box / 100
        let place = CGAffineTransform(translationX: (side - box) / 2, y: (side - box) / 2).scaledBy(x: unit, y: unit)
        var heartTransform = CGAffineTransform(translationX: 55, y: 60).scaledBy(x: 0.40, y: 0.40).concatenating(place)
        guard let heart = AppIconArtwork.heart.cgPath.copy(using: &heartTransform) else { context.restoreGState(); return }
        let stroked = heart.copy(strokingWithWidth: 16 * 0.40 * unit, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        let ring = stroked.union(heart)
        var houseTransform = place
        let house = AppIconArtwork.house.cgPath.copy(using: &houseTransform)
        let glyphColor = UIColor(rgb: glyph).cgColor
        // The house with the ring's outline cut out of it, so the ring is the glass itself.
        context.saveGState()
        let cut = CGMutablePath()
        cut.addRect(square.insetBy(dx: -side, dy: -side))
        cut.addPath(ring)
        context.addPath(cut)
        context.clip(using: .evenOdd)
        if let house {
            context.addPath(house)
            context.setFillColor(glyphColor)
            context.fillPath(using: .evenOdd)
        }
        context.restoreGState()
        context.addPath(heart)
        context.setFillColor(glyphColor)
        context.fillPath()
        context.restoreGState()
    }
}

/// A small copy of an app icon (``AppIconPreview``): the art clipped to the system's icon corner radius, with a hairline so
/// the edge reads on a white sheet as on a dark one. Decorative.
final class UKAppIconPreviewView: UIView {
    /// The Home Screen icon's corner radius as a fraction of its side.
    static let cornerFraction = AppIconPreview.cornerFraction

    init(choice: AppIconChoice, side: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        let art = UKAppIconArtworkView(tint: choice.tint, tintOpacity: AppIconChoice.tintOpacity, glyph: choice.glyph)
        art.frame = bounds
        art.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(art)
        layer.cornerRadius = side * Self.cornerFraction
        layer.cornerCurve = .continuous
        clipsToBounds = true
        let hairline = UIView()
        hairline.isUserInteractionEnabled = false
        hairline.frame = bounds
        hairline.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hairline.layer.cornerRadius = side * Self.cornerFraction
        hairline.layer.cornerCurve = .continuous
        hairline.layer.borderWidth = 0.5
        hairline.layer.borderColor = UIColor.label.withAlphaComponent(0.14).cgColor
        addSubview(hairline)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UKAppIconPreviewView, _) in
            view.subviews.last?.layer.borderColor = UIColor.label.withAlphaComponent(0.14).resolvedColor(with: view.traitCollection).cgColor
        }
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Choice cell

/// One icon in the grid (``AppIconChoiceButton``): its art in a ring, its name, "Default" under the app's own icon and a check on
/// the installed one. The cell is a button named "Navy and Sky" (", default" for the default), selected when installed.
final class UKAppIconChoiceCell: UICollectionViewCell {
    static let ringGap: CGFloat = 5
    private let ring = UIView()
    private let nameLabel = UILabel.uk(.subheadline, weight: .semibold, ink: UKDesignInk.primary)
    private let check = UIImageView()
    private let defaultLabel = UILabel.uk(.footnote, ink: UKDesignSurface.secondaryInSheet)
    private let stack = UIStackView()
    private var preview: UKAppIconPreviewView?
    private var side: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 0
        check.image = UIImage(systemName: "checkmark.circle.fill")
        check.tintColor = UKDesignInk.action
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.isAccessibilityElement = false
        let nameRow = UIStackView(arrangedSubviews: [check, nameLabel])
        nameRow.axis = .horizontal
        nameRow.spacing = HassTokens.Spacing.xs
        nameRow.alignment = .firstBaseline
        defaultLabel.text = "Default"
        defaultLabel.textAlignment = .center
        ring.layer.cornerCurve = .continuous
        ring.layer.borderWidth = 3
        ring.layer.borderColor = UKDesignInk.action.cgColor
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = HassTokens.Spacing.s
        stack.addArrangedSubview(ring)
        stack.addArrangedSubview(nameRow)
        stack.addArrangedSubview(defaultLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        ukFitted(layoutAttributes)
    }

    func configure(_ choice: AppIconChoice, isSelected: Bool, side newSide: CGFloat) {
        if preview == nil || side != newSide {
            preview?.removeFromSuperview()
            side = newSide
            let art = UKAppIconPreviewView(choice: choice, side: newSide)
            art.translatesAutoresizingMaskIntoConstraints = false
            ring.addSubview(art)
            NSLayoutConstraint.activate([
                art.topAnchor.constraint(equalTo: ring.topAnchor, constant: Self.ringGap),
                art.bottomAnchor.constraint(equalTo: ring.bottomAnchor, constant: -Self.ringGap),
                art.leadingAnchor.constraint(equalTo: ring.leadingAnchor, constant: Self.ringGap),
                art.trailingAnchor.constraint(equalTo: ring.trailingAnchor, constant: -Self.ringGap),
                art.widthAnchor.constraint(equalToConstant: newSide), art.heightAnchor.constraint(equalToConstant: newSide),
            ])
            ring.layer.cornerRadius = newSide * UKAppIconPreviewView.cornerFraction + Self.ringGap
            preview = art
        }
        nameLabel.text = choice.displayName
        defaultLabel.isHidden = !choice.isDefault
        check.isHidden = !isSelected
        let changes = { self.ring.layer.borderColor = UKDesignInk.action.withAlphaComponent(isSelected ? 1 : 0).cgColor }
        if window != nil { UKMotion.stateFade("AppIconChoiceButton", animated: true, changes) } else { changes() }
        accessibilityLabel = choice.isDefault ? "\(choice.spokenName), default" : choice.spokenName
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        accessibilityIdentifier = "appIcon.choice.\(choice.rawValue)"
    }
}

// MARK: - Picker sheet

/// Settings → App Icon (``AppIconPickerSheet``): the eight icons in a grid with their names, the installed one checked. Choosing
/// one installs it (``AppIconPickerModel/select(_:)``); iOS shows its own notice when the icon changes. The column count
/// follows the text size: the grid fills the width with columns at least 130 pt (scaled with the text) wide, one column at
/// accessibility sizes where the icon grows with the text.
final class UKAppIconPickerViewController: UKPageViewController, UICollectionViewDelegate, UKSheetFitting {
    private let model: AppIconPickerModel
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, AppIconChoice>!
    private var showingFailure = false
    var sheetFitScrollView: UIScrollView? { collectionView }

    private static let footerKind = "appIcon.footer"
    static let footerText = "iOS shows its own notice when the icon changes. Every icon also has dark and tinted Home Screen versions."

    init(model: AppIconPickerModel) {
        self.model = model
        super.init(sheetTitle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The sheet: titled "App Icon", content-fitted, a form sheet on iPad.
    static func present(model: AppIconPickerModel, from presenter: UIViewController) {
        var options = UKHassModalOptions(title: "App Icon")
        options.closeIdentifier = "appIcon.close"
        options.closeStaysInBar = true
        UKHassModalController(root: UKAppIconPickerViewController(model: model), options: options).present(from: presenter)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "appIcon.sheet"
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in self?.sectionLayout(environment) ?? Self.emptySection() }
        collectionView = UKWidthAwareCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        install(scrollView: collectionView)

        let cell = UICollectionView.CellRegistration<UKAppIconChoiceCell, AppIconChoice> { [weak self] cell, _, choice in
            guard let self else { return }
            cell.configure(choice, isSelected: self.model.isSelected(choice), side: UKFont.scaled(88, relativeTo: .body, traits: self.traitCollection))
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: Self.footerKind) { cell, _, _ in
            let label = UILabel.uk(.footnote, ink: UKDesignSurface.secondaryInSheet)
            label.text = Self.footerText
            label.accessibilityIdentifier = "appIcon.footer"
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            cell.contentView.addSubview(label)
            label.ukPin(to: cell.contentView)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, path, choice in
            collectionView.dequeueConfiguredReusableCell(using: cell, for: path, item: choice)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, path in
            collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: path)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, AppIconChoice>()
        snapshot.appendSections([0])
        snapshot.appendItems(AppIconChoice.allCases)
        dataSource.apply(snapshot, animatingDifferences: false)
        bag.observe { [weak self] in self?.modelChanged() }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: UKAppIconPickerViewController, _) in
            controller.collectionView.collectionViewLayout.invalidateLayout()
            var snapshot = controller.dataSource.snapshot()
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
            controller.dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    private static func emptySection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(1))
        return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
    }

    private func sectionLayout(_ environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let gap = HassTokens.Spacing.l
        let minimum = UKFont.scaled(130, relativeTo: .body, traits: environment.traitCollection)
        let available = environment.container.effectiveContentSize.width - 2 * gap
        // `GridItem(.adaptive(minimum:, spacing:))`: as many columns as fit, at least one.
        let columns = max(1, Int(((available + gap) / (minimum + gap)).rounded(.down)))
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)), heightDimension: .estimated(160))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(160)),
                                                       repeatingSubitem: item, count: columns)
        group.interItemSpacing = .fixed(gap)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = HassTokens.Spacing.xl
        section.contentInsets = NSDirectionalEdgeInsets(top: HassTokens.Spacing.s, leading: gap, bottom: gap, trailing: gap)
        let footer = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
            elementKind: Self.footerKind, alignment: .bottom)
        footer.contentInsets = NSDirectionalEdgeInsets(top: gap, leading: 0, bottom: 0, trailing: 0)
        section.boundarySupplementaryItems = [footer]
        return section
    }

    // MARK: Model

    private func modelChanged() {
        _ = model.selected
        _ = model.isChanging
        let failure = model.failureMessage
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
        if let failure, !showingFailure, view.window != nil { presentFailure(failure) }
    }

    private func presentFailure(_ message: String) {
        showingFailure = true
        let alert = UIAlertController(title: "Couldn't Change Icon", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
            self?.model.failureMessage = nil
            self?.showingFailure = false
        })
        (presentedViewController ?? self).present(alert, animated: true)
    }

    // MARK: Delegate

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { !model.isChanging }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let choice = dataSource.itemIdentifier(for: indexPath) else { return }
        Task { await model.select(choice) }
    }
}
#endif
