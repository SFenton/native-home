#if os(iOS)
import HassCore
import HassDesign
import UIKit

// The pieces the Climate, Bedroom and Room Devices sheets share: a scrolling column on the sheet's ground, a host that lets a
// hand-laid (frame-based) view live in an Auto Layout stack, titled sections, the grey and tinted capsule buttons and the
// cards and rows of the device sheets (`RoomDeviceSheetChrome`, `DeviceSection`, `TintedCapsuleButtonStyle`, `BedroomStyle`).

// MARK: - Wrapping labels

/// A wrapping label in an Auto Layout stack can keep the one-line height it measured before it had a width (the footnote under the
/// fan timer lost its second line). Each wrapping label that fills a vertical stack wraps at that stack's content width
/// (``UKWrapWidth``): a width the stack's own constraints decide, never the label's own last width. A label that does not fill a
/// vertical stack (a row's neighbour, a centred title) is left to its container, which caps it itself.
@MainActor
enum UKWrapSync {
    @discardableResult
    static func sync(_ root: UIView) -> Bool {
        var changed = false
        var queue = [root]
        while let view = queue.popLast() {
            if let label = view as? UILabel, label.numberOfLines == 0,
               let stack = label.superview as? UIStackView, stack.axis == .vertical, stack.alignment == .fill,
               UKWrapWidth.set(label, inFillStack: stack) {
                changed = true
            }
            queue.append(contentsOf: view.subviews)
        }
        return changed
    }
}

// MARK: - Grid host

/// Hosts a hand-laid view that reports its height for a width (``UKGridMeasuring``: a grid, a section header, a column) in an Auto
/// Layout stack: the host's intrinsic height follows the width it is given.
@MainActor
final class UKGridHost: UIView {
    let child: UIView
    private var height: CGFloat = 1

    init(_ child: UIView) {
        self.child = child
        super.init(frame: .zero)
        addSubview(child)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (host: UKGridHost, _) in host.remeasure() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Asks the child again (its content changed).
    func remeasure() {
        setNeedsLayout()
    }

    private func measure(_ width: CGFloat) -> CGFloat {
        if let measuring = child as? UKGridMeasuring { return ceil(measuring.gridHeight(forWidth: width)) }
        return ceil(child.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: height) }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: measure(size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let measured = measure(bounds.width)
        if measured != height {
            height = measured
            invalidateIntrinsicContentSize()
        }
        child.frame = CGRect(x: 0, y: 0, width: bounds.width, height: measured)
    }
}

// MARK: - Column page

/// A page on the sheet's grouped ground that scrolls a vertical stack: the `ScrollView { VStack { … }.frame(maxWidth:).padding(.l) }`
/// every device sheet is. Conforms to ``UKSheetFitting`` so a fitted sheet measures it.
@MainActor
class UKSheetColumnViewController: UKPageViewController, UKSheetFitting {
    let scrollView = UIScrollView()
    let stack = UIStackView()
    private let maxWidth: CGFloat
    private let spacing: CGFloat
    private let padding: UIEdgeInsets

    var sheetFitScrollView: UIScrollView? { scrollView }

    init(maxWidth: CGFloat, spacing: CGFloat = HassTokens.Spacing.xl,
         padding: UIEdgeInsets = UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l),
         context: UKContext = .sheetPlaceholder) {
        self.maxWidth = maxWidth
        self.spacing = spacing
        self.padding = padding
        super.init(context: context.with { $0.surface = .sheet }, title: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UKWrapSync.sync(stack)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.showsVerticalScrollIndicator = true
        install(scrollView: scrollView)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        let fill = stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(padding.left + padding.right))
        fill.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: padding.top),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -padding.bottom),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            fill,
        ])
    }
}

// MARK: - Sections

/// A titled group of controls (`DeviceSection`): the shared section header on the sheet, an optional footnote, then the content.
@MainActor
final class UKDeviceSection: UIStackView {
    init(title: String, footnote: String? = nil, content: [UIView]) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.m
        alignment = .fill
        let header = UKPageSectionHeaderView(title, inSheet: true)
        header.accessibilityTraits = .header
        addArrangedSubview(UKGridHost(header))
        if let footnote { addArrangedSubview(UKDeviceText.footnote(footnote)) }
        content.forEach(addArrangedSubview)
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Text the device sheets repeat.
@MainActor
enum UKDeviceText {
    static func footnote(_ text: String) -> UILabel {
        let label = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
        label.text = text
        return label
    }

    static func subheadline(_ text: String, ink: UIColor = UKDesignInk.secondary) -> UILabel {
        let label = UILabel.uk(.subheadline, ink: ink)
        label.text = text
        return label
    }

