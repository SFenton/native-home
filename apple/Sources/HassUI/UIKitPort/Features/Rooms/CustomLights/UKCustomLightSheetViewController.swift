#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// One custom light's sheet (`CustomLightSheet`; web `LightMoreInfoSheet.tsx`): its brightness tile and, for colour lights, the
/// Color, Reset to Warm White and Apply to All Lights rows, and one swatch per other light to copy that light's colour (direction G,
/// n4 custom light sheet).
///
/// The web draws a hue wheel and RGB sliders; the app uses the system colour picker instead (`UIColorWell`; HIG: Color wells), which
/// offers the same wheel, sliders and eyedropper and is familiar to VoiceOver users. A picked colour is sent 250 ms after the picker
/// settles. The page is the root of a ``UKHassModalController`` (`hassSheet(.page)`); its scroll view is the fit scroller.
@MainActor
final class UKCustomLightSheetViewController: UKPageViewController, UKSheetFitting {
    private let light: CustomLightsConfig.Light
    private let store: EntityStore
    private let caller: any HassServiceCalling
    private var pendingColor: Task<Void, Never>?
    private var currentRGB: CustomLightsConfig.RGB?

    private var scroll: UKPageScrollView!
    private let column = UKColumnView(spacing: HassTokens.Spacing.xl)
    private var tile: UKBrightnessTileView!
    private var colorRow: UKCustomLightColorRow!
    private var colorStack: UKRoomsModuleStack!
    private var resetRow: UKRoomsActionRow!
    private var applyRow: UKRoomsActionRow!
    private var othersSection: UKColumnView!
    private var swatches: [UKOtherLightSwatchView] = []
    private let swatchGrid = UKDynamicGridView(configuration: UKGridConfiguration(
        minCellWidth: 76, maxColumns: 4, spacing: HassTokens.Spacing.s, equalRowHeights: true))
    private var hasShown = false

    var sheetFitScrollView: UIScrollView? { scroll }

    /// - Parameters:
    ///   - light: The light.
    ///   - context: The sheet's context (`surface` is `.sheet`).
    init(light: CustomLightsConfig.Light, context: UKContext) {
        self.light = light
        store = context.store
        caller = context.roomsCaller
        super.init(context: context.with { $0.surface = .sheet }, title: light.title)
        navigationItem.title = light.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// "On · 80%", "Off" or "Unavailable" (`CustomLightSheet.subtitle`).
    static func subtitle(_ state: EntityState?) -> String { CustomLightSheet.subtitle(state) }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        let store = self.store
        let light = self.light

        let state = store.entity(light.entityId).state
        tile = UKBrightnessTileView(title: light.title, tint: UIColor(HassTokens.RGB.Tint.light),
                                    fillTint: CustomLightsConfig.RGB(entity: state).map(UIColor.init(lightRGB:)),
                                    percent: LightControl.percent(of: state), isUnavailable: state?.isUnavailable ?? true)
        tile.environment = UKTileEnvironment(context: context)
        tile.identifier = "customLight.brightness"
        tile.onPower = { [weak self] on in self?.send(LightControl.power(light.entityId, on: on)) }
        tile.onBrightness = { [weak self] percent in self?.send(LightControl.brightness(light.entityId, percent: Double(percent))) }

        // On the sheet's #2C2C2E cell; hairlines start at the row margin.
        colorRow = UKCustomLightColorRow { [weak self] color in self?.picked(color) }
        resetRow = UKRoomsActionRow(title: "Reset to Warm White", symbol: "arrow.counterclockwise", identifier: "customLight.reset",
                                    disabledInk: UKDesignSurface.secondaryInSheet) { [weak self] in
            guard let self else { return }
            self.caller.fire(CustomLightsConfig.reset(self.light.entityId))
        }
        applyRow = UKRoomsActionRow(title: "Apply to All Lights", symbol: "lightbulb.2", identifier: "customLight.applyAll",
                                    disabledInk: UKDesignSurface.secondaryInSheet) { [weak self] in
            self?.confirmApplyAll()
        }
        colorStack = UKRoomsModuleStack(hasGlyphs: false, surface: .sheet,
                                        rows: [UKRoomsFittedView(colorRow), UKRoomsFittedView(resetRow), UKRoomsFittedView(applyRow)])

        let others = CustomLightsConfig.lights.filter { $0 != light }
        for other in others {
            let swatch = UKOtherLightSwatchView(light: other) { [weak self] color in
                guard let self else { return }
                self.caller.fire(CustomLightsConfig.setColor(color, on: self.light.entityId))
            }
            swatches.append(swatch)
            bag.observe { [weak swatch] in
                let state = store.entity(other.entityId).state
                swatch?.show(rgb: CustomLightsConfig.RGB(entity: state), isUnavailable: state?.isUnavailable ?? true)
            }
        }
        swatchGrid.setItems(swatches.map { UKGridItem($0) })
        let gridBox = UKRoomsInsetBox(swatchGrid, insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: HassTokens.Spacing.m,
                                                                        bottom: HassTokens.Spacing.m, right: HassTokens.Spacing.m),
                                      fill: UKDesignSurface.sheetCell, cornerRadius: HassTokens.Radius.module)
        let othersHeader = UKPageSectionHeaderView("Copy Color From", inSheet: true)
        let othersColumn = UKColumnView(spacing: HassTokens.Spacing.m)
        othersColumn.setViews([othersHeader, gridBox])
        othersSection = othersColumn
        othersColumn.isHidden = others.isEmpty

