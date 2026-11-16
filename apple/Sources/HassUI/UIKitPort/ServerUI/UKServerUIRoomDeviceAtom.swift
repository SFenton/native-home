#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - Canonical domain atom host

@MainActor @Observable
private final class UKDeviceTimerSelection {
    var minutes: Int
    init(_ minutes: Int) { self.minutes = minutes }
}

/// One configured control, not a feature screen. Layout, tabs, collection and draft ownership stay outside.
@MainActor
final class UKServerUIRoomDeviceAtom: UIView, UKGridMeasuring {
    private(set) var definition: ServerUIRoomDeviceControl?
    private(set) var source: ServerUIRoomDeviceSource?
    private var context = UKContext.sheetPlaceholder
    private let content = UIStackView()
    private let feedback = UILabel.uk(.footnote, ink: UKInk.danger)
    private let bag = UKObservationBag()
    private var selection: UKDeviceTimerSelection?
    private var choice: UKSegmentedChoice<String>?
    private var tile: UKGlassTileView?
    private var toggle: UKControllerToggle?
    private var dial: UKThermostatDial?
    private var stepper: UKControllerStepper?
    private var pill: UKDeviceStatusPill?
    private var picker: UKFanTimerPicker?
    private var running: UKFanTimerRunning?
    private var lastFailure = false
    var onNavigate: ((ServerUICompositionDocument.Action, UIView) -> Void)?
    private lazy var roomClock = UKEverySecond { [weak self] now in self?.refreshRoomTile(at: now) }
    private var roomClockRunning = false

    var hasLocalEdits: Bool { selection?.minutes != definition?.initialMinutes && selection != nil }
    var hasFocusedControl: Bool {
        if containsFirstResponder(self) { return true }
        if let focused = UIAccessibility.focusedElement(using: .notificationVoiceOver) as? UIView { return focused.isDescendant(of: self) }
        return false
    }

    init() {
        super.init(frame: .zero)
        content.axis = .vertical
        content.spacing = HassTokens.Spacing.m
        addSubview(content)
        content.ukPin(to: self)
        feedback.isHidden = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ definition: ServerUIRoomDeviceControl, source: ServerUIRoomDeviceSource?, context: UKContext) {
        let changed = self.definition != definition || self.source !== source
        self.definition = definition
        self.source = source
        self.context = context
        if changed { build(definition) }
        bag.removeAll()
        bag.observe { [weak self] in self?.refresh() }
        if definition.control == .humidifierScheduling, let source, source.schedules != nil, !source.schedulesLoadRequested {
            Task { @MainActor in
                guard !source.schedulesLoadRequested else { return }
                do { try await source.loadSchedules() }
                catch { NSLog("ServerUI humidifier schedule load rejected") }
            }
        }
    }

