#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The room's wake-light alarms sheet (`WakeLightSheet`; pattern `.agents/patterns/bedroom-devices.md`; web `WakeLightModal`). Two tabs
/// in the bottom section bar: the alarm schedule (with stop controls while a wake runs) and room defaults. Adding or editing an
/// alarm pushes an editor inside the sheet. A mirrored bed alarm opens its bed's sheet through `onOpenBed`.
@MainActor
enum UKWakeLightSheet {
    /// - Parameters:
    ///   - onOpenBed: Called once this sheet has closed, with the bed side whose alarms to open: present the bed sheet from there.
    ///   - accessory: Shown under the tab bar (the gallery's last-call line).
    static func make(devices: BedroomDevices, initialTab: WakeLightSheet.Tab = .alarms, context: UKContext, accessory: UIView? = nil,
                     onOpenBed: @escaping (BedSide) -> Void = { _ in }) -> UKHassModalController {
        let content = UKWakeLightContent(devices: devices, tab: initialTab)
        let bar = content.tabBar.inset()
        var barView: UIView = bar
        if let accessory {
            let stack = UIStackView(arrangedSubviews: [bar, accessory])
            stack.axis = .vertical
            barView = stack
        }
        // With the room name the bar title clips at AX5.
        let root = UKSheetPinnedBarPage(content: content, bar: barView, scrollView: content.scrollView)
        var options = UKHassModalOptions(title: devices.wakeLight.config.title, fitKey: "WakeLightSheet")
        options.height = .full
        options.width = .page
        let modal = UKHassModalController(root: root, options: options)
        content.push = { [weak modal] page in
            guard let modal else { return }
            modal.push(page)
        }
        content.popToRoot = { [weak modal] in modal?.popToRootViewController(animated: true) }
        content.openBed = { [weak modal] side in
            modal?.dismiss(animated: true) { onOpenBed(side) }
        }
        return modal
    }
}

@MainActor
final class UKWakeLightContent: UKSheetColumnViewController {
    let devices: BedroomDevices
    private(set) var currentTab: WakeLightSheet.Tab
    var push: (UIViewController) -> Void = { _ in }
    var popToRoot: () -> Void = {}
    var openBed: (BedSide) -> Void = { _ in }
    private var controller: WakeLightController { devices.wakeLight }
    private let subtitle = UKDeviceText.subheadline("")
    private let alerts = UIStackView()
    private var alertSignature = ""
    private var alarmsTab: UKWakeAlarmsTab!
    private var defaultsTab: UKWakeDefaultsTab!
    private(set) lazy var tabBar = UKModalTabBar(
        tabs: WakeLightSheet.Tab.allCases, label: "\(controller.config.title) sections", title: { $0.title },
        symbol: { ModalTabSymbols.symbol(for: $0) }, selection: currentTab, identifier: "wake.tabs") { [weak self] in self?.select($0) }

    init(devices: BedroomDevices, tab: WakeLightSheet.Tab) {
        self.devices = devices
        self.currentTab = tab
        super.init(maxWidth: 720)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        subtitle.accessibilityIdentifier = "wake.subtitle"
        alerts.axis = .vertical
        alerts.spacing = HassTokens.Spacing.m
        alarmsTab = UKWakeAlarmsTab(devices: devices, edit: { [weak self] id in self?.openEditor(id) }, add: { [weak self] in self?.openEditor(nil) },
                                    openBed: { [weak self] side in self?.openBed(side) })
        defaultsTab = UKWakeDefaultsTab(controller: controller)
        alarmsTab.isHidden = currentTab != .alarms
        defaultsTab.isHidden = currentTab != .defaults
        [subtitle, alerts, alarmsTab, defaultsTab].forEach(stack.addArrangedSubview)
        bag.observe { [weak self] in self?.apply() }
    }

    private func select(_ next: WakeLightSheet.Tab) {
        guard next != currentTab else { return }
        currentTab = next
        alarmsTab.isHidden = next != .alarms
        defaultsTab.isHidden = next != .defaults
    }

