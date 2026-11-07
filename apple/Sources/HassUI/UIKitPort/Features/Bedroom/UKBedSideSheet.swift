#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// One bed side's sheet (`BedSideSheet`; pattern `.agents/patterns/bedroom-devices.md`; web `EightSleepBedModal` in SleepyPod climate
/// mode). The hero (level dial, power, hint and any ringing alarm) sits above the tab's content, or beside it where a split is allowed.
/// The tabs are the bottom section bar; alarm day pages and the alarm editor push inside the sheet.
@MainActor
enum UKBedSideSheet {
    /// - Parameter accessory: Shown under the tab bar (the gallery's last-call line).
    static func make(devices: BedroomDevices, side: BedSide, initialTab: BedSideSheet.Tab = .temperature, context: UKContext,
                     accessory: UIView? = nil) -> UKHassModalController {
        let sheetContext = context.with { $0.surface = .sheet }
        let content = UKBedSideContent(devices: devices, side: side, context: sheetContext, tab: initialTab)
        let bar = content.tabBar.inset()
        var barView: UIView = bar
        if let accessory {
            let stack = UIStackView(arrangedSubviews: [bar, accessory])
            stack.axis = .vertical
            barView = stack
        }
        let root = UKSheetPinnedBarPage(content: content, bar: barView)
        var options = UKHassModalOptions(title: devices.bed(side).title, fitKey: "BedSideSheet")
        options.height = .full
        options.width = .page
        let modal = UKHassModalController(root: root, options: options)
        content.modal = modal
        content.titleTarget = root
        content.scrollersChanged = { [weak root] scrolls in root?.setScrollers(scrolls) }
        content.bindTitle()
        return modal
    }
}

/// The sheet's page: hero and tabs, and the pushes.
@MainActor
final class UKBedSideContent: UIViewController {
    let devices: BedroomDevices
    let side: BedSide
    let context: UKContext
    weak var modal: UKHassModalController?
    weak var titleTarget: UIViewController?
    /// The hero and tabs columns, named to the sheet's page so the header fade and scroll to top follow them.
    var scrollersChanged: ([UIScrollView]) -> Void = { _ in }
    private(set) var currentTab: BedSideSheet.Tab
    private let bag = UKObservationBag()
    private var controller: BedSideController { devices.bed(side) }
    private var layout: UKHeroTabsViewController!
    private var tabViews: [BedSideSheet.Tab: UIView] = [:]
    private(set) lazy var tabBar = UKModalTabBar(
        tabs: BedSideSheet.Tab.allCases, label: "\(controller.config.title) sections", title: { $0.title },
        symbol: { ModalTabSymbols.symbol(for: $0) }, selection: currentTab, identifier: "bed.tabs") { [weak self] in self?.select($0) }

