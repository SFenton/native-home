#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A column page with the device sheet chrome (`RoomDeviceSheetChrome`): the title, an optional subtitle that follows state, Close as
/// `device.sheet.done`, and the sheet's identifier.
@MainActor
class UKDeviceSheetPage: UKSheetColumnViewController {
    private let subtitle: (() -> String?)?
    private let sheetIdentifier: String

    init(maxWidth: CGFloat, subtitle: (() -> String?)?, identifier: String) {
        self.subtitle = subtitle
        sheetIdentifier = identifier
        super.init(maxWidth: maxWidth)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityContainerType = .semanticGroup
        view.accessibilityIdentifier = sheetIdentifier
        if let subtitle {
            bag.observe { [weak self] in UKSheetSubtitle.apply(subtitle(), to: self?.navigationItem ?? UINavigationItem()) }
        }
    }

    /// The modal around the page.
    static func modal(_ page: UIViewController, title: String, width: HassSheetWidth, height: HassSheetHeight, key: String) -> UKHassModalController {
        var options = UKHassModalOptions(title: title, fitKey: key)
        options.closeIdentifier = "device.sheet.done"
        options.width = width
        options.height = height
        return UKHassModalController(root: page, options: options)
    }
}

/// Wraps a page's bottom accessory (the gallery's last-call line) in the modal: below the content.
@MainActor
enum UKDeviceSheetAccessory {
    /// The page, with `accessory` pinned below it when there is one.
    static func wrap(_ page: UIViewController, accessory: UIView?) -> UIViewController {
        guard let accessory else { return page }
        return UKSheetPinnedBarPage(content: page, bar: accessory)
    }
}

// MARK: - Grill

/// The grill sheet (`GrillSheet`; web `GrillModalContent.tsx`): the grill's state and its probe, pellet and mode cards.
@MainActor
enum UKGrillSheet {
    static func make(controller: GrillController, accessory: UIView?) -> UKHassModalController {
        let page = UKGrillPage(controller: controller)
        return UKDeviceSheetPage.modal(UKDeviceSheetAccessory.wrap(page, accessory: accessory), title: "\(controller.config.roomTitle): \(controller.config.title)",
                                       width: .form, height: .fitted, key: "GrillSheet")
    }
}

@MainActor
final class UKGrillPage: UKDeviceSheetPage {
    private let controller: GrillController
    private let circle = UIView()
    private let flame = UIImageView()
    private let stateLabel = UKDeviceText.subheadline("")
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
    private var tiles: [UKGlassTileView] = []
    private var lastOff: Bool?