    private func build(_ d: ServerUIRoomDeviceControl) {
        selection = nil
        choice = nil; tile = nil; toggle = nil; dial = nil; stepper = nil; pill = nil; picker = nil
        running?.setRunning(false)
        running = nil
        var views: [UIView] = []
        if d.control.hasOptions, d.control != .fanTimer {
            let labels = Dictionary(uniqueKeysWithValues: d.options.map { ($0.value, $0.label) })
            let choice = UKSegmentedChoice(label: d.node.title, options: d.options.map(\.value), title: { labels[$0] ?? $0 },
                                           selection: nil, identifier: d.node.id) { [weak self] in self?.send(.choose($0)) }
            self.choice = choice
            views = [UKDeviceSection(title: d.node.title, footnote: d.labels.footnote.isEmpty ? nil : d.labels.footnote, content: [choice])]
        } else {
            switch d.control {
            case .fanPower, .fanLock, .fanRoom, .grillDetail:
                let tile = UKGlassTileView(model: UKGlassTileModel(title: d.node.title, symbol: d.icon.drawn, isActive: false, isUnavailable: true, identifier: d.node.id))
                self.tile = tile
                views = [UKGridHost(tile)]
            case .fanTimer:
                if selection == nil { selection = UKDeviceTimerSelection(d.initialMinutes ?? 30) }
                let minutes = d.options.compactMap { Int($0.value) }
                let picker = UKFanTimerPicker(
                    minutes: minutes, labels: Dictionary(uniqueKeysWithValues: zip(minutes, d.options.map(\.label))), identifier: d.node.id,
                    selected: { [weak self] in self?.selection?.minutes ?? d.initialMinutes ?? 30 },
                    canStart: { [weak self] in
                        guard let self, case .fan(let model) = self.source?.controller else { return false }
                        return model.canStartTimer && !self.context.valuesPending && self.source?.hasPendingIntent == false
                    }, title: { minutes in d.options.first { $0.value == String(minutes) }?.actionLabel ?? d.labels.unavailable },
                    footnote: d.labels.footnote, select: { [weak self] in self?.selection?.minutes = $0 },
                    start: { [weak self] in
                        guard let minutes = self?.selection?.minutes else { return }
                        self?.send(.startTimer(minutes))
                    })
                let running = UKFanTimerRunning(
                    identifier: d.node.id, title: d.node.title, clearTitle: d.labels.cancel, unavailableText: d.labels.unavailable,
                    remaining: { [weak self] now in
                        guard case .fan(let model) = self?.source?.controller else { return nil }
                        return model.remainingSeconds(at: now)
                    }, fraction: { [weak self] now in
                        guard case .fan(let model) = self?.source?.controller else { return nil }
                        return model.remainingFraction(at: now)
                    }, available: { [weak self] in
                        guard let self, case .fan(let model) = self.source?.controller else { return false }
                        return model.timerAvailable && self.source?.hasPendingIntent == false
                    }, cancel: { [weak self] in self?.send(.cancelTimer) })
                self.picker = picker
                self.running = running
                views = [UKDeviceSection(title: d.node.title, content: [picker, running])]
            case .humidifierPower, .humidifierDisplay, .humidifierScheduling:
                let toggle = UKControllerToggle(isOn: false) { [weak self] in self?.send(.setOn($0)) }
                self.toggle = toggle
                views = [UKToggleLine(title: d.node.title, symbol: d.icon.drawn, toggle: toggle, identifier: d.node.id)]
            case .humidifierMist, .humidifierTarget:
                if case .humidifier(let model) = source?.controller {
                    let config = dialConfiguration(model, d)
                    let dial = UKThermostatDial(config, size: d.control == .humidifierMist ? .modal : .compact, surface: context.surface) { [weak self] in
                        if case .single(let value) = $0 { self?.send(.number(value)) }
                    }
                    dial.accessibilityIdentifier = d.node.id
                    self.dial = dial
                    views = [dial]
                    if !d.labels.footnote.isEmpty { views.append(UKDeviceText.footnote(d.labels.footnote)) }
                }
            case .humidifierTimer:
                let stepper = UKControllerStepper(value: 0, in: HumidifierController.timerRange, step: HumidifierController.timerStep,
                                                   title: d.node.title, format: { $0 == 0 ? d.labels.off : HumidifierController.formatMinutes($0) }) { [weak self] in self?.send(.number(Double($0))) }
                stepper.accessibilityIdentifier = d.node.id
                self.stepper = stepper
                views = [stepper]
            case .humidifierInfo:
                let pill = UKDeviceStatusPill(item: .init(title: d.node.title, icon: d.icon.drawn, value: d.labels.loading, tone: .neutral))
                self.pill = pill
                views = [pill]
            default: break
            }
        }
        content.ukSetArranged(views + [feedback])
    }