    init(devices: BedroomDevices, side: BedSide, context: UKContext, tab: BedSideSheet.Tab) {
        self.devices = devices
        self.side = side
        self.context = context
        self.currentTab = tab
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The sheet's title follows the scope ("Alex's Bed · Whole Bed").
    func bindTitle() {
        bag.observe { [weak self] in
            guard let self else { return }
            let title = controller.title
            titleTarget?.navigationItem.title = title
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let hero = UKBedHeroView(controller: controller, context: context, devices: devices) { [weak self] in self }
        let tabsColumn = UIStackView()
        tabsColumn.axis = .vertical
        tabsColumn.spacing = HassTokens.Spacing.xl
        for each in BedSideSheet.Tab.allCases {
            let view = makeTab(each)
            view.isHidden = each != currentTab
            tabViews[each] = view
            tabsColumn.addArrangedSubview(view)
        }
        layout = UKHeroTabsViewController(hero: hero, tabs: tabsColumn, identifierBase: "bed.layout") { window, regular, container in
            MediaRemoteLayout.usesTwoColumns(window: window, isRegularWidth: regular, container: container)
        }
        layout.onScrollViewsChanged = { [weak self] scrolls in self?.scrollersChanged(scrolls) }
        addChild(layout)
        layout.view.frame = view.bounds
        layout.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(layout.view)
        layout.didMove(toParent: self)
    }

    private func select(_ next: BedSideSheet.Tab) {
        guard next != currentTab else { return }
        currentTab = next
        for (each, view) in tabViews { view.isHidden = each != next }
    }

    private func makeTab(_ tab: BedSideSheet.Tab) -> UIView {
        switch tab {
        case .temperature: UKBedScheduleTab(controller: controller)
        case .specialModes: UKBedSpecialModesTab(controller: controller)
        case .alarms: UKBedAlarmsTab(controller: controller) { [weak self] route in self?.push(route) }
        case .status: UKBedStatusTab(controller: controller)
        }
    }

    // MARK: Pushes

    func push(_ route: BedSideSheet.Route) {
        guard let modal else { return }
        let page: UIViewController
        let title: String
        switch route {
        case let .day(day):
            page = UKBedAlarmDayPage(devices: devices, side: side, day: day) { [weak self] in self?.push($0) }
            title = "\(day.label) Alarms"
        case let .add(day):
            let editor = UKBedAlarmEditor(devices: devices, side: side, alarmId: nil, lockedDay: day) { [weak modal] in modal?.popToRootViewController(animated: true) }
            page = editor
            title = editor.pageTitle
        case let .edit(id):
            let editor = UKBedAlarmEditor(devices: devices, side: side, alarmId: id, lockedDay: nil) { [weak modal] in modal?.popToRootViewController(animated: true) }
            page = editor
            title = editor.pageTitle
        }
        page.title = title
        page.navigationItem.title = title
        modal.push(page)
    }
}

// MARK: - Hero

/// The level dial, power, hint and any ringing alarm.
@MainActor
final class UKBedHeroView: UIStackView {
    private let controller: BedSideController
    private let bag = UKObservationBag()
    private let presenter: () -> UIViewController?
    private let subtitle = UILabel.uk(.subheadline, ink: UKDesignInk.secondary, alignment: .center)
    private let unavailable = UKInlineAlertView("Bed controls are unavailable. No changes can be made until the active bed connection recovers.")
    private let noticeHolder = UIStackView()
    private let errorHolder = UIStackView()
    private let dial: UKThermostatDial
    private lazy var power = UKGreyCapsuleButton(title: "Turn On", systemImage: "power", minWidth: 160) { [weak self] in self?.powerTapped() }
    private let hint = UILabel.uk(.footnote, ink: UKDesignInk.secondary, alignment: .center)
    private let alarm: UKActiveBedAlarmView
    private var noticeSignature = ""
    private var errorSignature = ""
    private var showingScope = false

    init(controller: BedSideController, context: UKContext, devices: BedroomDevices, presenter: @escaping () -> UIViewController?) {
        self.controller = controller
        self.presenter = presenter
        dial = UKThermostatDial(BedDial.configuration(controller), size: .modal, surface: .sheet) { targets in
            if case let .single(value) = targets { controller.setTarget(value) }
        }
        alarm = UKActiveBedAlarmView(controller: controller)
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.l
        alignment = .fill
        subtitle.accessibilityIdentifier = "bed.subtitle"
        dial.accessibilityIdentifier = "bed.dial"
        power.accessibilityIdentifier = "bed.power"
        hint.accessibilityIdentifier = "bed.hint"
        for holder in [noticeHolder, errorHolder] { holder.axis = .vertical; holder.isHidden = true }
        // The power capsule keeps its own width, centred (a required hugging priority on a filling arranged view shrinks the whole column).
        let powerRow = UIStackView(arrangedSubviews: [power])
        powerRow.axis = .vertical
        powerRow.alignment = .center
        [subtitle, unavailable, noticeHolder, errorHolder, dial, powerRow, hint, alarm].forEach(addArrangedSubview)
        setCustomSpacing(HassTokens.Spacing.l, after: dial)
        bag.observe { [weak self] in self?.apply() }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply() {
        subtitle.text = controller.subtitle
        unavailable.isHidden = controller.sideAvailable
        let notice = controller.scope.notice
        let noticeKey = notice.map { "\($0.title)|\($0.message)|\(controller.scope.controlsWholeBed)" } ?? ""
        if noticeKey != noticeSignature {
            noticeSignature = noticeKey
            let box = notice.map { UKInfoBoxView(title: $0.title, message: $0.message, tone: controller.scope.controlsWholeBed ? .success : .neutral) }
            box?.accessibilityIdentifier = "bed.soloTrip"
            noticeHolder.ukSetArranged(box.map { [$0] } ?? [])
            noticeHolder.isHidden = box == nil
        }
        let error = controller.commandError ?? ""
        if error != errorSignature {
            errorSignature = error
            errorHolder.ukSetArranged(error.isEmpty ? [] : [UKInlineAlertView(error, severity: .error)])
            errorHolder.isHidden = error.isEmpty
        }
        dial.configuration = BedDial.configuration(controller)
        // The traveler's side is read-only: the hint below says so, and a disabled button would repeat it at 1.5:1.
        power.isHidden = !controller.scope.interactive
        power.superview?.isHidden = power.isHidden
        power.setTitle(controller.powerTitle)
        power.isEnabled = controller.canTogglePower
        hint.text = controller.hint
        if controller.scopePrompt != nil, !showingScope { presentScopePrompt() }
    }

    private func powerTapped() {
        guard controller.isOn else { controller.setPower(on: true); return }
        let sheet = UIAlertController(title: "Turn off \(controller.config.title)?", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Turn Off", style: .destructive) { [controller] _ in controller.setPower(on: false) })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        UKPopoverSource.view(power).attach(to: sheet.popoverPresentationController, fallback: power)
        present(sheet)
    }

    /// A two-choice question is a dialog on the dial that asked it, not a second sheet over this one (HIG: Sheets, "display one sheet
    /// at a time"; owner, 2026-10-24, `sheet-stacking-close`).
    private func presentScopePrompt() {
        guard let request = controller.scopePrompt else { return }
        showingScope = true
        let sheet = UIAlertController(title: BedScopeCopy.title, message: BedScopeCopy.message(bed: controller.config.title, request: request),
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: BedScopeCopy.tonight, style: .default) { [weak self, controller] _ in
            self?.showingScope = false
            controller.chooseScope(.tonight)
        })
        sheet.addAction(UIAlertAction(title: BedScopeCopy.allNights, style: .default) { [weak self, controller] _ in
            self?.showingScope = false
            controller.chooseScope(.allNights)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self, controller] _ in
            self?.showingScope = false
            controller.dismissScope()
        })
        UKPopoverSource.view(dial).attach(to: sheet.popoverPresentationController, fallback: dial)
        present(sheet, identifiers: [BedScopeCopy.tonight: "bed.scope.tonight", BedScopeCopy.allNights: "bed.scope.allNights", "Cancel": "bed.scope.cancel"])
    }

    private func present(_ alert: UIAlertController, identifiers: [String: String] = [:]) {
        guard let host = presenter() else { return }
        (host.presentedViewController ?? host).ukPresent(alert, identifiers: identifiers)
    }
}

// MARK: - Active alarm

/// "Alarm Active" with Snooze and Stop while the side's alarm rings or is snoozed (`ActiveBedAlarmSection`; web
/// `SleepypodActiveAlarmSection`). Snooze is a grey capsule and Stop the primary button.
@MainActor
final class UKActiveBedAlarmView: UIView {
    private let controller: BedSideController
    private let bag = UKObservationBag()
    private lazy var clock = UKEverySecond { [weak self] now in self?.tick(now) }
    private let header = UIStackView()
    private let detailLabel = UKDeviceText.subheadline("")
    private let snooze = UKGreyCapsuleButton(title: "Snooze", systemImage: "zzz", action: {})
    private let stop: UKPrimaryButton
    private let card: UKSheetCardView
    private var shown: Bool?

    init(controller: BedSideController) {
        self.controller = controller
        stop = UKPrimaryButton("Stop Alarm", systemImage: "stop.circle") { controller.stopAlarm() }
        let title = UILabel.uk(.title3, weight: .bold, ink: UKDesignInk.primary)
        title.text = "Alarm Active"
        title.accessibilityTraits = .header
        header.axis = .vertical
        header.spacing = HassTokens.Spacing.xs
        header.addArrangedSubview(title)
        header.addArrangedSubview(detailLabel)
        let buttons = UIStackView(arrangedSubviews: [snooze, stop])
        buttons.axis = .horizontal
        buttons.spacing = HassTokens.Spacing.m
        buttons.distribution = .fillEqually
        let column = UIStackView(arrangedSubviews: [header, buttons])
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.m
        card = UKSheetCardView(content: column)
        super.init(frame: .zero)
        snooze.addAction(UIAction { [controller] _ in controller.snoozeAlarm() }, for: .touchUpInside)
        snooze.accessibilityIdentifier = "bed.alarm.snooze"
        stop.accessibilityIdentifier = "bed.alarm.stop"
        card.isAccessibilityElement = false
        card.accessibilityContainerType = .semanticGroup
        card.accessibilityIdentifier = "bed.alarm.active"
        addSubview(card)
        card.ukPin(to: self)
        bag.observe { [weak self] in self?.apply() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply() {
        let state = controller.alarmState
        detailLabel.text = state == .ringing ? "Ringing" : "Snoozing"
        snooze.isEnabled = !(controller.alarmControlsReadOnly || state == .snoozed)
        stop.isEnabled = !controller.alarmControlsReadOnly
        clock.setRunning(state == .snoozed)
        if !state.isActive { snooze.setSubtitle(nil) }
        // An alarm starting settles the layout below it instead of cutting it (motion.md §6, a live change that moves layout).
        let show = state.isActive
        if shown != show {
            let first = shown == nil
            shown = show
            let change = { self.isHidden = !show; self.superview?.layoutIfNeeded() }
            if first || window == nil { isHidden = !show } else { UKMotion.animate(.standard) { change() } }
        }
    }

    private func tick(_ now: Date) {
        guard controller.alarmState == .snoozed else { return }
        snooze.setSubtitle(controller.snoozeRemaining(now: now))
    }
}

// MARK: - Tabs

/// Bedtime, Asleep and Dawn level steppers (`BedScheduleTab`; web `EightSleepScheduleTemperatureControl`).
@MainActor
final class UKBedScheduleTab: UIStackView {
    init(controller: BedSideController) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.m
        addArrangedSubview(UKBedroomSectionHeader(title: "Sleep Schedule", detail: "Recurring levels for each stage of the night."))
        for phase in SchedulePhase.allCases { addArrangedSubview(UKStageRowView(controller: controller, phase: phase)) }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// One stage row: an adjustable element named "<Stage> level", with its two step buttons.
@MainActor
final class UKStageRowView: UIView {
    private let controller: BedSideController
    private let phase: SchedulePhase
    private let row: UKBedroomRow
    private let down: UIButton
    private let up: UIButton
    private var element: UKAdjustableElement!
    private let bag = UKObservationBag()

    init(controller: BedSideController, phase: SchedulePhase) {
        self.controller = controller
        self.phase = phase
        down = Self.stepButton("minus", label: "Lower \(phase.label)", id: "bed.stage.\(phase.rawValue).down")
        up = Self.stepButton("plus", label: "Raise \(phase.label)", id: "bed.stage.\(phase.rawValue).up")
        let steps = UIStackView(arrangedSubviews: [down, up])
        steps.axis = .horizontal
        steps.spacing = HassTokens.Spacing.s
        row = UKBedroomRow(symbol: phase.symbol, title: phase.label, lines: [""], trailing: steps)
        super.init(frame: .zero)
        addSubview(row)
        row.ukPin(to: self)
        element = UKAdjustableElement(accessibilityContainer: self)
        self.element.accessibilityLabel = "\(phase.label) level"
        self.element.accessibilityIdentifier = "bed.stage.\(phase.rawValue)"
        self.element.accessibilityTraits = .adjustable
        self.element.increment = { [weak self] in self?.step(up: true) }
        self.element.decrement = { [weak self] in self?.step(up: false) }
        down.addAction(UIAction { [weak self] _ in self?.step(up: false) }, for: .touchUpInside)
        up.addAction(UIAction { [weak self] _ in self?.step(up: true) }, for: .touchUpInside)
        isAccessibilityElement = false
        bag.observe { [weak self] in self?.apply() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func stepButton(_ symbol: String, label: String, id: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.bodyEmphasis())), for: .normal)
        button.tintColor = UKDesignInk.primary
        button.backgroundColor = UKDesignSurface.separator
        button.layer.cornerRadius = HassTokens.minTarget / 2
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: HassTokens.minTarget),
            button.heightAnchor.constraint(equalToConstant: HassTokens.minTarget),
        ])
        button.accessibilityLabel = label
        button.accessibilityIdentifier = id
        return button
    }

    private func step(up: Bool) {
        guard controller.canStepStage(phase) else { return }
        controller.stepStage(phase, up: up)
    }

    private func apply() {
        let level = controller.stageLevel(phase)
        let enabled = controller.canStepStage(phase)
        let range = controller.stageRange(phase).range
        let text = controller.activePhase == phase ? "\(BedLevel.format(level)) · Now" : BedLevel.format(level)
        row.setLines([text])
        down.isEnabled = enabled && (level ?? range.lowerBound) > range.lowerBound
        up.isEnabled = enabled && (level ?? range.upperBound) < range.upperBound
        down.alpha = down.isEnabled ? 1 : 0.4
        up.alpha = up.isEnabled ? 1 : 0.4
        element.accessibilityValue = BedLevel.format(level)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshElementFrame()
    }

    /// The adjustable element covers the row up to the step buttons, which are elements of their own (an element over them would
    /// take their taps from assistive technologies). Read again whenever the elements are asked for: a frame set only from a
    /// layout pass stayed one point wide in a wide form sheet (the iPad audit's "Hit area is too small", 2026-11-02).
    private func refreshElementFrame() {
        row.layoutIfNeeded()
        let steps = down.superview.map { $0.convert($0.bounds, to: self) } ?? .zero
        let width = steps.minX > 1 ? steps.minX : bounds.width
        element.accessibilityFrameInContainerSpace = CGRect(x: 0, y: 0, width: max(width, HassTokens.minTarget), height: max(bounds.height, HassTokens.minTarget))
    }

    override var accessibilityElements: [Any]? {
        get {
            refreshElementFrame()
            return [element as Any, down, up]
        }
        set {}
    }
}

/// Hot Flash Mode (`BedSpecialModesTab`; web `EightSleepHotFlashControl`) as an action tile (*text, disc*, `HotFlashActions`): a snowflake disc
/// starts it and becomes a stop disc while it runs, and the body does what the disc shows, so a tap on the running tile cancels. The countdown
/// is the tile's state line; the separate cancel button is gone.
@MainActor
final class UKBedSpecialModesTab: UIStackView {
    private let controller: BedSideController
    private let bag = UKObservationBag()
    private let tile: UKGlassTileView
    private var now = Date()
    private lazy var clock = UKEverySecond { [weak self] now in
        self?.now = now
        self?.apply()
    }

