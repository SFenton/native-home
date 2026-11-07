#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The humidifier sheet (`HumidifierSheet`; web `HumidifierModal`): a mist dial with power, and Controls, Schedules and Info tabs in the
/// bottom section bar (direction G, Sheets). Scheduled activities are edited on a pushed page inside the sheet. A measured surface: the
/// dial and every value bind to the controller's own state and nothing redraws per frame.
@MainActor
enum UKHumidifierSheet {
    static func make(config: HumidifierConfig, connection: HassConnection, context: UKContext, initialTab: HumidifierTab = .controls,
                     accessory: UIView? = nil) -> UKHassModalController {
        make(config: config, store: connection.store, caller: connection, storage: connection, context: context, initialTab: initialTab, accessory: accessory)
    }

    static func make(config: HumidifierConfig, store: EntityStore, caller: any HassServiceCalling, storage: any HassScheduleStoring, context: UKContext,
                     initialTab: HumidifierTab = .controls, accessory: UIView? = nil) -> UKHassModalController {
        let controller = HumidifierController(config: config, store: store, caller: caller)
        let schedules = HumidifierScheduleController(config: config, store: store, caller: caller, storage: storage)
        let content = UKHumidifierContent(controller: controller, schedules: schedules, tab: initialTab)
        let bar = content.tabBar.inset()
        var barView: UIView = bar
        if let accessory {
            let stack = UIStackView(arrangedSubviews: [bar, accessory])
            stack.axis = .vertical
            barView = stack
        }
        let root = UKSheetPinnedBarPage(content: content, bar: barView)
        var options = UKHassModalOptions(title: controller.config.title, fitKey: "HumidifierSheet")
        options.closeIdentifier = "device.sheet.done"
        options.height = .full
        options.width = .page
        let modal = UKHassModalController(root: root, options: options)
        content.modal = modal
        content.subtitleTarget = root
        content.scrollersChanged = { [weak root] scrolls in root?.setScrollers(scrolls) }
        content.bindSubtitle()
        return modal
    }
}

@MainActor
final class UKHumidifierContent: UIViewController {
    let controller: HumidifierController
    let schedules: HumidifierScheduleController
    weak var modal: UKHassModalController?
    weak var subtitleTarget: UIViewController?
    /// The hero and tabs columns, named to the sheet's page so the header fade and scroll to top follow them.
    var scrollersChanged: ([UIScrollView]) -> Void = { _ in }
    private(set) var currentTab: HumidifierTab
    private var tabViews: [HumidifierTab: UIView] = [:]
    private let bag = UKObservationBag()
    private(set) lazy var tabBar = UKModalTabBar(
        tabs: HumidifierTab.allCases, label: "Humidifier sections", title: { $0.title }, symbol: { ModalTabSymbols.symbol(for: $0) },
        selection: currentTab, identifier: "humidifier.tabs") { [weak self] in self?.select($0) }