    private func refresh() {
        guard let d = definition else { return }
        let pending = source?.hasPendingIntent == true
        let loading = context.valuesPending
        isUserInteractionEnabled = (!pending || d.control == .fanRoom) && !loading && source != nil
        var visible = true
        var available = source != nil
        var selected: String?
        var on = false
        var text: String?
        var warning: String?
        if let source {
            switch source.controller {
            case .purifier(let model):
                switch d.control {
                case .purifierMode: selected = model.mode; available = !model.modeUnavailable
                case .purifierAuto: selected = model.autoMode; available = !model.autoModeUnavailable; visible = model.showsAutoModes
                case .purifierSpeed: selected = model.percentage; available = !model.fanUnavailable; visible = model.showsSpeeds
                default: available = false
                }
            case .fan(let model):
                switch d.control {
                case .fanPower: on = model.powerOn; available = model.powerAvailable
                case .fanLock: on = model.locked; available = model.lockAvailable
                case .fanRoom: on = model.powerOn; available = model.powerAvailable
                case .fanTimer:
                    picker?.isHidden = model.timerPending
                    running?.isHidden = !model.timerPending
                    running?.setRunning(model.timerPending)
                    available = model.canStartTimer
                default: available = false
                }
            case .grill(let model):
                if let detail = model.config.details.first(where: { $0.entityId == d.detailEntityId }) {
                    let display = model.display(detail)
                    available = !display.isUnavailable
                    on = display.isActive
                    text = detail.isSwitch ? nil : display.value
                } else { available = false }
            case .humidifier(let model):
                func has(_ id: String) -> Bool { !EntityState.isUnavailable(model.commands.entity(id)?.state) }
                available = !model.isBlocked
                if model.fault == .tank { warning = d.labels.tankFault }
                else if model.fault == .water { warning = d.labels.waterFault }
                switch d.control {
                case .humidifierMode: selected = model.mode.rawValue; available = available && has(model.config.modeEntityId)
                case .humidifierPresets:
                    selected = model.powerOn ? String(model.mistLevel) : nil
                    available = model.canSetLevel && has(model.config.mistLevelEntityId)
                case .humidifierWarm:
                    selected = String(model.warmLevel)
                    available = available && !model.isSleep && has(model.config.warmLevelEntityId)
                case .humidifierPower: on = model.powerOn; available = model.canTogglePower
                case .humidifierDisplay:
                    on = model.displayOn; visible = model.powerOn
                    available = available && !model.isSleep && has(model.config.displayEntityId)
                case .humidifierMist, .humidifierTarget:
                    visible = d.control != .humidifierTarget || model.mode == .targetHumidity
                    if d.control == .humidifierTarget {
                        if !model.targetHumidityValid { warning = d.labels.invalidTarget }
                        else if model.targetHumidity > 60 { warning = d.labels.highTarget }
                    }
                    available = available && has(d.control == .humidifierMist ? model.config.mistLevelEntityId : model.config.targetHumidityEntityId)
                    dial?.configuration = dialConfiguration(model, d, interactive: available && !pending && !loading)
                case .humidifierTimer:
                    visible = model.powerOn
                    available = available && has(model.config.timerMinutesEntityId)
                    stepper?.show(model.timerMinutes)
                case .humidifierInfo:
                    if let info = d.info {
                        let projection = source.infoItem(info)
                        available = projection != nil
                        var item = projection ?? .init(title: d.node.title, icon: d.icon.drawn, value: d.labels.unavailable, tone: .unavailable)
                        item.title = d.node.title; item.icon = d.icon.drawn
                        if loading { item.value = d.labels.loading; item.tone = .neutral }
                        pill?.update(item)
                        pill?.accessibilityIdentifier = d.node.id
                    }
                case .humidifierScheduling:
                    on = source.schedules?.enabled == true
                    available = source.schedules.map { $0.ready && !$0.loading && !$0.toggleDisabled } ?? false
                default: available = false
                }
            }
        }
        // Keep conditional controls in place during initial load; never flash a success-shaped selection.
        isHidden = !loading && !visible
        choice?.selection = loading ? nil : selected
        choice?.isEnabled = available && !pending && !loading
        toggle?.show(on)
        toggle?.isEnabled = available && !pending && !loading
        stepper?.isUserInteractionEnabled = available && !pending && !loading
        let failed = source.map { source in source.commands.overlay.trackedKeys.contains { source.commands.isFailed($0) }
            || source.schedules?.error != nil || source.schedules?.commands.overlay.trackedKeys.contains { source.schedules?.commands.isFailed($0) == true } == true } ?? false
        if d.control == .fanRoom {
            refreshRoomTile(at: Date())
            updateRoomClock()
        } else if let tile {
            let reading: Bool
            if case .grill(let model) = source?.controller { reading = model.config.details.first { $0.entityId == d.detailEntityId }?.isSwitch != true }
            else { reading = false }
            let phase: TileActionSpec.Phase = !available || loading ? .unavailable : pending ? .inFlight : .ready
            let spec = TileActionSpec(id: "device", verb: on ? d.labels.off : d.labels.on, symbol: d.icon.drawn, isOn: on,
                                      phase: phase, feedback: .optimistic, isError: failed)
            let value = loading ? d.labels.loading : failed ? d.labels.failed : !available ? d.labels.unavailable : text ?? (on ? d.labels.on : d.labels.off)
            var model = UKGlassTileModel(title: d.node.title, subtitle: value, symbol: d.icon.drawn, family: family(d.family),
                                        isActive: on, isUnavailable: !available || loading, isError: failed,
                                        kind: reading ? .state : .toggle, identifier: d.node.id, announcesFailure: false)
            if !reading { model.behavior = .perform("device"); model.actions = [spec].items }
            model.reapplyGeneration = context.store.reapplyGeneration
            tile.configure(model, environment: UKTileEnvironment(context: context), animated: window != nil,
                           perform: { [weak self] _ in self?.send(.setOn(!on)) })
        }
        let message = loading ? d.labels.loading : failed ? d.labels.failed : warning ?? (!available ? d.labels.unavailable : nil)
        feedback.text = message
        feedback.textColor = failed || warning != nil ? UKInk.danger : UKDesignInk.secondary
        feedback.isHidden = message == nil
        if failed && !lastFailure { UIAccessibility.post(notification: .announcement, argument: "\(d.node.title), \(d.labels.failed)") }
        lastFailure = failed
        ukRemeasureContainers(includingSelf: true)
    }

