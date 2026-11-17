#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Atomic climate presentation

/// Binds values and typed intents to canonical native controls, never a feature controller.
@MainActor
final class UKServerUIClimateControl: UIView, UKGridWrapping {
    private let column = UIStackView()
    private let bag = UKObservationBag()
    private let failure = TransientFailure()
    private var definition: ServerUIClimateControl?
    private var adapter: ServerUIClimateAdapter?
    private var dial: UKThermostatDial?
    private var row: UKRowView?
    private var toggle: UKControllerToggle?
    private var check: UKCheckRow?
    private var picker: UKHubPicker?
    private var hub: UKThermostatHubPill?
    private var choices: [(ServerUIClimateControl.Choice, UKClimateOptionButton, UKClimateOptionRow)] = []
    private var pinnedTarget: String?
    private var rejections = 0
    private var noticeView: UIView?
    private var noticeText: String?
    private var link: UKRowButton?
    private var roomTile: UKGlassTileView?
    private var navigate: (ServerUICompositionDocument.Action) -> Void = { _ in }
    private var statusText: UILabel?
    private var statusHolder: UIView?
    private var paragraphs: UIStackView?
    private var paragraphText: String?

    init() {
        super.init(frame: .zero)
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.s
        addSubview(column)
        column.ukPin(to: self)
        isAccessibilityElement = false
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        if let roomTile { return roomTile.gridHeight(forWidth: width) }
        return ceil(column.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: gridHeight(forWidth: size.width))
    }

    override func layoutSubviews() { super.layoutSubviews(); roomTile?.frame = bounds }

    func configure(_ control: ServerUIClimateControl, adapter: ServerUIClimateAdapter, context: UKContext,
                   navigate: @escaping (ServerUICompositionDocument.Action) -> Void = { _ in }) {
        let changed = definition != control || self.adapter !== adapter
        definition = control
        self.adapter = adapter
        self.navigate = navigate
        bag.removeAll()
        if changed {
            column.arrangedSubviews.forEach { column.removeArrangedSubview($0); $0.removeFromSuperview() }
            dial = nil; row = nil; toggle = nil; check = nil; picker = nil; hub = nil; choices = []
            noticeView = nil; noticeText = nil
            link = nil; roomTile?.removeFromSuperview(); roomTile = nil
            statusText = nil; statusHolder = nil; paragraphs = nil; paragraphText = nil
            column.isHidden = control.props.kind == .roomTile
            build(control, adapter: adapter, context: context)
            if ![.roomTile, .link, .status].contains(control.props.kind) { column.addArrangedSubview(UKFailureCaption(failure)) }
        }
        bag.observe { [weak self] in self?.sync(context: context) }
    }

