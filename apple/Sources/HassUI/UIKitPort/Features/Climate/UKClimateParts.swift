#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// `ClimateStyle` as UIKit colours.
@MainActor
enum UKClimateStyle {
    static let heat = UIColor(ClimateStyle.heatToken)
    static let cool = UIColor(ClimateStyle.coolToken)

    /// The tint for an `hvac_action`: heat, cool, or nil when idle (`ClimateStyle.tint(action:)`).
    static func tint(action: String) -> UIColor? {
        switch ThermostatThermalStatus(action: action) {
        case .heat: heat
        case .cool: cool
        default: nil
        }
    }

    static func symbol(_ mdi: String) -> String { ClimateStyle.symbol(mdi) }
}

// MARK: - Page notice

/// A notice on the wallpaper (`ClimateNotice`): a glyph and the text on a module, read as one element. A warning sits on the
/// dense module with an orange glyph.
@MainActor
final class UKClimateNoticeView: UIView {
    init(text: String, symbol: String = "info.circle", isWarning: Bool = false, identifier: String) {
        super.init(frame: .zero)
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.bodyEmphasis())))
        icon.tintColor = isWarning ? UKInk.warning : UKInk.action
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isAccessibilityElement = false
        let label = UILabel.uk(.subheadline, ink: .white)
        label.text = text
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = HassTokens.Spacing.m
        let module = UKModuleView.wrapping(row, density: isWarning ? .dense : .thin,
                                           insets: UIEdgeInsets(top: HassTokens.Spacing.m + 2, left: HassTokens.Spacing.l,
                                                                bottom: HassTokens.Spacing.m + 2, right: HassTokens.Spacing.l))
        addSubview(module)
        module.ukPin(to: self)
        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Hub pill

/// A pop-up menu of choices, the current one checked (`HubPicker`): the current value beside a glyph and an up-down chevron,
/// at least 44 pt each way. HIG: Pop-up buttons.
@MainActor
final class UKHubPicker: UIButton {
    private let label: String
    private let onSelect: (String) -> Void
    private let content = UIStackView()
    private let symbolView = UIImageView()
    private let valueLabel = UILabel.uk(.body, ink: UKInk.action, lines: 1)
    private let chevron = UIImageView()

    init(label: String, identifier: String, onSelect: @escaping (String) -> Void) {
        self.label = label
        self.onSelect = onSelect
        super.init(frame: .zero)
        showsMenuAsPrimaryAction = true
        symbolView.tintColor = UKInk.action
        symbolView.isAccessibilityElement = false
        symbolView.setContentHuggingPriority(.required, for: .horizontal)
        chevron.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.footnoteEmphasis()))
        chevron.tintColor = UKInk.action
        chevron.isAccessibilityElement = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = 4
        content.isUserInteractionEnabled = false
        content.addArrangedSubview(symbolView)
        content.addArrangedSubview(valueLabel)
        content.addArrangedSubview(chevron)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        accessibilityIdentifier = identifier
        accessibilityLabel = label
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the current value and the choices.
    func update(value: String, symbol: String?, options: [ClimateLogic.Option], selected: String?, systemIcons: Bool = false) {
        valueLabel.text = value
        symbolView.isHidden = symbol == nil
        symbolView.image = symbol.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.bodyEmphasis())) }
        accessibilityValue = value
        isEnabled = !options.isEmpty
        menu = UIMenu(children: options.map { option in
            UIAction(title: option.label, image: UIImage(systemName: systemIcons ? option.icon ?? "thermometer" : ClimateStyle.symbol(option.icon ?? "mdi:thermometer-check")),
                     state: option.value == selected ? .on : .off) { [weak self] _ in self?.onSelect(option.value) }
        })
    }
}

/// The physical thermostat's pill (`ThermostatHubPill`): one thin module with the hub's glyph tinted by `hvac_action`, its name
/// and state, and the mode and fan as two pop-up menus that each show their current value beside a glyph. At accessibility sizes
/// the menus drop under the text and show the value alone.
@MainActor
final class UKThermostatHubPill: UIView {
    private var controller: ClimateController?
    private let bag = UKObservationBag()
    private let icon = UIImageView()
    private let nameLabel = UILabel.uk(.subheadline, weight: .semibold, ink: .white)
    private let stateLabel = UILabel.uk(.footnote, ink: UKDesignSurface.secondaryOnModule)
    private let info = UIStackView()
    private let main = UIStackView()
    private let pickers = UIStackView()
    private let modePicker: UKHubPicker
    private let fanPicker: UKHubPicker
    private var lastTint: UIColor?
    private var stacked: Bool { traitCollection.isAccessibilitySize }

    /// The glyph beside the mode's name: the selected HVAC mode's own icon, else a thermometer.
    static func modeSymbol(selected: String?) -> String {
        ClimateStyle.symbol(selected.flatMap { ClimateConfig.hvacModeIcons[$0] } ?? "mdi:thermometer")
    }

