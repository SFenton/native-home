#if os(iOS)
import HassCore
import HassDesign
import UIKit

// The remote's other sections (`MediaRemoteTabs.swift`): Apps, Devices and Hue Sync, and the app tile the room page's quick-launch
// grid shares.

// MARK: - App tile

/// One app tile (`AppTile`; direction G, n4 remote apps and room Quick App Launch): the artwork on a rounded square (200 pt at most),
/// the app's name under it, and "Playing" with a media-pink ring while it runs. Unavailable dims only the artwork, so the name keeps
/// its contrast. On a page (``surface`` `.page`) the name is white and the square sits on the module; in the remote sheet
/// (`.sheet`) it is the label colour on the sheet's cell.
///
/// ```swift
/// let tile = UKAppTileView(surface: .page)
/// tile.identifierPrefix = "room.app."
/// tile.configure(app: app, display: remote.display(app), imageURL: url) { remote.tap(app) }
/// ```
/// Measured by width (``UKGridMeasuring``), so it sits in a ``UKDynamicGridView`` as a ``UKGridItem``. One VoiceOver button named by
/// the app, a switch or a selection by the app's semantics, identified `<identifierPrefix><title>` (`remote.app.` by default).
@MainActor
final class UKAppTileView: UIControl, UKGridMeasuring {
    struct Appearance: Equatable {
        let title: String
        let symbol: String
        let whiteBackground: Bool
        let activeText: String
    }
    /// Where the tile is drawn (`EnvironmentValues.tileSurface`).
    var surface: TileSurface { didSet { if surface != oldValue { applyColors() } } }
    /// The accessibility identifier is this plus the app's title.
    var identifierPrefix = "remote.app."
    /// Called when a configure changed the tile's height (another app, or "Playing" appearing or going): a grid that caches its tracks
    /// measures again (`grid.setItems(grid.items)`).
    var onHeightChange: (() -> Void)?

    private static let maximumArtwork: CGFloat = AppTile.maximumArtwork

    private(set) var app: Appearance?
    private var display: MediaRemoteController.AppDisplay?
    private var action: () -> Void = {}

    private let artwork = UIView()
    private let clip = UIView()
    private let ground = UIView()
    private let imageView = UKCachedImageView()
    private let fallback = UIImageView()
    private let border = UIView()
    private let titleLabel = UILabel()
    private let playingLabel = UILabel()

