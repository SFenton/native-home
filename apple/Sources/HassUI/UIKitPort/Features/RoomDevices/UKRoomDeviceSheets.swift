#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The factory the Rooms page opens a room's device sheet with, mirroring how `RoomDeviceModal` / `RoomDeviceModalSheet` pick a SwiftUI
/// sheet: resolve the device with `RoomDeviceModal.resolve(...)`, then
///
/// ```swift
/// if let sheet = UKRoomDeviceSheets.make(for: modal, context: context, onOpenBed: { side in /* present the bed sheet */ }) {
///     sheet.present(from: self)
/// }
/// ```
/// `onOpenBed` runs once the wake-light sheet has closed; present `.bed(devices, side:, tab: .alarms)` from there. The vacuum sheet
/// belongs to the Vacuums lane: this returns nil for `.vacuum`.
@MainActor
enum UKRoomDeviceSheets {
    static func make(for modal: RoomDeviceModal, context: UKContext, accessory: UIView? = nil,
                     onOpenBed: @escaping (BedSide) -> Void = { _ in }) -> UKHassModalController? {
        let sheetContext = context.with { $0.surface = .sheet }
        switch modal {
        case .vacuum:
            return nil
        case let .bathroomFan(fan, _):
            return UKBathroomFanSheet.make(controller: fan, accessory: accessory)
        case let .airPurifier(purifier):
            guard let caller = context.connection ?? context.caller else { return nil }
            return UKAirPurifierSheet.make(controller: AirPurifierController(config: purifier, store: context.store, caller: caller), accessory: accessory)
        case let .humidifier(humidifier):
            guard let connection = context.connection else { return nil }
            return UKHumidifierSheet.make(config: humidifier, connection: connection, context: sheetContext, accessory: accessory)
        case .grill:
            guard let caller = context.connection ?? context.caller else { return nil }
            return UKGrillSheet.make(controller: GrillController(config: .bearGrills, store: context.store, caller: caller), accessory: accessory)
        case let .wakeLight(devices, tab):
            return UKWakeLightSheet.make(devices: devices, initialTab: tab, context: sheetContext, accessory: accessory, onOpenBed: onOpenBed)
        case let .bed(devices, side, tab):
            return UKBedSideSheet.make(devices: devices, side: side, initialTab: tab, context: sheetContext, accessory: accessory)
        }
    }
}

// MARK: - Chrome

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

// MARK: - Air purifier

/// The air purifier sheet (`AirPurifierSheet`; web `AirQualityModalContent.tsx`): fan mode, then Auto's sub-mode or Manual's speed.
@MainActor
enum UKAirPurifierSheet {
    static func make(controller: AirPurifierController, accessory: UIView?) -> UKHassModalController {
        let page = UKAirPurifierPage(controller: controller)
        let root = UKDeviceSheetAccessory.wrap(page, accessory: accessory)
        let modal = UKDeviceSheetPage.modal(root, title: "\(controller.config.roomTitle) Air Quality", width: .form, height: .fitted, key: "AirPurifierSheet")
        return modal
    }
}

@MainActor
final class UKAirPurifierPage: UKDeviceSheetPage {
    private let controller: AirPurifierController
    private var sections: [UKChoiceSection] = []

    init(controller: AirPurifierController) {
        self.controller = controller
        super.init(maxWidth: 640, subtitle: { controller.summary }, identifier: "device.sheet.purifier")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\(controller.config.roomTitle) Air Quality"
        navigationItem.title = title
        let controls = UIStackView()
        controls.axis = .vertical
        controls.spacing = HassTokens.Spacing.xl
        controls.isAccessibilityElement = false
        controls.accessibilityContainerType = .semanticGroup
        controls.accessibilityLabel = "\(controller.config.roomTitle) air purifier controls"
        func section(_ title: String, options: [AirPurifierController.Option], id: String, selected: @escaping () -> String?, disabled: @escaping () -> Bool,
                     visible: @escaping () -> Bool, select: @escaping (AirPurifierController.Option) -> Void) -> UKChoiceSection {
            UKChoiceSection(title: title, options: options, id: id, selected: selected, disabled: disabled, visible: visible, select: select)
        }
        sections = [
            section("Fan Mode", options: AirPurifierController.fanModes, id: "mode", selected: { [controller] in controller.mode },
                    disabled: { [controller] in controller.modeUnavailable }, visible: { true }, select: controller.selectMode),
            section("Auto Mode", options: AirPurifierController.autoModes, id: "auto", selected: { [controller] in controller.autoMode },
                    disabled: { [controller] in controller.autoModeUnavailable }, visible: { [controller] in controller.showsAutoModes }, select: controller.selectAutoMode),
            section("Fan Speed", options: AirPurifierController.speeds, id: "speed", selected: { [controller] in controller.percentage },
                    disabled: { [controller] in controller.fanUnavailable }, visible: { [controller] in controller.showsSpeeds }, select: controller.selectSpeed),
        ]
        sections.forEach(controls.addArrangedSubview)
        stack.addArrangedSubview(controls)
        bag.observe { [weak self] in self?.sections.forEach { $0.refresh() } }
    }
}

