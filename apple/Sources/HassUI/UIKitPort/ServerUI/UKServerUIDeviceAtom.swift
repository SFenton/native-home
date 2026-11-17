#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Canonical device control bindings

/// A measured value/closure adapter, not a feature screen or a generic form renderer.
@MainActor
final class UKServerUIDeviceAtom: UIView, UKGridWrapping {
    private let column = UKColumnView(spacing: HassTokens.Spacing.s)
    private let notice = UILabel.uk(.subheadline, ink: UKInk.secondary)
    private let bag = UKObservationBag()
    private var definition: ServerUIDeviceControl?
    private var providerIdentity: ObjectIdentifier?
    private var content: UIView?
    private var refresh: () -> Void = {}
    private var localError: String?
    private var timeRows: [String: UKSprinklerTimeContent] = [:]

    /// The glyph of the custom-light manual toggle: the light pair.
    static let manualGlyph = "lightbulb.2"
    /// The ink of ``manualGlyph``: the lights family's.
    static var manualInk: UIColor { UIColor(ColorFamily.lights.glyphToken) }

    var hasActiveInteraction: Bool {
        func active(_ view: UIView) -> Bool {
            view.isFirstResponder || (view as? UIControl)?.isTracking == true
                || (view as? UKBrightnessTileView)?.hasActiveInteraction == true || view.subviews.contains(where: active)
        }
        return active(self)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(column)
        notice.numberOfLines = 0
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func bind(_ value: ServerUIDeviceControl, providers: ServerUIDeviceProviders, context: UKContext,
              presenter: @escaping () -> UIViewController?, navigate: @escaping (ServerUICompositionDocument.Action, UIView) -> Void,
              onError: @escaping (UKServerUIRendererError) -> Void) {
        let lights = providers.lights[value.sourceId], sprinkler = providers.sprinklers[value.sourceId]
        let identity = lights.map(ObjectIdentifier.init) ?? sprinkler.map(ObjectIdentifier.init)
        guard let identity else { onError(.init(code: .unavailableSource, pointer: "/document/dataSources")); return }
        if definition != value || providerIdentity != identity {
            definition = value
            providerIdentity = identity
            timeRows.removeAll()
            localError = nil
            let open: () -> Void = { [weak self] in
                guard let self, let action = value.action else { return }
                navigate(action, self)
            }
            if let lights { content = makeLight(value, source: lights, context: context, presenter: presenter, open: open) }
            else if let sprinkler { content = makeSprinkler(value, source: sprinkler, context: context, open: open) }
            if let content {
                let measured: UIView & UKGridMeasuring = (content as? (UIView & UKGridMeasuring)) ?? UKFittingBox(content)
                column.setViews([measured, UKLabelBox(notice)])
                content.accessibilityIdentifier = value.node.id
            }
        }
        bag.removeAll()
        bag.observe { [weak self] in
            guard let self else { return }
            refresh()
            column.views.first?.isHidden = content?.isHidden == true
            notice.text = localError ?? lights?.error ?? sprinkler?.error ?? sprinkler?.controller.errorMessage
                ?? value.zone.flatMap { sprinkler?.drafts[$0]?.error }
            notice.isHidden = notice.text == nil
            column.views.last?.isHidden = notice.isHidden
            ukRemeasureContainers(includingSelf: true)
        }
    }

    private func refuse() {
        localError = "This control changed or is unavailable. Try again."
        notice.text = localError
        notice.isHidden = false
        column.views.last?.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: localError)
        ukRemeasureContainers(includingSelf: true)
    }
    private func lightCall(_ source: ServerUICustomLightsSource, _ operation: @escaping @MainActor () async -> Bool) {
        let id = UUID().uuidString
        source.setEditing(id, true)
        Task { @MainActor [weak self] in
            defer { source.setEditing(id, false) }
            if !(await operation()) { self?.refuse() }
        }
    }

    // MARK: - Custom lights

