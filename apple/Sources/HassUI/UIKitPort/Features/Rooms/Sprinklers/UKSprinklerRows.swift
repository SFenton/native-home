#if os(iOS)
import HassCore
import HassDesign
import UIKit

// The contents of the Sprinklers sheet's list rows (`SprinklerRow`, `WrappingRowLabel`, `StepperRow`, `DayPicker`, the toggles and
// the status pills), each a view that is made once and told its state again with `show`.

// MARK: - Zone and program text

/// An icon, a title and secondary lines (`SprinklerRow`): one accessibility element, "title, line · line". While active the icon
/// and lines take the water colour (`#4CC9F0` on the sheet cell is 8:1), otherwise the secondary ink.
@MainActor
final class UKSprinklerRowContent: UKRowView {
    init() {
        super.init(UKRowContent("", style: .form))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// - Parameters:
    ///   - hint: Spoken after the label ("Water now").
    ///   - isEnabled: A row that cannot be used is dimmed and spoken as not enabled.
    func show(symbol: String, isActive: Bool, title: String, lines: [String], hint: String?, identifier: String?, isEnabled: Bool = true) {
        let joined = lines.joined(separator: " · ")
        let ink = isActive ? UIColor(SprinklerStyle.waterToken) : UKInk.secondary
        var content = UKRowContent(title, subtitle: joined.isEmpty ? nil : joined, symbol: symbol, glyph: ink, subtitleInk: ink, style: .form)
        content.subtitleStyle = .subheadline
        content.identifier = identifier
        content.hint = hint
        update(content)
        textTraits = isEnabled ? .button : [.button, .notEnabled]
        alpha = isEnabled ? 1 : 0.4
    }
}

/// A control around a row's text that opens something (the `NavigationLink` beside a program's switch), pressed to 60%.


// MARK: - Button rows

/// A list button's icon and title (`WrappingRowLabel`): the title wraps and the row grows with it. One accessibility element, a
/// button named for the title.
@MainActor
final class UKSprinklerButtonContent: UKRowView {
    init() {
        super.init(UKRowContent("", style: .form))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// - Parameter ink: The icon and title colour; the action tint while enabled.
    func show(title: String, symbol: String, ink: UIColor, isEnabled: Bool, identifier: String) {
        var content = UKRowContent(title, symbol: symbol, glyph: ink, style: .form)
        content.titleInk = ink
        content.identifier = identifier
        update(content)
        textTraits = isEnabled ? .button : [.button, .notEnabled]
    }
}

/// Plain text in a row (the "Days" label); hidden from VoiceOver, which reads the day buttons.
@MainActor
final class UKSprinklerPlainTextContent: UKRowView {
    init(_ text: String) {
        super.init(UKRowContent(text, style: .form))
        isTextAccessible = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Toggle row

/// A `Label` (tinted icon, primary title) and a switch that shows a controller's value (`ControllerToggle`). The switch is the row's
/// accessibility element, named for the title.
@MainActor
final class UKSprinklerToggleContent: UKRowView {
    private let toggle: UKControllerToggle
    private let sink: UKSprinklerSwitchSink

    init(symbol: String?) {
        let sink = UKSprinklerSwitchSink()
        let toggle = UKControllerToggle(isOn: false) { sink.send($0) }
        self.sink = sink
        self.toggle = toggle
        super.init(UKRowContent("", symbol: symbol, glyph: UKInk.action, style: .form))
        toggle.onTintColor = UKInk.action
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessory(toggle)
        isTextAccessible = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(title: String, isOn: Bool, isEnabled: Bool, identifier: String, send: @escaping (Bool) -> Void) {
        var content = rowContent
        content.title = title
        update(content, accessory: accessory)
        sink.send = send
        toggle.show(isOn)
        toggle.isEnabled = isEnabled
        toggle.accessibilityLabel = title
        toggle.accessibilityIdentifier = identifier
    }
}

/// Holds a switch's change handler, so the switch can be made before the row that answers it.
@MainActor
final class UKSprinklerSwitchSink {
    var send: (Bool) -> Void = { _ in }
}

/// A program's row: its text opens the schedule editor, its switch (named "<zone> schedule") enables it. The two are separate
/// controls in one row, and the row has no chevron (the link is not the row's root).
@MainActor
final class UKSprinklerProgramContent: UKRowView {
    private let tap = UKCheckToggle()
    private let toggle: UKControllerToggle
    private let sink: UKSprinklerSwitchSink
    private var open: () -> Void = {}

    init() {
        let sink = UKSprinklerSwitchSink()
        let toggle = UKControllerToggle(isOn: false) { sink.send($0) }
        self.sink = sink
        self.toggle = toggle
        var content = UKRowContent("", symbol: "calendar.badge.clock", style: .form)
        content.subtitleStyle = .subheadline
        super.init(content)
        toggle.onTintColor = UKInk.action
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessory(toggle)
        installTapTarget(tap)
        tap.addAction(UIAction { [weak self] _ in self?.open() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// - Parameters:
    ///   - isOn: The program is enabled (its switch).
    ///   - isAvailable: The program exists in Home Assistant; otherwise the row and its switch are disabled.
    func show(index: Int, name: String, isOn: Bool, lines: [String], isAvailable: Bool,
              open: @escaping () -> Void, send: @escaping (Bool) -> Void) {
        self.open = open
        sink.send = send
        let joined = lines.joined(separator: " · ")
        let ink = isOn ? UIColor(SprinklerStyle.waterToken) : UKInk.secondary
        var content = UKRowContent(name, subtitle: joined.isEmpty ? nil : joined, symbol: "calendar.badge.clock", glyph: ink, subtitleInk: ink, style: .form)
        content.subtitleStyle = .subheadline
        update(content, accessory: toggle)
        // The tap target is the element for the text (a button); the switch is its own, named "<zone> schedule".
        tap.isAccessibilityElement = true
        tap.accessibilityLabel = UKRowView.accessibilityLabel(title: name, subtitle: joined.isEmpty ? nil : joined)
        tap.accessibilityIdentifier = "sprinkler.program.\(index)"
        tap.accessibilityTraits = isAvailable ? .button : [.button, .notEnabled]
        tap.isEnabled = isAvailable
        alpha = isAvailable ? 1 : 0.4
        toggle.show(isOn)
        toggle.isEnabled = isAvailable
        toggle.accessibilityLabel = name
        toggle.accessibilityIdentifier = "sprinkler.program.\(index).enabled"
    }
}

// MARK: - Stepper row

/// A stepper whose label is an icon, a title and the value (`Stepper` with `StepperRow`). The label puts the value beside the title
/// when both fit and under it when they do not (`ViewThatFits`). The stepper is the row's accessibility element.
@MainActor
final class UKSprinklerStepperContent: UKFormStepperRow {
    private var step: (Int) -> Void = { _ in }

    init(symbol: String) {
        super.init(title: "", identifier: "", symbol: symbol, glyph: UKInk.action)
        onChange = { [weak self] value in self?.step(Int(value)) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// - Parameters:
    ///   - value: The value shown.
    ///   - valueText: "15 min", "100%".
    ///   - spokenValue: "15 minutes", "100 percent".
    func show(title: String, value: Int, range: ClosedRange<Int>, step: Int, valueText: String, spokenValue: String, isEnabled: Bool,
              identifier: String, onChange: @escaping (Int) -> Void) {
        self.step = onChange
        var content = rowContent
        content.title = title
        update(content, accessory: accessory)
        stepper.stepValue = Double(step)
        show(current: Double(value), minimum: Double(range.lowerBound), maximum: Double(range.upperBound), display: valueText,
             isEnabled: isEnabled, label: title)
        stepper.accessibilityValue = spokenValue
        stepper.accessibilityIdentifier = identifier
    }
}

// MARK: - Presets

/// The run time presets (`SegmentedChoice`, "Run time presets").
@MainActor
final class UKSprinklerPresetsContent: UIView {
    private let choice: UKSegmentedChoice<Int>

    init(onChoose: @escaping (Int) -> Void) {
        choice = UKSegmentedChoice(label: "Run time presets", options: SprinklersConfig.manualRunPresets, title: { "\($0) min" },
                                   selection: nil, identifier: "sprinkler.runTime.presets", select: onChoose)
        super.init(frame: .zero)
        choice.translatesAutoresizingMaskIntoConstraints = false
        addSubview(choice)
        choice.ukPin(to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(selection: Int?, isEnabled: Bool) {
        choice.selection = selection
        choice.isUserInteractionEnabled = isEnabled
        choice.alpha = isEnabled ? 1 : 0.5
    }
}

// MARK: - Alert

/// The controller's last failure (`InlineAlert(error)`), full width above the list.
@MainActor
final class UKSprinklerAlertContent: UIView {
    private var alert: UKInlineAlertView?

    func show(message: String) {
        guard accessibilityLabel != message else { return }
        accessibilityLabel = message
        alert?.removeFromSuperview()
        let view = UKInlineAlertView(message)
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        view.ukPin(to: self)
        alert = view
    }
}

// MARK: - Status pills

/// The controller's four status pills in a responsive grid (`DynamicGridLayout` of `StatusPill`): Controller, Battery, Next Watering
/// and Last Watering, on the grouped list's cells.
@MainActor
final class UKSprinklerPillGrid: UIView, UKGridMeasuring {
    private let grid: UKDynamicGridView
    private let pills: [UKStatusPillView]
    private let format = SprinklerFormat()
    private let kind: Kind

    enum Kind {
        /// The sheet's Status section: four pills on grouped list cells, up to four across.
        case sheet
        /// A controller card on the page: Battery, Next, Last and Hub on the module, two across with no gap.
        case card
    }

    init(kind: Kind, valuesPending: Bool) {
        self.kind = kind
        switch kind {
        case .sheet:
            grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, spacing: HassTokens.Spacing.s))
            pills = [
                UKStatusPillView(label: "Controller", value: "", symbol: "info.circle", surface: .groupedList),
                UKStatusPillView(label: "Battery", value: "", symbol: "battery.100percent", surface: .groupedList),
                UKStatusPillView(label: "Next Watering", value: "", symbol: "calendar.badge.clock", surface: .groupedList),
                UKStatusPillView(label: "Last Watering", value: "", symbol: "clock.arrow.circlepath", surface: .groupedList),
            ]
        case .card:
            grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 2, spacing: 0))
            pills = [
                UKStatusPillView(label: "Battery", value: "", symbol: "battery.100percent", surface: .module),
                UKStatusPillView(label: "Next Watering", value: "", symbol: "calendar.badge.clock", surface: .module),
                UKStatusPillView(label: "Last Watering", value: "", symbol: "clock.arrow.circlepath", surface: .module),
                UKStatusPillView(label: "Hub", value: "", symbol: "antenna.radiowaves.left.and.right", surface: .module),
            ]
        }
        super.init(frame: .zero)
        pills.forEach { $0.valuesPending = valuesPending }
        grid.setItems(pills.map { UKGridItem($0) })
        addSubview(grid)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKSprinklerPillGrid, _) in view.rescale() }
        rescale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The pill width scales with Dynamic Type (`@ScaledMetric(relativeTo: .footnote)`).
    private func rescale() {
        var configuration = grid.configuration
        configuration.minCellWidth = UKFont.scaled(150, relativeTo: .footnote, traits: traitCollection)
        grid.configuration = configuration
        setNeedsLayout()
    }

    /// Shows the controller's snapshot.
    func show(_ snapshot: SprinklerSnapshot) {
        switch kind {
        case .sheet:
            pills[0].configure(label: "Controller", value: format.status(snapshot),
                               symbol: snapshot.status == .watering ? SprinklerStyle.symbol : "info.circle",
                               tone: SprinklerControllerSheet.tone(snapshot))
            pills[1].configure(label: "Battery", value: format.battery(snapshot), symbol: "battery.100percent",
                               tone: snapshot.batteryLow ? .warning : .neutral)
            pills[2].configure(label: "Next Watering", value: format.nextStart(snapshot), symbol: "calendar.badge.clock")
            pills[3].configure(label: "Last Watering", value: format.lastStart(snapshot.lastRun),
                               detail: snapshot.lastRun.runTimeMinutes.map(format.minutes), symbol: "clock.arrow.circlepath")
        case .card:
            pills[0].configure(label: "Battery", value: format.battery(snapshot), symbol: "battery.100percent",
                               tone: snapshot.batteryLow ? .warning : .neutral)
            pills[1].configure(label: "Next Watering", value: format.nextStart(snapshot), symbol: "calendar.badge.clock")
            pills[2].configure(label: "Last Watering", value: format.lastStart(snapshot.lastRun), symbol: "clock.arrow.circlepath")
            pills[3].configure(label: "Hub", value: snapshot.hubConnected ? "Connected" : "Unavailable",
                               symbol: "antenna.radiowaves.left.and.right", tone: snapshot.hubConnected ? .ok : .unavailable)
        }
        setNeedsLayout()
    }

    var hinge: CGRect? {
        get { grid.hinge }
        set { grid.hinge = newValue }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { grid.gridHeight(forWidth: width) }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        grid.frame = bounds
    }
}

/// The Status section's row: the pill grid, as tall as its width needs.
@MainActor
final class UKSprinklerPillsRow: UKSprinklerWidthDrivenView {
    private let pills: UKSprinklerPillGrid

    init(valuesPending: Bool) {
        pills = UKSprinklerPillGrid(kind: .sheet, valuesPending: valuesPending)
        super.init(frame: .zero)
        addSubview(pills)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ snapshot: SprinklerSnapshot) {
        pills.show(snapshot)
        invalidateHeight()
    }

    override func height(forWidth width: CGFloat) -> CGFloat {
        pills.hinge = UKHinge.frame
        return pills.gridHeight(forWidth: width)
    }

    override func layoutContent() { pills.frame = bounds }
}

// MARK: - Day picker

/// A day button (`DayPicker`): a 44 pt circle filled with the water colour and dark text when chosen, a faint fill otherwise. It
/// reads the full day name and whether it is selected.
@MainActor
final class UKSprinklerDayButton: UIControl {
    private let disc = UIView()
    private let label = UILabel()
    private let day: Int
    private var chosen = false
    private var hasShown = false

    init(day: Int, action: @escaping () -> Void) {
        self.day = day
        super.init(frame: .zero)
        disc.isUserInteractionEnabled = false
        label.isUserInteractionEnabled = false
        label.text = SprinklerFormat.dayLetters[day]
        label.textAlignment = .center
        label.isAccessibilityElement = false
        addSubview(disc)
        addSubview(label)
        ukOnContentSizeChange { [weak self] in self?.label.font = UKFont.rowTitle(self?.traitCollection) }
        accessibilityLabel = SprinklerFormat.dayNames[day]
        accessibilityIdentifier = "sprinkler.schedule.day.\(day)"
        isAccessibilityElement = true
        addAction(UIAction { _ in action() }, for: .touchUpInside)
        show(chosen: false, isEnabled: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(chosen: Bool, isEnabled: Bool) {
        let changed = chosen != self.chosen
        self.chosen = chosen
        self.isEnabled = isEnabled
        let fill = chosen ? UIColor(SprinklerStyle.waterToken) : UIColor.secondaryLabel.withAlphaComponent(0.15)
        let ink = chosen ? UKInk.sheetGround : UKInk.primary
        let paint = {
            self.disc.backgroundColor = fill
            self.label.textColor = ink
        }
        if changed, hasShown, window != nil {
            UKMotion.stateFade("DayPicker", view: self, animated: true, paint)
        } else {
            paint()
        }
        hasShown = true
        accessibilityTraits = chosen ? [.button, .selected] : .button
        if !isEnabled { accessibilityTraits.insert(.notEnabled) }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = min(bounds.width, bounds.height)
        disc.frame = CGRect(x: (bounds.width - diameter) / 2, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
        disc.layer.cornerRadius = diameter / 2
        label.frame = bounds
    }
}

/// Seven day buttons, Sunday first (`DayPicker`). One row when seven 44 pt buttons fit; else Sunday to Wednesday over Thursday to
/// Saturday on a shared four-column grid, so Thursday lines up under Sunday (the folded iPhone Duo's row left 42 pt each).
@MainActor
final class UKSprinklerDayPickerRow: UKSprinklerWidthDrivenView {
    private var buttons: [UKSprinklerDayButton] = []
    private var days: Set<Int> = []
    private var toggle: (Int) -> Void = { _ in }

    init() {
        super.init(frame: .zero)
        for day in 0..<7 {
            let button = UKSprinklerDayButton(day: day) { [weak self] in self?.toggle(day) }
            buttons.append(button)
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(days: Set<Int>, isEnabled: Bool, toggle: @escaping (Int) -> Void) {
        self.toggle = toggle
        self.days = days
        for (day, button) in buttons.enumerated() { button.show(chosen: days.contains(day), isEnabled: isEnabled) }
    }

    private func fitsOneRow(_ width: CGFloat) -> Bool {
        width >= 7 * HassTokens.minTarget + 6 * HassTokens.Spacing.xs
    }

    override func height(forWidth width: CGFloat) -> CGFloat {
        fitsOneRow(width) ? HassTokens.minTarget : 2 * HassTokens.minTarget + HassTokens.Spacing.s
    }

    override func layoutContent() {
        let width = bounds.width
        let target = HassTokens.minTarget
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ button: UKSprinklerDayButton, x: CGFloat, y: CGFloat, w: CGFloat) {
            button.frame = CGRect(x: mirror ? width - x - w : x, y: y, width: w, height: target)
        }
        if fitsOneRow(width) {
            let w = (width - 6 * HassTokens.Spacing.xs) / 7
            for (day, button) in buttons.enumerated() { place(button, x: CGFloat(day) * (w + HassTokens.Spacing.xs), y: 0, w: w) }
        } else {
            let w = (width - 3 * HassTokens.Spacing.xs) / 4
            for (day, button) in buttons.enumerated() {
                let column = day % 4
                let row = day / 4
                place(button, x: CGFloat(column) * (w + HassTokens.Spacing.xs), y: CGFloat(row) * (target + HassTokens.Spacing.s), w: w)
            }
        }
    }
}

// MARK: - Start time row

/// A start time: "Start N" and a compact time picker, and a minus button that removes it (disabled for the only one).
@MainActor
final class UKSprinklerTimeContent: UKRowView {
    private let picker = UIDatePicker()
    private let remove = UIButton(type: .system)
    private var onPick: (Date) -> Void = { _ in }

    init(onRemove: @escaping () -> Void) {
        super.init(UKRowContent("", style: .form))
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .compact
        picker.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onPick(self.picker.date)
        }, for: .valueChanged)
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "minus.circle.fill", withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.title3)))
        configuration.baseForegroundColor = .systemRed
        remove.configuration = configuration
        remove.addAction(UIAction { _ in onRemove() }, for: .touchUpInside)
        remove.setContentHuggingPriority(.required, for: .horizontal)
        remove.widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        remove.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        let controls = UIStackView(arrangedSubviews: [picker, remove])
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = HassTokens.Spacing.s
        setAccessory(controls)
        isTextAccessible = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// - Parameter index: The zero-based position, for "Start 1" and the identifiers.
    func show(index: Int, date: Date, canRemove: Bool, isEnabled: Bool, onPick: @escaping (Date) -> Void) {
        self.onPick = onPick
        var content = rowContent
        content.title = "Start \(index + 1)"
        update(content, accessory: accessory)
        if picker.date != date { picker.setDate(date, animated: false) }
        picker.isEnabled = isEnabled
        picker.accessibilityLabel = "Start \(index + 1)"
        picker.accessibilityIdentifier = "sprinkler.schedule.time.\(index)"
        remove.isEnabled = canRemove && isEnabled
        remove.accessibilityLabel = "Remove Start Time \(index + 1)"
    }
}
#endif