    private func apply() {
        subtitle.text = WakeLight.subtitle(controller.snapshot, modal: true)
        let live = controller.live
        var views: [UIView] = []
        var key = ""
        if !live.compatible && live.contractVersion > 0 {
            views.append(UKInlineAlertView("Editing wake light alarms requires an integration update. Saved alarms remain available to view."))
            key += "compat"
        } else if !live.available {
            views.append(UKInlineAlertView(WakeLight.errorMessage("unavailable")))
            key += "unavailable"
        }
        if let error = controller.error {
            let alert = UKInlineAlertView(error, severity: .error)
            alert.accessibilityIdentifier = "wake.error"
            views.append(alert)
            key += "error:\(error)"
        }
        guard key != alertSignature else { return }
        alertSignature = key
        alerts.ukSetArranged(views)
        alerts.isHidden = views.isEmpty
    }

    private func openEditor(_ id: String?) {
        let editor = UKWakeLightEditor(devices: devices, alarmId: id) { [weak self] in self?.popToRoot() }
        editor.title = editor.pageTitle
        editor.navigationItem.title = editor.pageTitle
        push(editor)
    }
}

// MARK: - Wake Alarms tab

@MainActor
final class UKWakeAlarmsTab: UIStackView {
    private let devices: BedroomDevices
    private let edit: (String) -> Void
    private let add: () -> Void
    private let openBed: (BedSide) -> Void
    private var controller: WakeLightController { devices.wakeLight }
    private let bag = UKObservationBag()
    private var signature = ""