        column.setViews([tile, colorStack, othersColumn])
        scroll = UKPageScrollView(content: column, maxWidth: 640, padding: UIEdgeInsets(
            top: HassTokens.Spacing.l, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l))
        install(scrollView: scroll)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKCustomLightSheetViewController, _) in page.rescale() }
        rescale()
        bag.observe { [weak self] in self?.refresh() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if swatchGrid.hinge != UKHinge.frame { swatchGrid.hinge = UKHinge.frame }
    }

    /// The swatch width scales with Dynamic Type (`@ScaledMetric(relativeTo: .subheadline)`).
    private func rescale() {
        var configuration = swatchGrid.configuration
        configuration.minCellWidth = UKFont.scaled(76, relativeTo: .subheadline, traits: traitCollection)
        swatchGrid.configuration = configuration
        scroll?.contentChanged(animated: false)
    }

    // MARK: State

    private func refresh() {
        let state = store.entity(light.entityId).state
        let rgb = CustomLightsConfig.RGB(entity: state)
        let unavailable = state?.isUnavailable ?? true
        currentRGB = rgb
        UKSheetSubtitle.apply(Self.subtitle(state), to: navigationItem)

        tile.update(fillTint: rgb.map(UIColor.init(lightRGB:)), percent: LightControl.percent(of: state), isUnavailable: unavailable)

        let supportsColor = CustomLightsConfig.supportsColor(state)
        let hasOthers = CustomLightsConfig.lights.contains { $0 != light }
        colorStack.isHidden = !supportsColor
        othersSection.isHidden = !(supportsColor && hasOthers)
        colorRow.show(rgb: rgb, isEnabled: !unavailable, holdsSelection: pendingColor != nil)
        resetRow.isEnabled = !unavailable
        applyRow.isEnabled = !(unavailable || rgb == nil)
        scroll.contentChanged(animated: hasShown)
        hasShown = true
    }

    // MARK: Actions

    private func send(_ command: LightControl.Command) {
        let caller = caller
        Task { try? await caller.callService(command.domain, command.service, data: command.serviceData) }
    }

    /// Sends a picked colour once the picker settles, so dragging across the wheel does not flood the light.
    private func picked(_ color: UIColor) {
        guard let picked = CustomLightsConfig.RGB(uiColor: color), picked != currentRGB else { return }
        pendingColor?.cancel()
        pendingColor = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.pendingColor = nil
            self.caller.fire(CustomLightsConfig.setColor(picked, on: self.light.entityId))
        }
    }

    private func confirmApplyAll() {
        UKRoomsAlert.present(AlertCopy.applyToAllLights(count: CustomLightsConfig.lights.count), from: self,
                             confirmID: "customLight.applyAll.confirm") { [weak self] in
            guard let self, let rgb = self.currentRGB else { return }
            self.caller.fire(CustomLightsConfig.setColor(rgb, on: CustomLightsConfig.groupEntityId))
        }
    }
}

// MARK: - Color row

/// The Color row (`ColorPicker` with a `Label`): the palette icon and "Color" in primary ink, and the system colour well at the
/// trailing edge. 52 pt at least; the well is the row's accessibility element.
@MainActor
final class UKCustomLightColorRow: UKRowView {
    private let well = UIColorWell()
    private let onPick: (UIColor) -> Void