/// A titled segmented choice that shows and hides with state (`AirPurifierControls.section`).
@MainActor
final class UKChoiceSection: UIStackView {
    private let choice: UKSegmentedChoice<AirPurifierController.Option>
    private let options: [AirPurifierController.Option]
    private let selected: () -> String?
    private let disabled: () -> Bool
    private let visible: () -> Bool

    init(title: String, options: [AirPurifierController.Option], id: String, selected: @escaping () -> String?, disabled: @escaping () -> Bool,
         visible: @escaping () -> Bool, select: @escaping (AirPurifierController.Option) -> Void) {
        self.options = options
        self.selected = selected
        self.disabled = disabled
        self.visible = visible
        choice = UKSegmentedChoice(label: title, options: options, title: { $0.title }, selection: nil, identifier: "purifier.\(id)", select: select)
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.m
        let section = UKDeviceSection(title: title, content: [choice])
        addArrangedSubview(section)
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func refresh() {
        isHidden = !visible()
        choice.selection = options.first { $0.value == selected() }
        choice.isUserInteractionEnabled = !disabled()
        choice.alpha = disabled() ? 0.4 : 1
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

// MARK: - Bathroom fan

/// The bathroom fan sheet (`BathroomFanSheet`; web `BathroomFanModalContent.tsx`): Power and Lock tiles, and an off timer. Power is the
/// air (teal) family and Lock the security blue; the timer is a row of six lengths and one button, or a big orange countdown with a
/// thin progress bar and a Clear Timer button.
@MainActor
enum UKBathroomFanSheet {
    static func make(controller: BathroomFanController, accessory: UIView?) -> UKHassModalController {
        let page = UKBathroomFanPage(controller: controller)
        return UKDeviceSheetPage.modal(UKDeviceSheetAccessory.wrap(page, accessory: accessory), title: "\(controller.config.roomTitle) Fan",
                                       width: .form, height: .fitted, key: "BathroomFanSheet")
    }
}

@MainActor
final class UKBathroomFanPage: UKDeviceSheetPage {
    private let controller: BathroomFanController
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
    private var power: UKGlassTileView!
    private var lock: UKGlassTileView!
    private let timer = UIView()
    private var picker: UKFanTimerPicker!
    private var running: UKFanTimerRunning!

    init(controller: BathroomFanController) {
        self.controller = controller
        super.init(maxWidth: 560, subtitle: nil, identifier: "device.sheet.fan")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\(controller.config.roomTitle) Fan"
        navigationItem.title = title
        var environment = UKTileEnvironment()
        environment.surface = .sheet
        power = UKGlassTileView(model: powerModel(), environment: environment)
        lock = UKGlassTileView(model: lockModel(), environment: environment)
        for tile in [power, lock] { tile?.onPerform = { [controller] id in controller.runRail(id) } }
        grid.setItems([UKGridItem(power), UKGridItem(lock)])
        grid.configuration.minCellWidth = UKFont.scaled(132, relativeTo: .subheadline, traits: traitCollection)
        let host = UKGridHost(grid)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKBathroomFanPage, _) in
            page.grid.configuration.minCellWidth = UKFont.scaled(132, relativeTo: .subheadline, traits: page.traitCollection)
            host.remeasure()
        }
        stack.addArrangedSubview(host)
        picker = UKFanTimerPicker(controller: controller)
        running = UKFanTimerRunning(controller: controller)
        stack.addArrangedSubview(UKDeviceSection(title: "Timer", content: [picker, running]))
        bag.observe { [weak self] in
            guard let self else { return }
            power.configure(powerModel(), environment: environment)
            lock.configure(lockModel(), environment: environment)
            let pending = controller.timerPending
            picker.isHidden = pending
            running.isHidden = !pending
            running.setRunning(pending)
        }
    }

    private func powerModel() -> UKGlassTileModel {
        railModel(title: "Power", subtitle: controller.powerStateText, symbol: "power", family: .air, id: "power",
                  isActive: controller.powerOn && controller.powerAvailable, identifier: "fan.power")
    }

    private func lockModel() -> UKGlassTileModel {
        railModel(title: "Lock", subtitle: controller.lockStateText, symbol: controller.locked ? "lock.fill" : "lock.open", family: .securityHome,
                  id: "lock", isActive: controller.locked && controller.lockAvailable, identifier: "fan.lock")
    }

    /// One of the rail's discs as an action tile (`FanRailActions`): the disc carries the state glyph and the body does what it shows.
    private func railModel(title: String, subtitle: String, symbol: String, family: ColorFamily, id: String, isActive: Bool,
                           identifier: String) -> UKGlassTileModel {
        let spec = controller.railSpecs.first { $0.id == id }
        var model = UKGlassTileModel(
            title: title, subtitle: subtitle, symbol: symbol, family: family, isActive: isActive, isUnavailable: spec?.phase == .unavailable,
            behavior: TileBehavior(.action(1), primary: id), actions: spec.map { [TileActionItem($0)] } ?? [], identifier: identifier)
        model.stateCandidates = ["On", "Off", "Off in 00:00:00", "Locked", "Unlocked", "Unavailable"]
        return model
    }
}

/// The idle timer: six lengths, one primary button, one footnote (`FanTimerPicker`).
@MainActor
final class UKFanTimerPicker: UIStackView {
    private let controller: BathroomFanController
    private let bag = UKObservationBag()
    private let lengths = UKFanTimerLengthRow()
    private let start = UKPrimaryButton("") {}