    init(controller: BedSideController) {
        self.controller = controller
        tile = UKGlassTileView(model: Self.model(controller, now: Date()), environment: Self.environment)
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.m
        addArrangedSubview(UKBedroomSectionHeader(title: "Special Modes", detail: "Activating hot flash mode will set the bed to -10 for fifteen minutes."))
        addArrangedSubview(UKGridHost(tile))
        tile.onPerform = { [controller] _ in
            if controller.hotFlashActive { controller.cancelHotFlash() } else { controller.startHotFlash() }
        }
        bag.observe { [weak self] in self?.apply() }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static var environment: UKTileEnvironment {
        var environment = UKTileEnvironment()
        environment.surface = .sheet
        return environment
    }

    private static func model(_ controller: BedSideController, now: Date) -> UKGlassTileModel {
        let provider = HotFlashActions(controller.config, isReadOnly: controller.scope.readOnly)
        let shown = EntityState(entityId: controller.config.hotFlashActiveEntityId,
                                state: controller.hotFlashAvailable ? (controller.hotFlashActive ? "on" : "off") : "unavailable")
        var model = UKGlassTileModel(
            title: "Hot Flash Mode", subtitle: subtitle(controller, now: now), symbol: "snowflake", family: .cooling, isActive: controller.hotFlashActive,
            isUnavailable: !controller.hotFlashAvailable || controller.scope.readOnly,
            behavior: TileBehavior(.action(1), primary: HotFlashActions.actionId), actions: provider.actions(for: shown).items, identifier: "bed.hotFlash")
        model.stateCandidates = provider.stateTextCandidates
        return model
    }

    /// "Inactive", then "Cooling Bed" or the time remaining while it runs; "Unavailable" when the helper cannot be reached.
    private static func subtitle(_ controller: BedSideController, now: Date) -> String {
        guard controller.hotFlashAvailable else { return "Unavailable" }
        guard controller.hotFlashActive else { return "Inactive" }
        return controller.hotFlashCountdown(now: now).map { "\($0) Remaining" } ?? "Cooling Bed"
    }

    private func apply() {
        tile.configure(Self.model(controller, now: controller.hotFlashActive ? now : Date()), environment: Self.environment)
        clock.setRunning(controller.hotFlashActive)
    }
}

/// Alarms grouped by day (`BedAlarmsTab`; web `EightSleepAlarmList`).
@MainActor
final class UKBedAlarmsTab: UIStackView {
    private let controller: BedSideController
    private let push: (BedSideSheet.Route) -> Void
    private let list = UIStackView()
    private let add: UKPrimaryButton
    private let bag = UKObservationBag()
    private var signature = ""

