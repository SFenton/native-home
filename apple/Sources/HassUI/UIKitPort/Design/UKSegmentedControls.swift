#if os(iOS)
import HassDesign
import UIKit

// MARK: - Segmented choice

/// A short single choice, 2 to 4 options (`SegmentedChoice`; direction G, Controls): a segmented control, or a menu that names
/// the choice at accessibility text sizes, where segments cannot grow (HIG: Segmented controls). Choosing sends at once, and
/// the control holds no state: it shows ``selection``, so a rejected command leaves the old value on screen. Nothing is
/// selected while the device reports a value outside the options (a mist level between presets).
///
/// ```swift
/// let mode = UKSegmentedChoice(label: "Mist Level", options: levels, title: \.name, selection: current, identifier: "mist") { send($0) }
/// bag.observe { mode.selection = box.state.level }       // bind to the entity box
/// ```
/// XCUITest finds it by `identifier` and each option as a button named by its title.
public final class UKSegmentedChoice<Option: Hashable>: UIView {
    public var options: [Option] { didSet { rebuild() } }
    public var selection: Option? { didSet { showSelection() } }
    /// Off while the choice does not apply (the expiry horizon waits for its toggle): dimmed and not enabled for assistive technologies.
    public var isEnabled = true {
        didSet {
            segmented.isEnabled = isEnabled
            menu.isEnabled = isEnabled
            for control in [segmented, menu] {
                if isEnabled { control.accessibilityTraits.remove(.notEnabled) } else { control.accessibilityTraits.insert(.notEnabled) }
            }
        }
    }
    public let label: String
    public let identifier: String
    private let title: (Option) -> String
    private let select: (Option) -> Void
    private let segmented = UISegmentedControl()
    private let menu = UIButton(type: .system)
    private var builtAccessibility: Bool?

    public init(label: String, options: [Option], title: @escaping (Option) -> String, selection: Option?, identifier: String,
                select: @escaping (Option) -> Void) {
        self.label = label
        self.options = options
        self.title = title
        self.selection = selection
        self.identifier = identifier
        self.select = select
        super.init(frame: .zero)
        segmented.addAction(UIAction { [weak self] _ in self?.segmentChosen() }, for: .valueChanged)
        segmented.accessibilityIdentifier = identifier
        menu.accessibilityIdentifier = identifier
        menu.showsMenuAsPrimaryAction = true
        menu.contentHorizontalAlignment = .leading
        [segmented, menu].forEach { addSubview($0); $0.ukPin(to: self) }
        segmented.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        menu.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.rebuild() }
        rebuild()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private var isAccessibilityLayout: Bool { traitCollection.preferredContentSizeCategory.isAccessibilityCategory }

    private func rebuild() {
        builtAccessibility = isAccessibilityLayout
        segmented.isHidden = isAccessibilityLayout
        menu.isHidden = !isAccessibilityLayout
        segmented.removeAllSegments()
        for (index, option) in options.enumerated() { segmented.insertSegment(withTitle: title(option), at: index, animated: false) }
        menu.menu = UIMenu(children: options.map { option in
            UIAction(title: title(option), state: option == selection ? .on : .off) { [weak self] _ in self?.choose(option) }
        })
        showSelection()
    }

    private func showSelection() {
        let index = selection.flatMap { options.firstIndex(of: $0) }
        segmented.selectedSegmentIndex = index ?? UISegmentedControl.noSegment
        var configuration = UIButton.Configuration.plain()
        configuration.title = selection.map(title) ?? label
        configuration.image = UIImage(systemName: "chevron.up.chevron.down")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = HassTokens.Spacing.s
        configuration.contentInsets = .zero
        configuration.titleLineBreakMode = .byWordWrapping
        menu.configuration = configuration
        menu.accessibilityLabel = label
        menu.accessibilityValue = selection.map(title)
        menu.menu = UIMenu(children: options.map { option in
            UIAction(title: title(option), state: option == selection ? .on : .off) { [weak self] _ in self?.choose(option) }
        })
    }

    private func segmentChosen() {
        let index = segmented.selectedSegmentIndex
        if options.indices.contains(index) { choose(options[index]) }
        // The device's reported value is the selection: show it again until the controller echoes the new one.
        showSelection()
    }

    private func choose(_ option: Option) {
        if option != selection { select(option) }
    }
}