    init(controller: BathroomFanController) {
        self.controller = controller
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.m
        lengths.onSelect = { controller.selectedMinutes = $0 }
        start.action = { controller.startTimer() }
        start.accessibilityIdentifier = "fan.setTimer"
        [lengths, start, UKDeviceText.footnote(BathroomFanControls.timerFootnote)].forEach(addArrangedSubview)
        bag.observe { [weak self] in
            guard let self else { return }
            lengths.show(selection: controller.selectedMinutes)
            start.title = BathroomFanController.startButtonTitle(controller.selectedMinutes)
            start.isEnabled = controller.canStartTimer
        }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The six timer lengths as a segmented row (`FanTimerLengthRow`): 44 pt tall, the chosen one filled with the label's opposite. At
/// accessibility sizes the row wraps to three columns.
@MainActor
final class UKFanTimerLengthRow: UIView {
    var onSelect: (Int) -> Void = { _ in }
    private let minutes = BathroomFanController.timerMinutes
    private var segments: [UKFanTimerSegment] = []
    private let rows = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UKDesignSurface.sheetCell
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        segments = minutes.map { value in UKFanTimerSegment(minutes: value) { [weak self] in self?.onSelect(value) } }
        rows.axis = .vertical
        rows.spacing = 2
        addSubview(rows)
        rows.ukPin(to: self, insets: UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2))
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = "fan.timerLength"
        layoutRows()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKFanTimerLengthRow, _) in view.layoutRows() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func layoutRows() {
        let perRow = traitCollection.isAccessibilitySize ? 3 : segments.count
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

    init(minutes: Int, onTap: @escaping () -> Void) {
        self.minutes = minutes
        super.init(frame: .zero)
        label.text = BathroomFanController.segmentTitle(minutes)
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
        accessibilityLabel = BathroomFanController.durationTitle(minutes)
        accessibilityIdentifier = "fan.timerOption.\(minutes)"
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
    private let controller: BathroomFanController
    private let glyph = UIImageView()
    private let countdown = UILabel()
    private let bar = UKFanTimerProgressBar()
    private let clear: UKTintedCapsuleButton
    private let row = UIStackView()
    private let readout = UIView()
    private lazy var clock = UKEverySecond { [weak self] now in self?.tick(now) }

    init(controller: BathroomFanController) {
        self.controller = controller
        clear = UKTintedCapsuleButton(title: "Clear Timer", tint: UKInk.danger) { controller.cancelTimer() }
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
        readout.accessibilityLabel = "Timer"
        readout.accessibilityIdentifier = "fan.remaining"
        clear.accessibilityIdentifier = "fan.clearTimer"
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
        clock.setRunning(running)
        clear.isEnabled = controller.timerAvailable
    }

    private func tick(_ now: Date) {
        let remaining = controller.remainingSeconds(at: now)
        countdown.text = remaining.map(BathroomFanController.formatRemaining) ?? "Unavailable"
        // Whole minutes: the digits tick every second, the spoken value must not.
        readout.accessibilityValue = remaining.map(BathroomFanController.spokenCountdown) ?? "Unavailable"
        bar.fraction = controller.remainingFraction(at: now) ?? 0
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