    init(controller: GrillController) {
        self.controller = controller
        super.init(maxWidth: 560, subtitle: { controller.stateText }, identifier: "device.sheet.grill")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\(controller.config.roomTitle): \(controller.config.title)"
        navigationItem.title = title
        // The header circle grows with the glyph (`.title2`), so the flame stays inside it at accessibility sizes.
        flame.image = UIImage(systemName: "flame.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.title2)))
        flame.contentMode = .center
        circle.layer.cornerCurve = .continuous
        circle.addSubview(flame)
        flame.ukPin(to: circle)
        circle.translatesAutoresizingMaskIntoConstraints = false
        let size = UKFont.scaled(HassTokens.minTarget, relativeTo: .title2, traits: traitCollection)
        NSLayoutConstraint.activate([circle.widthAnchor.constraint(equalToConstant: size), circle.heightAnchor.constraint(equalToConstant: size)])
        circle.layer.cornerRadius = size / 2
        circle.isAccessibilityElement = false
        let name = UILabel.uk(.headline, ink: UKDesignInk.primary)
        name.text = controller.config.title
        let texts = UIStackView(arrangedSubviews: [name, stateLabel])
        texts.axis = .vertical
        texts.spacing = 2
        let header = UIStackView(arrangedSubviews: [circle, texts])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = HassTokens.Spacing.m
        header.isAccessibilityElement = true
        header.accessibilityIdentifier = "grill.header"
        stack.addArrangedSubview(header)

        let environment = UKTileEnvironment(context: UKContext(store: EntityStore()).with { $0.surface = .sheet })
        tiles = controller.config.details.map { detail in
            UKGlassTileView(model: Self.model(controller, detail), environment: environment) { [controller] in controller.toggle(detail) }
        }
        grid.setItems(tiles.map { UKGridItem($0) })
        grid.configuration.minCellWidth = UKFont.scaled(132, relativeTo: .subheadline, traits: traitCollection)
        let host = UKGridHost(grid)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKGrillPage, _) in
            page.grid.configuration.minCellWidth = UKFont.scaled(132, relativeTo: .subheadline, traits: page.traitCollection)
            host.remeasure()
        }
        stack.addArrangedSubview(host)
        bag.observe { [weak self] in
            guard let self else { return }
            let off = controller.isOff
            stateLabel.text = controller.stateText
            header.accessibilityLabel = "\(controller.config.title), \(controller.stateText)"
            let ink = off ? UKDesignSurface.secondaryInSheet : UIColor(ColorFamily.cooking.inkToken)
            let fill = off ? UKDesignSurface.sheetCell : (ColorFamily.cooking.fillToken.map { UIColor($0) } ?? .clear)
            if lastOff != off {
                lastOff = off
                UKMotion.stateFade("GrillControls", view: circle, animated: true) { [flame, circle] in
                    flame.tintColor = ink
                    circle.backgroundColor = fill
                }
            }
            for (tile, detail) in zip(tiles, controller.config.details) {
                tile.configure(Self.model(controller, detail), environment: environment, action: nil,
                               perform: { [controller] _ in controller.toggle(detail) })
            }
        }
    }

    /// A reading is a flat tile; Keep Warm and Super Smoke are action tiles (*text, disc*) with a power disc, explicit `turn_on` / `turn_off`
    /// through `GrillController.toggle(_:)` (`PowerToggleActions`).
    private static func model(_ controller: GrillController, _ detail: GrillConfig.Detail) -> UKGlassTileModel {
        let display = controller.display(detail)
        guard detail.isSwitch else {
            return UKGlassTileModel(title: detail.title, subtitle: display.value, symbol: SymbolMap.symbol(for: detail.icon), family: .cooking,
                                    isActive: display.isActive, isUnavailable: display.isUnavailable, kind: .state, identifier: "grill.\(detail.title)")
        }
        let provider = PowerToggleActions.entity(detail.entityId)
        let shown = EntityState(entityId: detail.entityId, state: display.isUnavailable ? "unavailable" : (display.isActive ? "on" : "off"))
        var model = UKGlassTileModel(
            title: detail.title, subtitle: display.value, symbol: SymbolMap.symbol(for: detail.icon), family: .cooking, isActive: display.isActive,
            isUnavailable: display.isUnavailable, behavior: TileBehavior(.action(1), primary: PowerToggleActions.actionId),
            actions: provider.actions(for: shown).items, identifier: "grill.\(detail.title)")
        model.stateCandidates = provider.stateTextCandidates
        return model
    }
}

// MARK: - Fan timer

/// The idle timer: six lengths, one primary button, one footnote (`FanTimerPicker`).
@MainActor
final class UKFanTimerPicker: UIStackView {
    private let selected: () -> Int
    private let canStart: () -> Bool
    private let buttonTitle: (Int) -> String
    private let bag = UKObservationBag()
    private let lengths: UKFanTimerLengthRow
    private let start = UKPrimaryButton("") {}

    convenience init(controller: BathroomFanController) {
        self.init(minutes: BathroomFanController.timerMinutes, labels: [:], identifier: "fan",
                  selected: { controller.selectedMinutes }, canStart: { controller.canStartTimer },
                  title: BathroomFanController.startButtonTitle, footnote: BathroomFanControls.timerFootnote,
                  select: { controller.selectedMinutes = $0 }, start: { controller.startTimer() })
    }

