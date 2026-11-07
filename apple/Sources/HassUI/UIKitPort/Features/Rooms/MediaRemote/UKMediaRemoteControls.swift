#if os(iOS)
import HassCore
import HassDesign
import UIKit

// The remote's controls (`MediaRemoteControls.swift`): the round keys, the power key, the 3×3 pad, the volume card, the transport
// row, the inline keyboard and the Remote section's column.

// MARK: - Round key

/// One configured remote button drawn as a round icon (`RemoteIconButton` in `RoundButtonStyle`; web `RemoteButton`), and the
/// always-visible power key (`PowerButton`, ``Role/power``).
///
/// A grey circle in the sheet's cell colour (clear for keys drawn on a card), pressed it shrinks to 94% (dims to 70% under Reduce
/// Motion), disabled it dims to 40%. A button with a colour rule (power) says its state by shape as well as colour: a filled
/// success disc with a dark glyph while on, an outlined neutral ring and glyph while off. A tap ticks (`UKTapFeedback.tap`).
@MainActor
final class UKRemoteRoundButton: UKRemoteControl {
    enum Role { case key, power }

    let controller: MediaRemoteController
    let button: MediaRemoteButton
    let role: Role
    var iconStyle: UIFont.TextStyle { didSet { if iconStyle != oldValue { updateGlyph() } } }
    var diameter: CGFloat {
        didSet {
            guard diameter != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }
    /// The circle's fill; clear for keys drawn on a card (volume), which keep their 44 pt target.
    var fill: UIColor? { didSet { circle.backgroundColor = fill } }
    /// The keyboard key asks for the text prompt on this entity.
    var onTextPrompt: (String) -> Void = { _ in }
    var onPress: () -> Void = {}
    /// When it returns true the key is disabled (`.disabled(controller.controlsDisabled)`).
    var disabledRule: (@MainActor (MediaRemoteController) -> Bool)? {
        // Observe again: the rule's own reads (`controlsDisabled`) are not tracked by the run made before it was set.
        didSet { bag.observe { [weak self] in self?.refresh() } }
    }
    /// Whether the inline keyboard is open: the keyboard key reads Expanded or Collapsed.
    var keyboardOpen: Bool? { didSet { if keyboardOpen != oldValue { refresh() } } }

    private let bag = UKObservationBag()
    private let body = UIView()
    private let circle = UIView()
    private let disc = UIView()
    private let ring = UIView()
    private let glyph = UIImageView()
    private let dot = UIView()
    private var shownTone: IconTone?
    private var hasShownTone = false

    init(controller: MediaRemoteController, button: MediaRemoteButton, role: Role = .key, diameter: CGFloat,
         iconStyle: UIFont.TextStyle = .title2, fill: UIColor? = UKDesignSurface.sheetCell) {
        self.controller = controller
        self.button = button
        self.role = role
        self.diameter = diameter
        self.iconStyle = iconStyle
        self.fill = fill
        super.init(frame: .zero)
        isAccessibilityElement = true
        body.isUserInteractionEnabled = false
        addSubview(body)
        circle.backgroundColor = fill
        disc.backgroundColor = UKRemoteStyle.powerOn
        ring.layer.borderWidth = 2
        dot.backgroundColor = UKDesignInk.primary
        glyph.contentMode = .center
        glyph.isAccessibilityElement = false
        for view in [circle, disc, ring, glyph, dot] {
            view.isUserInteractionEnabled = false
            body.addSubview(view)
        }
        disc.alpha = 0
        ring.alpha = 0
        dot.isHidden = button.hasIcon
        glyph.isHidden = !button.hasIcon
        accessibilityLabel = button.label
        accessibilityIdentifier = role == .power ? "remote.power" : "remote.button.\(button.label)"
        addAction(UIAction { [weak self] _ in self?.fire() }, for: .touchUpInside)
        ukOnContentSizeChange { [weak self] in self?.updateGlyph() }
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: Self, _) in self.updateRing() }
        updateRing()
        bag.observe { [weak self] in self?.refresh() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: diameter, height: diameter) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    override var isEnabled: Bool {
        didSet { if isEnabled != oldValue { updateDim() } }
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { updatePress() } }
    }

    // MARK: Drawing

    private func updateGlyph() {
        guard button.hasIcon else { return }
        let style: UIFont.TextStyle = button.icon == "mdi:circle" ? .footnote : iconStyle
        let font = UKFont.preferred(style, weight: .semibold, traits: traitCollection)
        glyph.transform = .identity
        glyph.image = UIImage(systemName: UKRemoteStyle.symbol(button.icon), withConfiguration: UIImage.SymbolConfiguration(font: font))
        glyph.sizeToFit()
        glyph.transform = CGAffineTransform(rotationAngle: button.iconRotationDegrees * .pi / 180)
        setNeedsLayout()
    }

    private func updateRing() {
        ring.layer.borderColor = UKRemoteStyle.powerOff.resolvedColor(with: traitCollection).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        body.transform = .identity
        body.frame = bounds
        circle.frame = body.bounds
        circle.layer.cornerRadius = bounds.width / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        glyph.center = center
        let badge = UKFont.scaled(46, relativeTo: .title1, traits: traitCollection)
        for view in [disc, ring] {
            view.bounds = CGRect(x: 0, y: 0, width: badge, height: badge)
            view.center = center
            view.layer.cornerRadius = badge / 2
        }
        let size = RemoteButtonIcon.selectDot
        dot.frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        dot.layer.cornerRadius = size / 2
        if isHighlighted { updatePress() }
    }

    private func updateDim() {
        alpha = isEnabled ? 1 : 0.4
    }

    /// Pressed shrinks the key; with Reduce Motion it dims instead (opacity is allowed).
    private func updatePress() {
        let pressed = isHighlighted
        let reduce = UKMotion.reduceMotion
        UKMotion.animate(.quick, reduced: .quick) { [self] in
            body.transform = pressed && !reduce ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            alpha = isEnabled ? (pressed && reduce ? 0.7 : 1) : 0.4
        }
    }

    private func applyTone(_ tone: IconTone?) {
        let changed = !hasShownTone || shownTone != tone
        hasShownTone = true
        shownTone = tone
        let color: UIColor = switch tone {
        case .active: UKRemoteStyle.powerOnGlyph
        case .inactive: UKRemoteStyle.powerOff
        case nil: UKDesignInk.primary
        }
        let work = { [self] in
            glyph.tintColor = color
            disc.alpha = tone == .active ? 1 : 0
            ring.alpha = tone == .inactive ? 1 : 0
        }
        // The power key's on and off colours cross-fade (`PowerButton`, motion-components.md).
        if changed, window != nil { UKMotion.stateColor(work) } else { work() }
    }

    // MARK: State

    private func refresh() {
        let semantics = controller.semantics(for: button)
        var value = applySemantics(semantics)
        switch role {
        case .power:
            // A toggle power button reads On/Off as a switch; a command one still reads the device's state.
            if case .toggle = semantics {} else { value = controller.isControlOff ? "Off" : "On" }
            accessibilityUserInputLabels = [button.label, controller.powerTitle]
        case .key:
            if let keyboardOpen { value = keyboardOpen ? "Expanded" : "Collapsed" }
        }
        accessibilityValue = value
        isEnabled = !(disabledRule?(controller) ?? false)
        if button.hasIcon { applyTone(controller.iconTone(for: button)) }
    }

    private func fire() {
        UKTapFeedback.tap()
        onPress()
        if let target = controller.press(button) { onTextPrompt(target) }
    }
}

