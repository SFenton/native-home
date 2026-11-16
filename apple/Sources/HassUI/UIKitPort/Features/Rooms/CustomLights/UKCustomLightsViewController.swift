#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The Custom Lights page (`CustomLightsScreen`; web `CustomLightsPage.tsx`; spec `.agents/pages/custom-lights/spec.md`).
///
/// Manual control of the front yard lights; while it is on, the lighting mode; in Custom mode, a brightness tile per light (tap
/// opens its colour sheet) and Reset All Lights. The page is a hand-laid column on the wallpaper, up to 960 pt wide, with the page
/// padding; each tile is bound to its own light's entity box.
@MainActor
final class UKCustomLightsViewController: UKPageViewController {
    private let store: EntityStore
    private let caller: any HassServiceCalling
    /// A light whose sheet opens as soon as the page is on screen (gallery and journeys).
    private var pendingOpen: CustomLightsConfig.Light?

    private let column = UKFoldColumns(spacing: HassTokens.Spacing.m)
    private var scroll: UKPageScrollView!
    private var header = UKPageSectionHeaderView(CustomLightsConfig.frontYardTitle)
    /// Holds the observations of the light tiles, which come from the house document, so a rebuild ends the old ones.
    private let structureBag = UKObservationBag()
    private var manualRow: UKModuleToggleRow!
    private var modeRow: UKLightingModeButton!
    private var modeFitted: UKRoomsFittedView!
    private var frontYard: UKRoomsModuleStack!
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
    private var resetCard: UKRoomsModuleStack!
    private var tiles: [UKBrightnessTileView] = []
    private var hasRefreshed = false
    private var manualIsOn = false

    /// Creates the page.
    /// - Parameters:
    ///   - context: The page's context: its store and its caller (service calls go there; a recorder in the gallery).
    ///   - openLight: A light whose sheet opens at once (gallery and journeys).
    init(context: UKContext, openLight: CustomLightsConfig.Light? = nil) {
        store = context.store
        caller = context.roomsCaller
        pendingOpen = openLight
        super.init(context: context, title: "Custom Lights")
    }