    static func body(_ text: String, ink: UIColor = UKDesignInk.primary) -> UILabel {
        let label = UILabel.uk(.body, ink: ink)
        label.text = text
        return label
    }
}

// MARK: - Capsule buttons

/// The grey capsule under a dial (`.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Ink.primary).controlSize(.large)`):
/// a label in primary ink on a faint wash of it. HIG: a secondary action next to the sheet's focus.
@MainActor
final class UKGreyCapsuleButton: UIButton {
    private let action: () -> Void

    init(title: String, systemImage: String?, minWidth: CGFloat = 0, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.tinted()
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        configuration.baseBackgroundColor = UKDesignInk.primary
        configuration.baseForegroundColor = UKDesignInk.primary
        configuration.image = systemImage.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = HassTokens.Spacing.s
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UKFont.bodyEmphasis()
            return attributes
        }
        self.configuration = configuration
        addAction(UIAction { [weak self] _ in self?.action() }, for: .touchUpInside)
        heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        if minWidth > 0 { widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true }
        accessibilityLabel = title
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A second line under the title in the footnote size (the snooze countdown), or none.
    func setSubtitle(_ text: String?) {
        guard configuration?.subtitle != text else { return }
        configuration?.subtitle = text
        configuration?.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UKFont.preferred(.footnote, monospacedDigit: true)
            return attributes
        }
    }

    /// Changes the title (the power button reads Turn On / Turn Off).
    func setTitle(_ title: String) {
        guard configuration?.title != title else { return }
        configuration?.title = title
        accessibilityLabel = title
    }
}

/// A capsule filled with its tint (16% on a dark sheet, 8% on a light one) and labelled in the tint: the sheet's secondary
/// destructive action (`TintedCapsuleButtonStyle`).
@MainActor
final class UKTintedCapsuleButton: UIControl {
    private let label = UILabel()
    private let tint: UIColor
    private let action: () -> Void
    private let wash = UIView()

    init(title: String, tint: UIColor, action: @escaping () -> Void) {
        self.tint = tint
        self.action = action
        super.init(frame: .zero)
        wash.isUserInteractionEnabled = false
        wash.layer.cornerCurve = .continuous
        addSubview(wash)
        wash.ukPin(to: self)
        label.font = UKFont.bodyEmphasis()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = tint
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = title
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.s),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.s),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HassTokens.Spacing.xl),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -HassTokens.Spacing.xl),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        addAction(UIAction { [weak self] _ in self?.action() }, for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        restyle()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UKTintedCapsuleButton, _) in view.restyle() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        wash.layer.cornerRadius = bounds.height / 2
    }

    private func restyle() {
        wash.backgroundColor = tint.withAlphaComponent(traitCollection.userInterfaceStyle == .light ? 0.08 : 0.16)
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.4 }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isEnabled ? (isHighlighted ? 0.8 : 1) : 0.4 }
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { isEnabled ? .button : [.button, .notEnabled] }
        set {}
    }
}

/// A button filled with a solid colour and a white label (`.borderedProminent` with `BedroomStyle.danger`): Stop and Delete.
@MainActor
final class UKFilledButton: UIButton {
    init(title: String, systemImage: String? = nil, fill: UIColor, action: @escaping () -> Void) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        configuration.baseBackgroundColor = fill
        configuration.baseForegroundColor = .white
        configuration.title = title
        configuration.image = systemImage.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = HassTokens.Spacing.s
        self.configuration = configuration
        addAction(UIAction { _ in action() }, for: .touchUpInside)
        heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        accessibilityLabel = title
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setTitle(_ title: String) {
        configuration?.title = title
        accessibilityLabel = title
    }
}

// MARK: - Cards