// MARK: - Pad

/// The 3×3 remote grid (`DirectionalPad`; `.agents/design/direction-g.md`, Controls: Remote): Back, Up and Power; Left, Select and
/// Right; Home, Down and the keyboard, as large grey circles with a light haptic on each press. Select is blank on a SHIELD and a dot
/// on Apple TV. A remote without a keyboard (Apple TV) leaves that corner empty. One accessibility group named "<remote> remote
/// controls" (`remote.dpad`), power read first.
@MainActor
final class UKRemoteDPadView: UIView, UKGridMeasuring {
    let controller: MediaRemoteController
    let keyboard: UKRemoteKeyboardState
    /// The pad must fit the width it is given (the leading column in two columns); false for no limit.
    let limitsToBounds: Bool

    private let bag = UKObservationBag()
    private let power: UKRemoteRoundButton
    private let rows: [[UKRemoteRoundButton?]]
    private let keyboardKey: UKRemoteRoundButton?

    init(controller: MediaRemoteController, keyboard: UKRemoteKeyboardState, limitsToBounds: Bool,
         onTextPrompt: @escaping (String) -> Void) {
        self.controller = controller
        self.keyboard = keyboard
        self.limitsToBounds = limitsToBounds
        let config = controller.config
        func key(_ button: MediaRemoteButton) -> UKRemoteRoundButton {
            let key = UKRemoteRoundButton(controller: controller, button: button, role: .key, diameter: 76, iconStyle: .title1)
            key.disabledRule = { $0.controlsDisabled }
            key.onTextPrompt = onTextPrompt
            return key
        }
        // Power stays enabled while the directions are disabled: it is how the device turns on.
        let powerKey = UKRemoteRoundButton(controller: controller, button: config.power, role: .power, diameter: 76, iconStyle: .title1)
        let keyboardKey = config.keyboard.map(key)
        power = powerKey
        self.keyboardKey = keyboardKey
        rows = [
            [key(config.back), key(config.up), powerKey],
            [key(config.left), key(config.select), key(config.right)],
            [key(config.home), key(config.down), keyboardKey],
        ]
        super.init(frame: .zero)
        for button in rows.flatMap({ $0 }).compactMap({ $0 }) { addSubview(button) }
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityLabel = "\(config.title) remote controls"
        accessibilityIdentifier = "remote.dpad"
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.setNeedsLayout()
            self.ukInvalidateEnclosingLayout()
        }
        bag.observe { [weak self] in
            guard let self else { return }
            keyboardKey?.keyboardOpen = keyboard.prompt.isOpen
            let hidden = controller.hidesKeyboard
            if keyboardKey?.isHidden != hidden { keyboardKey?.isHidden = hidden }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 64–104 pt with Dynamic Type, but never wider than three buttons fit in the width (never under 44 pt).
    private func diameter(forWidth width: CGFloat) -> CGFloat {
        DirectionalPad.diameter(scaled: UKFont.scaled(76, relativeTo: .title1, traits: traitCollection), maxWidth: limitsToBounds ? width : nil)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        3 * diameter(forWidth: width) + 2 * HassTokens.Spacing.m
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let d = diameter(forWidth: bounds.width)
        let spacing = HassTokens.Spacing.m
        let total = 3 * d + 2 * spacing
        let originX = (bounds.width - total) / 2
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (row, buttons) in rows.enumerated() {
            for (column, button) in buttons.enumerated() {
                guard let button else { continue }
                if button.diameter != d { button.diameter = d }
                let slot = mirror ? 2 - column : column
                button.frame = CGRect(x: originX + CGFloat(slot) * (d + spacing), y: CGFloat(row) * (d + spacing), width: d, height: d)
            }
        }
    }

    /// Power is read first, as it was above the pad.
    override var accessibilityElements: [Any]? {
        get {
            let others = rows.flatMap { $0 }.compactMap { $0 }.filter { $0 !== power && !$0.isHidden }
            return [power] + others
        }
        set {}
    }
}

// MARK: - Transport

/// Pause and Play in three equal columns with the middle one empty (`RemoteControlsTab.row`); one group named "Playback".
@MainActor
final class UKRemoteTransportRow: UIView, UKGridMeasuring {
    private let buttons: [UKRemoteRoundButton?]

