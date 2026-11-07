#if os(iOS)
import HassCore
import HassDesign
import UIKit

// The small views the wake-light and bed sheets share (`BedroomComponents.swift`).

// MARK: - Section header

/// A section title (heading trait): 20 Bold, the room section header's size, with an optional detail (`BedroomSectionHeader`).
@MainActor
final class UKBedroomSectionHeader: UIStackView {
    init(title: String, detail: String? = nil) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.xs
        let titleLabel = UILabel.uk(.title3, weight: .bold, ink: UKDesignInk.primary)
        titleLabel.text = title
        titleLabel.accessibilityTraits = .header
        addArrangedSubview(titleLabel)
        if let detail { addArrangedSubview(UKDeviceText.subheadline(detail)) }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Row

/// A list row with an icon, title, detail lines and a trailing control (`BedroomRow`; web `EightSleepAlarmGroupButton`, wake-light
/// schedule rows). With ``onOpen`` the icon and text are a button (VoiceOver, Switch Control and Full Keyboard Access); the
/// trailing control stays its own sibling element.
@MainActor
final class UKBedroomRow: UKRowView {
    private let openControl: UKCheckToggle?
    private var title: String
    private var openAction: (() -> Void)?

    init(symbol: String, title: String, lines: [String], isMuted: Bool = false, openIdentifier: String? = nil,
         onOpen: (() -> Void)? = nil, trailing: UIView? = nil) {
        openControl = onOpen == nil ? nil : UKCheckToggle()
        openAction = onOpen
        self.title = title
        var content = UKRowContent(title, subtitle: Self.joined(lines), symbol: symbol,
                                   glyph: isMuted ? UKDesignInk.secondary : UKDesignInk.primary, style: .form)
        content.titleInk = UKDesignInk.primary
        content.titleWeight = .semibold
        content.subtitleInk = UKDesignInk.secondary
        content.subtitleStyle = .subheadline
        content.glyphStyle = .title3
        content.horizontalPadding = HassTokens.Spacing.m
        content.verticalPadding = HassTokens.Spacing.s
        super.init(content, accessory: trailing, surface: .sheet)
        drawsCard = true
        cardColor = UKDesignSurface.sheetCell
        if let trailing {
            trailing.setContentHuggingPriority(.required, for: .horizontal)
            trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        if let control = openControl {
            // The text is the target: at least 44 pt tall, whatever the row's padding.
            installTapTarget(control)
            control.isAccessibilityElement = true
            control.accessibilityTraits = .button
            control.accessibilityIdentifier = openIdentifier ?? ""
            control.accessibilityLabel = ([title] + lines).joined(separator: ", ")
            control.addAction(UIAction { [weak self] _ in self?.openAction?() }, for: .touchUpInside)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func joined(_ lines: [String]) -> String? {
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// Replaces the detail lines under the title.
    func setLines(_ lines: [String]) {
        var content = rowContent
        content.subtitle = Self.joined(lines)
        update(content, accessory: accessory)
        openControl?.accessibilityLabel = ([title] + lines).joined(separator: ", ")
    }
}

// MARK: - Chips

/// One choice in a ``UKChoiceGrid`` or ``UKWeekdayPicker``: a 44 pt target, filled with the action fill while chosen and drawn with
/// a checkmark (the one selection rule: `selectionShowsCheckmark`).
@MainActor
final class UKChipButton: UIControl, UKGridMeasuring {
    enum Shape { case rounded(CGFloat), capsule }

    private let shape: Shape
    private let spacing: CGFloat
    private let boldWhenSelected: Bool
    private let label = UILabel()
    private let check = UIImageView()
    private let content = UIStackView()
    private let title: String
    private(set) var isChosen = false

    init(title: String, accessibilityTitle: String, shape: Shape, spacing: CGFloat, boldWhenSelected: Bool, identifier: String, onTap: @escaping () -> Void) {
        self.shape = shape
        self.spacing = spacing
        self.boldWhenSelected = boldWhenSelected
        self.title = title
        super.init(frame: .zero)
        label.text = title
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        check.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.caption2, weight: .bold)))
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.isAccessibilityElement = false
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = spacing
        content.isUserInteractionEnabled = false
        content.addArrangedSubview(check)
        content.addArrangedSubview(label)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
        layer.cornerCurve = .continuous
        accessibilityLabel = accessibilityTitle
        accessibilityIdentifier = identifier
        accessibilityTraits = .button
        isAccessibilityElement = true
        addAction(UIAction { _ in onTap() }, for: .touchUpInside)
        style(chosen: false, animated: false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Draws the chip chosen or not.
    func show(chosen: Bool, animated: Bool = true) {
        guard chosen != isChosen || label.font == nil else { return }
        style(chosen: chosen, animated: animated)
    }

    private func style(chosen: Bool, animated: Bool) {
        isChosen = chosen
        let apply = {
            self.backgroundColor = chosen ? UKDesignInk.actionFill : UKDesignSurface.sheetCell
            self.label.textColor = chosen ? .white : UKDesignInk.primary
            self.check.tintColor = chosen ? .white : UKDesignInk.primary
        }
        label.font = UKFont.preferred(.subheadline, weight: chosen ? (boldWhenSelected ? .bold : .semibold) : .regular)
        check.isHidden = !chosen
        accessibilityTraits = chosen ? [.button, .selected] : .button
        if animated, window != nil { UKMotion.stateFade("ChipButton", view: self, animated: true, apply) } else { apply() }
        setNeedsLayout()
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - 8 - (isChosen ? spacing + 12 : 0))
        return max(HassTokens.minTarget, ceil(label.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        UKWrapWidth.set(label, in: self, reserving: 8 + UKWrapWidth.reserved(besides: label, in: content))
        switch shape {
        case let .rounded(radius): layer.cornerRadius = radius
        case .capsule: layer.cornerRadius = bounds.height / 2
        }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.5 }
    }
}

/// A grid of single-choice tiles (`ChoiceGrid`; web radio tile grid for ramp and hold durations).
@MainActor
final class UKChoiceGrid<Value: Hashable>: UIStackView {
    private let options: [Value]
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 120, maxColumns: 5, fill: .none))
    private var chips: [UKChipButton] = []
    private let host: UKGridHost

    init(title: String, options: [Value], label: @escaping (Value) -> String, identifier: String, onSelect: @escaping (Value) -> Void) {
        self.options = options
        host = UKGridHost(grid)
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.s
        let heading = UILabel.uk(.subheadline, weight: .semibold, ink: UKDesignInk.primary)
        heading.text = title
        chips = options.map { option in
            UKChipButton(title: label(option), accessibilityTitle: label(option), shape: .rounded(12), spacing: 4, boldWhenSelected: false,
                         identifier: "\(identifier).\(option)") { onSelect(option) }
        }
        grid.setItems(chips.map { UKGridItem($0) })
        grid.configuration.minCellWidth = UKFont.scaled(120, relativeTo: .body, traits: traitCollection)
        addArrangedSubview(heading)
        addArrangedSubview(host)
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKChoiceGrid<Value>, _) in
            view.grid.configuration.minCellWidth = UKFont.scaled(120, relativeTo: .body, traits: view.traitCollection)
            view.host.remeasure()
        }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the chosen option and whether the grid takes taps.
    func show(selection: Value, isDisabled: Bool) {
        for (option, chip) in zip(options, chips) {
            chip.show(chosen: option == selection)
            chip.isEnabled = !isDisabled
        }
        host.remeasure()
    }
}

/// A Sunday to Saturday day picker (`WeekdayPicker`; web day chips).
@MainActor
final class UKWeekdayPicker: UIStackView {
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 52, maxColumns: 7))
    private var chips: [Weekday: UKChipButton] = [:]
    private let host: UKGridHost
    private var days: [Weekday]
    private let onChange: ([Weekday]) -> Void

    /// - Parameter title: The heading above the chips, or nil when the surrounding section already names them.
    init(title: String?, days: [Weekday], identifier: String, onChange: @escaping ([Weekday]) -> Void) {
        self.days = days
        self.onChange = onChange
        host = UKGridHost(grid)
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.s
        if let title {
            let heading = UILabel.uk(.subheadline, weight: .semibold, ink: UKDesignInk.primary)
            heading.text = title
            addArrangedSubview(heading)
        }
        for day in Weekday.allCases {
            chips[day] = UKChipButton(title: day.shortLabel, accessibilityTitle: day.label, shape: .capsule, spacing: 2, boldWhenSelected: true,
                                      identifier: "\(identifier).\(day.rawValue)") { [weak self] in self?.toggle(day) }
        }
        grid.setItems(Weekday.allCases.compactMap { chips[$0] }.map { UKGridItem($0) })
        grid.configuration.minCellWidth = UKFont.scaled(52, relativeTo: .body, traits: traitCollection)
        addArrangedSubview(host)
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        show(days: days)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKWeekdayPicker, _) in
            view.grid.configuration.minCellWidth = UKFont.scaled(52, relativeTo: .body, traits: view.traitCollection)
            view.host.remeasure()
        }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func toggle(_ day: Weekday) {
        let next = Weekday.ordered(days.contains(day) ? days.filter { $0 != day } : days + [day])
        days = next
        show(days: next)
        onChange(next)
    }

    func show(days: [Weekday]) {
        self.days = days
        for (day, chip) in chips { chip.show(chosen: days.contains(day)) }
        host.remeasure()
    }
}

/// An `HH:MM` time bound to a compact time picker (`ClockTimeField`).
@MainActor
enum UKClockTimeField {
    static func make(title: String, time: String, identifier: String, onChange: @escaping (String) -> Void) -> UKDatePickerLine {
        UKDatePickerLine(title: title, mode: .time, date: ClockTimeField.date(time), identifier: identifier) { onChange(ClockTimeField.string($0)) }
    }
}

// MARK: - Adjustable element

/// An accessibility element that adjusts with swipes up and down (`accessibilityAdjustableAction`).
final class UKAdjustableElement: UIAccessibilityElement {
    var increment: () -> Void = {}
    var decrement: () -> Void = {}

    override func accessibilityIncrement() { increment() }
    override func accessibilityDecrement() { decrement() }
}
#endif