    init(controller: HumidifierController, schedules: HumidifierScheduleController, tab: HumidifierTab) {
        self.controller = controller
        self.schedules = schedules
        self.currentTab = tab
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func bindSubtitle() {
        bag.observe { [weak self] in
            guard let self, let target = subtitleTarget else { return }
            UKSheetSubtitle.apply(controller.subtitle, to: target.navigationItem)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityContainerType = .semanticGroup
        view.accessibilityIdentifier = "device.sheet.humidifier"
        let hero = UKHumidifierHero(controller: controller)
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.xl
        let makers: [HumidifierTab: () -> UIView] = [
            .controls: { [controller] in UKHumidifierControlsTab(controller: controller) },
            .schedules: { [weak self] in
                guard let self else { return UIView() }
                return UKHumidifierSchedulesTab(schedules: schedules, onEdit: { [weak self] rule in
                    self?.schedules.clearError()
                    self?.edit(rule)
                }, onAdd: { [weak self] in
                    guard let self else { return }
                    schedules.clearError()
                    edit(HumidifierScheduleRule.new(mode: controller.mode, mistLevel: controller.mistLevel, targetHumidity: controller.targetHumidity,
                                                    warmLevel: controller.warmLevel, display: controller.displayOn))
                })
            },
            .info: { [controller] in UKHumidifierInfoTab(controller: controller) },
        ]
        for each in HumidifierTab.allCases {
            let tabView = makers[each]!()
            tabView.isHidden = each != currentTab
            tabViews[each] = tabView
            column.addArrangedSubview(tabView)
        }
        let layout = UKHeroTabsViewController(hero: hero, tabs: column, identifierBase: "humidifier.layout") { window, regular, container in
            HumidifierLayout.usesTwoColumns(window: window, isRegularWidth: regular, container: container)
        }
        layout.onScrollViewsChanged = { [weak self] scrolls in self?.scrollersChanged(scrolls) }
        addChild(layout)
        layout.view.frame = view.bounds
        layout.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(layout.view)
        layout.didMove(toParent: self)
        Task { await schedules.load() }
    }

    private func select(_ next: HumidifierTab) {
        guard next != currentTab else { return }
        currentTab = next
        for (each, tabView) in tabViews { tabView.isHidden = each != next }
    }

    private func edit(_ rule: HumidifierScheduleRule) {
        guard let modal else { return }
        let isNew = !schedules.rules.contains { $0.id == rule.id }
        let editor = UKHumidifierActivityEditor(schedules: schedules, rule: rule, isNew: isNew) { [weak modal] in modal?.popViewController(animated: true) }
        editor.title = editor.pageTitle
        editor.navigationItem.title = editor.pageTitle
        modal.push(editor)
    }
}

// MARK: - Hero

/// The mist dial, power button, hint, fault banner and the humidity and temperature readings (`HumidifierHero`).
@MainActor
final class UKHumidifierHero: UIStackView {
    private let controller: HumidifierController
    private let bag = UKObservationBag()
    private let dial: UKThermostatDial
    private lazy var power = UKGreyCapsuleButton(title: "Turn On", systemImage: "power", minWidth: 140) { [controller] in controller.togglePower() }
    private let hint = UILabel.uk(.footnote, ink: UKDesignInk.secondary, alignment: .center)
    private let faultHolder = UIStackView()
    private var faultMessage = ""
    private let humidity: UKDeviceStatusPill
    private let temperature: UKDeviceStatusPill
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4))

    init(controller: HumidifierController) {
        self.controller = controller
        dial = UKThermostatDial(HumidifierDials.mist(controller), size: .modal, surface: .sheet) { targets in
            if case let .single(value) = targets { controller.setLevel(Int(value.rounded())) }
        }
        humidity = UKDeviceStatusPill(item: .init(title: "Current Humidity", icon: "mdi:water-percent", value: controller.humidityText, tone: .neutral))
        temperature = UKDeviceStatusPill(item: .init(title: "Temperature", icon: "mdi:thermometer", value: controller.temperatureText, tone: .neutral))
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.l
        dial.accessibilityIdentifier = "humidifier.mistDial"
        power.accessibilityIdentifier = "humidifier.power"
        faultHolder.axis = .vertical
        faultHolder.isHidden = true
        grid.setItems([UKGridItem(humidity), UKGridItem(temperature)])
        // The power button keeps its own width, centred (`HumidifierHero`'s `.frame(minWidth: 140)`).
        let powerRow = UIStackView(arrangedSubviews: [power])
        powerRow.axis = .vertical
        powerRow.alignment = .center
        [dial, powerRow, hint, faultHolder, UKGridHost(grid)].forEach(addArrangedSubview)
        alignment = .fill
        bag.observe { [weak self] in self?.apply() }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply() {
        dial.configuration = HumidifierDials.mist(controller)
        power.setTitle(controller.powerOn ? "Turn Off" : "Turn On")
        power.isEnabled = controller.canTogglePower
        hint.text = controller.hint
        hint.isHidden = controller.hint == nil
        let message = controller.faultMessage ?? ""
        if message != faultMessage {
            faultMessage = message
            faultHolder.ukSetArranged(message.isEmpty ? [] : [UKInlineAlertView(message)])
            faultHolder.isHidden = message.isEmpty
        }
        humidity.update(.init(title: "Current Humidity", icon: "mdi:water-percent", value: controller.humidityText, tone: .neutral))
        temperature.update(.init(title: "Temperature", icon: "mdi:thermometer", value: controller.temperatureText, tone: .neutral))
    }
}

/// A labelled reading with a tone glyph (`DeviceStatusPill`; web `StatusPill`), on the sheet's cell colour. At accessibility sizes the
/// icon sits above the text, giving the value the pill's full width.
@MainActor
final class UKDeviceStatusPill: UIView, UKGridMeasuring {
    private let icon = UIImageView()
    private let titleLabel = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
    private let valueLabel = UILabel.uk(.subheadline, weight: .semibold, monospacedDigit: true, ink: UKDesignInk.primary)
    private let content = UIStackView()
    private var item: HumidifierController.InfoItem