    init(controller: MediaRemoteController) {
        let config = controller.config
        func key(_ button: MediaRemoteButton) -> UKRemoteRoundButton {
            let key = UKRemoteRoundButton(controller: controller, button: button, role: .key, diameter: 56, iconStyle: .title2)
            key.disabledRule = { $0.controlsDisabled }
            return key
        }
        buttons = [key(config.pause), nil, key(config.play)]
        super.init(frame: .zero)
        for button in buttons.compactMap({ $0 }) { addSubview(button) }
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityLabel = "Playback"
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.setNeedsLayout()
            self.ukInvalidateEnclosingLayout()
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var diameter: CGFloat { min(max(UKFont.scaled(56, relativeTo: .title2, traits: traitCollection), HassTokens.minTarget), 88) }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { diameter }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: diameter) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let d = diameter
        let column = bounds.width / 3
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (index, button) in buttons.enumerated() {
            guard let button else { continue }
            if button.diameter != d { button.diameter = d }
            let slot = CGFloat(mirror ? 2 - index : index)
            button.frame = CGRect(x: slot * column + (column - d) / 2, y: 0, width: d, height: d)
        }
    }
}

// MARK: - Volume

/// The speaker's card (`RemoteControlsTab.volumeCard`): its name and level, mute, and the slider between Volume Down and Volume Up,
/// on the sheet's cell colour with 26 pt corners. The slider commits on release, or at once for a step that arrives without a drag
/// (VoiceOver adjust), so a drag sends one service call (``SliderDraft``).
@MainActor
final class UKRemoteVolumeCard: UKRemoteMeasuredView {
    private let controller: MediaRemoteController
    private let titleLabel = UILabel()
    private let percentLabel = UILabel()
    private let slider = UKRemoteSlider()
    private let mute: UKRemoteRoundButton
    private let down: UKRemoteRoundButton
    private let up: UKRemoteRoundButton
    private let bag = UKObservationBag()
    private var volume = SliderDraft()