    init(surface: TileSurface = .page) {
        self.surface = surface
        super.init(frame: .zero)
        isAccessibilityElement = true
        artwork.isUserInteractionEnabled = false
        clip.layer.cornerRadius = HassTokens.Radius.chip
        clip.layer.cornerCurve = .continuous
        clip.clipsToBounds = true
        border.layer.cornerRadius = HassTokens.Radius.chip
        border.layer.cornerCurve = .continuous
        fallback.contentMode = .center
        fallback.isAccessibilityElement = false
        imageView.placeholder = fallback
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        playingLabel.numberOfLines = 0
        playingLabel.textAlignment = .center
        playingLabel.text = "Playing"
        playingLabel.isHidden = true
        for view in [artwork, titleLabel, playingLabel] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        artwork.addSubview(clip)
        artwork.addSubview(border)
        clip.addSubview(ground)
        clip.addSubview(imageView)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            titleLabel.font = UKFont.preferred(.subheadline, traits: traitCollection)
            playingLabel.font = UKFont.preferred(.footnote, traits: traitCollection)
            updateFallbackGlyph()
            setNeedsLayout()
            ukInvalidateEnclosingLayout()
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: Self, _) in self.applyColors() }
        NotificationCenter.default.addObserver(self, selector: #selector(transparencyChanged),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        addAction(UIAction { [weak self] _ in self?.action() }, for: .touchUpInside)
        applyColors()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func transparencyChanged() { applyColors() }

    /// Shows an app with its display state; calling it again with another app (a reused cell) or another state updates in place, the
    /// ring and glyph cross-fading once the tile is on screen.
    /// - Parameters:
    ///   - app: The app.
    ///   - display: How the controller shows it (`remote.display(app)`).
    ///   - imageURL: The artwork, or nil for the icon fallback.
    ///   - action: Runs on a tap.
    func configure(app: MediaRemoteApp, display: MediaRemoteController.AppDisplay, imageURL: URL?, action: @escaping () -> Void) {
        configure(appearance: .init(title: app.title, symbol: SymbolMap.symbol(for: app.icon ?? "mdi:play-box"),
                                    whiteBackground: app.whiteBackground, activeText: "Playing"),
                  display: display, imageURL: imageURL, action: action)
    }

    /// Authored copy and appearance over the canonical artwork, selection and accessibility presentation.
    func configure(appearance app: Appearance, display: MediaRemoteController.AppDisplay, imageURL: URL?,
                   identifier: String? = nil, action: @escaping () -> Void) {
        let appChanged = self.app != app
        let animated = !appChanged && window != nil
        self.app = app
        self.display = display
        self.action = action
        if appChanged {
            titleLabel.text = app.title
            fallback.image = nil
            updateFallbackGlyph()
        }
        if imageView.url != imageURL { imageView.url = imageURL }
        // No visible "Playing" line (owner, 2026-10-30): the ring says it, and VoiceOver still does.
        playingLabel.isHidden = true
        isEnabled = !display.isUnavailable
        artwork.alpha = display.isUnavailable ? 0.4 : 1
        accessibilityLabel = app.title
        accessibilityIdentifier = identifier ?? identifierPrefix + app.title
        switch display.semantics {
        case let .toggle(isOn):
            semanticTraits = [.button, .toggleButton]
            accessibilityValue = isOn ? "On" : "Off"
        case let .selection(isSelected):
            semanticTraits = isSelected ? [.button, .selected] : .button
            accessibilityValue = display.isActive ? app.activeText : nil
        case .command, .state:
            semanticTraits = .button
            accessibilityValue = display.isActive ? app.activeText : nil
        }
        applyColors(animated: animated)
        setNeedsLayout()
        if appChanged {
            ukInvalidateEnclosingLayout()
            onHeightChange?()
        }
    }

    private var semanticTraits: UIAccessibilityTraits = .button

    override var accessibilityTraits: UIAccessibilityTraits {
        get { isEnabled ? semanticTraits : semanticTraits.union(.notEnabled) }
        set { semanticTraits = newValue }
    }

    // MARK: Colours

    private func updateFallbackGlyph() {
        guard let app else { return }
        let font = UKFont.preferred(.largeTitle, traits: traitCollection)
        fallback.image = UIImage(systemName: app.symbol,
                                 withConfiguration: UIImage.SymbolConfiguration(font: font))
    }

    private func applyColors(animated: Bool = false) {
        let isActive = display?.isActive ?? false
        let isSheet = surface == .sheet
        if app?.whiteBackground == true {
            ground.backgroundColor = .white
        } else if isSheet {
            ground.backgroundColor = UKDesignSurface.sheetCell
        } else {
            // The module material, opaque with Reduce Transparency; the tile's own shape clips it.
            ground.backgroundColor = UKDesignSurface.moduleTint(.thin, reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)
        }
        titleLabel.textColor = UKDesignSurface.title(on: surface)
        playingLabel.textColor = UKDesignSurface.secondary(on: surface)
        let glyphColor: UIColor = app?.whiteBackground == true ? .black : (isActive ? UKRemoteStyle.activeFallback : UKRemoteStyle.idleFallback)
        let ring = (isActive ? UKRemoteStyle.mediaGlyph : UKInk.separator).resolvedColor(with: traitCollection).cgColor
        let width: CGFloat = isActive ? 3 : 1
        // The ring and the placeholder glyph follow state over the state timing (`stateColorTransition("AppTile")`).
        if animated, window != nil {
            UKMotion.fade(border.layer, keyPath: "borderColor", to: ring)
            UKMotion.fade(border.layer, keyPath: "borderWidth", to: width)
            UKMotion.dissolve(fallback) { [fallback] in fallback.tintColor = glyphColor }
        } else {
            border.layer.borderColor = ring
            border.layer.borderWidth = width
            fallback.tintColor = glyphColor
        }
    }

    // MARK: Layout

    private func artworkSide(forWidth width: CGFloat) -> CGFloat { min(Self.maximumArtwork, max(0, width)) }

    private func measure(_ label: UILabel, width: CGFloat) -> CGFloat {
        ceil(label.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        var height = artworkSide(forWidth: width) + HassTokens.Spacing.xs + measure(titleLabel, width: width)
        if !playingLabel.isHidden { height += HassTokens.Spacing.xs + measure(playingLabel, width: width) }
        return height
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = size.width.isFinite && size.width > 0 ? size.width : Self.maximumArtwork
        return CGSize(width: width, height: gridHeight(forWidth: width))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let side = artworkSide(forWidth: width)
        artwork.frame = CGRect(x: ((width - side) / 2).rounded(), y: 0, width: side, height: side)
        clip.frame = artwork.bounds
        border.frame = artwork.bounds
        ground.frame = clip.bounds
        imageView.frame = clip.bounds
        var y = side + HassTokens.Spacing.xs
        let titleHeight = measure(titleLabel, width: width)
        titleLabel.frame = CGRect(x: 0, y: y, width: width, height: titleHeight)
        y += titleHeight + HassTokens.Spacing.xs
        playingLabel.frame = CGRect(x: 0, y: y, width: width, height: measure(playingLabel, width: width))
    }
}

// MARK: - Apps

/// A list row of a label (a glyph, a title and optionally a subtitle) with an optional switch or checkmark at the trailing edge,
/// 44 pt at least: the shape of the Devices and Hue Sync rows (`Label` in a `List` row). The row is the control: a tap anywhere on a
/// switch row flips it (the drawn switch only shows the state), so the target is the whole row.
@MainActor
class UKRemoteLabelRow: UKRemoteControl {
    enum Trailing { case plain, toggle, checkmark }

    /// The canonical row, drawing only: this control is the touch target and the one accessibility element.
    private let row = UKRowView(UKRowContent("", style: .form), surface: .sheet)
    private let switchView = UISwitch()
    private let check = UIImageView()
    let bag = UKObservationBag()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        switchView.isUserInteractionEnabled = false
        switchView.isAccessibilityElement = false
        switchView.isHidden = true
        switchView.setContentHuggingPriority(.required, for: .horizontal)
        switchView.setContentCompressionResistancePriority(.required, for: .horizontal)
        check.contentMode = .center
        check.tintColor = UKDesignInk.action
        check.isHidden = true
        check.isAccessibilityElement = false
        check.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.bodyEmphasis(traitCollection)))
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.setContentCompressionResistancePriority(.required, for: .horizontal)
        let trailing = UIStackView(arrangedSubviews: [switchView, check])
        trailing.axis = .horizontal
        trailing.alignment = .center
        row.setAccessory(trailing)
        row.isUserInteractionEnabled = false
        row.isTextAccessible = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        row.ukPin(to: self)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            check.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.bodyEmphasis(traitCollection)))
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isEnabled: Bool {
        didSet { row.alpha = isEnabled ? 1 : 0.4 }
    }

    /// Shows the row's texts and glyph.
    func show(title: String, subtitle: String?, symbol: String, iconColor: UIColor, trailing: Trailing) {
        var content = UKRowContent(title, subtitle: subtitle, symbol: symbol, glyph: iconColor, style: .form)
        content.subtitleStyle = .subheadline
        row.update(content, accessory: row.accessory)
        switchView.isHidden = trailing != .toggle
        check.isHidden = trailing != .checkmark
        isUserInteractionEnabled = trailing != .plain
    }

    func setSwitch(_ isOn: Bool) {
        if switchView.isOn != isOn { switchView.setOn(isOn, animated: window != nil) }
    }

    func setChecked(_ isChecked: Bool) {
        check.alpha = isChecked ? 1 : 0
    }

    /// A tap runs `action`.
    func onTap(_ action: @escaping () -> Void) {
        addAction(UIAction { _ in action() }, for: .touchUpInside)
    }

    /// A switch row flips from its switch only, as a `Toggle` in a list does; a tap on the label leaves it alone.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !switchView.isHidden, let touch = touches.first {
            let target = switchView.convert(switchView.bounds, to: self).insetBy(dx: -HassTokens.Spacing.l, dy: -bounds.height)
            if !target.contains(touch.location(in: self)) {
                super.touchesCancelled(touches, with: event)
                return
            }
        }
        super.touchesEnded(touches, with: event)
    }

    /// VoiceOver's double tap runs the action whatever part of the row it would land on.
    override func accessibilityActivate() -> Bool {
        guard isEnabled, isUserInteractionEnabled else { return false }
        sendActions(for: .touchUpInside)
        return true
    }
}

