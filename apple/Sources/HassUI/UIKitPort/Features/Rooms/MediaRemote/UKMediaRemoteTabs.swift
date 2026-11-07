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
    /// Where the tile is drawn (`EnvironmentValues.tileSurface`).
    var surface: TileSurface { didSet { if surface != oldValue { applyColors() } } }
    /// The accessibility identifier is this plus the app's title.
    var identifierPrefix = "remote.app."
    /// Called when a configure changed the tile's height (another app, or "Playing" appearing or going): a grid that caches its tracks
    /// measures again (`grid.setItems(grid.items)`).
    var onHeightChange: (() -> Void)?

    private static let maximumArtwork: CGFloat = AppTile.maximumArtwork

    private(set) var app: MediaRemoteApp?
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
        accessibilityIdentifier = identifierPrefix + app.title
        switch display.semantics {
        case let .toggle(isOn):
            semanticTraits = [.button, .toggleButton]
            accessibilityValue = isOn ? "On" : "Off"
        case let .selection(isSelected):
            semanticTraits = isSelected ? [.button, .selected] : .button
            accessibilityValue = display.isActive ? "Playing" : nil
        case .command, .state:
            semanticTraits = .button
            accessibilityValue = display.isActive ? "Playing" : nil
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
        fallback.image = UIImage(systemName: SymbolMap.symbol(for: app.icon ?? "mdi:play-box"),
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

/// The Apps section (`RemoteAppsTab`): the section title over a grid of app tiles, 100 pt columns (scaled with the subheadline) up to
/// four, equal row heights.
@MainActor
final class UKRemoteAppsView: UIView, UKGridMeasuring {
    private let controller: MediaRemoteController
    private let column = UKColumnView(spacing: HassTokens.Spacing.m)
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(fill: .none))
    private let bag = UKObservationBag()

    init(controller: MediaRemoteController, imageServer: HassServer?, context: UKContext) {
        self.controller = controller
        super.init(frame: .zero)
        let tiles = controller.config.apps.map { app -> UKAppTileView in
            let tile = UKAppTileView(surface: .sheet)
            let url = imageServer.flatMap { server in app.imagePath.map { server.url($0) } }
            bag.observe { [weak tile] in
                tile?.configure(app: app, display: controller.display(app), imageURL: url) { controller.tap(app) }
            }
            tile.onHeightChange = { [weak self] in
                guard let self else { return }
                grid.setItems(grid.items)
            }
            return tile
        }
        grid.setItems(tiles.map { UKGridItem($0) })
        grid.hinge = context.shell?.windowHinge
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            var configuration = grid.configuration
            configuration.minCellWidth = UKFont.scaled(DynamicGridMetrics.tileMinWidth, relativeTo: .subheadline, traits: traitCollection)
            configuration.maxColumns = 4
            configuration.equalRowHeights = true
            grid.configuration = configuration
        }
        column.setViews([UKPageSectionHeaderView(controller.config.appSectionTitle, inSheet: true), grid])
        addSubview(column)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        column.frame = bounds
    }
}