    init(item: HumidifierController.InfoItem) {
        self.item = item
        super.init(frame: .zero)
        backgroundColor = UKDesignSurface.sheetCell
        layer.cornerRadius = HassTokens.Radius.tile
        layer.cornerCurve = .continuous
        icon.contentMode = .center
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        let texts = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        texts.axis = .vertical
        texts.spacing = 2
        content.addArrangedSubview(icon)
        content.addArrangedSubview(texts)
        addSubview(content)
        content.ukPin(to: self, insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: HassTokens.Spacing.m, bottom: HassTokens.Spacing.m, right: HassTokens.Spacing.m))
        heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        isAccessibilityElement = true
        apply(animated: false)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKDeviceStatusPill, _) in view.apply(animated: false) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ next: HumidifierController.InfoItem) {
        guard next != item else { return }
        item = next
        apply(animated: true)
    }

    private func apply(animated: Bool) {
        let stacked = traitCollection.isAccessibilitySize
        content.axis = stacked ? .vertical : .horizontal
        // Stacked, the texts take the pill's full width (a leading alignment sized them from their own wrap width, 24 pt, a letter a line).
        content.alignment = stacked ? .fill : .center
        icon.contentMode = stacked ? .left : .center
        content.spacing = stacked ? HassTokens.Spacing.s : HassTokens.Spacing.s
        icon.image = UIImage(systemName: SymbolMap.symbol(for: item.icon), withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.body)))
        titleLabel.text = item.title
        valueLabel.text = item.value
        let tint = Self.color(item.tone)
        if animated { UKMotion.stateFade("DeviceStatusPill", view: icon, animated: true) { [icon] in icon.tintColor = tint } } else { icon.tintColor = tint }
        accessibilityLabel = item.title
        accessibilityValue = item.value
        accessibilityIdentifier = "humidifier.info.\(item.title)"
    }

    static func color(_ tone: HumidifierController.InfoItem.Tone) -> UIColor {
        switch tone {
        case .ok: UIColor(ColorFamily.occupancy.glyphToken)
        case .active: UIColor(ColorFamily.water.glyphToken)
        case .warning: UKInk.warning
        case .danger: UKInk.danger
        case .neutral: UKDesignInk.secondary
        case .unavailable: UIColor(HassTokens.RGB.Ink.unavailable)
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        ceil(systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                     withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }
}

// MARK: - Controls

/// Mode, mist presets, target humidity, warm mist, device timer and display (`HumidifierControlsTab`; web `ControlsPanel`).
@MainActor
final class UKHumidifierControlsTab: UIStackView {
    private let controller: HumidifierController
    private let bag = UKObservationBag()
    private let mode: UKSegmentedChoice<HumidifierMode>
    private let mist: UKSegmentedChoice<HumidifierConfig.Preset>
    private let warm: UKSegmentedChoice<HumidifierConfig.Preset>
    private let targetSection: UIStackView
    private let targetAlertHolder = UIStackView()
    private var targetAlertKey = ""
    private let targetDial: UKThermostatDial
    private let targetNote = UIStackView()
    private var targetNoteHigh: Bool?
    private let timerSection: UKDeviceSection
    private let timerStepper: UKControllerStepper
    private let cancelTimer = UIButton(type: .system)
    private let displaySection: UKDeviceSection
    private let displayToggle: UKControllerToggle

    init(controller: HumidifierController) {
        self.controller = controller
        mode = UKSegmentedChoice(label: "Mode", options: HumidifierMode.allCases, title: { $0.title }, selection: controller.mode, identifier: "humidifier.mode") { controller.setMode($0) }
        mist = UKSegmentedChoice(label: "Mist output", options: HumidifierConfig.mistPresets, title: { $0.title }, selection: nil, identifier: "humidifier.mist") { controller.setLevel($0.value) }
        warm = UKSegmentedChoice(label: "Warm mist", options: HumidifierConfig.warmLevels, title: { $0.title }, selection: nil, identifier: "humidifier.warm") { controller.setWarmLevel($0.value) }
        targetDial = UKThermostatDial(HumidifierDials.target(controller), size: .compact, surface: .sheet) { targets in
            if case let .single(value) = targets { controller.setTargetHumidity(value) }
        }
        timerStepper = UKControllerStepper(value: controller.timerMinutes, in: HumidifierController.timerRange, step: HumidifierController.timerStep,
                                           title: "Turn Off In", format: { HumidifierController.formatMinutes($0) }, send: controller.setTimerMinutes)
        displayToggle = UKControllerToggle(isOn: controller.displayOn) { controller.setDisplay($0) }
        targetSection = UIStackView()
        timerSection = UKDeviceSection(title: "Device Timer", footnote: "This one-shot timer turns the humidifier off. Recurring activities live in Schedules.", content: [timerStepper, cancelTimer])
        let displayLine = UKToggleLine(title: "Display", symbol: "display", toggle: displayToggle, identifier: "humidifier.display")
        displaySection = UKDeviceSection(title: "Display", content: [displayLine])
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.xl
        targetDial.accessibilityIdentifier = "humidifier.targetDial"
        timerStepper.accessibilityIdentifier = "humidifier.timer"
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "xmark")
        configuration.imagePadding = HassTokens.Spacing.s
        configuration.baseForegroundColor = UKInk.danger
        configuration.contentInsets = .zero
        cancelTimer.configuration = configuration
        cancelTimer.contentHorizontalAlignment = .leading
        cancelTimer.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        cancelTimer.accessibilityIdentifier = "humidifier.cancelTimer"
        cancelTimer.addAction(UIAction { _ in controller.setTimerMinutes(0) }, for: .touchUpInside)
        let targetContent = UIStackView(arrangedSubviews: [targetAlertHolder, targetDial, targetNote])
        targetContent.axis = .vertical
        targetContent.spacing = HassTokens.Spacing.m
        targetSection.axis = .vertical
        targetSection.addArrangedSubview(UKDeviceSection(title: "Target Humidity", content: [targetContent]))
        targetAlertHolder.axis = .vertical
        targetNote.axis = .vertical
        [UKDeviceSection(title: "Mode", content: [mode]),
         UKDeviceSection(title: "Mist Output", footnote: "Use the dial for exact levels, or choose a quick preset.", content: [mist]),
         targetSection, UKDeviceSection(title: "Warm Mist", content: [warm]), timerSection, displaySection].forEach(addArrangedSubview)
        bag.observe { [weak self] in self?.apply() }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply() {
        let blocked = controller.isBlocked
        mode.selection = controller.mode
        mode.isEnabled = !blocked
        mist.selection = controller.powerOn ? HumidifierConfig.mistPresets.first { $0.value == controller.mistLevel } : nil
        let locked = blocked || controller.isSleep
        mist.isEnabled = !locked
        warm.selection = HumidifierConfig.warmLevels.first { $0.value == controller.warmLevel }
        warm.isEnabled = !locked
        targetSection.isHidden = controller.mode != .targetHumidity
        let alertKey = controller.targetHumidityValid ? "" : "invalid"
        if alertKey != targetAlertKey {
            targetAlertKey = alertKey
            targetAlertHolder.ukSetArranged(alertKey.isEmpty ? [] : [UKInlineAlertView("Choose a target before relying on Auto Humidity.", symbol: "humidity")])
        }
        targetDial.configuration = HumidifierDials.target(controller)
        let high = controller.targetHumidity > 60
        if targetNoteHigh != high {
            targetNoteHigh = high
            targetNote.ukSetArranged([high ? UKInlineAlertView("Targets above 60% can encourage condensation and mold.") : UKDeviceText.footnote("40–50% is the recommended comfort range for most homes.")])
        }
        timerSection.isHidden = !controller.powerOn
        displaySection.isHidden = !controller.powerOn
        timerStepper.show(controller.timerMinutes)
        timerStepper.isUserInteractionEnabled = !blocked
        if let remaining = controller.timerRemaining, remaining > 0 {
            cancelTimer.isHidden = false
            var configuration = cancelTimer.configuration
            configuration?.title = "Cancel Timer · \(HumidifierController.formatSeconds(remaining)) Remaining"
            configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UKFont.preferred(.body)
                return attributes
            }
            cancelTimer.configuration = configuration
        } else {
            cancelTimer.isHidden = true
        }
        displayToggle.show(controller.displayOn)
        displayToggle.isEnabled = !(blocked || controller.isSleep)
    }
}