/// A device row (`RemoteDeviceRow`): its glyph in the media family colour while on, its name and state, and a switch, a checkmark or
/// nothing for its semantics. Toggles and toggling commands are switches (`remote.device.<title>`), a source choice is a checkmark
/// button, a device that only reports a state is a plain element.
@MainActor
final class UKRemoteDeviceRow: UKRemoteLabelRow {
    convenience init(controller: MediaRemoteController, device: MediaRemoteDevice) {
        self.init(title: device.title, symbol: SymbolMap.symbol(for: device.icon), state: { controller.display(device) },
                  action: { controller.tap(device) })
    }

    /// Value/closure row shared with configured Devices atoms.
    init(title: String, symbol: String, state: @escaping () -> MediaRemoteController.DeviceDisplay, action: @escaping () -> Void) {
        super.init(frame: .zero)
        accessibilityIdentifier = "remote.device.\(title)"
        onTap(action)
        bag.observe { [weak self] in
            guard let self else { return }
            let display = state()
            let active = display.isActive && !display.isUnavailable
            let color = active ? UKRemoteStyle.mediaGlyph : UKRemoteStyle.mediaOffGlyph
            switch display.semantics {
            case let .toggle(isOn):
                show(title: title, subtitle: display.subtitle, symbol: symbol, iconColor: color, trailing: .toggle)
                setSwitch(isOn)
                asSwitch(label: "\(title), \(display.subtitle)", isOn: isOn)
            case .command:
                // Every command device toggles its device (`media_player.toggle`, the PC's on/off pair).
                show(title: title, subtitle: display.subtitle, symbol: symbol, iconColor: color, trailing: .toggle)
                setSwitch(display.isActive)
                asSwitch(label: "\(title), \(display.subtitle)", isOn: display.isActive)
            case let .selection(isSelected):
                show(title: title, subtitle: display.subtitle, symbol: symbol, iconColor: color, trailing: .checkmark)
                setChecked(isSelected)
                accessibilityLabel = title
                accessibilityValue = display.subtitle
                semanticTraits = isSelected ? [.button, .selected] : .button
            case .state:
                show(title: title, subtitle: display.subtitle, symbol: symbol, iconColor: color, trailing: .plain)
                accessibilityLabel = title
                accessibilityValue = display.subtitle
                semanticTraits = []
            }
            isEnabled = !display.isDisabled
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

extension UKRemoteLabelRow {
    /// Reads as a switch named `label` with the state as its "1" or "0" value, as a `Toggle` row does.
    func asSwitch(label: String, isOn: Bool) {
        accessibilityLabel = label
        accessibilityValue = isOn ? "1" : "0"
        semanticTraits = [.button, .toggleButton]
    }
}

// MARK: - Hue Sync rows

/// A Hue Sync power or light-sync switch row (`HueSyncTab.toggleRow`): a glyph in the lights family colour while on.
@MainActor
final class UKRemoteHueToggleRow: UKRemoteLabelRow {
    convenience init(controller: MediaRemoteController, title: String, entityId: String, symbol: String,
                     offProjections: [String] = [], onProjections: [String] = []) {
        self.init(title: title, symbol: symbol, state: {
            var display = controller.hueToggle(entityId)
            display.subtitle = ""
            return display
        },
                  action: { controller.toggleHue(entityId, offProjections: offProjections, onProjections: onProjections) })
    }

    init(title: String, symbol: String, state: @escaping () -> MediaRemoteController.ToggleDisplay, action: @escaping () -> Void) {
        super.init(frame: .zero)
        accessibilityIdentifier = "remote.hue.\(title)"
        onTap(action)
        bag.observe { [weak self] in
            guard let self else { return }
            let toggle = state()
            show(title: title, subtitle: toggle.subtitle.isEmpty ? nil : toggle.subtitle,
                 symbol: symbol, iconColor: toggle.isOn ? UKRemoteStyle.lightsGlyph : UKRemoteStyle.lightsOffGlyph,
                 trailing: .toggle)
            setSwitch(toggle.isOn)
            asSwitch(label: title, isOn: toggle.isOn)
            isEnabled = !toggle.isUnavailable
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// An HDMI input row (`HueSyncTab.hdmiRow`): a checkmark button named by the input, its status as the value, disabled while the
/// port is unplugged.
@MainActor
final class UKRemoteHdmiRow: UKRemoteLabelRow {
    struct State {
        let selected: Bool
        let disconnected: Bool
        let disabled: Bool
        let subtitle: String
        var symbol: String? = nil
    }

    convenience init(controller: MediaRemoteController, hue: HueSyncConfig, option: String) {
        self.init(title: option, symbol: "tv", state: {
            let input = controller.hdmiInputs(hue).first { $0.option == option }
            return State(selected: input?.isSelected == true, disconnected: input?.isDisconnected ?? true,
                         disabled: input?.isDisabled ?? true, subtitle: input?.subtitle ?? "Unavailable",
                         symbol: input?.isDisconnected == true ? "tv.slash" : "tv")
        }, action: { controller.selectHue(hue.hdmiInputEntityId, option: option) })
        accessibilityIdentifier = "remote.hue.hdmi.\(option)"
    }

    init(title: String, symbol: String, state: @escaping () -> State, action: @escaping () -> Void) {
        super.init(frame: .zero)
        onTap(action)
        bag.observe { [weak self] in
            guard let self else { return }
            let input = state()
            let lit = input.selected && !input.disconnected
            show(title: title, subtitle: input.subtitle, symbol: input.symbol ?? symbol,
                 iconColor: lit ? UKRemoteStyle.mediaGlyph : UKRemoteStyle.mediaOffGlyph, trailing: .checkmark)
            setChecked(input.selected)
            accessibilityLabel = title
            accessibilityValue = input.subtitle
            semanticTraits = input.selected ? [.button, .selected] : .button
            // Outside the combined element, so an unplugged port reads as dimmed.
            isEnabled = !input.disabled
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A short Hue Sync choice (`HueSyncTab.choice`), with a segmented control, an accessibility-size menu and unavailable copy.
@MainActor
final class UKRemoteHueChoiceRow: UIView {
    private let bag = UKObservationBag()
    private let unavailable = UILabel.uk(.body, ink: UKDesignInk.secondary)
    private let choice: UKSegmentedChoice<String>

    /// - Parameter ordersSyncModes: Lists the options in the Sync Box's mode order (`MediaRemoteState.orderedSyncModes`).
    convenience init(controller: MediaRemoteController, title: String, entityId: String, identifier: String, ordersSyncModes: Bool = false,
                     choose: @escaping (String) -> Void) {
        self.init(title: title, identifier: identifier, unavailableText: "Unavailable", optionTitle: { StateText.titleCase($0) },
                  reportsUnavailable: false,
                  state: {
            let display = controller.hueSelect(entityId)
            return (ordersSyncModes ? MediaRemoteState.orderedSyncModes(display.options) : display.options,
                    display.selected, display.isUnavailable)
        }, choose: choose)
    }

    init(title: String, identifier: String, unavailableText: String, optionTitle: @escaping (String) -> String,
         reportsUnavailable: Bool = true,
         state: @escaping () -> (options: [String], selected: String, unavailable: Bool), choose: @escaping (String) -> Void) {
        choice = UKSegmentedChoice<String>(label: title, options: [], title: optionTitle, selection: nil,
                                           identifier: identifier, select: choose)
        super.init(frame: .zero)
        unavailable.text = unavailableText
        unavailable.isAccessibilityElement = true
        unavailable.accessibilityLabel = title
        unavailable.accessibilityValue = unavailableText
        unavailable.accessibilityIdentifier = identifier
        for view in [unavailable, choice] as [UIView] {
            addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.xs),
                view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.xs),
                view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        unavailable.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        bag.observe { [weak self] in
            guard let self else { return }
            let select = state()
            let options = select.options
            let missing = options.isEmpty || (reportsUnavailable && select.unavailable)
            unavailable.isHidden = !missing
            choice.isHidden = missing
            if choice.options != options { choice.options = options }
            if choice.selection != select.selected { choice.selection = select.selected }
            choice.isUserInteractionEnabled = !select.unavailable
            choice.alpha = select.unavailable ? 0.4 : 1
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The Hue Sync brightness field (`HueSyncTab.brightnessField`): "Brightness" and its value over a slider that commits on release.
@MainActor
final class UKRemoteHueBrightnessRow: UKRowView {
    private let readState: () -> MediaRemoteController.BrightnessDisplay
    private let commit: (Double) -> Void
    private let editingChanged: (Bool) -> Void
    private let unavailableText: String?
    private let slider = UKRemoteSlider()
    private let bag = UKObservationBag()
    private var brightness = SliderDraft()

    convenience init(controller: MediaRemoteController, entityId: String) {
        self.init(title: "Brightness", state: { controller.hueBrightness(entityId) },
                  commit: { controller.setHueBrightness(entityId, value: $0) })
    }

    init(title: String, unavailableText: String? = nil, state: @escaping () -> MediaRemoteController.BrightnessDisplay,
         commit: @escaping (Double) -> Void, editingChanged: @escaping (Bool) -> Void = { _ in }) {
        readState = state
        self.commit = commit
        self.editingChanged = editingChanged
        self.unavailableText = unavailableText
        super.init(UKRowContent(title, value: " ", style: .form), surface: .sheet)
        isTextAccessible = false
        slider.tintColor = UIColor(HassTokens.RGB.Tint.light)
        slider.accessibilityLabel = title
        slider.accessibilityIdentifier = "remote.hue.brightness"
        slider.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        slider.addAction(UIAction { [weak self] _ in self?.beginEditing() }, for: .touchDown)
        slider.addAction(UIAction { [weak self] _ in self?.changed() }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in self?.endEditing() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
        setBody(slider)
        bag.observe { [weak self] in self?.refresh() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refresh() {
        let display = readState()
        let shown = brightness.shown(live: display.value)
        let valueText = display.isUnavailable ? (unavailableText ?? display.unavailableText ?? "Unavailable") : MediaRemoteState.numberString(shown)
        var content = rowContent
        content.value = valueText
        update(content)
        slider.minimumValue = Float(display.range.lowerBound)
        slider.maximumValue = Float(display.range.upperBound)
        slider.step = Float(display.step)
        if abs(Double(slider.value) - shown) > 0.0001 { slider.setValue(Float(shown), animated: false) }
        slider.isEnabled = !display.isUnavailable
        slider.accessibilityValue = valueText
    }

    private func beginEditing() {
        editingChanged(true)
        brightness.editingChanged(true, live: readState().value, commit: commit)
    }

    private func changed() {
        slider.snap()
        brightness.set(Double(slider.value), commit: commit)
        refresh()
    }

    private func endEditing() {
        brightness.editingChanged(false, live: readState().value, commit: commit)
        editingChanged(false)
        refresh()
    }
}

// MARK: - Lists

#endif