    // MARK: View

    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .page }

    override func viewDidLoad() {
        super.viewDidLoad()
        manualRow = UKModuleToggleRow(ManualControlRow.title, symbol: "lightbulb.2", glyph: UIColor(ColorFamily.lights.offGlyphToken),
                                      isOn: false) { [weak self] in
            guard let self else { return }
            self.send(CustomLightsConfig.setManualControl(on: !self.manualIsOn))
        }
        manualRow.accessibilityIdentifier = "customLights.manual"
        // The page is tinted with the action ink (`.tint(HassTokens.Ink.action)`), which colours the switch's track.
        (manualRow.row.accessory as? UISwitch)?.onTintColor = UKInk.action

        modeRow = UKLightingModeButton { [weak self] mode in self?.send(CustomLightsConfig.selectMode(mode)) }
        modeFitted = UKRoomsFittedView(modeRow)
        frontYard = UKRoomsModuleStack(rows: [UKRoomsFittedView(manualRow), modeFitted])

        buildTiles()

        // Reset is a list row, not a grey button (direction G, Sheets and Primary buttons).
        let reset = UKRoomsActionRow(title: "Reset All Lights", symbol: "arrow.counterclockwise", identifier: "customLights.resetAll") { [weak self] in
            self?.confirmReset()
        }
        resetCard = UKRoomsModuleStack(hasGlyphs: false, rows: [UKRoomsFittedView(reset)])

        // Partly folded: the header and the switch and mode card lead; the light tiles and Reset All Lights trail, level with the card
        // (`.agents/design/section-sides.md`, rule 6). Lying flat the page is one column up to 960 pt, as before.
        setColumnSections()
        column.sideInset = HassTokens.Spacing.l
        column.flatMaxWidth = 960
        column.splitIdentifier = "customLights.columns.split"
        column.isRegular = { [weak self] in self?.traitCollection.horizontalSizeClass == .regular }
        column.offeredHeight = { [weak self] in self?.scroll.bounds.height ?? 0 }
        grid.isHidden = true
        resetCard.isHidden = true
        scroll = UKPageScrollView(content: column,
                                   padding: UIEdgeInsets(top: HassTokens.Spacing.m, left: 0, bottom: HassTokens.Spacing.m, right: 0))
        scroll.accessibilityIdentifier = "customLights.scroll"
        install(scrollView: scroll)

        grid.followsFold = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKCustomLightsViewController, _) in page.rescale() }
        rescale()
        bag.observe { [weak self] in self?.refresh() }
        bag.observe { [weak self] in
            guard let self else { return }
            column.hinge = context.shell?.windowHinge
        }
    }

    private func setColumnSections() {
        column.setSections([.init(header, side: .leading), .init(frontYard, side: .leading),
                            .init(grid, side: .trailing, levelWith: 1), .init(resetCard, side: .trailing)])
    }

    /// Builds the header title and a brightness tile per light from the house document. Called from `viewDidLoad` and again by
    /// ``houseLayoutDidChange()``.
    private func buildTiles() {
        structureBag.removeAll()
        tiles = []
        let environment = UKTileEnvironment(context: context)
        let store = self.store
        for light in CustomLightsConfig.lights {
            let state = store.entity(light.entityId).state
            let tile = UKBrightnessTileView(title: light.title, tint: UIColor(HassTokens.RGB.Tint.light),
                                            fillTint: CustomLightsConfig.RGB(entity: state).map(UIColor.init(lightRGB:)),
                                            percent: LightControl.percent(of: state), isUnavailable: state?.isUnavailable ?? true)
            tile.environment = environment
            tile.identifier = "customLights.light.\(light.entityId)"
            tile.onPower = { [weak self] on in self?.send(LightControl.power(light.entityId, on: on)) }
            tile.onBrightness = { [weak self] percent in self?.send(LightControl.brightness(light.entityId, percent: Double(percent))) }
            tile.onOpen = { [weak self] in self?.show(light) }
            tiles.append(tile)
            structureBag.observe { [weak tile] in
                let state = store.entity(light.entityId).state
                tile?.update(fillTint: CustomLightsConfig.RGB(entity: state).map(UIColor.init(lightRGB:)),
                             percent: LightControl.percent(of: state), isUnavailable: state?.isUnavailable ?? true)
            }
        }
        grid.setItems(tiles.map { UKGridItem($0) })
    }

    override func houseLayoutDidChange() {
        buildTiles()
        header = UKPageSectionHeaderView(CustomLightsConfig.frontYardTitle)
        setColumnSections()
        refresh()
        scroll.contentChanged(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let light = pendingOpen {
            pendingOpen = nil
            show(light)
        }
    }

    /// The tile width scales with Dynamic Type (`@ScaledMetric(relativeTo: .subheadline)`).
    private func rescale() {
        guard isViewLoaded else { return }
        var configuration = grid.configuration
        configuration.minCellWidth = UKFont.scaled(150, relativeTo: .subheadline, traits: traitCollection)
        grid.configuration = configuration
        scroll?.contentChanged(animated: false)
    }

    // MARK: State

    /// Reads the manual switch, the mode and the lights' colours (for the mode swatch) and shows them.
    private func refresh() {
        let manual = store.entity(CustomLightsConfig.manualControlEntityId).state
        let select = store.entity(CustomLightsConfig.modeEntityId).state
        let manualOn = manual?.state == "on"
        let mode = CustomLightsConfig.mode(select)
        let showsLights = manualOn && mode == CustomLightsConfig.customMode
        let unavailable = manual?.isUnavailable ?? true
        manualIsOn = manualOn

        manualRow.setOn(manualOn, animated: hasRefreshed)
        manualRow.row.update(
            UKRowContent(ManualControlRow.title, symbol: "lightbulb.2",
                               glyph: UIColor(manualOn ? ColorFamily.lights.glyphToken : ColorFamily.lights.offGlyphToken), glyphOpacity: unavailable ? 0.5 : 1),
            accessory: manualRow.row.accessory)
        manualRow.isEnabled = !unavailable

        modeRow.configure(mode: mode, swatch: swatch(mode), modes: CustomLightsConfig.modes(select))

        let structureChanged = modeFitted.isHidden == manualOn || grid.isHidden == showsLights
        modeFitted.isHidden = !manualOn
        grid.isHidden = !showsLights
        resetCard.isHidden = !showsLights
        if structureChanged || !hasRefreshed { scroll.contentChanged(animated: hasRefreshed) }
        hasRefreshed = true
    }

    /// The swatch for a mode; Custom shows the lights' live colours.
    private func swatch(_ mode: String) -> [CustomLightsConfig.RGB] {
        let colors = CustomLightsConfig.lights.compactMap { CustomLightsConfig.RGB(entity: store.entity($0.entityId).state) }
        return CustomLightsConfig.swatch(for: mode, custom: colors)
    }

    // MARK: Actions

    private func send(_ call: ServiceCall) { caller.fire(call) }

    private func send(_ command: LightControl.Command) {
        let caller = caller
        Task { try? await caller.callService(command.domain, command.service, data: command.serviceData) }
    }

    private func confirmReset() {
        UKRoomsAlert.present(AlertCopy.resetAllLights(count: CustomLightsConfig.lights.count), from: self,
                             confirmID: "customLights.resetAll.confirm") { [weak self] in
            self?.send(CustomLightsConfig.reset())
        }
    }

    /// Presents a light's sheet (`hassSheet(.page)`).
    private func show(_ light: CustomLightsConfig.Light) {
        guard presentedViewController == nil else { return }
        let sheet = UKCustomLightSheetViewController(light: light, context: context.with { $0.surface = .sheet })
        var options = UKHassModalOptions(title: light.title)
        options.width = .page
        let modal = UKHassModalController(root: sheet, options: options)
#if DEBUG
        UKRoomsLastCall.attach(to: modal, caller: context.caller)
#endif
        modal.present(from: self)
    }
}