    init(controller: BedSideController, push: @escaping (BedSideSheet.Route) -> Void) {
        self.controller = controller
        self.push = push
        add = UKPrimaryButton("Add Alarm", systemImage: "plus") { push(.add(nil)) }
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.m
        list.axis = .vertical
        list.spacing = HassTokens.Spacing.m
        add.accessibilityIdentifier = "bed.alarms.add"
        addArrangedSubview(UKBedroomSectionHeader(title: "Alarms"))
        addArrangedSubview(list)
        addArrangedSubview(add)
        bag.observe { [weak self] in self?.apply() }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply() {
        add.isEnabled = controller.alarmsEditable
        let groups = controller.alarmGroups
        let key = "\(controller.alarmsAvailable)|\(controller.alarmsEditable)|" + groups.map { "\($0.day.rawValue):\($0.alarms.map { "\($0.id)\($0.time)\($0.enabled)" })" }.joined()
        guard key != signature else { return }
        signature = key
        var views: [UIView] = []
        if !controller.alarmsAvailable {
            views.append(UKInlineAlertView("Home Assistant alarm schedule data is unavailable."))
        } else if controller.alarms.isEmpty {
            views.append(UKDeviceText.subheadline("No alarms yet. Add one to choose days and a time."))
        }
        for group in groups {
            // The row's text is the button and the switch its sibling, so VoiceOver gives the switch its own stop.
            var trailing: UIView
            if group.alarms.count == 1, let alarm = group.alarms.first {
                trailing = UKBedAlarmToggle.make(controller: controller, alarm: alarm)
            } else {
                let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
                chevron.tintColor = UKDesignInk.secondary
                chevron.isAccessibilityElement = false
                trailing = chevron
            }
            views.append(UKBedroomRow(symbol: group.enabledCount > 0 ? "alarm" : "alarm.waves.left.and.right", title: group.title,
                                      lines: [group.alarms.map { ClockTime.display($0.time) }.joined(separator: ", "), group.summary],
                                      isMuted: group.enabledCount == 0, openIdentifier: "bed.alarms.\(group.day.rawValue)",
                                      onOpen: { [push] in push(.day(group.day)) }, trailing: trailing))
        }
        list.ukSetArranged(views)
    }
}

/// An alarm's on/off switch (`BedAlarmToggle`).
@MainActor
enum UKBedAlarmToggle {
    static func make(controller: BedSideController, alarm: BedAlarm) -> UIView {
        let toggle = UKControllerToggle(isOn: alarm.enabled) { _ = controller.setEnabled(alarm, $0) }
        toggle.isEnabled = controller.alarmsEditable
        toggle.accessibilityLabel = "\(alarm.day.label) \(ClockTime.display(alarm.time)) alarm"
        toggle.accessibilityIdentifier = "bed.alarm.\(alarm.day.rawValue).\(alarm.time).enabled"
        return toggle
    }
}

/// One day's alarms (`BedAlarmDayPage`; web `EightSleepAlarmDayPage`).
@MainActor
final class UKBedAlarmDayPage: UKSheetColumnViewController {
    private let devices: BedroomDevices
    private let side: BedSide
    private let day: Weekday
    private let push: (BedSideSheet.Route) -> Void
    private let list = UIStackView()
    private var signature = ""
    private var controller: BedSideController { devices.bed(side) }

