#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Status row

/// A label and its value in an inset cell, read as one element; stacks the value under the label when they don't fit side by side
/// (AX sizes, the folded Duo) (`SetupStatusRow`). The Location step's "Location Access" row is this row (``UKLocationStatusRow``).
@MainActor
class UKSetupStatusRow: UKRowView {
    init(label text: String, value: String, valueColor: UIColor = UKDesignInk.secondary, identifier: String) {
        var content = UKRowContent(text, value: value)
        content.valueInk = valueColor
        content.identifier = identifier
        super.init(content)
        drawsCard = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows a new value.
    func setValue(_ value: String, color: UIColor) {
        var content = rowContent
        content.value = value
        content.valueInk = color
        update(content, accessory: accessory)
    }
}

// MARK: - Point row

/// One point on a Setup step: a symbol (a dot when none), a title and an optional line of detail, read as one element
/// (`SetupPointRow`).
@MainActor
final class UKSetupPointRow: UIView {
    /// - Parameters:
    ///   - point: The point.
    ///   - identifier: Prefix of the identifier: `<prefix>.<key or symbol>`.
    init(point: SetupPoint, identifier: String) {
        super.init(frame: .zero)
        let isBullet = point.symbol == SetupPoint.bullet
        let icon = UIImageView()
        icon.tintColor = UKDesignInk.action
        icon.contentMode = .center
        icon.isAccessibilityElement = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UILabel.uk(point.detail == nil ? .body : .headline, ink: UKDesignInk.primary)
        titleLabel.text = point.title
        var texts: [UIView] = [titleLabel]
        if let detail = point.detail {
            let detailLabel = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
            detailLabel.text = detail
            texts.append(detailLabel)
        }
        let column = UIStackView.ukColumn(texts, spacing: HassTokens.Spacing.xs)
        let row = UIStackView(arrangedSubviews: [icon, column])
        row.axis = .horizontal
        row.alignment = isBullet ? .top : .firstBaseline
        row.spacing = HassTokens.Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        row.ukPin(to: self)
        // A dot has no baseline of its own: it spans the first line of text, so the row is at least that tall.
        if isBullet { icon.heightAnchor.constraint(equalTo: titleLabel.heightAnchor).isActive = true }
        let width = icon.widthAnchor.constraint(equalToConstant: UKScaled.value(32, relativeTo: .title2, traits: traitCollection))
        width.isActive = true
        func restyle(_ traits: UITraitCollection) {
            width.constant = UKScaled.value(32, relativeTo: .title2, traits: traits)
            let configuration = isBullet
                ? UIImage.SymbolConfiguration(pointSize: 8)
                : UIImage.SymbolConfiguration(font: UKFont.preferred(.title2, traits: traits))
            icon.image = UIImage(systemName: point.symbol, withConfiguration: configuration)
        }
        restyle(traitCollection)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKSetupPointRow, _) in restyle(view.traitCollection) }
        isAccessibilityElement = true
        accessibilityLabel = point.detail.map { "\(point.title), \($0)" } ?? point.title
        accessibilityIdentifier = "\(identifier).\(point.key ?? point.symbol)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Step page

/// What a Setup step draws (`SetupStepPage`): a symbol, a title and a message, a status row, the points, a footnote, and the actions
/// at the end of the content.
struct UKSetupStepContent {
    var symbol: String
    var symbolColor: UIColor = UKDesignInk.action
    var title: String
    var message: String
    var points: [SetupPoint] = []
    var footnote: String?
    /// Prefix of the accessibility identifiers: `<prefix>.title`, `.message`, `.footnote`.
    var identifier: String
    var status: UIView?
    var actions: [UIView] = []
}

/// The scrolling page every Setup step shares (`.agents/patterns/modal-sheet.md`). Not pinned: on an iPad form sheet a pinned bar
/// covered the last point (audit, 2026-10-14). Subclasses set ``content``; the page redraws.
@MainActor
class UKSetupStepPageViewController: UKPageViewController, UKSheetFitting {
    /// The step's bar title (`SetupStep.barTitle`).
    let barTitle: String
    var content: UKSetupStepContent { didSet { if isViewLoaded { apply() } } }
    private let container = UKColumnContainer(
        spacing: HassTokens.Spacing.xl,
        margins: NSDirectionalEdgeInsets(top: HassTokens.Spacing.l, leading: HassTokens.Spacing.xl, bottom: HassTokens.Spacing.l, trailing: HassTokens.Spacing.xl),
        maxWidth: 560, clearsHinge: true)
    private let symbolView = UIImageView()
    private let titleLabel = UILabel.uk(.title2, weight: .bold, ink: UKDesignInk.primary)
    private let messageLabel = UILabel.uk(.body, ink: UKDesignInk.secondary)
    private let footnoteLabel = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
    private let heading = UIStackView.ukColumn(spacing: HassTokens.Spacing.m)
    private let pointsStack = UIStackView.ukColumn(spacing: HassTokens.Spacing.l)
    private let actionBar = UIStackView.ukColumn(spacing: HassTokens.Spacing.s)

