#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Bedroom primitive adapter

/// One configured atomic control. UIKit fields and canonical bedroom controls retain native input/AX behavior.
@MainActor
final class UKServerUIBedroomControl: UIStackView, UKGridMeasuring {
    private var definition: ServerUIBedroomControl?
    private var providerIdentity: ObjectIdentifier?
    private var sharedFeedback = false
    private let bag = UKObservationBag()
    private let errorLabel = UILabel.uk(.footnote, ink: UKDesignInk.primary)
    private var refresh: () -> Void = {}
    private var scopeVisible = false
    private var localError: String?
    private var now = Date()
    private var completed: () -> Void = {}
    private lazy var clock = UKEverySecond { [weak self] now in self?.now = now; self?.refresh() }

    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.s
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ value: ServerUIBedroomControl, provider: UKServerUIBedroomProvider,
                   presenter: @escaping () -> UIViewController?, onError: @escaping (UKServerUIRendererError) -> Void,
                   context: UKContext = .sheetPlaceholder,
                   sharedFeedback: Bool = false,
                   navigate: @escaping (ServerUICompositionDocument.Action, UIView) -> Void = { _, _ in },
                   completed: @escaping () -> Void = {}) {
        self.completed = completed
        guard definition != value || providerIdentity != provider.identity || self.sharedFeedback != sharedFeedback else { refresh(); return }
        definition = value
        providerIdentity = provider.identity
        self.sharedFeedback = sharedFeedback
        bag.removeAll()
        clock.setRunning(false)
        localError = nil
        let control: UIView
        if value.kind == .addAlarm {
            let button = UKPrimaryButton(value.label, systemImage: "plus") { [weak self] in
                guard let self, let action = value.action else { return }
                navigate(action, self)
            }
            refresh = { [weak button] in
                switch provider {
                case .bed(let bed): button?.isEnabled = bed.alarmsEditable
                case .wake(let wake): button?.isEnabled = wake.canEdit && wake.live.available && !wake.configurationPending
                case .draft: button?.isEnabled = false
                }
            }
            control = button
        } else if value.kind == .bedTile || value.kind == .wakeTile {
            let open: () -> Void = { [weak self] in
                guard let self, let action = value.action else { return }
                navigate(action, self)
            }
            switch provider {
            case .bed(let bed): control = UKBedroomTile.bedSide(bed, context: context, action: open)
            case .wake(let wake): control = UKBedroomTile.wakeLight(wake, context: context, action: open)
            case .draft: control = UKServerUIRejected.view("bedroom tile over a draft", pointer: "/document/dataSources", onError: onError)
            }
            refresh = {}
        } else {
            control = make(value, provider: provider, presenter: presenter, onError: onError)
        }
        control.accessibilityIdentifier = value.node.id + ".input"
        errorLabel.accessibilityIdentifier = value.node.id + ".error"
        ukSetArranged([control, errorLabel])
        bag.observe { [weak self] in
            guard let self else { return }
            refresh()
            if case .draft(let draft) = provider { control.isUserInteractionEnabled = !draft.busy && !draft.completed }
            errorLabel.text = localError ?? ((value.kind == .wakeSummary || value.kind == .feedback || sharedFeedback) ? nil
                : provider.error ?? (provider.available ? nil : value.unavailableText))
            errorLabel.isHidden = errorLabel.text == nil
            self.isHidden = control.isHidden && errorLabel.isHidden
            ukRemeasureContainers(includingSelf: true)
        }
    }

    func showUnavailable(_ value: ServerUIBedroomControl, message: String) {
        bag.removeAll()
        clock.setRunning(false)
        definition = nil
        providerIdentity = nil
        refresh = {}
        isHidden = false
        errorLabel.text = value.label + ": " + message
        errorLabel.isHidden = false
        errorLabel.accessibilityIdentifier = value.node.id + ".error"
        ukSetArranged([errorLabel])
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: gridHeight(forWidth: size.width))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { scopeVisible = false }
        refresh()
    }

    private func refused(_ onError: (UKServerUIRendererError) -> Void) {
        localError = "This control changed. Review it before trying again."
        errorLabel.text = localError
        errorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: localError)
        onError(.init(code: .interactionBlocked, pointer: "/document/dataSources"))
    }

    private func make(_ value: ServerUIBedroomControl, provider: UKServerUIBedroomProvider,
                      presenter: @escaping () -> UIViewController?,
                      onError: @escaping (UKServerUIRendererError) -> Void) -> UIView {
        switch provider {
        case .bed(let bed): return makeBed(value, bed: bed, presenter: presenter, onError: onError)
        case .wake(let wake): return makeWake(value, wake: wake)
        case .draft(let draft): return makeDraft(value, draft: draft, presenter: presenter, onError: onError)
        }
    }

    // MARK: - Bed controls

    private func makeBed(_ value: ServerUIBedroomControl, bed: BedSideController,
                         presenter: @escaping () -> UIViewController?,
                         onError: @escaping (UKServerUIRendererError) -> Void) -> UIView {
        switch value.kind {
        case .target:
            let dial = UKThermostatDial(BedDial.configuration(bed), size: .modal, surface: .sheet) { targets in
                if case .single(let level) = targets { bed.setTarget(level) }
            }
            refresh = { [weak self, weak dial] in
                var configuration = BedDial.configuration(bed)
                configuration.title = value.label
                configuration.readoutAccessibilityLabelOverride = configuration.readoutAccessibilityLabelOverride?
                    .replacingOccurrences(of: bed.config.title, with: value.label)
                dial?.configuration = configuration
                self?.showScope(value, bed: bed, source: dial, presenter: presenter, onError: onError)
            }
            return dial
        case .stage:
            guard let phase = value.parameter.flatMap(SchedulePhase.init(rawValue:)) else {
                return UKServerUIRejected.view("unknown schedule phase", pointer: "/document/dataSources", onError: onError)
            }
            let row = UKStageRowView(controller: bed, phase: phase, label: value.label)
            refresh = { [weak self, weak row] in self?.showScope(value, bed: bed, source: row, presenter: presenter, onError: onError) }
            return row
        case .reading:
            let row = UKBedroomRow(symbol: "", title: value.label, lines: [])
            refresh = { [weak row] in row?.setLines([Self.reading(value, bed: bed)]) }
            return row
        case .power:
            let button = UKGreyCapsuleButton(title: value.label, systemImage: "power", action: {})
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button, bed.canTogglePower else { return }
                guard bed.isOn else { bed.setPower(on: true); return }
                let ticket = bed.scope
                self.confirm(value, source: button, presenter: presenter, onError: onError) {
                    guard bed.canTogglePower, bed.isOn, bed.scope == ticket else { self.refused(onError); return }
                    bed.setPower(on: false)
                }
            }, for: .touchUpInside)
            refresh = { [weak button] in
                button?.setTitle(bed.canTogglePower ? (bed.isOn ? value.activeLabel ?? value.label : value.label) : value.unavailableText)
                button?.isHidden = !bed.scope.interactive
                button?.isEnabled = bed.canTogglePower
            }
            return button
        case .mode:
            let tile = UKGlassTileView(model: mode(value, bed: bed))
            tile.onPerform = { _ in
                guard bed.hotFlashAvailable, !bed.scope.readOnly else { return }
                if bed.hotFlashActive { bed.cancelHotFlash() } else { bed.startHotFlash() }
            }
            refresh = { [weak self, weak tile] in
                guard let self else { return }
                tile?.configure(mode(value, bed: bed))
                clock.setRunning(bed.hotFlashActive && window != nil)
            }
            return UKGridHost(tile)
        case .snooze, .stop:
            let button: UIControl = value.kind == .snooze
                ? UKGreyCapsuleButton(title: value.label, systemImage: "zzz", action: {})
                : UKPrimaryButton(value.label) {}
            button.addAction(UIAction { _ in
                guard !bed.alarmControlsReadOnly, bed.alarmState.isActive else { return }
                if value.kind == .snooze, bed.alarmState == .ringing { bed.snoozeAlarm() }
                else if value.kind == .stop { bed.stopAlarm() }
            }, for: .touchUpInside)
            refresh = { [weak button] in
                button?.isHidden = !bed.alarmState.isActive
                button?.isEnabled = !bed.alarmControlsReadOnly && (value.kind != .snooze || bed.alarmState == .ringing)
            }
            return button
        default: return UKServerUIRejected.view("control kind not served by a bed provider", pointer: "/document/dataSources", onError: onError)
        }
    }

    private func mode(_ value: ServerUIBedroomControl, bed: BedSideController) -> UKGlassTileModel {
        let shown = EntityState(entityId: bed.config.hotFlashActiveEntityId,
                                state: bed.hotFlashAvailable ? (bed.hotFlashActive ? "on" : "off") : "unavailable")
        let provider = HotFlashActions(bed.config, isReadOnly: bed.scope.readOnly)
        let active = bed.hotFlashCountdown(now: now).map { "\($0) \(value.countdownSuffix ?? "")" } ?? value.activeLabel
        return UKGlassTileModel(title: value.label, subtitle: bed.hotFlashAvailable
            ? (bed.hotFlashActive ? active : value.inactiveLabel) : value.unavailableText,
            symbol: value.icon?.drawn ?? "", family: modeFamily(value.family), isActive: bed.hotFlashActive,
            isUnavailable: !bed.hotFlashAvailable || bed.scope.readOnly,
            behavior: TileBehavior(.action(1), primary: HotFlashActions.actionId),
            actions: provider.actions(for: shown).items, identifier: value.node.id)
    }

    private func modeFamily(_ family: ServerUIBedroomControl.ModeFamily?) -> ColorFamily? {
        switch family {
        case .neutral, nil: nil
        case .lights: .lights
        case .cooling: .cooling
        case .heating: .heating
        }
    }

    private static func reading(_ value: ServerUIBedroomControl, bed: BedSideController) -> String {
        let metric = value.parameter
        let unavailable = value.unavailableText
        let config = bed.config
        if metric == "current-temperature" { return bed.currentTemperature.map { BedFormat.temperature($0) } ?? unavailable }
        let ids = ["loop-temperature": config.pumpLoopTemperatureEntityId, "pump-rpm": config.pumpRpmEntityId,
                   "heart-rate": config.heartRateEntityId, "breathing": config.breathingRateEntityId, "hrv": config.hrvEntityId]
        if metric == "pump-status" {
            let states = [config.pumpClogEntityId, config.pumpStallEntityId].compactMap { bed.store.entity($0).state }
            guard states.count == 2, !states.contains(where: \.isUnavailable) else { return unavailable }
            return (states.contains { $0.state == "on" } ? value.activeLabel : value.inactiveLabel) ?? unavailable
        }
        guard let id = metric.flatMap({ ids[$0] }), let state = bed.store.entity(id).state, !state.isUnavailable else { return unavailable }
        return BedFormat.metric(state)
    }

    // MARK: - Wake controls

    private func makeWake(_ value: ServerUIBedroomControl, wake: WakeLightController) -> UIView {
        if value.kind == .wakeSummary {
            refresh = {}
            return UKWakeStatusView(controller: wake, identifier: value.node.id, unavailableText: value.unavailableText)
        }
        if value.kind == .wakeStop {
            if let episode = value.episode {
                let card = UKWakeEpisodeView(controller: wake, stopLabel: value.label, episode: episode,
                                             identifier: value.node.id + ".stop")
                refresh = { [weak card] in card?.refresh() }
                return card
            }
            let button = UKFilledButton(title: value.label, fill: UKDeviceStyle.danger) {
                guard wake.live.available, !wake.stopping, wake.live.episodeRef != nil else { return }
                Task { await wake.endEpisode() }
            }
            refresh = { [weak button] in
                button?.isHidden = wake.snapshot.activeOccurrences.isEmpty
                button?.isEnabled = wake.live.available && !wake.stopping
            }
            return button
        }
        let labels = Dictionary(uniqueKeysWithValues: value.options.map { ($0.value, $0.label) })
        let grid = UKChoiceGrid(title: value.label, options: value.options.map(\.value),
                               label: { labels[$0] ?? $0 }, identifier: value.node.id) { selected in
            guard let minutes = Int(selected), wake.canEdit, wake.live.available, !wake.configurationPending,
                  value.kind != .wakeHold || wake.snapshot.contractVersion >= 6 else { return }
            var next = wake.snapshot.defaults
            if value.kind == .wakeRamp {
                guard next.rampMinutes != minutes else { return }
                next.rampMinutes = minutes
            } else {
                guard next.postWakeHoldMinutes != minutes else { return }
                next.postWakeHoldMinutes = minutes
            }
            Task { await wake.updateDefaults(next) }
        }
        let note = value.showsExplanation ? UKDeviceText.footnote("") : nil
        refresh = { [weak grid, weak note] in
            let defaults = wake.snapshot.defaults
            grid?.show(selection: String(value.kind == .wakeRamp ? defaults.rampMinutes : defaults.postWakeHoldMinutes),
                       isDisabled: !wake.canEdit || !wake.live.available || wake.configurationPending
                        || (value.kind == .wakeHold && wake.snapshot.contractVersion < 6))
            note?.text = WakeLight.postWakeHoldExplanation(contractVersion: wake.snapshot.contractVersion)
        }
        if let note {
            let column = UIStackView(arrangedSubviews: [grid, note])
            column.axis = .vertical
            column.spacing = HassTokens.Spacing.xl
            return column
        }
        return grid
    }

    // MARK: - Retained draft inputs

    private func makeDraft(_ value: ServerUIBedroomControl, draft: ServerUIBedroomDraft,
                           presenter: @escaping () -> UIViewController?,
                           onError: @escaping (UKServerUIRendererError) -> Void) -> UIView {
        func edit(_ bed: (inout BedSideController.AlarmDraft) -> Void, _ wake: (inout WakeLight.Alarm) -> Void) {
            guard !draft.busy else { return }
            switch draft.value {
            case .bed(var alarm): bed(&alarm); draft.update { $0 = .bed(alarm) }
            case .wake(var alarm): wake(&alarm); draft.update { $0 = .wake(alarm) }
            }
        }
        switch value.kind {
        case .feedback:
            let column = UIStackView()
            column.axis = .vertical
            column.spacing = value.parameter == "problems" ? HassTokens.Spacing.s : 0
            var previous: [String]?
            refresh = { [weak column] in
                let messages = value.parameter == "error" ? draft.feedbackError.map { [$0] } ?? []
                    : (draft.dirty || draft.isNew ? draft.problems : [])
                guard previous != messages else { return }
                previous = messages
                column?.ukSetArranged(messages.map {
                    value.parameter == "error" ? UKInlineAlertView($0, severity: .error) : UKInlineAlertView($0)
                })
            }
            return column
        case .bedTarget:
            guard let side = value.parameter.flatMap(BedSide.init(rawValue:)) else {
                return UKServerUIRejected.view("unknown bed side", pointer: "/document/dataSources", onError: onError)
            }
            let line = UKToggleLine(title: value.label, toggle: UISwitch(), identifier: value.node.id)
            line.toggle.addAction(UIAction { [weak line] _ in
                guard let on = line?.toggle.isOn, draft.bedTargets.contains(where: { $0.side == side && $0.available }) else { return }
                edit({ _ in }, {
                    if on && !$0.bedSides.contains(side) { $0.bedSides.append(side) }
                    if !on { $0.bedSides.removeAll { $0 == side } }
                })
            }, for: .valueChanged)
            refresh = { [weak line] in
                let target = draft.bedTargets.first { $0.side == side }
                line?.isHidden = !draft.isNew || target == nil
                line?.toggle.isEnabled = !draft.busy && target?.available == true
                line?.toggle.isOn = Self.wake(draft)?.bedSides.contains(side) == true
            }
            return line
        case .weekdays:
            let spoken = Dictionary(uniqueKeysWithValues: value.options.map { ($0.value, $0.accessibilityLabel ?? $0.label) })
            let picker = UKWeekdayPicker(title: value.label, days: Self.days(draft), choices: value.options.compactMap {
                guard let day = Weekday(rawValue: $0.value) else { return nil }; return (day, $0.label)
            }, identifier: value.node.id, accessibilityLabel: { day, label in spoken[day.rawValue] ?? label }) {
                selected in edit({ $0.days = selected }, { $0.weekdays = selected })
            }
            refresh = { [weak picker] in
                picker?.show(days: Self.days(draft))
                picker?.isUserInteractionEnabled = !draft.busy
                switch draft.value {
                case .bed(let alarm): picker?.isHidden = alarm.lockedDay != nil
                case .wake(let alarm): picker?.isHidden = alarm.kind != .weekly
                }
            }
            return picker
        case .time:
            let picker = UKClockTimeField.make(title: value.label, time: Self.time(draft), identifier: value.node.id) { selected in
                edit({ $0.time = selected }, { $0.localTime = selected })
            }
            refresh = { [weak picker] in
                picker?.isUserInteractionEnabled = !draft.busy
                picker?.picker.date = ClockTimeField.date(Self.time(draft))
            }
            return picker
        case .enabled, .wakeLink:
            let line = UKToggleLine(title: value.label, toggle: UISwitch(), identifier: value.node.id)
            line.toggle.addAction(UIAction { [weak line] _ in
                guard let selected = line?.toggle.isOn else { return }
                edit({ if value.kind == .enabled { $0.enabled = selected } else { $0.wakeLightEnabled = selected } },
                     { $0.enabled = selected })
            }, for: .valueChanged)
            refresh = { [weak line] in
                line?.toggle.isEnabled = !draft.busy
                switch draft.value {
                case .bed(let alarm): line?.toggle.isOn = value.kind == .enabled ? alarm.enabled : alarm.wakeLightEnabled
                case .wake(let alarm): line?.toggle.isOn = alarm.enabled
                }
            }
            return line
        case .name:
            let field = UKOutlinedTextField(placeholder: value.label, text: Self.wake(draft)?.label ?? "", limit: 40, identifier: value.node.id)
            field.onChange = { selected in edit({ _ in }, { $0.label = selected }) }
            refresh = { [weak field] in
                field?.isUserInteractionEnabled = !draft.busy
                if field?.isFirstResponder != true { field?.show(Self.wake(draft)?.label ?? "") }
            }
            return value.showsHeading ? UKBedroomField.labeled(value.label, field: field) : field
        case .alarmKind:
            let labels = Dictionary(uniqueKeysWithValues: value.options.map { ($0.value, $0.label) })
            let choice = UKSegmentedChoice(label: value.label, options: value.options.map(\.value),
                title: { labels[$0] ?? $0 }, selection: Self.wake(draft)?.kind.rawValue ?? "weekly", identifier: value.node.id) { selected in
                    edit({ _ in }, { alarm in
                        guard let kind = WakeLight.Kind(rawValue: selected) else { return }
                        alarm.kind = kind
                        if kind == .once, alarm.date == nil {
                            alarm.date = WakeLight.dateString(Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
                        }
                        if kind == .weekly, alarm.weekdays.isEmpty { alarm.weekdays = Weekday.workdays }
                    })
                }
            refresh = { [weak choice] in
                choice?.selection = Self.wake(draft)?.kind.rawValue ?? "weekly"
                choice?.isUserInteractionEnabled = !draft.busy
            }
            return value.showsHeading ? UKBedroomField.labeled(value.label, field: choice) : choice
        case .ramp:
            let labels = Dictionary(uniqueKeysWithValues: value.options.map { ($0.value, $0.label) })
            let grid = UKChoiceGrid(title: value.label, options: value.options.map(\.value),
                                   label: { labels[$0] ?? $0 }, identifier: value.node.id) { selected in
                edit({ _ in }, { alarm in
                    alarm.rampMinutes = Int(selected) ?? alarm.rampMinutes
                })
            }
            refresh = { [weak grid] in
                let alarm = Self.wake(draft)
                grid?.show(selection: String(alarm?.rampMinutes ?? 0),
                           isDisabled: draft.busy)
            }
            return grid
        case .date:
            let picker = UKDatePickerLine(title: value.label, mode: .date,
                date: Self.wake(draft)?.date.flatMap { WakeLight.date($0) } ?? .now, identifier: value.node.id) { selected in
                    edit({ _ in }, { $0.date = WakeLight.dateString(selected) })
                }
            refresh = { [weak picker] in
                picker?.isHidden = Self.wake(draft)?.kind != .once
                picker?.isUserInteractionEnabled = !draft.busy
                picker?.picker.date = Self.wake(draft)?.date.flatMap { WakeLight.date($0) } ?? .now
            }
            return picker
        case .save, .delete, .reload:
            let button: UIControl
            if value.kind == .delete { button = UKFilledButton(title: value.label, fill: UKDeviceStyle.danger) {} }
            else if value.kind == .reload { button = UKBedroomField.reloadButton(title: value.label, identifier: value.node.id) }
            else { button = UKPrimaryButton(value.label) {} }
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button else { return }
                switch value.kind {
                case .save: Task { if await draft.save() { self.completed() } }
                case .reload: _ = draft.reload()
                case .delete:
                    let ticket = draft.value
                    self.confirm(value, source: button, presenter: presenter, alarm: draft.openedWakeAlarm, onError: onError) {
                        Task { if await draft.delete(confirming: ticket) { self.completed() } }
                    }
                default: break
                }
            }, for: .touchUpInside)
            refresh = { [weak button] in
                button?.isEnabled = value.kind == .save ? draft.canSave : value.kind == .delete ? draft.canDelete : !draft.busy
                if value.kind == .reload { button?.isHidden = !draft.needsReload }
                if value.kind == .delete { button?.isHidden = draft.isNew }
                if value.kind == .save { (button as? UKPrimaryButton)?.title = draft.busy ? "Saving…" : value.label }
            }
            return button
        default: return UKServerUIRejected.view("control kind not served by a draft", pointer: "/document/dataSources", onError: onError)
        }
    }

    private static func days(_ draft: ServerUIBedroomDraft) -> [Weekday] {
        switch draft.value { case .bed(let alarm): alarm.days; case .wake(let alarm): alarm.weekdays }
    }
    private static func time(_ draft: ServerUIBedroomDraft) -> String {
        switch draft.value { case .bed(let alarm): alarm.time; case .wake(let alarm): alarm.localTime }
    }
    private static func wake(_ draft: ServerUIBedroomDraft) -> WakeLight.Alarm? {
        if case .wake(let alarm) = draft.value { alarm } else { nil }
    }

    // MARK: - Mandatory native questions

    private func confirm(_ value: ServerUIBedroomControl, source: UIView, presenter: () -> UIViewController?,
                         alarm: WakeLight.Alarm? = nil, onError: (UKServerUIRendererError) -> Void, action: @escaping () -> Void) {
        guard let question = value.confirmation, let host = presenter(), host.presentedViewController == nil else {
            refused(onError); return
        }
        let message: String
        if question.messageFormat != nil {
            guard let alarm else { refused(onError); return }
            message = question.message(for: alarm)
        } else { message = question.message }
        let alert = UIAlertController(title: question.title, message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: question.confirmLabel, style: .destructive) { _ in action() })
        alert.addAction(UIAlertAction(title: question.cancelLabel, style: .cancel))
        UKPopoverSource.view(source).attach(to: alert.popoverPresentationController, fallback: source)
        host.ukPresent(alert, identifiers: [
            question.confirmLabel: value.node.id + ".confirm",
            question.cancelLabel: value.node.id + ".cancel"
        ])
    }

    private func showScope(_ value: ServerUIBedroomControl, bed: BedSideController, source: UIView?,
                           presenter: () -> UIViewController?, onError: @escaping (UKServerUIRendererError) -> Void) {
        guard !scopeVisible, let request = bed.scopePrompt, let question = value.scope,
              let source, let host = presenter(), host.viewIfLoaded?.window != nil, host.presentedViewController == nil else { return }
        scopeVisible = true
        let scope = bed.scope
        let alert = UIAlertController(title: question.title, message: question.message, preferredStyle: .actionSheet)
        for (label, choice) in [(question.tonightLabel, BedTemperatureScope.tonight), (question.allNightsLabel, .allNights)] {
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.scopeVisible = false
                guard bed.scopePrompt == request, bed.scope == scope else { self?.refused(onError); return }
                bed.chooseScope(choice)
            })
        }
        alert.addAction(UIAlertAction(title: question.cancelLabel, style: .cancel) { [weak self] _ in
            self?.scopeVisible = false
            if bed.scopePrompt == request { bed.dismissScope() }
        })
        UKPopoverSource.view(source).attach(to: alert.popoverPresentationController, fallback: source)
        host.ukPresent(alert, identifiers: [
            question.tonightLabel: value.node.id + ".scope.tonight",
            question.allNightsLabel: value.node.id + ".scope.allNights",
            question.cancelLabel: value.node.id + ".scope.cancel"
        ])
    }
}
#endif