    init(devices: BedroomDevices, side: BedSide, day: Weekday, push: @escaping (BedSideSheet.Route) -> Void) {
        self.devices = devices
        self.side = side
        self.day = day
        self.push = push
        super.init(maxWidth: 640, spacing: HassTokens.Spacing.m)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        list.axis = .vertical
        list.spacing = HassTokens.Spacing.m
        let add = UKPrimaryButton("Add Alarm", systemImage: "plus") { [push, day] in push(.add(day)) }
        add.accessibilityIdentifier = "bed.day.add"
        stack.addArrangedSubview(UKActiveBedAlarmView(controller: controller))
        stack.addArrangedSubview(list)
        stack.addArrangedSubview(add)
        bag.observe { [weak self] in
            guard let self else { return }
            add.isEnabled = controller.alarmsEditable
            refresh()
        }
    }

    private func refresh() {
        let alarms = controller.alarms.filter { $0.day == day }.sorted { ClockTime.minutes($0.time) < ClockTime.minutes($1.time) }
        let key = "\(controller.alarmsEditable)|" + alarms.map { "\($0.id)\($0.time)\($0.enabled)" }.joined()
        guard key != signature else { return }
        signature = key
        var views: [UIView] = []
        if alarms.isEmpty { views.append(UKDeviceText.subheadline("No alarms yet. Add one to choose days and a time.")) }
        for alarm in alarms {
            views.append(UKBedroomRow(symbol: alarm.enabled ? "alarm" : "alarm.waves.left.and.right", title: ClockTime.display(alarm.time),
                                      lines: [alarm.enabled ? "Enabled" : "Disabled"], isMuted: !alarm.enabled,
                                      openIdentifier: "bed.day.alarm.\(alarm.time)", onOpen: { [push] in push(.edit(alarm.id)) },
                                      trailing: UKBedAlarmToggle.make(controller: controller, alarm: alarm)))
        }
        list.ukSetArranged(views)
    }
}

/// Adds or edits a bed alarm (`BedAlarmEditor`; web `EightSleepAlarmEditor`).
@MainActor
final class UKBedAlarmEditor: UKSheetColumnViewController {
    private let devices: BedroomDevices
    private let side: BedSide
    private let onDone: () -> Void
    private var draft: BedSideController.AlarmDraft
    private let initial: BedSideController.AlarmDraft
    private var saving = false
    private var controller: BedSideController { devices.bed(side) }
    private let alarm: UKActiveBedAlarmView
    private let errorHolder = UIStackView()
    private var days: UKWeekdayPicker?
    private let enabledLine: UKToggleLine
    private let wakeLine: UKToggleLine
    private let problemsHolder = UIStackView()
    private let save: UKPrimaryButton
    private let delete: UKFilledButton