// MARK: - Info

/// Device state and environment readings (`HumidifierInfoTab`; web `InfoPanel`).
@MainActor
final class UKHumidifierInfoTab: UIStackView {
    private let controller: HumidifierController
    private let bag = UKObservationBag()
    private let deviceGrid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4))
    private let environmentGrid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4))
    private var deviceKey = ""
    private var environmentKey = ""
    private var pills: [String: UKDeviceStatusPill] = [:]
    private let deviceHost: UKGridHost
    private let environmentHost: UKGridHost

    init(controller: HumidifierController) {
        self.controller = controller
        deviceHost = UKGridHost(deviceGrid)
        environmentHost = UKGridHost(environmentGrid)
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.xl
        addArrangedSubview(UKDeviceSection(title: "Device State", content: [deviceHost]))
        addArrangedSubview(UKDeviceSection(title: "Environment", content: [environmentHost]))
        bag.observe { [weak self] in self?.apply() }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (tab: UKHumidifierInfoTab, _) in tab.columns() }
        columns()
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// One column at accessibility sizes so values like "Humidifying" never break mid-word.
    private func columns() {
        let max = traitCollection.isAccessibilitySize ? 1 : 3
        deviceGrid.configuration.maxColumns = max
        environmentGrid.configuration.maxColumns = max
        deviceHost.remeasure()
        environmentHost.remeasure()
    }

    private func apply() {
        refresh(controller.deviceItems, grid: deviceGrid, key: &deviceKey, host: deviceHost, prefix: "d")
        refresh(controller.environmentItems, grid: environmentGrid, key: &environmentKey, host: environmentHost, prefix: "e")
    }

    private func refresh(_ items: [HumidifierController.InfoItem], grid: UKDynamicGridView, key: inout String, host: UKGridHost, prefix: String) {
        let next = items.map(\.title).joined(separator: "|")
        if next != key {
            key = next
            grid.setItems(items.map { item in
                let pill = pills["\(prefix).\(item.title)"] ?? UKDeviceStatusPill(item: item)
                pills["\(prefix).\(item.title)"] = pill
                return UKGridItem(pill)
            })
            host.remeasure()
        }
        for item in items { pills["\(prefix).\(item.title)"]?.update(item) }
    }
}