    init(devices: BedroomDevices, edit: @escaping (String) -> Void, add: @escaping () -> Void, openBed: @escaping (BedSide) -> Void) {
        self.devices = devices
        self.edit = edit
        self.add = add
        self.openBed = openBed
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.xl
        bag.observe { [weak self] in self?.rebuild() }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rebuild() {
        let snapshot = controller.snapshot
        let editable = controller.canEdit && controller.live.available
        let pendingKey = snapshot.alarms.map { "\($0.id):\(controller.isPending(alarmId: $0.id)):\(snapshot.isLinked($0))" }
        let key = [
            snapshot.activeOccurrences.map(\.alarmId).joined(separator: ","), snapshot.currentBlockers.joined(separator: ","),
            snapshot.alarms.map { "\($0.id)|\($0.label)|\($0.enabled)|\($0.localTime)|\($0.rampMinutes)|\(WakeLight.scheduleLabel($0))" }.joined(separator: ";"),
            pendingKey.joined(separator: ","), "\(controller.canEdit)\(controller.live.available)\(controller.configurationPending)\(controller.stopping)",
        ].joined(separator: "#")
        guard key != signature else { return }
        signature = key
        var views: [UIView] = []
        if !snapshot.activeOccurrences.isEmpty { views.append(activeControls(snapshot)) }
        for code in snapshot.currentBlockers { views.append(UKInlineAlertView(WakeLight.blockerMessage(code))) }
        var schedule: [UIView] = [UKBedroomSectionHeader(title: "Wake Alarm Schedule")]
        if snapshot.alarms.isEmpty { schedule.append(UKDeviceText.subheadline("No wake alarms yet.")) }
        for alarm in snapshot.alarms {
            schedule.append(alarm.isNative ? nativeRow(alarm, editable: editable) : mirroredRow(alarm, snapshot: snapshot))
        }
        if controller.canEdit {
            let button = UKPrimaryButton("Add Wake Alarm", systemImage: "plus") { [add] in add() }
            button.isEnabled = snapshot.available && !controller.configurationPending
            button.accessibilityIdentifier = "wake.add"
            schedule.append(button)
        } else {
            schedule.append(UKDeviceText.footnote("Only Home Assistant administrators can edit wake alarms."))
        }
        let column = UIStackView(arrangedSubviews: schedule)
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.m
        views.append(column)
        ukSetArranged(views)
    }

    private func activeControls(_ snapshot: WakeLight.Snapshot) -> UIView {
        var parts: [UIView] = [UKBedroomSectionHeader(title: "Active Wake-Light Controls",
                                                      detail: "Stopping ends this wake for the room and leaves the lights as they are.")]
        for occurrence in snapshot.activeOccurrences {
            let alarm = snapshot.alarms.first { $0.id == occurrence.alarmId }
            parts.append(UKDeviceText.subheadline("\(alarm?.label ?? "Wake Alarm") · \(WakeLight.displayTime(occurrence.wakeAt))", ink: UKDesignInk.primary))
        }
        let stop = UKFilledButton(title: controller.stopping ? "Stopping Wake Lights…" : "Stop Wake-Light Episode", fill: UKDeviceStyle.danger) { [controller] in
            Task { await controller.endEpisode() }
        }
        stop.isEnabled = !(controller.stopping || !controller.live.available)
        stop.accessibilityIdentifier = "wake.stop"
        parts.append(stop)
        let column = UIStackView(arrangedSubviews: parts)
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.m
        return UKSheetCardView(content: column)
    }

    private func nativeRow(_ alarm: WakeLight.Alarm, editable: Bool) -> UIView {
        let pending = controller.isPending(alarmId: alarm.id)
        let toggle = UKControllerToggle(isOn: alarm.enabled) { [controller] enabled in
            var next = alarm
            next.enabled = enabled
            Task { await controller.save(next) }
        }
        toggle.isEnabled = editable && !pending
        toggle.accessibilityLabel = alarm.label
        toggle.accessibilityIdentifier = "wake.alarm.\(alarm.id).enabled"
        return UKBedroomRow(symbol: alarm.enabled ? "alarm" : "alarm.waves.left.and.right", title: alarm.label,
                            lines: ["\(WakeLight.scheduleLabel(alarm)) · \(WakeLight.displayTime(alarm.localTime))", "Ramp: \(WakeLight.rampLabel(alarm.rampMinutes))"],
                            isMuted: !alarm.enabled, openIdentifier: "wake.alarm.\(alarm.id)", onOpen: editable ? { [edit] in edit(alarm.id) } : nil,
                            trailing: toggle)
    }

    private func mirroredRow(_ alarm: WakeLight.Alarm, snapshot: WakeLight.Snapshot) -> UIView {
        let source = alarm.sourceRef.flatMap(controller.config.source(id:))
        let keys = alarm.linkKeys()
        let linked = snapshot.isLinked(alarm)
        let title = source?.alarmLabel ?? alarm.sourceLabel ?? alarm.label
        let toggle = UKControllerToggle(isOn: linked) { [controller] enabled in
            Task { await controller.setLinks(keys, enabled: enabled) }
        }
        toggle.isEnabled = !(!controller.canEdit || !controller.live.available || keys.isEmpty || controller.arePending(linkKeys: keys))
        toggle.accessibilityLabel = "Use room wake lights for the \(title) alarm"
        toggle.accessibilityIdentifier = "wake.alarm.\(alarm.id).link"
        var parts: [UIView] = [UKBedroomRow(symbol: "bed.double", title: title, lines: ["\(WakeLight.scheduleLabel(alarm)) · \(WakeLight.displayTime(alarm.localTime))"],
                                            isMuted: !alarm.enabled || !linked, trailing: toggle)]
        if let source {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: "arrow.up.forward.app")
            configuration.imagePadding = HassTokens.Spacing.s
            configuration.title = "Open Linked-Device Alarm Editor"
            configuration.baseForegroundColor = UKDesignInk.primary // The accent renders 2.5:1 on the card.
            configuration.contentInsets = .zero
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UKFont.rowTitle()
                return attributes
            }
            let button = UIButton(configuration: configuration)
            button.contentHorizontalAlignment = .leading
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
            button.accessibilityIdentifier = "wake.alarm.\(alarm.id).open"
            button.addAction(UIAction { [openBed] _ in openBed(source.side) }, for: .touchUpInside)
            parts.append(button)
        }
        let column = UIStackView(arrangedSubviews: parts)
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.s
        return column
    }
}