    private func build(_ control: ServerUIClimateControl, adapter: ServerUIClimateAdapter, context: UKContext) {
        let props = control.props
        switch props.kind {
        case .notice: break
        case .status where props.presentation == .headline || props.presentation == .metric || props.presentation == .paragraphs:
            let content: UIView
            if props.presentation == .paragraphs {
                let stack = UIStackView()
                stack.axis = .vertical
                stack.spacing = HassTokens.Spacing.s
                stack.accessibilityContainerType = .semanticGroup
                paragraphs = stack
                content = stack
            } else {
                let value = UILabel.uk(props.presentation == .headline ? .headline : .body,
                    weight: props.presentation == .headline ? .semibold : .regular,
                    monospacedDigit: props.presentation == .metric, ink: UKDesignInk.primary,
                    alignment: props.presentation == .metric ? .right : .natural)
                statusText = value
                if props.presentation == .metric {
                    let title = UILabel.uk(.body, ink: UKDesignInk.primary)
                    title.text = control.node.title
                    title.setContentHuggingPriority(.required, for: .horizontal)
                    let stack = UIStackView(arrangedSubviews: [title, value])
                    stack.axis = .horizontal
                    stack.alignment = .firstBaseline
                    stack.spacing = HassTokens.Spacing.m
                    content = stack
                } else { content = value }
            }
            let holder = UKClimateRows.padded(content)
            holder.accessibilityIdentifier = control.node.id
            if props.presentation == .metric {
                holder.isAccessibilityElement = true
                statusHolder = holder
            }
            column.addArrangedSubview(holder)
        case .roomTile:
            let tile = UKGlassTileView(model: .init(title: control.node.title, symbol: ServerUISymbolFallback.resolve(props.icon), isActive: false, identifier: control.node.id),
                                      environment: UKTileEnvironment(context: context))
            roomTile = tile
            addSubview(tile)
        case .check:
            let title = UILabel.uk(.body, ink: UKDesignInk.primary)
            title.text = control.node.title
            let check = UKCheckRow(content: title)
            check.toggle.accessibilityLabel = control.node.title
            check.toggle.accessibilityIdentifier = control.node.id
            check.onToggle = { [weak self, weak adapter] in
                guard let self, let adapter else { return }
                self.send(.toggle(adapter.target), target: adapter.target, expected: control)
            }
            self.check = check
            column.addArrangedSubview(check)
        case .hub:
            guard let settings = props.hub else { return }
            let hub = UKThermostatHubPill(
                title: control.node.title, symbol: ServerUISymbolFallback.resolve(props.icon), identifier: control.node.id,
                modeLabel: settings.modeLabel, fanLabel: settings.fanLabel,
                onMode: { [weak self, weak adapter] value in
                    guard let self, let adapter else { return }
                    self.send(.mode(adapter.target, value), target: adapter.target, expected: control)
                }, onFan: { [weak self, weak adapter] value in
                    guard let self, let adapter else { return }
                    self.send(.fan(adapter.target, value), target: adapter.target, expected: control)
                })
            self.hub = hub
            column.addArrangedSubview(hub)
        case .dial:
            guard let settings = props.dial else { return }
            let size: UKThermostatDial.Size
            switch settings.size { case .page: size = .page; case .modal: size = .modal; case .compact: size = .compact }
            let dial = UKThermostatDial(ThermostatDialConfiguration(entity: adapter.entity, title: control.node.title),
                                       size: size, surface: context.surface) { [weak self] in self?.commit($0) }
            dial.onEditingChanged = { [weak self, weak adapter] editing in
                adapter?.setEditing(editing, controlID: control.node.id)
                if !editing { self?.sync(context: context) }
            }
            self.dial = dial
            column.addArrangedSubview(dial)
        case .options:
            for choice in props.choices ?? [] {
                let option = UKClimateOptionRow(title: choice.label, detail: choice.detail, symbol: ServerUISymbolFallback.resolve(choice.icon),
                                                identifier: control.node.id + "." + choice.value, surface: context.surface)
                let button = UKClimateOptionButton(option)
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
                button.accessibilityIdentifier = control.node.id + "." + choice.value
                button.accessibilityLabel = [choice.label, choice.detail].filter { !$0.isEmpty }.joined(separator: ", ")
                button.onTap = { [weak self, weak adapter] in
                    guard let self, let adapter else { return }
                    self.send(.select(adapter.target, choice.value), target: adapter.target, expected: control)
                }
                choices.append((choice, button, option))
                column.addArrangedSubview(button)
            }
            let row = UKRowView(.init(control.node.title, symbol: ServerUISymbolFallback.resolve(props.icon), style: .form), surface: context.surface)
            self.row = row
            column.addArrangedSubview(row)
        default:
            let row = UKRowView(.init(control.node.title, symbol: ServerUISymbolFallback.resolve(props.icon), showsChevron: props.kind == .link,
                                     style: .form), surface: context.surface)
            self.row = row
            switch props.kind {
            case .toggle, .explicitSwitch:
                let toggle = UKControllerToggle(isOn: false) { [weak self, weak adapter] on in
                    guard let self, let adapter else { return }
                    self.send(props.kind == .toggle ? .toggle(adapter.target) : .setSwitch(adapter.target, on),
                              target: adapter.target, expected: control)
                }
                toggle.accessibilityLabel = control.node.title
                toggle.accessibilityHint = props.hint
                toggle.accessibilityIdentifier = control.node.id
                row.isTextAccessible = false
                row.setAccessory(toggle)
                self.toggle = toggle
            case .mode, .fan, .preset:
                let picker = UKHubPicker(label: control.node.title, identifier: control.node.id) { [weak self, weak adapter] option in
                    guard let self, let adapter else { return }
                    let target = self.pinnedTarget ?? adapter.target
                    let intent: ClimateConfiguredIntent
                    switch props.kind {
                    case .mode: intent = .mode(target, option)
                    case .fan: intent = .fan(target, option)
                    default: intent = .preset(target, option)
                    }
                    self.send(intent, target: target, expected: control)
                }
                row.setAccessory(picker)
                self.picker = picker
            default:
                row.isAccessibilityElement = true
                row.accessibilityTraits = .staticText
                row.accessibilityIdentifier = control.node.id
            }
            if props.kind == .link {
                let button = UKRowButton(row)
                button.accessibilityIdentifier = control.node.id
                button.onTap = { [weak self] in self?.open(expected: control) }
                link = button
                column.addArrangedSubview(button)
            } else {
                column.addArrangedSubview(row)
            }
        }
    }