// MARK: - Badged segments

/// One segment of ``UKBadgedTabSegments``: an icon (with its count badge) and/or a title, at least 44 pt tall, named for
/// VoiceOver with its count ("Overdue Chores, 3 items") and marked selected (`BadgedTabSegment`).
final class UKBadgedTabSegment: UIControl {
    let title: String
    let symbol: String?
    let badge: Int
    let showsTitle: Bool
    private let image = UIImageView()
    private let label = UILabel()
    private let badgeView = UKSegmentBadge()
    private(set) var isChosen = false

    init(title: String, symbol: String?, badge: Int, showsTitle: Bool, position: String, identifier: String) {
        self.title = title
        self.symbol = symbol
        self.badge = badge
        self.showsTitle = showsTitle
        super.init(frame: .zero)
        let column = UIStackView()
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 2
        column.isUserInteractionEnabled = false
        if let symbol {
            image.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(showsTitle ? .body : .title3)))
            image.contentMode = .center
            image.addSubview(badgeView)
            badgeView.translatesAutoresizingMaskIntoConstraints = false
            // `.overlay(alignment: .topTrailing)` offset by (10, -8).
            NSLayoutConstraint.activate([
                badgeView.trailingAnchor.constraint(equalTo: image.trailingAnchor, constant: 10),
                badgeView.topAnchor.constraint(equalTo: image.topAnchor, constant: -8),
            ])
            badgeView.update(ModalTabBarStyle.badgeText(badge))
            column.addArrangedSubview(image)
        }
        if showsTitle {
            label.text = title
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
            label.numberOfLines = 1
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = true
            column.addArrangedSubview(label)
        }
        addSubview(column)
        column.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            column.centerYAnchor.constraint(equalTo: centerYAnchor),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor), column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: showsTitle && symbol != nil ? ModalTabBarStyle.titledSegmentHeight : ModalTabBarStyle.iconSegmentHeight),
        ])
        isAccessibilityElement = true
        accessibilityLabel = ModalTabBarStyle.accessibilityTitle(title, badge: badge)
        accessibilityValue = position
        accessibilityIdentifier = identifier
        setChosen(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setChosen(_ chosen: Bool, animated: Bool) {
        isChosen = chosen
        let color = UIColor(chosen ? HassTokens.RGB.Ink.primary : HassTokens.RGB.Ink.secondary)
        label.font = UKFont.preferred(.caption1, weight: chosen ? .semibold : .regular)
        image.tintColor = color
        label.textColor = color
        accessibilityTraits = chosen ? [.button, .selected] : .button
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: showsTitle && symbol != nil ? ModalTabBarStyle.titledSegmentHeight : ModalTabBarStyle.iconSegmentHeight)
    }
}