// MARK: - Defaults

/// Room ramp and post-wake hold (`WakeLightDefaultsTab`; web Defaults tab).
@MainActor
final class UKWakeDefaultsTab: UIStackView {
    private let controller: WakeLightController
    private let bag = UKObservationBag()
    private let ramp: UKChoiceGrid<Int>
    private let hold: UKChoiceGrid<Int>
    private let note = UKDeviceText.footnote("")

    init(controller: WakeLightController) {
        self.controller = controller
        func update(_ keyPath: WritableKeyPath<WakeLight.Defaults, Int>, _ value: Int) {
            var next = controller.snapshot.defaults
            guard next[keyPath: keyPath] != value else { return }
            next[keyPath: keyPath] = value
            Task { await controller.updateDefaults(next) }
        }
        ramp = UKChoiceGrid(title: "Light Ramp Duration", options: WakeLight.rampMinutes, label: WakeLight.durationLabel, identifier: "wake.defaults.ramp") { update(\.rampMinutes, $0) }
        hold = UKChoiceGrid(title: "Post-Wake Hold Time", options: WakeLight.holdMinutes, label: WakeLight.durationLabel, identifier: "wake.defaults.hold") { update(\.postWakeHoldMinutes, $0) }
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.xl
        [UKBedroomSectionHeader(title: "Wake-Light Defaults", detail: "New wake alarms start with this light ramp."), ramp, hold, note].forEach(addArrangedSubview)
        bag.observe { [weak self] in self?.apply() }
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply() {
        let snapshot = controller.snapshot
        let editable = controller.canEdit && controller.live.available && !controller.configurationPending
        let holdSupported = snapshot.contractVersion >= 6
        ramp.show(selection: snapshot.defaults.rampMinutes, isDisabled: !editable)
        hold.show(selection: snapshot.defaults.postWakeHoldMinutes, isDisabled: !editable || !holdSupported)
        note.text = holdSupported
            ? "How long the lights stay at full brightness after the wake time before normal lighting resumes."
            : "Post-wake hold requires a wake light integration update."
    }
}

// MARK: - Editor

/// Adds or edits one wake alarm (`WakeLightEditor`; web `WakeLightAlarmEditor`).
@MainActor
final class UKWakeLightEditor: UKSheetColumnViewController {
    private let devices: BedroomDevices
    private let alarmId: String?
    private let onDone: () -> Void
    private var draft: WakeLight.Alarm
    private var initial: WakeLight.Alarm
    private var addToBeds: Set<BedSide> = []
    private var saving = false
    private var controller: WakeLightController { devices.wakeLight }
    private var isNew: Bool { alarmId == nil }
    private var problems: [String] { WakeLight.problems(draft) }
    private var dirty: Bool { isNew || hasEdits }
    private var hasEdits: Bool { !draft.sameEdits(as: initial) }
    private var locked: Bool { !controller.live.available || !controller.canEdit || controller.configurationPending || saving }
    private var latest: WakeLight.Alarm? { alarmId.flatMap { id in controller.live.alarms.first { $0.id == id } } }
    private var stale: Bool {
        controller.errorCode == "revision_conflict" && (controller.requiresAlarmReload || (latest.map { $0.revision != draft.revision } ?? false))
    }

    var pageTitle: String { isNew ? "Add Wake Alarm" : initial.label }