    private func refreshRoomTile(at now: Date) {
        guard let d = definition, d.control == .fanRoom, let rail = d.fanRail, let tile, case .fan(let model) = source?.controller else { return }
        let loading = context.valuesPending
        let text: String
        if loading { text = d.labels.loading }
        else if model.commandFailed { text = d.labels.failed }
        else if !model.powerAvailable { text = d.labels.unavailable }
        else if !model.powerOn { text = d.labels.off }
        else if let seconds = model.remainingSeconds(at: now), seconds > 0 {
            text = "\(d.labels.action) \(BathroomFanController.formatRemaining(seconds))"
        } else { text = d.labels.on }
        var ordered = model.railSpecs
        if rail.order.first == "power" { ordered.reverse() }
        let specs = ordered.map { original in
            var spec = original.with(phase: loading ? .unavailable : source?.hasPendingIntent == true ? .inFlight : original.phase)
            if spec.id == "power" {
                spec.symbol = rail.powerIcon.drawn
                spec.verb = model.powerOn ? rail.powerOff : rail.powerOn
            } else if spec.id == "lock" {
                spec.symbol = model.locked ? rail.lockedIcon.drawn : rail.unlockedIcon.drawn
                spec.verb = model.locked ? rail.unlock : rail.lock
            }
            return spec
        }
        var spoken = [loading ? d.labels.loading : model.powerOn ? d.labels.on : d.labels.off]
        if !loading, model.powerOn, let seconds = model.remainingSeconds(at: now), seconds > 0 {
            spoken.append("\(d.labels.action) \(BathroomFanController.spokenCountdown(seconds))")
        }
        if !loading, model.lockAvailable, model.locked { spoken.append(rail.locked) }
        var tileModel = UKGlassTileModel(title: d.node.title, subtitle: text, symbol: d.icon.drawn, family: family(d.family),
                                         isActive: model.powerOn, isUnavailable: !model.powerAvailable || loading,
                                         isError: model.commandFailed, behavior: .navigate, actions: specs.items,
                                         identifier: d.node.id, spokenValue: !model.powerAvailable ? d.labels.unavailable : spoken.joined(separator: ", "),
                                         announcesFailure: false)
        tileModel.stateCandidates = [d.labels.on, d.labels.off, d.labels.failed, d.labels.unavailable, d.labels.loading]
        tileModel.reapplyGeneration = context.store.reapplyGeneration
        tile.configure(tileModel, environment: UKTileEnvironment(context: context), animated: window != nil,
                       action: { [weak self, weak tile] in
            guard let self, let tile, let action = self.definition?.navigationAction else { return }
            self.onNavigate?(action, tile)
        }, perform: { [weak self] id in
            guard let self else { return }
            do {
                guard let source = self.source, !self.context.valuesPending else { throw ServerUIRoomDeviceSource.Failure.unavailable }
                if id == "power" { try source.perform(.fanPower, intent: .setOn(!model.powerOn)) }
                else if id == "lock" { try source.perform(.fanLock, intent: .setOn(!model.locked)) }
                else { throw ServerUIRoomDeviceSource.Failure.invalidIntent }
            } catch {
                self.feedback.text = d.labels.failed
                self.feedback.isHidden = false
                UIAccessibility.post(notification: .announcement, argument: "\(d.node.title), \(d.labels.failed)")
                NSLog("ServerUI fan rail intent rejected")
            }
        })
    }