    var sheetFitScrollView: UIScrollView? { container.scrollView }

    init(barTitle: String, content: UKSetupStepContent) {
        self.barTitle = barTitle
        self.content = content
        super.init(sheetTitle: barTitle)
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        install(scrollView: container.scrollView)
        symbolView.isAccessibilityElement = false
        symbolView.contentMode = .scaleAspectFit
        symbolView.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.accessibilityTraits = [.header, .staticText]
        heading.alignment = .leading
        for label in [titleLabel, messageLabel] { label.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        for view in [symbolView, titleLabel, messageLabel] { heading.addArrangedSubview(view) }
        container.column.addArrangedSubview(heading)
        container.column.addArrangedSubview(pointsStack)
        container.column.addArrangedSubview(footnoteLabel)
        container.column.addArrangedSubview(actionBar)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKSetupStepPageViewController, _) in page.updateSymbol() }
        apply()
    }

    private func updateSymbol() {
        let size = UKScaled.value(56, relativeTo: .largeTitle, traits: traitCollection)
        symbolView.image = UIImage(systemName: content.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size))
        symbolView.tintColor = content.symbolColor
    }

    private func apply() {
        let content = content
        updateSymbol()
        titleLabel.text = content.title
        titleLabel.accessibilityIdentifier = "\(content.identifier).title"
        messageLabel.text = content.message
        messageLabel.accessibilityIdentifier = "\(content.identifier).message"
        // The status row sits between the heading and the points.
        for old in container.column.arrangedSubviews where old is UKSetupStatusRow {
            container.column.removeArrangedSubview(old)
            old.removeFromSuperview()
        }
        if let status = content.status, let index = container.column.arrangedSubviews.firstIndex(of: heading) {
            container.column.insertArrangedSubview(status, at: index + 1)
        }
        for old in pointsStack.arrangedSubviews { pointsStack.removeArrangedSubview(old); old.removeFromSuperview() }
        for point in content.points { pointsStack.addArrangedSubview(UKSetupPointRow(point: point, identifier: "\(content.identifier).point")) }
        pointsStack.isHidden = content.points.isEmpty
        footnoteLabel.text = content.footnote
        footnoteLabel.isHidden = content.footnote == nil
        footnoteLabel.accessibilityIdentifier = "\(content.identifier).footnote"
        for old in actionBar.arrangedSubviews { actionBar.removeArrangedSubview(old); old.removeFromSuperview() }
        for action in content.actions { actionBar.addArrangedSubview(action) }
    }
}

/// A text button of the Setup steps ("Not Now"): the label carries the 44 pt target and its shape.
@MainActor
final class UKSetupTextButton: UIControl {
    private let label = UILabel.uk(.body, weight: .semibold, ink: UKDesignInk.action, alignment: .center)
    var action: () -> Void

    init(_ title: String, identifier: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        label.text = title
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor), label.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        addAction(UIAction { [weak self] _ in self?.action() }, for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool { didSet { label.alpha = isHighlighted ? 0.6 : 1 } }
}
#endif