/// The count on a segment's icon, "9+" past nine; nothing for none. Hidden from VoiceOver because the segment's own name speaks
/// the count.
final class UKSegmentBadge: UIView {
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(HassTokens.RGB.Ink.badge)
        isAccessibilityElement = false
        // The badge rides on a small icon, so it stops at the first accessibility size.
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: UIFont.systemFont(ofSize: 12, weight: .bold), maximumPointSize: 12 * 1.35)
        label.textColor = .white
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 16), heightAnchor.constraint(greaterThanOrEqualToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ text: String?) {
        label.text = text
        isHidden = text == nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// The segments of a ``UKModalTabBar`` with count badges: a segmented control's look (the selected segment lifted onto the
/// sheet's cell colour) built from buttons, so each segment can carry a badge and its own spoken name. The selected capsule
/// glides to the new segment with ``UKMotion/Token/segment`` (a jump under Reduce Motion). The glass capsule around them belongs
/// to the bar (`BadgedTabSegments`).
final class UKBadgedTabSegments<Item: Hashable & Identifiable>: UIView {
    private let segments: [ModalTabSegment<Item>]
    private let lift = UIView()
    private let row = UIStackView()
    private var views: [UKBadgedTabSegment] = []
    var onSelect: (Item) -> Void = { _ in }
    var selection: Item {
        didSet { if selection != oldValue { updateSelection(animated: true) } }
    }

    init(segments: [ModalTabSegment<Item>], showsTitles: Bool, selection: Item, identifier: String, label: String) {
        self.segments = segments
        self.selection = selection
        super.init(frame: .zero)
        lift.backgroundColor = UIColor(HassTokens.RGB.Surface.sheetCell)
        lift.isUserInteractionEnabled = false
        lift.accessibilityIdentifier = "\(identifier).lift"
        addSubview(lift)
        row.axis = .horizontal
        row.distribution = .fillEqually
        addSubview(row)
        row.ukPin(to: self)
        for (index, segment) in segments.enumerated() {
            let view = UKBadgedTabSegment(
                title: segment.title, symbol: segment.symbol, badge: segment.badge, showsTitle: showsTitles || segment.symbol == nil,
                position: ModalTabBarStyle.positionValue(index: index, count: segments.count), identifier: "\(identifier).\(segment.id)")
            view.addAction(UIAction { [weak self] _ in self?.choose(segment.item) }, for: .touchUpInside)
            views.append(view)
            row.addArrangedSubview(view)
        }
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityLabel = label
        accessibilityIdentifier = identifier
        updateSelection(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func choose(_ item: Item) {
        // The selected segment glides to the new one; under Reduce Motion it jumps (HIG Motion).
        selection = item
        onSelect(item)
    }

    private func updateSelection(animated: Bool) {
        for (index, segment) in segments.enumerated() { views[index].setChosen(segment.item == selection, animated: animated) }
        if animated, window != nil {
            UKMotion.animate(.segment) { [self] in placeLift() }
        } else {
            placeLift()
        }
    }

    private func placeLift() {
        layoutIfNeeded()
        guard segments.contains(where: { $0.item == selection }) else { lift.isHidden = true; return }
        lift.isHidden = false
        syncLiftFrame()
    }

    /// Puts the lift on the selected segment. The row lays its segments out in its own pass, after this view's, so it is laid
    /// out first: a stale segment frame left the lift wider or shifted past the bar after a width change.
    private func syncLiftFrame() {
        guard let index = segments.firstIndex(where: { $0.item == selection }) else { return }
        row.layoutIfNeeded()
        lift.frame = views[index].frame
        lift.layer.cornerRadius = lift.bounds.height / 2
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncLiftFrame()
    }
}

// MARK: - Modal tab bar

/// The one section switcher for a tabbed modal (`ModalTabBar`; pattern `.agents/patterns/modal-sheet.md`): a system segmented
/// control on a glass capsule, pinned along the bottom of the modal like the web's `ModalIconTabNav`. On iPhone (compact width)
/// the segments are icons, on iPad and the unfolded Duo text titles; a bar with badges draws its own segments; at accessibility
/// text sizes it becomes a menu of text titles. Icon segments still carry their titles for VoiceOver.
///
/// ```swift
/// let bar = UKModalTabBar(tabs: Tab.allCases, label: "Thermostat sections", title: { $0.title }, symbol: { ModalTabSymbols.symbol(for: $0) },
///                         badge: nil, selection: tab, identifier: "climate.tabs") { tab = $0 }
/// let page = UKPinnedBarViewController(content: sheetContent, bar: bar.inset())     // along the bottom, over the content
/// ```
public final class UKModalTabBar<Item: Hashable & Identifiable>: UIView {
    let segments: [ModalTabSegment<Item>]
    public let label: String
    public let identifier: String
    private let hasSymbols: Bool
    private let hasBadges: Bool
    private let onSelect: (Item) -> Void
    private var badged: UKBadgedTabSegments<Item>?
    private var segmented: UISegmentedControl?
    public var selection: Item {
        didSet {
            guard selection != oldValue else { return }
            badged?.selection = selection
            syncNative()
        }
    }

    public init(tabs: [Item], label: String, title: (Item) -> String, symbol: ((Item) -> String)? = nil, badge: ((Item) -> Int)? = nil,
                selection: Item, identifier: String, onSelect: @escaping (Item) -> Void) {
        segments = tabs.map { ModalTabSegment(item: $0, title: title($0), symbol: symbol?($0), badge: badge?($0) ?? 0) }
        self.label = label
        hasSymbols = symbol != nil
        hasBadges = badge != nil
        self.selection = selection
        self.identifier = identifier
        self.onSelect = onSelect
        super.init(frame: .zero)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitHorizontalSizeClass.self]) { (self: Self, _) in self.rebuild() }
        rebuild()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The bar with the padding that pins it to a modal's edge (`modalTabBar`): 16 pt each side, 8 above and below.
    public func inset() -> UIView {
        let wrapper = UIView()
        wrapper.addSubview(self)
        ukPin(to: wrapper, insets: UIEdgeInsets(top: HassTokens.Spacing.s, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.s, right: HassTokens.Spacing.l))
        return wrapper
    }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        badged = nil
        segmented = nil
        let form = ModalTabBarStyle.form(hasSymbols: hasSymbols, hasBadges: hasBadges, compactWidth: traitCollection.horizontalSizeClass == .compact,
                                         accessibilitySize: traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
        let glass = UKNavigationGlassView(shape: .capsule)
        addSubview(glass)
        glass.ukPin(to: self)
        let inner = glass.contentView
        switch form {
        case .menu:
            // Titles, not icons: at accessibility sizes the section names are what a reader needs.
            let button = UIButton(type: .system)
            button.showsMenuAsPrimaryAction = true
            button.contentHorizontalAlignment = .leading
            var configuration = UIButton.Configuration.plain()
            configuration.title = segments.first { $0.item == selection }?.title
            configuration.image = UIImage(systemName: "chevron.up.chevron.down")
            configuration.imagePlacement = .trailing
            configuration.imagePadding = HassTokens.Spacing.s
            configuration.contentInsets = .zero
            button.configuration = configuration
            // One line, truncating, as a menu picker's label: a wrapped title made the bar taller than the page it covers.
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.menu = UIMenu(children: segments.map { segment in
                UIAction(title: ModalTabBarStyle.accessibilityTitle(segment.title, badge: segment.badge),
                         state: segment.item == selection ? .on : .off) { [weak self] _ in self?.choose(segment.item) }
            })
            button.accessibilityLabel = label
            button.accessibilityValue = segments.first { $0.item == selection }?.title
            button.accessibilityIdentifier = identifier
            inner.addSubview(button)
            button.ukPin(to: inner, insets: UIEdgeInsets(top: 0, left: HassTokens.Spacing.m, bottom: 0, right: HassTokens.Spacing.m))
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        case .badged, .badgedWithTitles:
            // A system segmented control draws a title or an image, never a badge: draw our own segments on the same capsule.
            let segmentsView = UKBadgedTabSegments(segments: segments, showsTitles: form == .badgedWithTitles, selection: selection, identifier: identifier, label: label)
            segmentsView.onSelect = { [weak self] item in self?.choose(item) }
            badged = segmentsView
            inner.addSubview(segmentsView)
            segmentsView.ukPin(to: inner, insets: UIEdgeInsets(top: ModalTabBarStyle.glassInset, left: ModalTabBarStyle.glassInset, bottom: ModalTabBarStyle.glassInset, right: ModalTabBarStyle.glassInset))
        case .icons, .text:
            let control = UISegmentedControl()
            for (index, segment) in segments.enumerated() {
                if form == .icons, let symbol = segment.symbol, let image = UIImage(systemName: symbol) {
                    // A label, not a bare image: the segmented control reads its title to VoiceOver.
                    image.accessibilityLabel = segment.title
                    control.insertSegment(with: image, at: index, animated: false)
                } else {
                    control.insertSegment(withTitle: segment.title, at: index, animated: false)
                }
            }
            control.addAction(UIAction { [weak self, weak control] _ in
                guard let self, let control, self.segments.indices.contains(control.selectedSegmentIndex) else { return }
                self.choose(self.segments[control.selectedSegmentIndex].item)
            }, for: .valueChanged)
            control.accessibilityLabel = label
            control.accessibilityIdentifier = identifier
            segmented = control
            inner.addSubview(control)
            control.ukPin(to: inner, insets: UIEdgeInsets(top: ModalTabBarStyle.glassInset, left: ModalTabBarStyle.glassInset, bottom: ModalTabBarStyle.glassInset, right: ModalTabBarStyle.glassInset))
            // The floor the system's large segmented control already meets, stated so it holds on every OS.
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
            syncNative()
        }
    }

    private func syncNative() {
        segmented?.selectedSegmentIndex = segments.firstIndex { $0.item == selection } ?? UISegmentedControl.noSegment
    }

    private func choose(_ item: Item) {
        selection = item
        onSelect(item)
    }
}
#endif