    var pageTitle: String { draft.title }
    private var hasEdits: Bool { draft != initial }

    init(devices: BedroomDevices, side: BedSide, alarmId: String?, lockedDay: Weekday?, onDone: @escaping () -> Void) {
        self.devices = devices
        self.side = side
        self.onDone = onDone
        let controller = devices.bed(side)
        let alarm = alarmId.flatMap { id in controller.alarms.first { $0.id == id } }
        let start = alarm.map { controller.editDraft($0, wakeLight: devices.wakeLight.snapshot) } ?? controller.newAlarmDraft(lockedDay: lockedDay)
        draft = start
        initial = start
        self.alarm = UKActiveBedAlarmView(controller: controller)
        enabledLine = UKToggleLine(title: "Alarm Enabled", toggle: UISwitch(), identifier: "bed.editor.enabled")
        wakeLine = UKToggleLine(title: "Use Room Wake Lights", toggle: UISwitch(), identifier: "bed.editor.wakeLight")
        save = UKPrimaryButton("Save") {}
        delete = UKFilledButton(title: "Delete", fill: UKDeviceStyle.danger) {}
        super.init(maxWidth: 640)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        errorHolder.axis = .vertical
        problemsHolder.axis = .vertical
        problemsHolder.spacing = HassTokens.Spacing.m
        stack.addArrangedSubview(alarm)
        stack.addArrangedSubview(errorHolder)
        if draft.lockedDay == nil {
            let picker = UKWeekdayPicker(title: "Days", days: draft.days, identifier: "bed.editor.day") { [weak self] in
                self?.draft.days = $0
                self?.changed()
            }
            days = picker
            stack.addArrangedSubview(picker)
        }
        stack.addArrangedSubview(UKClockTimeField.make(title: "Time", time: draft.time, identifier: "bed.editor.time") { [weak self] in
            self?.draft.time = $0
            self?.changed()
        })
        enabledLine.toggle.isOn = draft.enabled
        enabledLine.toggle.addAction(UIAction { [weak self] _ in
            self?.draft.enabled = self?.enabledLine.toggle.isOn ?? true
            self?.changed()
        }, for: .valueChanged)
        enabledLine.isHidden = draft.editingId == nil
        wakeLine.toggle.isOn = draft.wakeLightEnabled
        wakeLine.toggle.addAction(UIAction { [weak self] _ in
            self?.draft.wakeLightEnabled = self?.wakeLine.toggle.isOn ?? false
            self?.changed()
        }, for: .valueChanged)
        stack.addArrangedSubview(enabledLine)
        stack.addArrangedSubview(wakeLine)
        stack.addArrangedSubview(problemsHolder)
        save.action = { [weak self] in self?.saveTapped() }
        save.accessibilityIdentifier = "bed.editor.save"
        stack.addArrangedSubview(save)
        delete.accessibilityIdentifier = "bed.editor.delete"
        delete.addAction(UIAction { [weak self] _ in self?.confirmDelete() }, for: .touchUpInside)
        delete.isHidden = draft.editingId == nil
        stack.addArrangedSubview(delete)
        UKHassModal.hidesSystemBack(self)
        bag.observe { [weak self] in self?.apply() }
    }