    private let errorHolder = UIStackView()
    private let reload = UIButton(type: .system)
    private var kindChoice: UKSegmentedChoice<WakeLight.Kind>!
    private var nameField: UKOutlinedTextField!
    private var days: UKWeekdayPicker!
    private var date: UKDatePickerLine!
    private var ramp: UKChoiceGrid<Int>!
    private let enabledLine = UKToggleLine(title: "Wake Alarm Enabled", toggle: UISwitch(), identifier: "wake.editor.enabled")
    private let bedHolder = UIStackView()
    private let bedNote = UKDeviceText.footnote("Adding one-time alarms to a bed requires a wake light integration update.")
    private let problemHolder = UIStackView()
    private let save = UKPrimaryButton("Save") {}
    private let delete = UKFilledButton(title: "Delete", fill: UKDeviceStyle.danger) {}
    private var bedToggles: [BedSide: UKToggleLine] = [:]

    init(devices: BedroomDevices, alarmId: String?, onDone: @escaping () -> Void) {
        self.devices = devices
        self.alarmId = alarmId
        self.onDone = onDone
        let existing = alarmId.flatMap { id in devices.wakeLight.snapshot.alarms.first { $0.id == id } }
        let start = existing ?? WakeLight.Alarm.new(id: UUID().uuidString.lowercased(), defaults: devices.wakeLight.snapshot.defaults)
        var weekly = start
        if existing == nil {
            weekly.kind = .weekly
            weekly.weekdays = Weekday.workdays
            weekly.date = nil
        }
        draft = weekly
        initial = weekly
        super.init(maxWidth: 720)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        UKHassModal.hidesSystemBack(self)
        errorHolder.axis = .vertical
        var configuration = UIButton.Configuration.tinted()
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        configuration.title = "Open Latest Alarm, Replace Draft"
        configuration.baseForegroundColor = UKInk.action
        configuration.baseBackgroundColor = UKInk.action
        reload.configuration = configuration
        reload.accessibilityIdentifier = "wake.editor.reload"
        reload.addAction(UIAction { [weak self] _ in self?.reloadDraft() }, for: .touchUpInside)
        reload.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true

        let kindHeading = UILabel.uk(.subheadline, weight: .semibold, ink: UKDesignInk.primary)
        kindHeading.text = "Alarm Type"
        kindChoice = UKSegmentedChoice(label: "Alarm Type", options: WakeLight.Kind.allCases, title: { $0.label }, selection: draft.kind, identifier: "wake.editor.kind") { [weak self] in self?.setKind($0) }
        let nameHeading = UILabel.uk(.subheadline, weight: .semibold, ink: UKDesignInk.primary)
        nameHeading.text = "Alarm Name"
        nameField = UKOutlinedTextField(placeholder: "Alarm Name", text: draft.label, limit: 40, identifier: "wake.editor.name")
        nameField.onChange = { [weak self] in self?.draft.label = $0; self?.changed() }
        days = UKWeekdayPicker(title: "Days", days: draft.weekdays, identifier: "wake.editor.day") { [weak self] in self?.draft.weekdays = $0; self?.changed() }
        let time = UKClockTimeField.make(title: "Wake Time", time: draft.localTime, identifier: "wake.editor.time") { [weak self] in self?.draft.localTime = $0; self?.changed() }
        date = UKDatePickerLine(title: "Alarm Date", mode: .date, date: draft.date.flatMap { WakeLight.date($0) } ?? .now, identifier: "wake.editor.date") { [weak self] in
            self?.draft.date = WakeLight.dateString($0)
            self?.changed()
        }
        ramp = UKChoiceGrid(title: "Light Ramp Duration", options: WakeLight.rampMinutes, label: WakeLight.durationLabel, identifier: "wake.editor.ramp") { [weak self] in
            self?.draft.rampMinutes = $0
            self?.changed()
        }
        enabledLine.toggle.addAction(UIAction { [weak self] _ in self?.draft.enabled = self?.enabledLine.toggle.isOn ?? true; self?.changed() }, for: .valueChanged)
        bedHolder.axis = .vertical
        problemHolder.axis = .vertical
        problemHolder.spacing = HassTokens.Spacing.s
        save.action = { [weak self] in self?.saveTapped() }
        save.accessibilityIdentifier = "wake.editor.save"
        delete.accessibilityIdentifier = "wake.editor.delete"
        delete.addAction(UIAction { [weak self] _ in self?.confirmDelete() }, for: .touchUpInside)
        delete.isHidden = isNew
        for target in devices.bedTargets {
            let line = UKToggleLine(title: "Add to \(target.title)", toggle: UISwitch(), identifier: "wake.editor.bed.\(target.side.rawValue)")
            line.toggle.addAction(UIAction { [weak self, weak line] _ in
                guard let self, let line else { return }
                if line.toggle.isOn { addToBeds.insert(target.side) } else { addToBeds.remove(target.side) }
                changed()
            }, for: .valueChanged)
            bedToggles[target.side] = line
            bedHolder.addArrangedSubview(line)
        }
        bedHolder.addArrangedSubview(bedNote)
        bedHolder.isHidden = !isNew
        let kindColumn = UIStackView(arrangedSubviews: [kindHeading, kindChoice])
        kindColumn.axis = .vertical
        kindColumn.spacing = HassTokens.Spacing.s
        let nameColumn = UIStackView(arrangedSubviews: [nameHeading, nameField])
        nameColumn.axis = .vertical
        nameColumn.spacing = HassTokens.Spacing.s
        [errorHolder, reload, kindColumn, nameColumn, days, time, date, ramp, enabledLine, bedHolder, problemHolder, save, delete].forEach(stack.addArrangedSubview)
        enabledLine.toggle.isOn = draft.enabled
        bag.observe { [weak self] in self?.apply() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent { controller.clearError() }
    }

    /// Re-reads everything the draft and the controller decide.
    private func apply() {
        errorHolder.ukSetArranged(controller.error.map { error in
            let alert = UKInlineAlertView(error, severity: .error)
            alert.accessibilityIdentifier = "wake.editor.error"
            return [alert]
        } ?? [])
        reload.isHidden = !stale
        kindChoice.selection = draft.kind
        days.isHidden = draft.kind != .weekly
        date.isHidden = draft.kind != .once
        ramp.show(selection: draft.rampMinutes, isDisabled: false)
        let oneTimeUnsupported = draft.kind == .once && controller.snapshot.contractVersion < 5
        for target in devices.bedTargets { bedToggles[target.side]?.toggle.isEnabled = target.available && !oneTimeUnsupported }
        bedNote.isHidden = !oneTimeUnsupported
        let shownProblems = !problems.isEmpty && dirty ? problems : []
        problemHolder.ukSetArranged(shownProblems.map { UKInlineAlertView($0) })
        save.isEnabled = !(locked || !dirty || !problems.isEmpty || stale)
        save.title = saving ? "Saving…" : "Save"
        delete.isEnabled = !locked
        stack.isUserInteractionEnabled = !saving
        navigationItem.leftBarButtonItem = UKSheetItems.back(identifier: "wake.editor.back", hasChanges: hasEdits, isEnabled: !saving, presenter: self) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        UKDiscardGuard.apply(to: self, hasChanges: hasEdits, isBusy: saving)
    }

    private func changed() { apply() }

    private func setKind(_ kind: WakeLight.Kind) {
        guard kind != draft.kind else { return }
        draft.kind = kind
        if kind == .once {
            draft.date = draft.date ?? WakeLight.dateString(Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now, calendar: .current)
            date.picker.date = draft.date.flatMap { WakeLight.date($0) } ?? .now
        } else if draft.weekdays.isEmpty {
            draft.weekdays = Weekday.workdays
            days.show(days: draft.weekdays)
        }
        changed()
    }

    private func saveTapped() {
        saving = true
        apply()
        Task { [weak self] in
            guard let self else { return }
            let ok = await devices.saveWakeAlarm(draft, isNew: isNew, addToBeds: addToBeds)
            saving = false
            apply()
            if ok { onDone() }
        }
    }

    private func confirmDelete() {
        guard let alarmId else { return }
        let spec = AlertCopy.delete("Alarm", detail: "Set for \(WakeLight.displayTime(initial.localTime)) on \(WakeLight.scheduleLabel(initial)).")
        UKAlerts.confirmationDialog(spec, from: self, source: .view(delete)) { [weak self] in
            guard let self else { return }
            saving = true
            apply()
            Task { [weak self] in
                guard let self else { return }
                let ok = await controller.delete(alarmId: alarmId)
                saving = false
                apply()
                if ok { onDone() }
            }
        }
    }

    private func reloadDraft() {
        if let latest {
            draft = latest
            initial = latest
            nameField.show(latest.label)
            days.show(days: latest.weekdays)
            enabledLine.toggle.isOn = latest.enabled
        }
        controller.clearError()
        apply()
    }
}

// MARK: - Tiles

/// A room tile for a bedroom device, bound to its controller (`BedSideTile`, `WakeLightTile`). The Rooms page places it in its grid.
@MainActor
final class UKBedroomTile: UIView, UKGridMeasuring {
    private let tile: UKGlassTileView
    private let bag = UKObservationBag()
    private lazy var clock = UKEverySecond { [weak self] now in self?.refresh(now: now) }
    private let model: (Date) -> UKGlassTileModel
    private let runs: () -> Bool
    private let action: () -> Void