/// A card on the sheet's cell colour (`BedroomStyle.card`): padded 16 pt, `HassTokens.Radius.tile` corners.
@MainActor
final class UKSheetCardView: UIView {
    init(content: UIView, insets: UIEdgeInsets = UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l)) {
        super.init(frame: .zero)
        backgroundColor = UKDesignSurface.sheetCell
        layer.cornerRadius = HassTokens.Radius.tile
        layer.cornerCurve = .continuous
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// `RoomDeviceStyle` and the stateful pieces the device sheets repeat.
@MainActor
enum UKDeviceStyle {
    /// Stop and Delete fills: a deep red that keeps white labels at about 6:1 (`BedroomStyle.danger`).
    static let danger = UIColor(red: 0.76, green: 0.12, blue: 0.12, alpha: 1)

    /// Cross-fades a glyph or label colour when it follows state (`stateForeground`).
    static func setInk(_ view: UIView, to color: UIColor, component: String, set: @escaping () -> Void) {
        UKMotion.stateFade(component, view: view, animated: true, set)
    }
}

/// A once-a-second clock for countdowns (`EverySecond`): calls `tick` now and every second while `isRunning`.
///
/// A `tick` may call ``setRunning(_:)`` again (a view's `apply()` both redraws and decides whether the clock runs); that call
/// adjusts the timer but does not tick again, so the two never recurse.
@MainActor
final class UKEverySecond {
    private var timer: Timer?
    private let tick: (Date) -> Void
    private var isTicking = false

    init(tick: @escaping (Date) -> Void) {
        self.tick = tick
    }

    /// Runs the clock, or stops it (nothing on screen counts down).
    func setRunning(_ running: Bool) {
        if running, timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.fire() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !running {
            timer?.invalidate()
            timer = nil
        }
        fire()
    }

    private func fire() {
        guard !isTicking else { return }
        isTicking = true
        defer { isTicking = false }
        tick(Date())
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { MainActor.assumeIsolated { timer?.invalidate() } }
}

/// A caption-sized switch row: a label on the left, a switch on the right, at least 44 pt (`Toggle(...).frame(minHeight: 44)`).
@MainActor
final class UKToggleLine: UIView {
    let toggle: UISwitch
    private let titleLabel: UILabel

    init(title: String, symbol: String? = nil, toggle: UISwitch, identifier: String) {
        self.toggle = toggle
        titleLabel = UILabel.uk(.body, ink: UKDesignInk.primary)
        super.init(frame: .zero)
        titleLabel.text = title
        var parts: [UIView] = []
        if let symbol {
            let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.body))))
            icon.tintColor = UKDesignInk.primary
            icon.setContentHuggingPriority(.required, for: .horizontal)
            icon.isAccessibilityElement = false
            parts.append(icon)
        }
        parts.append(titleLabel)
        let row = UIStackView(arrangedSubviews: parts + [toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.s
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(row)
        row.ukPin(to: self)
        heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        toggle.accessibilityLabel = title
        toggle.accessibilityIdentifier = identifier
        isAccessibilityElement = false
        accessibilityElements = [toggle]
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A rounded text field that grows with Dynamic Type (a `TextField(axis: .vertical)` with a 1 to 3 line limit in an 8 pt outline).
@MainActor
final class UKOutlinedTextField: UIView, UITextViewDelegate {
    private let textView = UITextView()
    private let placeholderLabel = UILabel.uk(.body, ink: .placeholderText)
    private let limit: Int
    var onChange: (String) -> Void = { _ in }

    init(placeholder: String, text: String, limit: Int, identifier: String) {
        self.limit = limit
        super.init(frame: .zero)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        textView.font = UKFont.preferred(.body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = UKDesignInk.primary
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.returnKeyType = .done
        textView.delegate = self
        textView.text = text
        textView.accessibilityIdentifier = identifier
        textView.accessibilityLabel = placeholder
        placeholderLabel.text = placeholder
        placeholderLabel.isHidden = !text.isEmpty
        placeholderLabel.isAccessibilityElement = false
        for view in [textView, placeholderLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.s),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.s),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HassTokens.Spacing.m),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -HassTokens.Spacing.m),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        restyle()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UKOutlinedTextField, _) in view.restyle() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func restyle() {
        layer.borderColor = UIColor.secondaryLabel.withAlphaComponent(0.4).resolvedColor(with: traitCollection).cgColor
    }

    /// Replaces the text without reporting a change.
    func show(_ text: String) {
        guard textView.text != text else { return }
        textView.text = text
        placeholderLabel.isHidden = !text.isEmpty
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        // One line per name: no newlines, at most `limit` characters.
        let cleaned = String(textView.text.filter { !$0.isNewline }.prefix(limit))
        if cleaned != textView.text { textView.text = cleaned }
        placeholderLabel.isHidden = !cleaned.isEmpty
        onChange(cleaned)
    }
}

/// A `DatePicker` row: the title on the left and the compact picker on the right, 44 pt at least.
@MainActor
final class UKDatePickerLine: UIView {
    let picker = UIDatePicker()