    init(controller: MediaRemoteController) {
        self.controller = controller
        let config = controller.config
        func key(_ button: MediaRemoteButton) -> UKRemoteRoundButton {
            let key = UKRemoteRoundButton(controller: controller, button: button, role: .key, diameter: HassTokens.minTarget,
                                          iconStyle: .body, fill: .clear)
            key.disabledRule = { $0.volumeDisabled }
            return key
        }
        mute = key(config.volumeMute)
        down = key(config.volumeDown)
        up = key(config.volumeUp)
        super.init(frame: .zero)
        backgroundColor = UKDesignSurface.sheetCell
        layer.cornerRadius = HassTokens.Radius.module
        layer.cornerCurve = .continuous

        titleLabel.text = config.volumeTitle
        titleLabel.textColor = UKDesignInk.primary
        titleLabel.numberOfLines = 0
        titleLabel.isAccessibilityElement = false
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        percentLabel.textColor = UKDesignSurface.secondaryInSheet
        percentLabel.isAccessibilityElement = false
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)
        percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            titleLabel.font = UKFont.preferred(.headline, traits: traitCollection)
            percentLabel.font = UKFont.preferred(.headline, weight: .regular, monospacedDigit: true, traits: traitCollection)
        }

        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.step = 1
        slider.tintColor = UKDesignInk.action
        slider.accessibilityLabel = "\(config.volumeTitle) volume"
        slider.accessibilityIdentifier = "remote.volume"
        slider.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        slider.addAction(UIAction { [weak self] _ in self?.beginEditing() }, for: .touchDown)
        slider.addAction(UIAction { [weak self] _ in self?.changed() }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in self?.endEditing() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let top = UIStackView(arrangedSubviews: [titleLabel, percentLabel, mute])
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = HassTokens.Spacing.m
        let bottom = UIStackView(arrangedSubviews: [down, slider, up])
        bottom.axis = .horizontal
        bottom.alignment = .center
        bottom.spacing = HassTokens.Spacing.xs
        let content = UIStackView(arrangedSubviews: [top, bottom])
        content.axis = .vertical
        content.spacing = HassTokens.Spacing.s
        addSubview(content)
        content.ukPin(to: self, insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: HassTokens.Spacing.l,
                                                      bottom: HassTokens.Spacing.m, right: HassTokens.Spacing.l))

        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityLabel = config.volumeTitle
        accessibilityIdentifier = "remote.section.volume"
        bag.observe { [weak self] in self?.refresh() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var accessibilityElements: [Any]? {
        get { [mute, down, slider, up] }
        set {}
    }

    private var commit: (Double) -> Void {
        { [controller] in controller.setVolume(percent: Int($0.rounded())) }
    }

    private func refresh() {
        let shown = volume.shown(live: Double(controller.volumePercent))
        let whole = Int(shown.rounded())
        percentLabel.text = "\(whole)%"
        if abs(Double(slider.value) - shown) > 0.01 { slider.setValue(Float(shown), animated: false) }
        slider.accessibilityValue = "\(whole) percent"
        slider.isEnabled = !controller.volumeDisabled
    }

    private func beginEditing() {
        volume.editingChanged(true, live: Double(controller.volumePercent), commit: commit)
    }

    private func changed() {
        slider.snap()
        volume.set(Double(slider.value), commit: commit)
        refresh()
    }

    private func endEditing() {
        volume.editingChanged(false, live: Double(controller.volumePercent), commit: commit)
        refresh()
    }
}