    private func changed() {
        problemsHolder.ukSetArranged(controller.problems(draft).map { UKInlineAlertView($0) })
        save.isEnabled = !saving && controller.problems(draft).isEmpty
        navigationItem.title = draft.title
        refreshBack()
    }

    private func apply() {
        let error = devices.wakeLight.error
        errorHolder.ukSetArranged(error.map { [UKInlineAlertView($0, severity: .error)] } ?? [])
        delete.isEnabled = !saving && controller.alarmsEditable
        changed()
    }

    private func refreshBack() {
        navigationItem.leftBarButtonItem = UKSheetItems.back(identifier: "bed.editor.back", hasChanges: hasEdits, isEnabled: !saving, presenter: self) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        UKDiscardGuard.apply(to: self, hasChanges: hasEdits, isBusy: saving)
    }

    private func setSaving(_ value: Bool) {
        saving = value
        view.isUserInteractionEnabled = !value
        save.title = value ? "Saving…" : "Save"
        changed()
        delete.isEnabled = !value && controller.alarmsEditable
    }

    private func saveTapped() {
        setSaving(true)
        Task { [weak self] in
            guard let self else { return }
            let ok = await controller.save(draft, wakeLight: devices.wakeLight)
            setSaving(false)
            if ok { onDone() }
        }
    }