    private init(environment: UKTileEnvironment, model: @escaping (Date) -> UKGlassTileModel, runs: @escaping () -> Bool, action: @escaping () -> Void) {
        self.model = model
        self.runs = runs
        self.action = action
        tile = UKGlassTileView(model: model(.now), environment: environment, action: action)
        super.init(frame: .zero)
        addSubview(tile)
        bag.observe { [weak self] in
            guard let self else { return }
            self.refresh(now: .now)
            self.clock.setRunning(self.runs())
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refresh(now: Date) { tile.configure(model(now), action: action) }

    /// A bed side's tile (web SleepyPod tile).
    static func bedSide(_ controller: BedSideController, context: UKContext, action: @escaping () -> Void) -> UKBedroomTile {
        UKBedroomTile(environment: UKTileEnvironment(context: context), model: { now in
            let face = BedroomStyle.face(action: controller.action, level: controller.displayedTarget, isAvailable: controller.sideAvailable)
            return UKGlassTileModel(title: controller.config.title, subtitle: controller.tileSubtitle(now: now), symbol: "bed.double", family: face.family,
                                    // Fills while the side is on (`ThermostatTileFace.bedSide`).
                                    isActive: face.isActive && !controller.scope.readOnly,
                                    // An unavailable side dims and says "Unavailable" and is not mistaken for "Off".
                                    isUnavailable: !controller.sideAvailable, kind: .navigate, identifier: "room.card.\(controller.config.title)")
        }, runs: { controller.hotFlashHolding }, action: action)
    }

    /// The wake light's tile (web "Wake-Light Alarms" tile).
    static func wakeLight(_ controller: WakeLightController, context: UKContext, action: @escaping () -> Void) -> UKBedroomTile {
        UKBedroomTile(environment: UKTileEnvironment(context: context), model: { _ in
            let snapshot = controller.snapshot
            return UKGlassTileModel(title: controller.config.title, subtitle: WakeLight.subtitle(snapshot), symbol: "sunrise", family: .lights,
                                    // Fills only while a wake is running (ramping, holding or snoozed); an armed alarm stays dark and the
                                    // subtitle names the next one (colour never carries the state alone).
                                    isActive: WakeLight.fillsTile(snapshot), kind: .navigate, identifier: "room.card.\(controller.config.title)")
        }, runs: { false }, action: action)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { tile.gridHeight(forWidth: width) }

    override func sizeThatFits(_ size: CGSize) -> CGSize { tile.sizeThatFits(size) }

    override func layoutSubviews() {
        super.layoutSubviews()
        tile.frame = bounds
    }
}
#endif