// MARK: - Schedules

/// The Schedules tab (`HumidifierSchedulesTab`; web `SchedulesPanel`): the scheduling switch, the activities, and Add.
@MainActor
final class UKHumidifierSchedulesTab: UIStackView {
    private let schedules: HumidifierScheduleController
    private let onEdit: (HumidifierScheduleRule) -> Void
    private let bag = UKObservationBag()
    private let toggle: UKActionToggle
    private let errorHolder = UIStackView()
    private var errorKey = ""
    private let list = UIStackView()
    private var listKey = ""
    private let add: UKPrimaryButton
    private let note = UKDeviceText.footnote("Only Home Assistant administrators can edit scheduled activities.")
    private let toggleRow: UKRowView

    init(schedules: HumidifierScheduleController, onEdit: @escaping (HumidifierScheduleRule) -> Void, onAdd: @escaping () -> Void) {
        self.schedules = schedules
        self.onEdit = onEdit
        toggle = UKActionToggle(isOn: schedules.enabled) { schedules.toggleEnabled() }
        add = UKPrimaryButton("Add Scheduled Activity", systemImage: "plus") { onAdd() }
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        // The canonical row on a card of its own: the switch is its accessory, the title and subtitle follow the controller.
        var content = UKRowContent("", symbol: "calendar", glyph: UKDesignInk.primary, style: .form)
        content.titleWeight = .semibold
        content.horizontalPadding = HassTokens.Spacing.m
        content.verticalPadding = HassTokens.Spacing.m
        toggleRow = UKRowView(content, accessory: toggle, surface: .sheet)
        toggleRow.drawsCard = true
        toggleRow.cardColor = UKDesignSurface.sheetCell
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.xl
        toggle.accessibilityIdentifier = "humidifier.scheduling"
        toggle.accessibilityLabel = "Scheduling"
        errorHolder.axis = .vertical
        list.axis = .vertical
        list.spacing = HassTokens.Spacing.s
        add.accessibilityIdentifier = "humidifier.addActivity"
        let switchColumn = UIStackView(arrangedSubviews: [toggleRow, UKDeviceText.footnote("Schedules run on Home Assistant. Manual changes last until the next activity or restart/reconnect recovery.")])
        switchColumn.axis = .vertical
        switchColumn.spacing = HassTokens.Spacing.s
        [switchColumn, errorHolder, UKDeviceSection(title: "Activities", content: [list]), add, note].forEach(addArrangedSubview)
        bag.observe { [weak self] in self?.apply() }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply() {
        var content = toggleRow.rowContent
        content.title = schedules.toggleTitle
        content.subtitle = schedules.toggleSubtitle
        toggleRow.update(content, accessory: toggle)
        toggle.show(schedules.enabled)
        toggle.isEnabled = !schedules.toggleDisabled
        let error = schedules.error ?? ""
        if error != errorKey {
            errorKey = error
            errorHolder.ukSetArranged(error.isEmpty ? [] : [UKInlineAlertView(error)])
        }
        add.isEnabled = !(schedules.loading || schedules.saving || !schedules.ready)
        add.isHidden = !schedules.canEdit
        note.isHidden = schedules.canEdit
        let key = "\(schedules.loading)|\(schedules.ready)|\(schedules.canEdit)|\(schedules.saving)|" + schedules.rules.map {
            "\($0.id)\($0.label)\($0.days)\($0.start)\($0.end)\(HumidifierSchedule.profileSummary($0))\(schedules.isRunning($0))"
        }.joined()
        guard key != listKey else { return }
        listKey = key
        if schedules.loading && !schedules.ready {
            let spinner = UKArcSpinnerView(.compact, label: "Loading scheduled activities…")
            spinner.color = UKDesignInk.secondary
            list.ukSetArranged([spinner])
        } else if schedules.rules.isEmpty {
            list.ukSetArranged([UKDeviceText.subheadline("No activities yet. Add morning, evening, or overnight profiles.")])
        } else {
            list.ukSetArranged(schedules.rules.map(row))
        }
    }

    private func row(_ rule: HumidifierScheduleRule) -> UIView {
        let running = schedules.isRunning(rule)
        let title = UILabel.uk(.body, weight: .semibold, ink: UKDesignInk.primary)
        title.text = rule.label
        let when = UKDeviceText.subheadline("\(HumidifierSchedule.formatDays(rule.days)) · \(HumidifierSchedule.formatTimes(start: rule.start, end: rule.end))")
        let profile = UKDeviceText.footnote(HumidifierSchedule.profileSummary(rule) + (running ? " • Active now" : ""))
        profile.textColor = running ? UIColor(ColorFamily.water.glyphToken) : UKDesignInk.secondary
        let texts = UIStackView(arrangedSubviews: [title, when, profile])
        texts.axis = .vertical
        texts.spacing = 2
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.footnoteEmphasis())))
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let content = UIStackView(arrangedSubviews: [texts, chevron])
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = HassTokens.Spacing.m
        content.isUserInteractionEnabled = false
        let button = UIControl()
        button.backgroundColor = UKDesignSurface.sheetCell
        button.layer.cornerRadius = HassTokens.Radius.tile
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = running ? 1 : 0
        button.layer.borderColor = UIColor(ColorFamily.water.glyphToken).cgColor
        button.addSubview(content)
        content.ukPin(to: button, insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: HassTokens.Spacing.m, bottom: HassTokens.Spacing.m, right: HassTokens.Spacing.m))
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        button.isEnabled = schedules.canEdit && !schedules.saving
        button.addAction(UIAction { [onEdit] _ in onEdit(rule) }, for: .touchUpInside)
        button.isAccessibilityElement = true
        button.accessibilityLabel = [rule.label, "\(HumidifierSchedule.formatDays(rule.days)) · \(HumidifierSchedule.formatTimes(start: rule.start, end: rule.end))",
                                     HumidifierSchedule.profileSummary(rule) + (running ? " • Active now" : "")].joined(separator: ", ")
        button.accessibilityTraits = button.isEnabled ? .button : [.button, .notEnabled]
        button.accessibilityIdentifier = "humidifier.activity.\(rule.label)"
        return button
    }
}