    private func updateRoomClock() {
        let shouldRun: Bool
        if definition?.control == .fanRoom, case .fan(let model) = source?.controller { shouldRun = window != nil && model.showsCountdown }
        else { shouldRun = false }
        if shouldRun != roomClockRunning {
            roomClockRunning = shouldRun
            roomClock.setRunning(shouldRun)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRoomClock()
    }

    private func dialConfiguration(_ model: HumidifierController, _ d: ServerUIRoomDeviceControl, interactive: Bool = false) -> ThermostatDialConfiguration {
        var configuration = d.control == .humidifierMist
            ? HumidifierDials.mist(model, title: d.node.title, actionLabel: d.labels.action, handleLabel: d.node.title,
                                  offText: d.labels.off, sleepText: d.labels.sleep)
            : HumidifierDials.target(model, title: d.node.title, actionLabel: d.labels.action, handleLabel: d.node.title)
        configuration.isInteractive = interactive && (d.control != .humidifierMist || model.canSetLevel)
        return configuration
    }

    private func send(_ intent: ServerUIRoomDeviceSource.Intent) {
        guard let d = definition else { return }
        do {
            guard !context.valuesPending, let source else { throw ServerUIRoomDeviceSource.Failure.unavailable }
            try source.perform(d.control, intent: intent, detailEntityId: d.detailEntityId)
        } catch {
            feedback.text = d.labels.failed
            feedback.isHidden = false
            UIAccessibility.post(notification: .announcement, argument: "\(d.node.title), \(d.labels.failed)")
            NSLog("ServerUI room-device intent rejected")
        }
    }

    private func family(_ family: ServerUIRoomDeviceControl.Family) -> ColorFamily? {
        switch family {
        case .neutral: nil
        case .air: .air
        case .security: .securityHome
        case .cooking: .cooking
        case .water: .water
        }
    }

    private func containsFirstResponder(_ view: UIView) -> Bool {
        view.isFirstResponder || view.subviews.contains { containsFirstResponder($0) }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        ceil(content.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }
}
#endif