    init(onPick: @escaping (UIColor) -> Void) {
        self.onPick = onPick
        super.init(UKRowContent("Color", symbol: "paintpalette", glyph: UKDesignInk.primary, style: .module))
        well.supportsAlpha = false
        well.title = "Color"
        well.selectedColor = .white
        well.accessibilityLabel = "Color"
        well.accessibilityIdentifier = "customLight.color"
        well.setContentHuggingPriority(.required, for: .horizontal)
        well.addAction(UIAction { [weak self] _ in
            guard let self, let color = self.well.selectedColor else { return }
            self.onPick(color)
        }, for: .valueChanged)
        setAccessory(well)
        isTextAccessible = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the light's colour (white while it has none) and whether the well can be used. While a pick is waiting to be sent the
    /// well keeps what the person chose.
    func show(rgb: CustomLightsConfig.RGB?, isEnabled: Bool, holdsSelection: Bool) {
        well.isEnabled = isEnabled
        guard !holdsSelection else { return }
        let color = rgb.map(UIColor.init(lightRGB:)) ?? .white
        if well.selectedColor != color { well.selectedColor = color }
    }
}

// MARK: - Other light swatch

/// Copies another light's colour onto the open light (`OtherLightSwatch`; web `OtherLightButton`): a circle of its colour with its
/// name under it, or an empty ring and "Off" (or "Unavailable") while it has no colour. An off light reads as plain text and ignores
/// taps (a disabled one dimmed its status to 2:1 on a light sheet's white cell).
@MainActor
final class UKOtherLightSwatchView: UIControl, UKGridMeasuring {
    private let light: CustomLightsConfig.Light
    private let apply: (CustomLightsConfig.RGB) -> Void
    private let circle = UIView()
    private let nameLabel = UILabel.uk(.footnote, ink: UKInk.secondary, alignment: .center)
    private let statusLabel = UILabel.uk(.footnote, ink: UKInk.secondary, alignment: .center)
    private var rgb: CustomLightsConfig.RGB?
    private var isUnavailableLight = false
    private var hasShown = false

    init(light: CustomLightsConfig.Light, apply: @escaping (CustomLightsConfig.RGB) -> Void) {
        self.light = light
        self.apply = apply
        super.init(frame: .zero)
        circle.isUserInteractionEnabled = false
        circle.layer.borderWidth = 0
        for label in [nameLabel, statusLabel] {
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = false
        }
        nameLabel.text = light.title
        addSubview(circle)
        addSubview(nameLabel)
        addSubview(statusLabel)
        isAccessibilityElement = true
        accessibilityLabel = "Apply \(light.title) Color"
        accessibilityIdentifier = "customLight.other.\(light.entityId)"
        addAction(UIAction { [weak self] _ in
            guard let self, let rgb = self.rgb else { return }
            self.apply(rgb)
        }, for: .touchUpInside)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKOtherLightSwatchView, _) in
            view.setNeedsLayout()
            view.invalidateIntrinsicContentSize()
        }
        show(rgb: nil, isUnavailable: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the other light's colour and availability.
    func show(rgb: CustomLightsConfig.RGB?, isUnavailable: Bool) {
        let changed = rgb != self.rgb
        self.rgb = rgb
        isUnavailableLight = isUnavailable
        let status = rgb == nil ? (isUnavailable ? "Unavailable" : "Off") : nil
        statusLabel.text = status
        statusLabel.isHidden = status == nil
        isUserInteractionEnabled = rgb != nil
        accessibilityValue = rgb == nil ? (isUnavailable ? "Unavailable" : "Off") : ""
        // An off light has no colour to apply: plain text, not a button that does nothing.
        accessibilityTraits = rgb != nil ? .button : []
        let paint = {
            if let rgb {
                self.circle.backgroundColor = UIColor(lightRGB: rgb)
                self.circle.layer.borderWidth = 0
            } else {
                self.circle.backgroundColor = .clear
                self.circle.layer.borderWidth = 1.5
                self.circle.layer.borderColor = UKDesignSurface.secondaryInSheet.resolvedColor(with: self.traitCollection).cgColor
            }
        }
        if changed, hasShown, window != nil {
            UKMotion.stateFade("OtherLightSwatch", view: circle, animated: true, paint)
        } else {
            paint()
        }
        hasShown = true
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    private var diameter: CGFloat {
        max(UKFont.scaled(48, relativeTo: .title1, traits: traitCollection), HassTokens.minTarget)
    }

    private func labelHeight(_ label: UILabel, width: CGFloat) -> CGFloat {
        ceil(label.sizeThatFits(CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude)).height)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        var height = diameter + HassTokens.Spacing.xs + labelHeight(nameLabel, width: width)
        if !statusLabel.isHidden { height += HassTokens.Spacing.xs + labelHeight(statusLabel, width: width) }
        return height
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let d = diameter
        circle.frame = CGRect(x: (bounds.width - d) / 2, y: 0, width: d, height: d)
        circle.layer.cornerRadius = d / 2
        var y = d + HassTokens.Spacing.xs
        let nameHeight = labelHeight(nameLabel, width: bounds.width)
        nameLabel.frame = CGRect(x: 0, y: y, width: bounds.width, height: nameHeight)
        y += nameHeight + HassTokens.Spacing.xs
        statusLabel.frame = CGRect(x: 0, y: y, width: bounds.width, height: statusLabel.isHidden ? 0 : labelHeight(statusLabel, width: bounds.width))
    }
}
#endif