// MARK: - Activity editor

/// The pushed editor for one activity (`HumidifierActivityEditor`; web `ScheduleEditor` + `ScheduleDetailFooter`).
@MainActor
final class UKHumidifierActivityEditor: UKSheetColumnViewController {
    private let schedules: HumidifierScheduleController
    private let isNew: Bool
    private let onClose: () -> Void
    private var draft: HumidifierScheduleRule
    private let initial: HumidifierScheduleRule
    private var conflict: ScheduleConflict? { schedules.conflict(for: draft) }
    private var hasEdits: Bool { draft != initial }
    private var canSave: Bool { draft.isComplete && conflict == nil && !schedules.saving }
    private var nameField: UKOutlinedTextField!
    private var days: UKWeekdayPicker!
    private var modeButton: UIButton!
    private let profile = UIStackView()
    private var mistDial: UKThermostatDial!
    private var targetSection: UIView!
    private var targetDial: UKThermostatDial!
    private var warm: UKSegmentedChoice<HumidifierConfig.Preset>!
    private var displayToggle: UISwitch!
    private let alertHolder = UIStackView()
    private let delete = UKFilledButton(title: "Delete Activity", systemImage: "trash", fill: UKDeviceStyle.danger) {}
    private var saveItem: UIBarButtonItem!
    private var start: UKDatePickerLine!
    private var end: UKDatePickerLine!