    init(title: String, mode: UIDatePicker.Mode, date: Date, identifier: String, onChange: @escaping (Date) -> Void) {
        super.init(frame: .zero)
        picker.datePickerMode = mode
        picker.preferredDatePickerStyle = .compact
        picker.date = date
        picker.accessibilityIdentifier = identifier
        picker.accessibilityLabel = title
        picker.addAction(UIAction { [weak picker] _ in if let picker { onChange(picker.date) } }, for: .valueChanged)
        let label = UILabel.uk(.body, ink: UKDesignInk.primary)
        label.text = title
        picker.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, picker])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.s
        addSubview(row)
        row.ukPin(to: self)
        heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

extension UIStackView {
    /// Replaces every arranged subview.
    func ukSetArranged(_ views: [UIView]) {
        for view in arrangedSubviews { removeArrangedSubview(view); view.removeFromSuperview() }
        views.forEach(addArrangedSubview)
    }
}

extension UKSheetCardView: UKGridMeasuring {
    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        ceil(systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                     withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }
}

// MARK: - Column scroll

/// A scroll view holding one vertical stack, centred and capped at `maxWidth` with padding: `ScrollView { VStack }.frame(maxWidth:)
/// .padding(.l)`.
@MainActor
final class UKColumnScroll: UIScrollView {
    let stack = UIStackView()

    init(maxWidth: CGFloat?, spacing: CGFloat, padding: CGFloat = HassTokens.Spacing.l) {
        super.init(frame: .zero)
        alwaysBounceVertical = false
        stack.axis = .vertical
        stack.spacing = spacing
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let fill = stack.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor, constant: -padding * 2)
        fill.priority = UILayoutPriority(999)
        var constraints = [
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -padding),
            stack.centerXAnchor.constraint(equalTo: frameLayoutGuide.centerXAnchor),
            fill,
        ]
        if let maxWidth { constraints.append(stack.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)) }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        UKWrapSync.sync(stack)
    }
}

// MARK: - Hero and tabs

/// A sheet page with a hero (dial, power, notices) above the tab content, or beside it where the window may split (`HumidifierLayout`,
/// `MediaRemoteLayout`: iPad and the unfolded iPhone Duo in landscape): the hero in a leading column, the tab in a trailing one.
/// The container carries `<base>.twoColumn` or `<base>.singleColumn`.
@MainActor
final class UKHeroTabsViewController: UKPaneViewController {
    private let hero: UIView
    private let tabs: UIView
    private let base: String
    private let usesTwoColumns: (CGSize, Bool, CGSize) -> Bool
    private var twoColumns: Bool?
    private var scrolls: [UIScrollView] = []
    /// Called with the columns each time they are rebuilt (one or two by width), so the sheet's page can name its scroller.
    var onScrollViewsChanged: (([UIScrollView]) -> Void)?

    init(hero: UIView, tabs: UIView, identifierBase: String, usesTwoColumns: @escaping (CGSize, Bool, CGSize) -> Bool) {
        self.hero = hero
        self.tabs = tabs
        base = identifierBase
        self.usesTwoColumns = usesTwoColumns
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isAccessibilityElement = false
        view.accessibilityContainerType = .semanticGroup
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // A sheet's own size class is compact on iPad, so the decision reads the window.
        let window = view.window
        let two = usesTwoColumns(window?.bounds.size ?? view.bounds.size, (window?.traitCollection ?? traitCollection).horizontalSizeClass == .regular, view.bounds.size)
        if two != twoColumns { rebuild(two) }
        if two {
            let half = view.bounds.width / 2
            scrolls.first?.frame = CGRect(x: 0, y: 0, width: half, height: view.bounds.height)
            scrolls.last?.frame = CGRect(x: half, y: 0, width: half, height: view.bounds.height)
        } else {
            scrolls.first?.frame = view.bounds
        }
    }

    private func rebuild(_ two: Bool) {
        twoColumns = two
        scrolls.forEach { $0.removeFromSuperview() }
        hero.removeFromSuperview()
        tabs.removeFromSuperview()
        if two {
            let left = UKColumnScroll(maxWidth: nil, spacing: HassTokens.Spacing.xl)
            let right = UKColumnScroll(maxWidth: nil, spacing: HassTokens.Spacing.xl)
            left.stack.addArrangedSubview(hero)
            right.stack.addArrangedSubview(tabs)
            scrolls = [left, right]
        } else {
            let single = UKColumnScroll(maxWidth: 640, spacing: HassTokens.Spacing.xl)
            single.stack.addArrangedSubview(hero)
            single.stack.addArrangedSubview(tabs)
            scrolls = [single]
        }
        scrolls.forEach(view.addSubview)
        view.accessibilityIdentifier = two ? "\(base).twoColumn" : "\(base).singleColumn"
        onScrollViewsChanged?(scrolls)
    }
}
#endif