// MARK: - Lighting Mode row

/// The Lighting Mode row: palette icon, then the mode's swatch and name in the tint with the pop-up chevrons (`LightingModeButton`,
/// web `modeSelect`). A pop-up menu of the modes showing the current one (HIG, Pop-up buttons): no sheet and no plain chevron. A
/// `UIButton` whose primary action is the menu, drawn as a module row with the pressed highlight of ``UKRowButton``.
@MainActor
final class UKLightingModeButton: UIButton {
    private let row: UKRowView
    private let highlightView = UIView()
    private let swatchHolder = UIView()
    private var swatchView: UKGradientSwatch?
    private var swatchColors: [UIColor] = []
    private let modeLabel = UILabel.uk(.body, ink: UKInk.action)
    private var mode = ""
    private let select: (String) -> Void

    init(select: @escaping (String) -> Void) {
        self.select = select
        let chevron = UIImageView(image: UIImage(systemName: "chevron.up.chevron.down",
                                                 withConfiguration: UIImage.SymbolConfiguration(font: UKFont.footnoteEmphasis())))
        chevron.tintColor = UKInk.action
        chevron.contentMode = .center
        chevron.isAccessibilityElement = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        swatchHolder.setContentHuggingPriority(.required, for: .horizontal)
        swatchHolder.setContentCompressionResistancePriority(.required, for: .horizontal)
        swatchHolder.isAccessibilityElement = false
        modeLabel.isAccessibilityElement = false
        let accessory = UIStackView(arrangedSubviews: [swatchHolder, modeLabel, chevron])
        accessory.axis = .horizontal
        accessory.alignment = .center
        accessory.spacing = HassTokens.Spacing.s
        accessory.isUserInteractionEnabled = false
        row = UKRowView(UKRowContent(CustomLightsConfig.lightingModeTitle, symbol: "paintpalette"), accessory: accessory)
        super.init(frame: .zero)
        highlightView.backgroundColor = UKDesignInk.primary
        highlightView.alpha = 0
        highlightView.isUserInteractionEnabled = false
        row.isUserInteractionEnabled = false
        for view in [highlightView, row] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.ukPin(to: self)
        }
        showsMenuAsPrimaryAction = true
        isAccessibilityElement = true
        accessibilityIdentifier = "customLights.mode"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the mode, its swatch and the modes the select offers.
    func configure(mode: String, swatch: [CustomLightsConfig.RGB], modes: [String]) {
        self.mode = mode
        modeLabel.text = mode
        setSwatch(swatch.map(UIColor.init(lightRGB:)))
        let actions = modes.map { option in
            UIAction(title: option, state: option == mode ? .on : .off) { [weak self] _ in self?.select(option) }
        }
        // An inline `Picker` in a `Menu`: the modes as one group titled for the setting.
        menu = UIMenu(title: CustomLightsConfig.lightingModeTitle, options: .displayInline, children: actions)
    }

    private func setSwatch(_ colors: [UIColor]) {
        guard colors != swatchColors else { return }
        swatchColors = colors
        let replace = {
            self.swatchView?.removeFromSuperview()
            self.swatchView = nil
            if !colors.isEmpty {
                let view = UKGradientSwatch(colors: colors)
                view.translatesAutoresizingMaskIntoConstraints = false
                self.swatchHolder.addSubview(view)
                view.ukPin(to: self.swatchHolder)
                self.swatchView = view
            }
            self.swatchHolder.isHidden = colors.isEmpty
        }
        // The swatch's colours follow state (`stateColorTransition`).
        if swatchHolder.window != nil {
            UKMotion.stateFade("LightingModeButton", view: swatchHolder, animated: true, replace)
        } else {
            replace()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            if isHighlighted {
                highlightView.alpha = 0.10
            } else {
                UKMotion.quick { self.highlightView.alpha = 0 }
            }
        }
    }

    override var accessibilityLabel: String? {
        get { CustomLightsConfig.lightingModeTitle }
        set {}
    }

    override var accessibilityValue: String? {
        get { mode }
        set {}
    }

    override var accessibilityHint: String? {
        get { "Shows the lighting modes." }
        set {}
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { .button }
        set {}
    }
}

extension UIColor {
    /// A Home Assistant `rgb_color` (`Color.init(rgb:)`).
    convenience init(lightRGB rgb: CustomLightsConfig.RGB) {
        self.init(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}
#endif