    var pageTitle: String { isNew ? "Add Activity" : draft.label }

    init(schedules: HumidifierScheduleController, rule: HumidifierScheduleRule, isNew: Bool, onClose: @escaping () -> Void) {
        self.schedules = schedules
        self.isNew = isNew
        self.onClose = onClose
        draft = rule
        initial = rule
        super.init(maxWidth: 640)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        UKHassModal.hidesSystemBack(self)
        nameField = UKOutlinedTextField(placeholder: "Name", text: draft.label, limit: 40, identifier: "activity.name")
        nameField.onChange = { [weak self] in self?.draft.label = $0; self?.edited() }
        days = UKWeekdayPicker(title: nil, days: draft.days, identifier: "activity.day") { [weak self] in self?.draft.days = $0; self?.edited() }
        start = UKDatePickerLine(title: "Start", mode: .time, date: ActivityTime.date(from: draft.start), identifier: "activity.start") { [weak self] in
            self?.draft.start = ActivityTime.string(from: $0)
            self?.edited()
        }
        end = UKDatePickerLine(title: "End", mode: .time, date: ActivityTime.date(from: draft.end), identifier: "activity.end") { [weak self] in
            self?.draft.end = ActivityTime.string(from: $0)
            self?.edited()
        }
        modeButton = UIButton(type: .system)
        modeButton.showsMenuAsPrimaryAction = true
        modeButton.contentHorizontalAlignment = .leading
        modeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        modeButton.accessibilityIdentifier = "activity.mode"
        modeButton.accessibilityLabel = "Mode"

        mistDial = UKThermostatDial(HumidifierDials.scheduledMist(draft.mistLevel), size: .compact, surface: .sheet) { [weak self] targets in
            if case let .single(value) = targets { self?.draft.mistLevel = Int(value.rounded()); self?.edited() }
        }
        mistDial.accessibilityIdentifier = "activity.mistDial"
        targetDial = UKThermostatDial(HumidifierDials.scheduledTarget(draft.targetHumidity), size: .compact, surface: .sheet) { [weak self] targets in
            if case let .single(value) = targets { self?.draft.targetHumidity = Int(value.rounded()); self?.edited() }
        }
        targetDial.accessibilityIdentifier = "activity.targetDial"
        targetSection = UKDeviceSection(title: "Target Humidity", content: [targetDial])
        let dials = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 260, maxColumns: 2, fill: .none))
        dials.setItems([UKGridItem(UKDeviceSection(title: "Mist Level", content: [mistDial])), UKGridItem(targetSection)])
        warm = UKSegmentedChoice(label: "Warm mist", options: HumidifierConfig.warmLevels, title: { $0.title },
                                 selection: HumidifierConfig.warmLevels.first { $0.value == draft.warmLevel }, identifier: "activity.warm") { [weak self] in
            self?.draft.warmLevel = $0.value
            self?.edited()
        }
        displayToggle = UISwitch()
        displayToggle.isOn = draft.display
        displayToggle.addAction(UIAction { [weak self] _ in self?.draft.display = self?.displayToggle.isOn ?? false; self?.edited() }, for: .valueChanged)
        let displayLine = UKToggleLine(title: "Display", symbol: "display", toggle: displayToggle, identifier: "activity.display")
        profile.axis = .vertical
        profile.spacing = HassTokens.Spacing.xl
        [UKGridHost(dials), UKDeviceSection(title: "Warm Mist", content: [warm]), UKDeviceSection(title: "Display", content: [displayLine])].forEach(profile.addArrangedSubview)
        alertHolder.axis = .vertical
        alertHolder.spacing = HassTokens.Spacing.m
        delete.accessibilityIdentifier = "activity.delete"
        delete.addAction(UIAction { [weak self] _ in self?.confirmDelete() }, for: .touchUpInside)
        delete.isHidden = isNew
        [UKDeviceSection(title: "Name", content: [nameField]), UKDeviceSection(title: "Days", content: [days]),
         UKDeviceSection(title: "Time", content: [start, end]), UKDeviceSection(title: "Mode", content: [modeButton]),
         profile, alertHolder, delete].forEach(stack.addArrangedSubview)
        saveItem = UIBarButtonItem(title: "Save", primaryAction: UIAction { [weak self] _ in self?.saveTapped() })
        saveItem.accessibilityIdentifier = "activity.save"
        navigationItem.rightBarButtonItem = saveItem
        bag.observe { [weak self] in self?.apply() }
    }

    private func edited() {
        // Sleep runs its own profile, which keeps the display off.
        if draft.mode == .sleep, draft.display { draft.display = false; displayToggle.isOn = false }
        apply()
    }

    private func apply() {
        modeButton.configuration = {
            var configuration = UIButton.Configuration.plain()
            configuration.title = draft.mode.title
            configuration.image = UIImage(systemName: "chevron.up.chevron.down")
            configuration.imagePlacement = .trailing
            configuration.imagePadding = HassTokens.Spacing.s
            configuration.contentInsets = .zero
            return configuration
        }()
        modeButton.accessibilityValue = draft.mode.title
        modeButton.menu = UIMenu(children: HumidifierMode.allCases.map { mode in
            UIAction(title: mode.title, state: mode == draft.mode ? .on : .off) { [weak self] _ in self?.draft.mode = mode; self?.edited() }
        })
        profile.isHidden = draft.mode == .sleep
        targetSection.isHidden = draft.mode != .targetHumidity
        mistDial.configuration = HumidifierDials.scheduledMist(draft.mistLevel)
        targetDial.configuration = HumidifierDials.scheduledTarget(draft.targetHumidity)
        warm.selection = HumidifierConfig.warmLevels.first { $0.value == draft.warmLevel }
        displayToggle.isEnabled = true
        var alerts: [UIView] = []
        if draft.days.isEmpty { alerts.append(UKInlineAlertView("Select at least one day.")) }
        if !HumidifierSchedule.isValidTime(draft.start) || !HumidifierSchedule.isValidTime(draft.end) { alerts.append(UKInlineAlertView("Choose valid start and end times.")) }
        if let message = conflict?.message ?? schedules.error { alerts.append(UKInlineAlertView(message)) }
        alertHolder.ukSetArranged(alerts)
        delete.isEnabled = !schedules.saving
        saveItem.title = schedules.saving ? "Saving…" : "Save"
        saveItem.isEnabled = canSave
        navigationItem.title = pageTitle
        navigationItem.leftBarButtonItem = UKSheetItems.back(identifier: "activity.back", hasChanges: hasEdits, isEnabled: !schedules.saving, presenter: self) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        UKDiscardGuard.apply(to: self, hasChanges: hasEdits, isBusy: schedules.saving)
    }

    private func saveTapped() {
        Task { [weak self] in
            guard let self else { return }
            if await schedules.save(draft) { onClose() }
        }
    }

    private func confirmDelete() {
        UKAlerts.confirmationDialog(AlertCopy.delete("Activity", named: draft.label), from: self, source: .view(delete)) { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                if await schedules.delete(draft.id) { onClose() }
            }
        }
    }
}
#endif