// MARK: - Label rows

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
    init(controller: MediaRemoteController, device: MediaRemoteDevice) {
        super.init(frame: .zero)
        accessibilityIdentifier = "remote.device.\(device.title)"
        onTap { controller.tap(device) }
        bag.observe { [weak self] in
            guard let self else { return }
            let display = controller.display(device)
            let active = display.isActive && !display.isUnavailable
            let color = active ? UKRemoteStyle.mediaGlyph : UKRemoteStyle.mediaOffGlyph
            let symbol = SymbolMap.symbol(for: device.icon)
            switch display.semantics {
            case let .toggle(isOn):
                show(title: device.title, subtitle: display.subtitle, symbol: symbol, iconColor: color, trailing: .toggle)
                setSwitch(isOn)
                asSwitch(label: "\(device.title), \(display.subtitle)", isOn: isOn)
            case .command:
                // Every command device toggles its device (`media_player.toggle`, the PC's on/off pair).
                show(title: device.title, subtitle: display.subtitle, symbol: symbol, iconColor: color, trailing: .toggle)
                setSwitch(display.isActive)
                asSwitch(label: "\(device.title), \(display.subtitle)", isOn: display.isActive)
            case let .selection(isSelected):
                show(title: device.title, subtitle: display.subtitle, symbol: symbol, iconColor: color, trailing: .checkmark)
                setChecked(isSelected)
                accessibilityLabel = device.title
                accessibilityValue = display.subtitle
                semanticTraits = isSelected ? [.button, .selected] : .button
            case .state:
                show(title: device.title, subtitle: display.subtitle, symbol: symbol, iconColor: color, trailing: .plain)
                accessibilityLabel = device.title
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
    init(controller: MediaRemoteController, title: String, entityId: String, symbol: String,
         offProjections: [String] = [], onProjections: [String] = []) {
        super.init(frame: .zero)
        accessibilityIdentifier = "remote.hue.\(title)"
        onTap { controller.toggleHue(entityId, offProjections: offProjections, onProjections: onProjections) }
        bag.observe { [weak self] in
            guard let self else { return }
            let toggle = controller.hueToggle(entityId)
            show(title: title, subtitle: nil, symbol: symbol, iconColor: toggle.isOn ? UKRemoteStyle.lightsGlyph : UKRemoteStyle.lightsOffGlyph,
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
    init(controller: MediaRemoteController, hue: HueSyncConfig, option: String) {
        super.init(frame: .zero)
        accessibilityIdentifier = "remote.hue.hdmi.\(option)"
        onTap { controller.selectHue(hue.hdmiInputEntityId, option: option) }
        bag.observe { [weak self] in
            guard let self, let input = controller.hdmiInputs(hue).first(where: { $0.option == option }) else { return }
            let lit = input.isSelected && !input.isDisconnected
            show(title: input.option, subtitle: input.subtitle, symbol: input.isDisconnected ? "tv.slash" : "tv",
                 iconColor: lit ? UKRemoteStyle.mediaGlyph : UKRemoteStyle.mediaOffGlyph, trailing: .checkmark)
            setChecked(input.isSelected)
            accessibilityLabel = input.option
            accessibilityValue = input.subtitle
            semanticTraits = input.isSelected ? [.button, .selected] : .button
            // Outside the combined element, so an unplugged port reads as dimmed.
            isEnabled = !input.isDisabled
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A short Hue Sync choice (`HueSyncTab.choice`): a segmented control (a menu at accessibility sizes), or "Unavailable" while the
/// select reports no options.
@MainActor
final class UKRemoteHueChoiceRow: UIView {
    private let bag = UKObservationBag()
    private let unavailable = UILabel.uk(.body, ink: UKDesignInk.secondary)
    private let choice: UKSegmentedChoice<String>

    /// - Parameter ordersSyncModes: Lists the options in the Sync Box's mode order (`MediaRemoteState.orderedSyncModes`).
    init(controller: MediaRemoteController, title: String, entityId: String, identifier: String, ordersSyncModes: Bool = false,
         choose: @escaping (String) -> Void) {
        choice = UKSegmentedChoice<String>(label: title, options: [], title: { StateText.titleCase($0) }, selection: nil,
                                           identifier: identifier, select: choose)
        super.init(frame: .zero)
        unavailable.text = "Unavailable"
        unavailable.isAccessibilityElement = true
        unavailable.accessibilityLabel = title
        unavailable.accessibilityValue = "Unavailable"
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
            let select = controller.hueSelect(entityId)
            let options = ordersSyncModes ? MediaRemoteState.orderedSyncModes(select.options) : select.options
            unavailable.isHidden = !options.isEmpty
            choice.isHidden = options.isEmpty
            if choice.options != options { choice.options = options }
            if choice.selection != select.selected { choice.selection = select.selected }
            choice.isUserInteractionEnabled = !select.isUnavailable
            choice.alpha = select.isUnavailable ? 0.4 : 1
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The Hue Sync brightness field (`HueSyncTab.brightnessField`): "Brightness" and its value over a slider that commits on release.
@MainActor
final class UKRemoteHueBrightnessRow: UKRowView {
    private let controller: MediaRemoteController
    private let entityId: String
    private let slider = UKRemoteSlider()
    private let bag = UKObservationBag()
    private var brightness = SliderDraft()

    init(controller: MediaRemoteController, entityId: String) {
        self.controller = controller
        self.entityId = entityId
        super.init(UKRowContent("Brightness", value: " ", style: .form), surface: .sheet)
        isTextAccessible = false
        slider.tintColor = UIColor(HassTokens.RGB.Tint.light)
        slider.accessibilityLabel = "Brightness"
        slider.accessibilityIdentifier = "remote.hue.brightness"
        slider.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        slider.addAction(UIAction { [weak self] _ in self?.beginEditing() }, for: .touchDown)
        slider.addAction(UIAction { [weak self] _ in self?.changed() }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in self?.endEditing() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
        setBody(slider)
        bag.observe { [weak self] in self?.refresh() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var commit: (Double) -> Void {
        { [controller, entityId] in controller.setHueBrightness(entityId, value: $0) }
    }

    private func refresh() {
        let display = controller.hueBrightness(entityId)
        let shown = brightness.shown(live: display.value)
        let valueText = display.unavailableText ?? MediaRemoteState.numberString(shown)
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
        brightness.editingChanged(true, live: controller.hueBrightness(entityId).value, commit: commit)
    }

    private func changed() {
        slider.snap()
        brightness.set(Double(slider.value), commit: commit)
        refresh()
    }

    private func endEditing() {
        brightness.editingChanged(false, live: controller.hueBrightness(entityId).value, commit: commit)
        refresh()
    }
}

// MARK: - Lists

/// The Devices section (`RemoteDevicesTab`): the remote's devices as an inset grouped list under a "Devices" header.
@MainActor
final class UKRemoteDevicesViewController: UKPaneViewController {
    private let form = UKFormViewController()
    private let controller: MediaRemoteController

    init(controller: MediaRemoteController) {
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let controller = controller
        form.setSections([
            UKFormSection(id: "devices", header: "Devices", headerStyle: .system, rows: controller.config.devices.map { device in
                UKFormRow(id: device.id, .custom { UKRemoteDeviceRow(controller: controller, device: device) })
            }),
        ], animated: false)
        addChild(form)
        form.view.frame = view.bounds
        form.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(form.view)
        form.didMove(toParent: self)
    }
}

/// The Hue Sync section (`HueSyncTab`): Sync Box power and light sync, sync mode, intensity and brightness, and HDMI input, as an
/// inset grouped list (direction G, n4 remote Hue Sync). Departure from the web: tapping the selected sync mode again while not syncing
/// no longer restarts syncing (a segmented control does not report a tap on its selected segment); Light Sync starts it.
@MainActor
final class UKRemoteHueSyncViewController: UKPaneViewController {
    private let form = UKFormViewController()
    private let controller: MediaRemoteController
    private let hue: HueSyncConfig
    private let bag = UKObservationBag()
    private var shownInputs: [String]?

    init(controller: MediaRemoteController, hue: HueSyncConfig) {
        self.controller = controller
        self.hue = hue
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(form)
        form.view.frame = view.bounds
        form.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(form.view)
        form.didMove(toParent: self)
        // The HDMI rows follow the select's options (HDMI 1 to 4 until it reports any); the rows bind themselves.
        bag.observe { [weak self] in
            guard let self else { return }
            let inputs = controller.hdmiInputs(hue).map(\.option)
            if inputs != shownInputs {
                shownInputs = inputs
                form.setSections(sections(inputs: inputs), animated: false)
            }
        }
    }

    private func sections(inputs: [String]) -> [UKFormSection] {
        let controller = controller
        let hue = hue
        return [
            UKFormSection(id: "power", header: "Power and Sync", footer: HueSyncTab.help, headerStyle: .system, rows: [
                UKFormRow(id: "power", .custom {
                    UKRemoteHueToggleRow(controller: controller, title: "Sync Box Power", entityId: hue.powerEntityId, symbol: "power",
                                         offProjections: [hue.lightSyncEntityId])
                }),
                UKFormRow(id: "lightSync", .custom {
                    UKRemoteHueToggleRow(controller: controller, title: "Light Sync", entityId: hue.lightSyncEntityId, symbol: "lightbulb.2",
                                         onProjections: [hue.powerEntityId])
                }),
            ]),
            UKFormSection(id: "mode", header: "Sync Mode", headerStyle: .system, rows: [
                UKFormRow(id: "mode", .custom {
                    UKRemoteHueChoiceRow(controller: controller, title: "Sync Mode", entityId: hue.syncModeEntityId, identifier: "remote.hue.mode",
                                         ordersSyncModes: true) { controller.selectSyncMode(hue, mode: $0) }
                }),
            ]),
            UKFormSection(id: "intensity", header: "Intensity", headerStyle: .system, rows: [
                UKFormRow(id: "intensity", .custom {
                    UKRemoteHueChoiceRow(controller: controller, title: "Intensity", entityId: hue.intensityEntityId, identifier: "remote.hue.intensity") {
                        controller.selectHue(hue.intensityEntityId, option: $0)
                    }
                }),
                UKFormRow(id: "brightness", .custom { UKRemoteHueBrightnessRow(controller: controller, entityId: hue.brightnessEntityId) }),
            ]),
            UKFormSection(id: "hdmi", header: "HDMI Input", headerStyle: .system, rows: inputs.map { option in
                UKFormRow(id: "hdmi.\(option)", .custom { UKRemoteHdmiRow(controller: controller, hue: hue, option: option) })
            }),
        ]
    }
}
#endif