    /// Canonical timer presentation over authored values and closures.
    init(minutes: [Int], labels: [Int: String], identifier: String, selected: @escaping () -> Int,
         canStart: @escaping () -> Bool, title: @escaping (Int) -> String, footnote: String,
         select: @escaping (Int) -> Void, start: @escaping () -> Void) {
        self.selected = selected
        self.canStart = canStart
        buttonTitle = title
        lengths = UKFanTimerLengthRow(minutes: minutes, labels: labels, identifier: identifier)
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.m
        lengths.onSelect = select
        self.start.action = start
        self.start.accessibilityIdentifier = "\(identifier).setTimer"
        [lengths, self.start, UKDeviceText.footnote(footnote)].forEach(addArrangedSubview)
        bag.observe { [weak self] in
            guard let self else { return }
            lengths.show(selection: selected())
            self.start.title = buttonTitle(selected())
            self.start.isEnabled = canStart()
        }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The six timer lengths as a segmented row (`FanTimerLengthRow`): 44 pt tall, the chosen one filled with the label's opposite. At
/// accessibility sizes the row wraps to three columns.
@MainActor
final class UKFanTimerLengthRow: UIView {
    var onSelect: (Int) -> Void = { _ in }
    private let minutes: [Int]
    private var segments: [UKFanTimerSegment] = []
    private let rows = UIStackView()

    init(minutes: [Int] = BathroomFanController.timerMinutes, labels: [Int: String] = [:], identifier: String = "fan") {
        self.minutes = minutes
        super.init(frame: .zero)
        backgroundColor = UKDesignSurface.sheetCell
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        segments = minutes.map { value in
            UKFanTimerSegment(minutes: value, title: labels[value], identifier: "\(identifier).timerOption.\(value)") { [weak self] in self?.onSelect(value) }
        }
        rows.axis = .vertical
        rows.spacing = 2
        addSubview(rows)
        rows.ukPin(to: self, insets: UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2))
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = "\(identifier).timerLength"
        layoutRows()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKFanTimerLengthRow, _) in view.layoutRows() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func layoutRows() {
        let perRow = max(1, traitCollection.isAccessibilitySize ? 3 : segments.count)
        let groups = stride(from: 0, to: segments.count, by: perRow).map { Array(segments[$0..<min($0 + perRow, segments.count)]) }
        rows.ukSetArranged(groups.map { group in
            let row = UIStackView(arrangedSubviews: group)
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 2
            return row
        })
    }

    func show(selection: Int) {
        for (value, segment) in zip(minutes, segments) { segment.show(chosen: value == selection) }
    }
}

/// One length in the row: a 44 pt target, filled when chosen (`FanTimerSegment`).
@MainActor
final class UKFanTimerSegment: UIControl {
    private let label = UILabel()
    private let minutes: Int

    init(minutes: Int, title: String? = nil, identifier: String? = nil, onTap: @escaping () -> Void) {
        self.minutes = minutes
        super.init(frame: .zero)
        label.text = title ?? BathroomFanController.segmentTitle(minutes)
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor), label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        accessibilityLabel = title ?? BathroomFanController.durationTitle(minutes)
        accessibilityIdentifier = identifier ?? "fan.timerOption.\(minutes)"
        isAccessibilityElement = true
        addAction(UIAction { _ in onTap() }, for: .touchUpInside)
        show(chosen: false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(chosen: Bool) {
        label.font = UKFont.preferred(.subheadline, weight: chosen ? .semibold : .regular, monospacedDigit: true)
        label.textColor = chosen ? UIColor(HassTokens.RGB.Surface.selectedSegmentInk) : UKDesignInk.primary
        backgroundColor = chosen ? UIColor(HassTokens.RGB.Surface.selectedSegment) : .clear
        accessibilityTraits = chosen ? [.button, .selected] : .button
    }
}

/// A running timer (`FanTimerRunning`): a timer glyph and the countdown, both 40 pt in the web's timer orange, a thin progress bar that
/// empties as the time runs out, and Clear Timer as a red tinted capsule.
@MainActor
final class UKFanTimerRunning: UIStackView {
    private let remaining: (Date) -> Int?
    private let fraction: (Date) -> Double?
    private let available: () -> Bool
    private let unavailableText: String
    private var running = false
    private let glyph = UIImageView()
    private let countdown = UILabel()
    private let bar = UKFanTimerProgressBar()
    private let clear: UKTintedCapsuleButton
    private let row = UIStackView()
    private let readout = UIView()
    private lazy var clock = UKEverySecond { [weak self] now in self?.tick(now) }