    private func sync(context: UKContext) {
        guard let definition, let adapter else { return }
        let props = definition.props
        let pending = context.valuesPending
        let enabled = !pending && adapter.isEnabled
        if let notice = props.notice {
            let text = pending ? props.loadingText : adapter.notice(notice)
            isHidden = text == nil
            if text != noticeText {
                if let noticeView { column.removeArrangedSubview(noticeView); noticeView.removeFromSuperview() }
                noticeText = text
                if let text {
                    let view: UIView
                    if context.surface == .sheet {
                        let row = UKRowView(.init(text, symbol: ServerUISymbolFallback.resolve(props.icon), style: .form), surface: .sheet)
                        row.isAccessibilityElement = true
                        row.accessibilityLabel = text
                        row.accessibilityIdentifier = definition.node.id
                        view = row
                    } else {
                        view = UKClimateNoticeView(text: text, symbol: ServerUISymbolFallback.resolve(props.icon), isWarning: notice.isWarning, identifier: definition.node.id)
                    }
                    noticeView = view
                    column.insertArrangedSubview(view, at: 0)
                }
            }
        } else {
            isHidden = props.kind == .check && (adapter.configuration.trackingGate?.trackedEntityId).flatMap(adapter.shown) == "on"
        }
        if dial?.isEditing != true {
            let changedTarget = pinnedTarget != nil && pinnedTarget != adapter.target
            pinnedTarget = adapter.target
            if let dial, let settings = props.dial {
                var value = ThermostatDialConfiguration(entity: adapter.entity, title: definition.node.title)
                value.min = settings.minimum; value.max = settings.maximum; value.step = settings.step; value.unit = settings.unit
                let reportedUnit = adapter.entity?.attributes["temperature_unit"]?.string
                    ?? adapter.entity?.attributes["unit_of_measurement"]?.string
                let matchingUnit = reportedUnit == nil || reportedUnit == settings.unit
                value.isUnavailable = pending || adapter.entity?.isUnavailable != false || !matchingUnit
                value.isInteractive = enabled && matchingUnit
                if let action = adapter.configuration.actionEntityId.flatMap(adapter.lookup) {
                    value.action = ClimateLogic.hvacAction(action)
                }
                dial.configuration = value
                if changedTarget { dial.resetEdits() }
            }
        }
        toggle?.show(adapter.shown(adapter.target) == "on")
        toggle?.isEnabled = enabled
        toggle?.accessibilityHint = enabled ? props.hint : props.unavailableText
        if let check {
            let selected = adapter.shown(adapter.target) == "on"
            check.setChecked(selected, checkedTint: UKInk.action, uncheckedTint: UKDesignSurface.secondaryInSheet, dimmed: !enabled)
            check.toggle.isEnabled = enabled
            check.toggle.accessibilityHint = enabled ? props.hint : props.unavailableText
            check.toggle.accessibilityTraits = !enabled ? [.button, .notEnabled] : selected ? [.button, .selected] : .button
        }
        var subtitle = pending ? props.loadingText : adapter.entity?.isUnavailable != false ? props.unavailableText : props.hint
        if let status = props.status, !pending {
            subtitle = adapter.status(status) ?? props.unavailableText
        }
        if props.kind == .explicitSwitch, props.status != nil {
            toggle?.accessibilityLabel = "\(definition.node.title), \(subtitle)"
        }
        if let row {
            var content = row.rowContent
            content.subtitle = subtitle
            row.update(content, accessory: row.accessory)
            row.accessibilityLabel = definition.node.title
            row.accessibilityValue = subtitle
        }
        statusText?.text = props.presentation == .headline ? "\(definition.node.title): \(subtitle)" : subtitle
        statusHolder?.accessibilityLabel = definition.node.title
        statusHolder?.accessibilityValue = subtitle
        if let paragraphs, paragraphText != subtitle {
            paragraphs.arrangedSubviews.forEach { paragraphs.removeArrangedSubview($0); $0.removeFromSuperview() }
            for (index, text) in subtitle.components(separatedBy: "\n\n").filter({ !$0.isEmpty }).enumerated() {
                let label = UILabel.uk(.body, ink: UKDesignInk.primary)
                label.text = text
                label.accessibilityIdentifier = definition.node.id + ".paragraph.\(index)"
                paragraphs.addArrangedSubview(label)
            }
            paragraphText = subtitle
        }
        if let link {
            link.isEnabled = !pending && adapter.navigationEnabled(props)
            link.accessibilityLabel = definition.node.title
            link.accessibilityValue = subtitle
        }
        if let roomTile {
            var environment = UKTileEnvironment(context: context)
            environment.layout = .anchoredBottom
            environment.titleLines = 2
            let model = UKGlassTileModel(title: definition.node.title,
                subtitle: pending ? props.loadingText : adapter.roomSubtitle ?? props.unavailableText,
                symbol: ServerUISymbolFallback.resolve(props.icon), family: .neutral, fillRGB: RoomPalette.fill(at: props.paletteIndex),
                isActive: false, kind: .navigate, identifier: definition.node.id)
            roomTile.configure(model, environment: environment) { [weak self] in self?.open(expected: definition) }
        }
        let supported = adapter.choices(props)
        if props.kind == .options, supported.isEmpty, let row {
            var content = row.rowContent
            content.subtitle = pending ? props.loadingText : props.unavailableText
            row.update(content, accessory: nil)
            row.accessibilityValue = content.subtitle
        }
        if let hub, let settings = props.hub {
            let mode = adapter.selected(.mode), fan = adapter.selected(.fan)
            let modeChoice = settings.modes.first { $0.value == mode }
            let fanChoice = settings.fans.first { $0.value == fan }
            let state = pending ? props.loadingText : modeChoice?.label ?? props.unavailableText
            hub.update(state: state, action: ClimateLogic.hvacAction(adapter.entity),
                       modes: adapter.choices(settings.modes, kind: .mode).map { .init(value: $0.value, label: $0.label, icon: ServerUISymbolFallback.resolve($0.icon)) },
                       mode: mode, modeSymbol: modeChoice.map { ServerUISymbolFallback.resolve($0.icon) },
                       fans: adapter.choices(settings.fans, kind: .fan).map { .init(value: $0.value, label: $0.label, icon: ServerUISymbolFallback.resolve($0.icon)) },
                       fan: fan, fanText: fanChoice?.label ?? props.unavailableText, fanSymbol: fanChoice.map { ServerUISymbolFallback.resolve($0.icon) },
                       enabled: enabled, systemIcons: true)
        }
        if let picker {
            let selected = adapter.selected(props.kind)
            let value = pending ? props.loadingText : props.choices?.first { $0.value == selected }?.label ?? props.unavailableText
            picker.update(value: value, symbol: nil,
                          options: supported.map { .init(value: $0.value, label: $0.label, icon: nil, description: $0.detail) },
                          selected: selected)
            // Use authored SF symbols rather than the legacy MDI option table.
            picker.menu = UIMenu(children: supported.map { choice in
                let target = adapter.target
                return UIAction(title: choice.label, image: UIImage(systemName: ServerUISymbolFallback.resolve(choice.icon)),
                                state: selected == choice.value ? .on : .off) { [weak self] _ in
                    let intent: ClimateConfiguredIntent
                    switch props.kind {
                    case .mode: intent = .mode(target, choice.value)
                    case .fan: intent = .fan(target, choice.value)
                    default: intent = .preset(target, choice.value)
                    }
                    self?.send(intent, target: target, expected: definition)
                }
            })
            picker.isEnabled = enabled && !supported.isEmpty
        }
        for (choice, button, option) in choices {
            button.isHidden = !supported.contains { $0.value == choice.value }
            button.isEnabled = enabled
            let selected = adapter.selected(.options) == choice.value
            button.isSelected = selected
            option.showSelection(selected)
        }
        if props.kind == .options { row?.isHidden = !supported.isEmpty }
        ukRemeasureContainers(includingSelf: true)
    }