// MARK: - Keyboard

/// The inline keyboard under the pad (`RemoteControlsTab.keyboardForm`; web `TextPromptForm`): the field with Send and Cancel on one
/// row, stacked at accessibility sizes.
@MainActor
final class UKRemoteKeyboardForm: UKRemoteMeasuredView, UITextFieldDelegate {
    private let controller: MediaRemoteController
    private let keyboard: UKRemoteKeyboardState
    private let caption = UILabel.uk(.subheadline, ink: UKDesignSurface.secondaryInSheet)
    private let field = UITextField()
    private let send = UIButton(type: .system)
    private let cancel = UIButton(type: .system)
    private let row = UIStackView()
    private let bag = UKObservationBag()

    init(controller: MediaRemoteController, keyboard: UKRemoteKeyboardState) {
        self.controller = controller
        self.keyboard = keyboard
        super.init(frame: .zero)
        caption.text = "Text to send"
        caption.isAccessibilityElement = false

        field.borderStyle = .roundedRect
        field.placeholder = "Enter text"
        field.font = .ukFont(.body)
        field.adjustsFontForContentSizeCategory = true
        // Free text for a TV: no autocapitalization or autocorrection (web `autoCapitalize="none"`).
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .send
        field.delegate = self
        field.accessibilityLabel = "Text to send"
        field.accessibilityIdentifier = "remote.keyboard.field"
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let text = field.text ?? ""
            if keyboard.prompt.text != text { keyboard.prompt.text = text }
        }, for: .editingChanged)

        var sendConfiguration = UIButton.Configuration.filled()
        sendConfiguration.title = "Send"
        sendConfiguration.buttonSize = .large
        send.configuration = sendConfiguration
        send.accessibilityIdentifier = "remote.keyboard.send"
        send.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        var cancelConfiguration = UIButton.Configuration.tinted()
        cancelConfiguration.title = "Cancel"
        cancelConfiguration.buttonSize = .large
        cancel.configuration = cancelConfiguration
        cancel.accessibilityIdentifier = "remote.keyboard.cancel"
        cancel.addAction(UIAction { [weak self] _ in self?.keyboard.prompt.close() }, for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [send, cancel])
        buttons.axis = .horizontal
        buttons.spacing = HassTokens.Spacing.s
        let buttonsHost = UIView()
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttonsHost.addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.topAnchor.constraint(equalTo: buttonsHost.topAnchor), buttons.bottomAnchor.constraint(equalTo: buttonsHost.bottomAnchor),
            buttons.leadingAnchor.constraint(equalTo: buttonsHost.leadingAnchor),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: buttonsHost.trailingAnchor),
        ])
        buttonsHost.setContentHuggingPriority(.required, for: .horizontal)
        buttonsHost.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addArrangedSubview(field)
        row.addArrangedSubview(buttonsHost)
        row.spacing = HassTokens.Spacing.s
        let column = UIStackView(arrangedSubviews: [caption, row])
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.s
        addSubview(column)
        column.ukPin(to: self)
        ukOnContentSizeChange { [weak self] in self?.updateAxis() }

        bag.observe { [weak self] in
            guard let self else { return }
            let prompt = keyboard.prompt
            if field.text != prompt.text { field.text = prompt.text }
            send.isEnabled = !prompt.isBlank
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Field, Send and Cancel on one row like the web, so keyboard avoidance that keeps the focused field visible keeps the buttons
    /// visible too; stacked at accessibility sizes.
    private func updateAxis() {
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            row.axis = .vertical
            row.alignment = .fill
        } else {
            row.axis = .horizontal
            row.alignment = .center
        }
    }

    private func submit() {
        keyboard.prompt.submit(with: controller)
    }

    /// Moves the insertion point into the field.
    func focus() {
        guard window != nil else { return }
        field.becomeFirstResponder()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Opened from the pad while another section showed (two columns): focus once the field is here.
        if window != nil, keyboard.prompt.isOpen, !isHidden { DispatchQueue.main.async { [weak self] in self?.focus() } }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return false
    }
}