    private func confirmDelete() {
        let spec = BedAlarmEditor.deletePrompt(time: ClockTime.display(draft.time), day: draft.days.first?.label)
        UKAlerts.confirmationDialog(spec, from: self, source: .view(delete)) { [weak self] in
            guard let self else { return }
            setSaving(true)
            Task { [weak self] in
                guard let self else { return }
                let ok = await controller.delete(draft, wakeLight: devices.wakeLight)
                setSaving(false)
                if ok { onDone() }
            }
        }
    }
}

// MARK: - Status

/// Pod readings (`BedStatusTab`; web `EightSleepStatusPanel`, climate mode).
@MainActor
final class UKBedStatusTab: UIStackView {
    private let controller: BedSideController
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4))
    private var valueLabels: [UILabel] = []
    private var cards: [UKSheetCardView] = []
    private let bag = UKObservationBag()
    private let host: UKGridHost

    private struct Reading { var title: String; var value: String; var symbol: String }

    init(controller: BedSideController) {
        self.controller = controller
        host = UKGridHost(grid)
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.m
        addArrangedSubview(UKBedroomSectionHeader(title: "Status"))
        for reading in readings() {
            let title = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
            let attachment = NSTextAttachment(image: UIImage(systemName: reading.symbol, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.subheadline)))?.withTintColor(UKDesignInk.secondary) ?? UIImage())
            let text = NSMutableAttributedString(attachment: attachment)
            text.append(NSAttributedString(string: "  \(reading.title)"))
            title.attributedText = text
            let value = UILabel.uk(.title3, weight: .semibold, monospacedDigit: true, ink: UKDesignInk.primary)
            value.text = reading.value
            valueLabels.append(value)
            let column = UIStackView(arrangedSubviews: [title, value])
            column.axis = .vertical
            column.spacing = HassTokens.Spacing.xs
            let card = UKSheetCardView(content: column)
            card.isAccessibilityElement = true
            card.accessibilityLabel = "\(reading.title), \(reading.value)"
            card.accessibilityIdentifier = "bed.status.\(reading.title)"
            cards.append(card)
        }
        grid.setItems(cards.map { UKGridItem($0) })
        grid.configuration.minCellWidth = UKFont.scaled(150, relativeTo: .body, traits: traitCollection)
        addArrangedSubview(host)
        bag.observe { [weak self] in self?.apply() }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (tab: UKBedStatusTab, _) in
            tab.grid.configuration.minCellWidth = UKFont.scaled(150, relativeTo: .body, traits: tab.traitCollection)
            tab.host.remeasure()
        }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func readings() -> [Reading] {
        let config = controller.config
        let entity = { (id: String) in self.controller.store.entity(id).state }
        let pumpProblem = entity(config.pumpClogEntityId)?.state == "on" || entity(config.pumpStallEntityId)?.state == "on"
        return [
            Reading(title: "Current Temp", value: BedFormat.temperature(controller.currentTemperature), symbol: "thermometer.medium"),
            Reading(title: "Pump Status", value: pumpProblem ? "Check pump" : "OK", symbol: "drop"),
            Reading(title: "Loop Temp", value: BedFormat.metric(entity(config.pumpLoopTemperatureEntityId)), symbol: "arrow.triangle.2.circlepath"),
            Reading(title: "Pump RPM", value: BedFormat.metric(entity(config.pumpRpmEntityId)), symbol: "gauge.with.dots.needle.33percent"),
            Reading(title: "Heart Rate", value: BedFormat.metric(entity(config.heartRateEntityId)), symbol: "heart"),
            Reading(title: "Breathing", value: BedFormat.metric(entity(config.breathingRateEntityId)), symbol: "lungs"),
            Reading(title: "HRV", value: BedFormat.metric(entity(config.hrvEntityId)), symbol: "waveform.path.ecg"),
        ]
    }

    private func apply() {
        for (index, reading) in readings().enumerated() {
            valueLabels[index].text = reading.value
            cards[index].accessibilityLabel = "\(reading.title), \(reading.value)"
        }
    }
}
#endif