    convenience init(controller: BathroomFanController) {
        self.init(identifier: "fan", title: "Timer", clearTitle: "Clear Timer", unavailableText: "Unavailable",
                  remaining: controller.remainingSeconds, fraction: controller.remainingFraction,
                  available: { controller.timerAvailable }, cancel: { controller.cancelTimer() })
    }

    /// Countdown values are supplied by the controller; this view never starts or emulates an automation.
    init(identifier: String, title: String, clearTitle: String, unavailableText: String,
         remaining: @escaping (Date) -> Int?, fraction: @escaping (Date) -> Double?,
         available: @escaping () -> Bool, cancel: @escaping () -> Void) {
        self.remaining = remaining
        self.fraction = fraction
        self.available = available
        self.unavailableText = unavailableText
        clear = UKTintedCapsuleButton(title: clearTitle, tint: UKInk.danger, action: cancel)
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.m
        glyph.tintColor = UKInk.timer
        glyph.isAccessibilityElement = false
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        countdown.textColor = UKInk.timer
        countdown.numberOfLines = 0
        countdown.adjustsFontForContentSizeCategory = true
        row.addArrangedSubview(glyph)
        row.addArrangedSubview(countdown)
        readout.addSubview(row)
        row.ukPin(to: readout)
        readout.isAccessibilityElement = true
        readout.accessibilityLabel = title
        readout.accessibilityIdentifier = "\(identifier).remaining"
        clear.accessibilityIdentifier = "\(identifier).clearTimer"
        [readout, bar, clear].forEach(addArrangedSubview)
        isHidden = true
        applyFonts()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKFanTimerRunning, _) in view.applyFonts() }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyFonts() {
        let size = UKFont.scaled(40, relativeTo: .largeTitle, traits: traitCollection)
        glyph.image = UIImage(systemName: "timer", withConfiguration: UIImage.SymbolConfiguration(pointSize: size))
        countdown.font = UIFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        // The glyph stacks above the countdown at accessibility sizes, so the number keeps its scaled size.
        row.axis = traitCollection.isAccessibilitySize ? .vertical : .horizontal
        row.alignment = traitCollection.isAccessibilitySize ? .leading : .center
        row.spacing = traitCollection.isAccessibilitySize ? HassTokens.Spacing.s : HassTokens.Spacing.m
    }

    func setRunning(_ running: Bool) {
        self.running = running
        clock.setRunning(running && window != nil)
        clear.isEnabled = available()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        clock.setRunning(running && window != nil)
    }

    private func tick(_ now: Date) {
        let remaining = remaining(now)
        countdown.text = remaining.map(BathroomFanController.formatRemaining) ?? unavailableText
        // Whole minutes: the digits tick every second, the spoken value must not.
        readout.accessibilityValue = remaining.map(BathroomFanController.spokenCountdown) ?? unavailableText
        bar.fraction = fraction(now) ?? 0
    }
}

/// A thin capsule bar in the timer orange (`FanTimerProgressBar`). `fraction` is how much is left, 1 at the start. Decorative.
@MainActor
final class UKFanTimerProgressBar: UIView {
    var fraction: Double = 0 { didSet { setNeedsLayout() } }
    private let fill = UIView()
    static let height: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UKInk.timer.withAlphaComponent(0.22)
        fill.backgroundColor = UKInk.timer
        addSubview(fill)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        fill.layer.cornerRadius = bounds.height / 2
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * min(1, max(0, fraction)), height: bounds.height)
    }
}

#endif