    private func makeLight(_ value: ServerUIDeviceControl, source: ServerUICustomLightsSource, context: UKContext,
                           presenter: @escaping () -> UIViewController?, open: @escaping () -> Void) -> UIView {
        let id = value.entityId ?? ""
        switch value.kind {
        case .manual:
            // The light pair in the lights family's ink (the reference's `lightbulb.2`), not the hand.
            let row = UKSprinklerToggleContent(symbol: Self.manualGlyph, glyph: Self.manualInk)
            refresh = { [weak row, weak self] in
                row?.show(title: value.node.title, isOn: source.manual?.state == "on",
                          isEnabled: source.manual?.isUnavailable == false, identifier: value.node.id) { enabled in
                    self?.lightCall(source) { await source.setManual(enabled) }
                }
            }
            return row
        case .mode:
            let row = UKLightingModeButton(title: value.node.title) { [weak self] option in
                self?.lightCall(source) { await source.selectMode(option) }
            }
            refresh = { [weak row] in
                row?.configure(mode: source.mode?.state ?? "Unavailable", swatch: source.swatch, modes: source.modes)
                row?.isEnabled = source.manual?.state == "on" && source.mode?.isUnavailable == false
                row?.isHidden = source.manual?.state != "on"
            }
            return row
        case .brightness:
            let tile = UKBrightnessTileView(title: value.node.title, tint: UIColor(HassTokens.RGB.Tint.light), percent: 0)
            tile.environment = UKTileEnvironment(context: context)
            tile.identifier = value.node.id
            tile.words = UKLightWords(value.words)
            if value.action != nil { tile.onOpen = open }
            let send: (LightControl.Command) -> Void = { [weak self] command in
                do {
                    guard source.canEdit(id), let light = source.light(id) else { self?.refuse(); return }
                    try light.perform(command)
                } catch { self?.refuse() }
            }
            tile.onPower = { send(LightControl.power(id, on: $0)) }
            tile.onBrightness = { send(LightControl.brightness(id, percent: Double($0))) }
            refresh = { [weak tile] in
                let light = source.light(id), state = light?.shown
                tile?.update(fillTint: CustomLightsConfig.RGB(entity: state).map(UIColor.init(lightRGB:)),
                             percent: LightControl.percent(of: state), isUnavailable: !source.canEdit(id),
                             isFailed: light?.isFailed == true)
                tile?.isHidden = !source.isCustom
            }
            return tile
        case .color:
            let row = UKCustomLightColorRow { [weak self] color in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
                guard color.getRed(&r, green: &g, blue: &b, alpha: &alpha) else { self?.refuse(); return }
                source.setColor(.init(Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())), on: id)
            }
            refresh = { [weak row] in
                let state = source.store.entity(id).state
                row?.show(rgb: CustomLightsConfig.RGB(entity: state),
                          isEnabled: source.canEdit(id) && CustomLightsConfig.supportsColor(state),
                          holdsSelection: source.protectsPublication)
                row?.isHidden = !CustomLightsConfig.supportsColor(state)
            }
            return row
        case .copyColor:
            guard let from = value.copySourceId, let light = source.settings.lights.first(where: { $0.entityId == from }) else {
                return UKServerUIRejected.view("light member")
            }
            let view = UKOtherLightSwatchView(light: light) { [weak self] _ in
                self?.lightCall(source) { await source.copyColor(from: from, to: id) }
            }
            refresh = { [weak view] in
                let state = source.store.entity(from).state
                view?.show(rgb: source.canEdit(id) ? CustomLightsConfig.RGB(entity: state) : nil,
                           isUnavailable: state?.isUnavailable != false)
            }
            return view
        case .reset, .resetAll, .applyAll:
            let row = UKRoomsActionRow(title: value.node.title,
                symbol: value.kind == .applyAll ? "lightbulb.2" : "arrow.counterclockwise", identifier: value.node.id) { [weak self] in
                guard let self else { return }
                if value.kind == .reset { lightCall(source) { await source.resetLight(id) }; return }
                let action: ServerUICustomLightsSource.Confirmation.Action
                if value.kind == .applyAll {
                    guard let rgb = CustomLightsConfig.RGB(entity: source.store.entity(id).state) else { refuse(); return }
                    action = .applyColor(id, rgb)
                } else { action = .reset }
                guard let ticket = source.confirmation(action), let question = value.confirmation,
                      let presenter = presenter(), presenter.presentedViewController == nil else { refuse(); return }
                let alert = UIAlertController(title: question.title, message: question.message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: question.cancelLabel, style: .cancel))
                alert.addAction(UIAlertAction(title: question.confirmLabel, style: .default) { [weak self] _ in
                    self?.lightCall(source) { await source.confirm(ticket) }
                })
                presenter.present(alert, animated: true)
            }
            refresh = { [weak row] in
                row?.isEnabled = value.kind == .resetAll ? source.isCustom : source.canEdit(id)
                row?.isHidden = !source.isCustom
            }
            return row
        default: return UKServerUIRejected.view("custom-light control")
        }
    }

    // MARK: - Sprinklers

    private func makeSprinkler(_ value: ServerUIDeviceControl, source: ServerUISprinklerSource, context: UKContext,
                              open: @escaping () -> Void) -> UIView {
        let controller = source.controller, zone = value.zone ?? 0, format = SprinklerFormat()
        let send: (ServerUISprinklerSource.Intent) -> Void = { [weak self] intent in
            let task = source.start(intent)
            Task { @MainActor [weak self] in if !(await task.value) { self?.refuse() } }
        }
        switch value.kind {
        case .card:
            let card = UKSprinklerControllerCard(controller: controller, context: context, open: open, stop: { send(.stop) })
            card.onHeightChange = { [weak self] in self?.ukRemeasureContainers(includingSelf: true) }
            refresh = {}
            return card
        case .status:
            let pills = UKSprinklerPillGrid(kind: .sheet, valuesPending: context.valuesPending)
            refresh = { [weak pills] in pills?.show(controller.snapshot) }
            return pills
        case .waterBlocker:
            let label = UILabel.uk(.body, ink: UKInk.secondary)
            label.numberOfLines = 0
            refresh = { [weak label] in label?.text = source.wateringBlocker; label?.isHidden = source.wateringBlocker == nil }
            return label
        case .programEnabled:
            let row = UKSprinklerToggleContent(symbol: "calendar")
            refresh = { [weak row] in
                guard let program = controller.program(zone) else { return }
                row?.show(title: value.node.title, isOn: program.enabled,
                          isEnabled: program.available && !controller.hasPendingCommands, identifier: value.node.id) {
                    send(.enabled(zone, $0))
                }
            }
            return row
        case .rainDelay, .smartWatering:
            let row = UKSprinklerToggleContent(symbol: value.kind == .rainDelay ? "cloud.heavyrain" : "wand.and.stars")
            refresh = { [weak row] in
                row?.show(title: value.node.title, isOn: value.kind == .rainDelay ? controller.rainDelay : controller.smartWatering,
                          isEnabled: controller.snapshot.available && !controller.hasPendingCommands, identifier: value.node.id) {
                    send(value.kind == .rainDelay ? .rainDelay($0) : .smartWatering($0))
                }
            }
            return row
        case .zone:
            let row = UKSprinklerRowContent(), button = UKRowButton(row, onTap: open)
            refresh = { [weak row, weak button] in
                let state = controller.snapshot.zones[zone], active = controller.activeValve == state.config.valveEntityId
                row?.show(symbol: SprinklerStyle.symbol, isActive: active, title: state.name,
                          lines: [!state.available ? "Unavailable" : active ? "Watering" : "Closed", format.lastStart(state.lastRun)],
                          hint: "Water now", identifier: value.node.id, isEnabled: state.available)
                button?.isEnabled = state.available
            }
            return button
        case .program:
            let row = UKSprinklerProgramContent()
            refresh = { [weak row] in
                guard let program = controller.program(zone) else { return }
                let name = controller.snapshot.zones[zone].name
                row?.show(index: zone, name: format.programName(zone: name), isOn: program.enabled,
                          lines: [format.summary(program), format.details(program, zone: name)],
                          isAvailable: program.available && !controller.hasPendingCommands, open: open) { send(.enabled(zone, $0)) }
            }
            return row
        case .duration, .budget:
            let row = UKSprinklerStepperContent(symbol: value.kind == .duration ? "timer" : "drop")
            let draft = value.kind == .budget ? source.draft(zone) : nil
            refresh = { [weak row] in
                let number = draft?.value.budget ?? source.duration(zone), duration = value.kind == .duration
                row?.show(title: value.node.title, value: number, range: duration ? 1...60 : 0...200, step: duration ? 1 : 5,
                          valueText: duration ? "\(number) min" : "\(number)%", spokenValue: duration ? "\(number) minutes" : "\(number) percent",
                          isEnabled: draft?.busy != true, identifier: value.node.id) { next in
                    if let draft { draft.update { $0.budget = next } } else { source.setDuration(next, zone: zone) }
                }
            }
            return row
        case .presets:
            let row = UKSprinklerPresetsContent { source.setDuration($0, zone: zone) }
            refresh = { [weak row] in row?.show(selection: source.duration(zone), isEnabled: !controller.hasPendingCommands) }
            return row
        case .days:
            let row = UKSprinklerDayPickerRow()
            guard let draft = source.draft(zone) else { return UKServerUIRejected.view("sprinkler zone") }
            refresh = { [weak row] in
                row?.show(days: draft.value.days, isEnabled: !draft.busy) { day in
                    draft.update { if !$0.days.insert(day).inserted { $0.days.remove(day) } }
                }
            }
            return row
        case .times:
            guard let draft = source.draft(zone) else { return UKServerUIRejected.view("sprinkler zone") }
            return makeTimes(draft)
        case .stop, .start, .startProgram, .apply, .reload:
            let draft = [.apply, .reload].contains(value.kind) ? source.draft(zone) : nil
            let row = UKGreyCapsuleButton(title: value.node.title,
                systemImage: value.kind == .stop ? "stop.circle" : value.kind == .reload ? "arrow.clockwise" : "checkmark") { [weak self] in
                switch value.kind {
                case .stop: send(.stop)
                case .start: send(.water(zone))
                case .startProgram: send(.startProgram(zone))
                case .reload: draft?.reload()
                case .apply:
                    guard let draft else { self?.refuse(); return }
                    Task { @MainActor [weak self] in if !(await draft.save()) { self?.refuse() } }
                default: break
                }
            }
            refresh = { [weak row] in
                switch value.kind {
                case .stop: row?.isEnabled = controller.isWatering && !controller.hasPendingCommands
                case .start, .startProgram: row?.isEnabled = controller.canStartWatering && !controller.hasPendingCommands
                case .apply: row?.isEnabled = draft?.canSave == true
                case .reload: row?.isEnabled = draft?.busy == false && draft?.dirty == false
                default: break
                }
            }
            return row
        default: return UKServerUIRejected.view("sprinkler control")
        }
    }

    private func makeTimes(_ draft: ServerUISprinklerDraft) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        let add = UKRoomsActionRow(title: "Add Start Time", symbol: "plus.circle", identifier: "sprinkler.schedule.addTime") { draft.addTime() }
        stack.addArrangedSubview(add)
        refresh = { [weak self, weak stack, weak add] in
            guard let self, let stack, let add else { return }
            let values = draft.value.times
            let keys = Set(values.map(\.id))
            for (id, row) in timeRows where !keys.contains(id) {
                stack.removeArrangedSubview(row); row.removeFromSuperview(); timeRows[id] = nil
            }
            for (index, time) in values.enumerated() {
                let row = timeRows[time.id] ?? UKSprinklerTimeContent { draft.removeTime(time.id) }
                timeRows[time.id] = row
                if row.superview == nil { stack.insertArrangedSubview(row, at: index) }
                guard let date = SprinklerFormat.date(clock: time.value) else { refuse(); continue }
                row.show(index: index, date: date, canRemove: values.count > 1, isEnabled: !draft.busy) { date in
                    draft.update {
                        guard let index = $0.times.firstIndex(where: { $0.id == time.id }) else { return }
                        $0.times[index].value = SprinklerFormat.clock(from: date)
                    }
                }
            }
            add.isEnabled = !draft.busy && values.count < 4
        }
        return stack
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() { super.layoutSubviews(); column.frame = bounds }
}
#endif