// MARK: - Remote section

/// The Remote section's column (`RemoteControlsTab`, with the pad above it in one column): the pad, the inline keyboard while open,
/// the volume card while the remote shows one, and the transport keys; 24 pt apart.
@MainActor
final class UKRemoteControlsView: UIView, UKGridMeasuring {
    private let controller: MediaRemoteController
    private let keyboard: UKRemoteKeyboardState
    private let column = UKColumnView(spacing: HassTokens.Spacing.xl)
    private let keyboardForm: UKRemoteKeyboardForm
    private let volumeCard: UKRemoteVolumeCard
    private let transport: UKRemoteTransportRow
    private let bag = UKObservationBag()
    private var hasRun = false

    /// - Parameter padPrompt: Non-nil puts the pad above the section (one column); its keyboard key reports through it.
    init(controller: MediaRemoteController, keyboard: UKRemoteKeyboardState, padPrompt: ((String) -> Void)?) {
        self.controller = controller
        self.keyboard = keyboard
        keyboardForm = UKRemoteKeyboardForm(controller: controller, keyboard: keyboard)
        volumeCard = UKRemoteVolumeCard(controller: controller)
        transport = UKRemoteTransportRow(controller: controller)
        super.init(frame: .zero)
        var views: [UIView] = []
        if let padPrompt {
            views.append(UKRemoteDPadView(controller: controller, keyboard: keyboard, limitsToBounds: false, onTextPrompt: padPrompt))
        }
        views += [keyboardForm, volumeCard, transport]
        column.setViews(views)
        addSubview(column)
        keyboardForm.isHidden = true
        bag.observe { [weak self] in self?.refresh() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        column.frame = bounds
    }

    private func refresh() {
        let open = keyboard.prompt.isOpen
        let showsVolume = controller.showsVolume
        let animated = hasRun && window != nil
        hasRun = true
        column.setNeedsLayout()
        if volumeCard.isHidden == showsVolume { volumeCard.isHidden = !showsVolume }
        if keyboardForm.isHidden == open {
            keyboardForm.isHidden = !open
            if open {
                keyboardForm.alpha = 0
                UKMotion.animate(.standard) { [self] in
                    keyboardForm.alpha = 1
                    if animated { column.layoutIfNeeded() }
                }
                // The field takes focus once it is on screen.
                DispatchQueue.main.async { [weak self] in self?.keyboardForm.focus() }
            } else {
                keyboardForm.endEditing(true)
            }
        }
        ukInvalidateEnclosingLayout()
    }
}
#endif