    convenience init(controller: ClimateController) {
        self.init(title: "Thermostat Hub", symbol: ClimateStyle.symbol("mdi:thermostat"), identifier: "climate.hub",
                  modeLabel: "Thermostat Hub Mode", fanLabel: "Thermostat Hub Fan",
                  onMode: { controller.setHubMode($0) }, onFan: { controller.setHubFan($0) })
        self.controller = controller
        bag.observe { [weak self] in self?.apply() }
    }

    /// Value/closure entry point for composed controls; the legacy binding initializer is unchanged.
    init(title: String, symbol: String, identifier: String, modeLabel: String, fanLabel: String,
         onMode: @escaping (String) -> Void, onFan: @escaping (String) -> Void) {
        modePicker = UKHubPicker(label: modeLabel, identifier: identifier + ".mode", onSelect: onMode)
        fanPicker = UKHubPicker(label: fanLabel, identifier: identifier + ".fan", onSelect: onFan)
        super.init(frame: .zero)
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.title2)))
        icon.contentMode = .center
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        icon.isAccessibilityElement = false
        nameLabel.text = title
        let texts = UIStackView(arrangedSubviews: [nameLabel, stateLabel])
        texts.axis = .vertical
        texts.spacing = 2
        info.axis = .horizontal
        info.alignment = .center
        info.spacing = HassTokens.Spacing.m
        info.addArrangedSubview(icon)
        info.addArrangedSubview(texts)
        info.isAccessibilityElement = true
        info.accessibilityIdentifier = identifier
        pickers.axis = .horizontal
        pickers.alignment = .center
        pickers.spacing = HassTokens.Spacing.xs
        pickers.addArrangedSubview(modePicker)
        pickers.addArrangedSubview(fanPicker)
        pickers.setContentHuggingPriority(.required, for: .horizontal)
        pickers.setContentCompressionResistancePriority(.required, for: .horizontal)
        main.alignment = .center
        main.addArrangedSubview(info)
        main.addArrangedSubview(pickers)
        let module = UKModuleView.wrapping(main, insets: UIEdgeInsets(top: HassTokens.Spacing.s, left: HassTokens.Spacing.m,
                                                                      bottom: HassTokens.Spacing.s, right: HassTokens.Spacing.m))
        addSubview(module)
        module.ukPin(to: self)
        isAccessibilityElement = false
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (pill: UKThermostatHubPill, _) in
            pill.reflow()
            if pill.controller != nil { pill.apply() }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply() {
        guard let controller else { return }
        let entity = controller.entity(ClimateConfig.hubEntityId)
        let action = ClimateLogic.hvacAction(entity)
        let mode = controller.shown(ClimateController.hubModeKey)
        let state = ClimateLogic.compactState(entity, state: mode)
        let fans = ClimateLogic.fanModeOptions(entity)
        let fanMode = controller.shown(ClimateController.hubFanKey)
        update(state: state, action: action, modes: ClimateLogic.hvacModeOptions(entity), mode: mode,
               modeSymbol: Self.modeSymbol(selected: mode), fans: fans, fan: fanMode,
               fanText: ClimateLogic.selectOption(fanMode ?? ""), fanSymbol: ClimateStyle.symbol("mdi:fan"))
    }

    private func reflow() {
        main.axis = stacked ? .vertical : .horizontal
        main.alignment = stacked ? .leading : .center
        main.spacing = stacked ? HassTokens.Spacing.s : HassTokens.Spacing.m
    }

    /// Renders caller-owned modes, labels and symbols using the canonical layout and state animation.
    func update(state: String, action: String, modes: [ClimateLogic.Option], mode: String?, modeSymbol: String?,
                fans: [ClimateLogic.Option], fan: String?, fanText: String, fanSymbol: String?,
                enabled: Bool = true, systemIcons: Bool = false) {
        reflow()
        let tint = UKClimateStyle.tint(action: action) ?? UKDesignSurface.secondaryOnModule
        if tint != lastTint {
            lastTint = tint
            UKMotion.stateFade("ThermostatHubPill", view: icon, animated: true) { [icon] in icon.tintColor = tint }
        }
        stateLabel.text = state
        info.accessibilityLabel = "\(nameLabel.text ?? ""), \(state)"
        modePicker.update(value: state, symbol: stacked ? nil : modeSymbol,
                          options: modes, selected: mode, systemIcons: systemIcons)
        modePicker.isEnabled = enabled && !modes.isEmpty
        fanPicker.isHidden = fans.isEmpty
        if !fans.isEmpty {
            fanPicker.update(value: fanText, symbol: stacked ? nil : fanSymbol,
                             options: fans, selected: fan, systemIcons: systemIcons)
            fanPicker.isEnabled = enabled
        }
    }
}

// MARK: - Entry rows

#endif