    private func open(expected: ServerUIClimateControl) {
        guard definition == expected, let adapter, adapter.navigationEnabled(expected.props), let action = expected.action else { return }
        navigate(action)
    }

    private func send(_ intent: ClimateConfiguredIntent, target: String, expected: ServerUIClimateControl? = nil,
                      rejected: (() -> Void)? = nil) {
        guard let adapter, let definition else { return }
        guard expected == nil || expected == definition else {
            failure.show(definition.props.errorText)
            return
        }
        adapter.submit(intent, expectedTarget: target) { [weak self] in
            guard let self else { return }
            rejected?()
            failure.show(definition.props.errorText)
        }
    }

    private func commit(_ targets: ThermostatTargets) {
        guard let adapter, let pinnedTarget, let definition, let settings = definition.props.dial else { return }
        let values = targets.serviceData
        guard values.values.allSatisfy({ $0.isFinite && $0 >= settings.minimum && $0 <= settings.maximum }) else {
            failure.show(definition.props.errorText)
            return
        }
        let ids: [String]
        if case .range = targets, pinnedTarget == adapter.configuration.entityId, !adapter.configuration.rangeCommitEntityIds.isEmpty {
            ids = adapter.configuration.rangeCommitEntityIds
        } else { ids = [pinnedTarget] }
        send(.temperature(ids, values, unit: settings.unit), target: pinnedTarget) { [weak self, weak adapter] in
            guard let self, adapter?.target == pinnedTarget else { return }
            rejections += 1
            dial?.rejection = ThermostatRejection(targets: targets, count: rejections)
        }
    }
}
#endif
