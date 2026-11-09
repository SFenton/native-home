#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

/// Gallery page for direction G's foundation (`.agents/design/direction-g.md`): the arc spinner, status chips, tile faces and the
/// light dragger, modules, the primary button, and a sheet with tiles on the sheet surface. Drawn on a stand-in wallpaper (a photo-like
/// gradient under G's scrim) so screenshots and the rendered contrast audit see the same layering as a page. Launch with
/// `FENTON_GALLERY=direction-g`; the same launch arguments as the SwiftUI page (`-directionGSheet open`, `-directionGOrder lower|layouts|finish`,
/// `-directionGFinish solid`, `-directionGLayout row`, `-directionGAnimate YES`, `-directionGSheetSection Families`).
///
/// Not the design tiles lane's: the primary button, the modal chrome and its bottom section bar (the sheet uses a segmented control
/// in a toolbar here), and the module list of the sheet's Settings section. Those stand in until the controls and lists lanes land.
@MainActor
enum UKDirectionGGallery {
    static func make() -> UIViewController {
        UKGalleryGround.navigation(root: UKDirectionGViewController())
    }
}

/// A Direction G gallery option: the `FENTON_GALLERY_DIRECTION_G_*` variable (which a reused journey app changes per test) wins over
/// the launch argument `key`. Read when the gallery is built, never cached per process.
func ukDirectionGOption(_ key: String, environment: String) -> String? {
    ProcessInfo.processInfo.environment[environment] ?? UserDefaults.standard.string(forKey: key)
}

@MainActor
final class UKDirectionGViewController: UIViewController {
    private var lastAction = "none" { didSet { lastCallLabel.text = "Last action: \(lastAction)" } }
    private var brightness = 60
    private let lastCallLabel = UILabel()
    private weak var lightTile: UKBrightnessTileView?
    private let defaults = UserDefaults.standard

    /// `-directionGOrder` and `-directionGLayout` also come as `FENTON_GALLERY_DIRECTION_G_ORDER` / `FENTON_GALLERY_DIRECTION_G_LAYOUT`, which
    /// a reused journey app can change between tests (a launch argument cannot be reset, so it always launches fresh). The variable wins.
    private func option(_ key: String, environment: String) -> String? {
        ukDirectionGOption(key, environment: environment)
    }

    private var order: String? { option("directionGOrder", environment: "FENTON_GALLERY_DIRECTION_G_ORDER") }
    private var lowerFirst: Bool { order == "lower" }
    private var layoutsOnly: Bool { order == "layouts" }
    private var finishOnly: Bool { order == "finish" }
    private var onlyFinish: TileFinish? {
        option("directionGFinish", environment: "FENTON_GALLERY_DIRECTION_G_FINISH").flatMap(TileFinish.init(rawValue:))
    }
    private var onlyLayout: TileLayout? {
        option("directionGLayout", environment: "FENTON_GALLERY_DIRECTION_G_LAYOUT").flatMap(TileLayout.init(rawValue:))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Direction G"
        navigationItem.largeTitleDisplayMode = .always
        // Still arcs, so XCUITest sees the app go idle (`animationsPaused`); `-directionGAnimate YES` turns them.
        UKDesign.animationsPaused = !defaults.bool(forKey: "directionGAnimate")

        let wallpaper = UKGalleryWallpaperView()
        wallpaper.frame = view.bounds
        wallpaper.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(wallpaper)

        var sections: [UIView] = []
        if ProcessInfo.processInfo.environment["FENTON_GALLERY_CLEAN"] != "1" {
            sections.append(lastCall())
        }
        if finishOnly {
            sections.append(finishes())
        } else if layoutsOnly {
            sections.append(layouts())
        } else if lowerFirst {
            sections += lower() + [chips(), tiles(), layouts()]
        } else {
            sections += [chips(), tiles(), layouts(), finishes()] + lower()
        }
        let column = UKColumnView(spacing: HassTokens.Spacing.xl, insets: UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l))
        column.setViews(sections)
        let scroll = UKColumnScrollView(content: column)
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scroll)
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = UKGalleryGround.color

        // `-directionGSheet open` presents the section sheet at launch, so a journey audits it (also at AX5) without a tap.
        if option("directionGSheet", environment: "FENTON_GALLERY_DIRECTION_G_SHEET") == "open" {
            DispatchQueue.main.async { [weak self] in self?.presentSheet() }
        }
    }

    // MARK: Sections

    private func lastCall() -> UIView {
        lastCallLabel.text = "Last action: \(lastAction)"
        lastCallLabel.numberOfLines = 3
        lastCallLabel.textColor = UKInk.primary
        lastCallLabel.accessibilityIdentifier = "gallery.lastCall"
        lastCallLabel.ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            let base = UKFont.preferred(.caption1, traits: lastCallLabel.traitCollection)
            lastCallLabel.font = UIFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
        }
        return UKDirectionGModuleView(content: lastCallLabel, padding: HassTokens.Spacing.m)
    }

    private func lower() -> [UIView] {
        [modules(), spinners(), primaryButton("Open Section Sheet", symbol: "rectangle.bottomthird.inset.filled", family: nil, id: "g.primary") { [weak self] in
            self?.presentSheet()
        }, primaryButton("Start Watering", symbol: nil, family: .water, id: "g.primary.water") { [weak self] in
            self?.lastAction = "start watering"
        }]
    }

    private func chips() -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        let specs: [(String, String, String, ColorFamily, Bool)] = [
            ("Lights", "3 On", "lightbulb.2", .lights, true),
            ("Security", "Armed Home", "shield.lefthalf.filled", .securityHome, true),
            ("Climate", "68–71°", "thermometer.medium", .climate, true),
            ("Occupancy", "Occupied", "figure.walk", .occupancy, true),
            ("Contact Sensors", "Back Deck Open", "door.left.hand.open", .contact, true),
            ("Air Quality", "AQI 21 · PM2.5 3", "aqi.medium", .air, true),
            ("Doors", "All Closed", "door.left.hand.closed", .contact, false),
        ]
        let chips = specs.map { title, summary, symbol, family, active -> UKGalleryChipView in
            let chip = UKGalleryChipView(title: title, summary: summary, symbol: symbol, family: family, isActive: active, tint: nil)
            chip.accessibilityIdentifier = "g.chip.\(title)"
            chip.addAction(UIAction { [weak self] _ in self?.lastAction = "chip \(title)" }, for: .touchUpInside)
            return chip
        }
        return section("Status Chips", UKHorizontalRow(views: chips, spacing: HassTokens.Spacing.s))
    }

    private func tile(_ title: String, _ subtitle: String, _ symbol: String, _ family: ColorFamily, _ active: Bool, id: String? = nil) -> UIView {
        let tile = UKGlassTileView(model: UKGlassTileModel(title: title, subtitle: subtitle, symbol: symbol, family: family, isActive: active, identifier: id ?? "g.tile.\(title)"))
        tile.action = { [weak self] in self?.lastAction = "tile \(title)" }
        return tile
    }

    private func grid(_ views: [UIView], environment: UKTileEnvironment = UKTileEnvironment()) -> UKDynamicGridView {
        for case let tile as UKGlassTileView in views { tile.configure(tile.model, environment: environment, animated: false) }
        let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 4, equalRowHeights: true))
        grid.setItems(views.map { UKGridItem($0) })
        return grid
    }

    private func tiles() -> UIView {
        let light = UKBrightnessTileView(title: "Kitchen Lights", tint: UIColor(ColorFamily.lights.glyphToken), percent: brightness)
        light.identifier = "g.tile.light"
        light.onPower = { [weak self, weak light] on in
            self?.brightness = on ? 100 : 0
            self?.lastAction = "power \(on)"
            light?.update(fillTint: nil, percent: self?.brightness ?? 0, isUnavailable: false)
        }
        light.onBrightness = { [weak self, weak light] value in
            self?.brightness = value
            self?.lastAction = "brightness \(value)"
            light?.update(fillTint: nil, percent: value, isUnavailable: false)
        }
        lightTile = light
        let dishwasher = UKGlassTileView(model: UKGlassTileModel(title: "Dishwasher", subtitle: "Washing · 40%", symbol: "dishwasher", family: .cleaning,
                                                                isActive: true, progress: 0.4, identifier: "g.tile.Dishwasher"))
        dishwasher.action = { [weak self] in self?.lastAction = "tile Dishwasher" }
        let garage = UKGlassTileView(model: UKGlassTileModel(title: "Garage Door", subtitle: "Didn't Respond", symbol: "door.garage.closed", family: .contact,
                                                            isActive: false, isError: true, identifier: "g.tile.Garage Door"))
        garage.action = { [weak self] in self?.lastAction = "tile Garage Door" }
        let unassigned = UKGlassTileView(model: UKGlassTileModel(title: "Unassigned Device", subtitle: "On", symbol: "switch.2", tint: UIColor.systemTeal,
                                                                 isActive: true, identifier: "g.tile.Unassigned"))
        unassigned.action = { [weak self] in self?.lastAction = "tile Unassigned" }
        let views: [UIView] = [
            light,
            tile("Office Lamp", "Off", "lamp.desk", .lights, false),
            tile("Living Room Purifier", "Auto · 42%", "air.purifier", .air, true),
            tile("Bath Fan", "Off", "fan", .air, false),
            tile("Living Room TV", "Netflix", "tv", .media, true),
            tile("Towel Rack", "On", "powerplug", .power, true),
            dishwasher,
            tile("Bedroom 1 Closet", "Occupied", "figure.walk", .occupancy, true),
            tile("Back Deck Door", "Open", "door.left.hand.open", .contact, true),
            garage,
            tile("Sprinklers", "Next Run 6:00 AM", "sprinkler.and.droplets", .water, false),
            unassigned,
        ]
        return section("Tiles", grid(views))
    }

    /// The four tile arrangements side by side on the same tiles (`TileLayout`), for the owner to compare and override.
    private func layouts() -> UIView {
        let blocks = TileLayout.allCases.filter { onlyLayout == nil || $0 == onlyLayout }.map { @MainActor (layout: TileLayout) -> UIView in
            @MainActor func layoutTile(_ title: String, _ subtitle: String, _ symbol: String, _ family: ColorFamily, _ active: Bool) -> UIView {
                let tile = UKGlassTileView(model: UKGlassTileModel(title: title, subtitle: subtitle, symbol: symbol, family: family, isActive: active,
                                                                   identifier: "g.layout.\(layout.rawValue).\(title)"))
                tile.action = { [weak self] in self?.lastAction = "tile \(title)" }
                return tile
            }
            let kitchen = UKGlassTileView(model: UKGlassTileModel(title: "Kitchen", symbol: "stove", family: .neutral, fillRGB: RoomPalette.fill(at: 6),
                                                                  isActive: false, kind: .navigate, identifier: "g.layout.\(layout.rawValue).Kitchen"))
            kitchen.action = { [weak self] in self?.lastAction = "tile Kitchen" }
            let security = UKGlassTileView(model: UKGlassTileModel(title: "Security System", subtitle: "Armed Home", symbol: "shield", family: .securityHome,
                                                                   isActive: false, kind: .navigate, identifier: "g.layout.\(layout.rawValue).Security"))
            security.action = { [weak self] in self?.lastAction = "tile Security System" }
            var environment = UKTileEnvironment()
            environment.layout = layout
            let grid = grid([
                layoutTile("Office Lamp", "Off", "lamp.desk", .lights, false),
                layoutTile("Living Room Purifier", "Auto · 42%", "air.purifier", .air, true),
                layoutTile("Bedroom 1 Closet", "Occupied", "figure.walk", .occupancy, true),
                kitchen, security,
                layoutTile("Towel Rack", "On", "powerplug", .power, true),
            ], environment: environment)
            return UKColumnView(views: [UKGalleryHeading(layout.title + (layout == .standard ? " (Shipped)" : ""), style: .headline), grid], spacing: HassTokens.Spacing.s)
        }
        return section("Tile Layouts", UKColumnView(views: blocks, spacing: HassTokens.Spacing.m))
    }

    /// The shipped tinted glass finish beside the solid one it falls back to with Reduce Transparency or Increase Contrast, on the same
    /// tiles (``TileFinish``): off, on in a family colour, lit, dark ink on a bright fill, an error, a room and a long name.
    private func finishes() -> UIView {
        let blocks = TileFinish.allCases.filter { onlyFinish == nil || $0 == onlyFinish }.map { @MainActor (finish: TileFinish) -> UIView in
            let summary = UILabel()
            summary.numberOfLines = 0
            summary.text = finish.summary
            summary.textColor = .white
            summary.ukOnContentSizeChange { summary.font = UKFont.preferred(.footnote, traits: summary.traitCollection) }
            return UKColumnView(views: [UKGalleryHeading(finish.title, style: .headline), summary, UKFinishSampleGrid(finish: finish, surface: .page)], spacing: HassTokens.Spacing.s)
        }
        return section("Tile Finish", UKColumnView(views: blocks, spacing: HassTokens.Spacing.m))
    }

    private func modules() -> UIView {
        func label(_ text: String, style: UIFont.TextStyle, color: UIColor) -> UILabel {
            let label = UILabel()
            label.numberOfLines = 0
            label.text = text
            label.textColor = color
            label.ukOnContentSizeChange { label.font = UKFont.preferred(style, weight: style == .headline ? .semibold : nil, traits: label.traitCollection) }
            return label
        }
        let thin = UKDirectionGModuleView(
            content: UKColumnView(views: [
                label("Thin Module", style: .headline, color: UKInk.primary),
                label("Cards, inset lists and tiles on the wallpaper.", style: .subheadline, color: UIColor(HassTokens.RGB.Surface.secondaryOnModule)),
            ], spacing: HassTokens.Spacing.s), padding: HassTokens.Spacing.l, density: .thin)
        thin.isAccessibilityElement = true
        thin.accessibilityLabel = "Thin Module, Cards, inset lists and tiles on the wallpaper."
        thin.accessibilityIdentifier = "g.module.thin"
        let dense = UKDirectionGModuleView(
            content: UKColumnView(views: [
                label("3 Chores Overdue", style: .headline, color: UKInk.danger),
                label("Milk Expires Tomorrow", style: .subheadline, color: UKInk.warning),
            ], spacing: HassTokens.Spacing.s), padding: HassTokens.Spacing.l, density: .dense)
        dense.isAccessibilityElement = true
        dense.accessibilityLabel = "3 Chores Overdue, Milk Expires Tomorrow"
        dense.accessibilityIdentifier = "g.module.dense"
        return section("Modules", UKColumnView(views: [thin, dense], spacing: HassTokens.Spacing.s))
    }

    private func spinners() -> UIView {
        let page = UKArcSpinnerView(.page)
        let compact = UKArcSpinnerView(.compact, label: "Updating")
        let inline = UKArcSpinnerView(.inline, label: "Sending Open")
        inline.color = UKInk.action
        let progress = UKArcProgressView(title: "Loading Recipes", size: .compact)
        for spinner in [page, compact, inline] { spinner.color = .white }
        let row = UKHorizontalRow(views: [page, compact, inline, progress], spacing: HassTokens.Spacing.xl, centered: true)
        row.accessibilityIdentifier = "g.spinners"
        row.accessibilityContainerType = .semanticGroup
        return section("Loading", row)
    }

    private func primaryButton(_ title: String, symbol: String?, family: ColorFamily?, id: String, action: @escaping () -> Void) -> UIView {
        let button = UKGalleryPrimaryButton(title: title, symbol: symbol, family: family)
        button.accessibilityIdentifier = id
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func section(_ title: String, _ content: UIView) -> UIView {
        UKColumnView(views: [UKGalleryHeading(title, style: .title3), content], spacing: HassTokens.Spacing.m)
    }

    // MARK: Sheet

    private func presentSheet() {
        UKDirectionGSheetViewController.make().present(from: self)
    }
}

// MARK: - Sheet

/// A sheet with tiles on the sheet surface. Launch with `FENTON_APPEARANCE=light` to draw it in the light appearance; the page behind
/// stays dark.
@MainActor
final class UKDirectionGSheetViewController: UIViewController {
    enum Section: String, CaseIterable, Identifiable {
        case controls = "Controls", families = "Families", finish = "Finish", apps = "Apps", settings = "Settings"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .controls: "appletvremote.gen4"
            case .families: "circle.hexagongrid"
            case .finish: "sparkles.rectangle.stack"
            case .apps: "play.rectangle"
            case .settings: "gearshape"
            }
        }
    }

    /// The sheet as the app draws one: a full-height modal with the circle-X and the section bar pinned at the bottom
    /// (`HassModal` + `modalTabBar`).
    static func make() -> UKHassModalController {
        let content = UKDirectionGSheetViewController()
        let bar = UKModalTabBar(tabs: Section.allCases, label: "TV sections", title: { $0.rawValue }, symbol: { $0.symbol },
                                selection: content.section, identifier: "g.sheet.tabs") { [weak content] in content?.select($0) }
        let root = UKPinnedBarViewController(content: content, bar: bar.inset())
        var options = UKHassModalOptions(title: "Living Room TV", fitKey: "DirectionGSheet")
        options.width = .page
        options.height = .full
        return UKHassModalController(root: root, options: options)
    }

    func select(_ new: Section) {
        section = new
        rebuild()
    }

    private(set) var section = Section(rawValue: ukDirectionGOption("directionGSheetSection", environment: "FENTON_GALLERY_DIRECTION_G_SHEET_SECTION") ?? "") ?? .controls
    private let onlyFinish = ukDirectionGOption("directionGFinish", environment: "FENTON_GALLERY_DIRECTION_G_FINISH").flatMap(TileFinish.init(rawValue:))
    private var scroll: UKColumnScrollView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UKInk.sheetGround
        rebuild()
    }

    private var environment: UKTileEnvironment {
        var environment = UKTileEnvironment()
        environment.surface = .sheet
        return environment
    }

    private func grid(_ models: [UKGlassTileModel]) -> UIView {
        let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 4, equalRowHeights: true))
        grid.setItems(models.map { UKGridItem(UKGlassTileView(model: $0, environment: environment)) })
        return grid
    }

    private func rebuild() {
        scroll?.removeFromSuperview()
        let content: UIView
        switch section {
        case .controls:
            content = grid([
                UKGlassTileModel(title: "Power", subtitle: "On", symbol: "power", family: .media, isActive: true),
                UKGlassTileModel(title: "Mute", subtitle: "Off", symbol: "speaker.slash", family: .media, isActive: false),
                UKGlassTileModel(title: "Floor Lamp", subtitle: "Off", symbol: "lamp.floor", family: .lights, isActive: false),
                UKGlassTileModel(title: "Table Lamp", subtitle: "60%", symbol: "lamp.table", family: .lights, isActive: true),
                UKGlassTileModel(title: "Bath Fan", subtitle: "Didn't Respond", symbol: "fan", family: .air, isActive: false, isError: true),
                UKGlassTileModel(title: "Unassigned Device", subtitle: "On", symbol: "switch.2", tint: UIColor.systemTeal, isActive: true),
                UKGlassTileModel(title: "Dishwasher", subtitle: "Washing · 40%", symbol: "dishwasher", family: .cleaning, isActive: true, progress: 0.4),
                UKGlassTileModel(title: "Armed Home", subtitle: "Since 6:51 PM", symbol: "house", family: .securityHome, isActive: false,
                                 wash: ColorFamily.securityHome.fillToken.map { UIColor($0) }),
            ])
        case .families:
            content = grid(ColorFamily.allCases.map {
                UKGlassTileModel(title: $0.rawValue.prefix(1).uppercased() + $0.rawValue.dropFirst(), subtitle: "Off", symbol: "circle.hexagongrid", family: $0, isActive: false)
            })
        case .finish:
            content = UKColumnView(views: TileFinish.allCases.filter { onlyFinish == nil || $0 == onlyFinish }.map { finish in
                UKColumnView(views: [UKGalleryHeading(finish.title, style: .headline, color: UKInk.primary), UKFinishSampleGrid(finish: finish, surface: .sheet)],
                             spacing: HassTokens.Spacing.s)
            }, spacing: HassTokens.Spacing.l)
        case .apps:
            content = grid([UKGlassTileModel(title: "Netflix", symbol: "play.rectangle", family: .media, isActive: false, kind: .command)])
        case .settings:
            let label = UILabel()
            label.text = "Settings rows belong to the lists lane."
            label.textColor = UKInk.secondaryInSheet
            label.numberOfLines = 0
            label.ukOnContentSizeChange { label.font = UKFont.preferred(.body, traits: label.traitCollection) }
            content = label
        }
        let column = UKColumnView(spacing: 0, insets: UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l))
        column.setViews([content])
        let scroll = UKColumnScrollView(content: column)
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(scroll, at: 0)
        self.scroll = scroll
    }
}

// MARK: - Finish sample grid

/// The tiles the finishes are judged on: off, on in a family colour, lit, bright with dark ink, an error, a room, a long name and a
/// coloured navigation tile, drawn with one ``TileFinish``. On a page they sit on the wallpaper; in a sheet, on the cell.
@MainActor
final class UKFinishSampleGrid: UIView, UKGridMeasuring {
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 4, equalRowHeights: true))

    init(finish: TileFinish, surface: TileSurface) {
        super.init(frame: .zero)
        var environment = UKTileEnvironment()
        environment.finish = finish
        environment.surface = surface
        func sample(_ title: String, _ subtitle: String, _ symbol: String, _ family: ColorFamily, _ active: Bool) -> UKGridItem {
            UKGridItem(UKGlassTileView(model: UKGlassTileModel(title: title, subtitle: subtitle, symbol: symbol, family: family, isActive: active,
                                                               identifier: "g.finish.\(finish.rawValue).\(title)"), environment: environment))
        }
        grid.setItems([
            sample("Office Lamp", "Off", "lamp.desk", .lights, false),
            sample("Table Lamp", "60%", "lamp.table", .lights, true),
            sample("Living Room Purifier", "Auto · 42%", "air.purifier", .air, true),
            sample("Bath Fan", "Off", "fan", .air, false),
            sample("Towel Rack", "On", "powerplug", .power, true),
            sample("Thermostat", "Heating to 68°", "thermometer.medium", .heating, true),
            UKGridItem(UKGlassTileView(model: UKGlassTileModel(title: "Garage Door", subtitle: "Didn't Respond", symbol: "door.garage.closed", family: .contact,
                                                               isActive: false, isError: true, identifier: "g.finish.\(finish.rawValue).Garage Door"), environment: environment)),
            UKGridItem(UKGlassTileView(model: UKGlassTileModel(title: "Kitchen", symbol: "stove", family: .neutral, fillRGB: RoomPalette.fill(at: 6),
                                                               isActive: false, kind: .navigate, identifier: "g.finish.\(finish.rawValue).Kitchen"), environment: environment)),
        ])
        addSubview(grid)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { grid.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() {
        super.layoutSubviews()
        grid.frame = bounds
    }
}

// MARK: - Gallery parts

/// A heading: a text style, a header trait.
@MainActor
final class UKGalleryHeading: UILabel, UKGridMeasuring {
    enum Style { case title3, headline }

    init(_ text: String, style: Style, color: UIColor = .white) {
        super.init(frame: .zero)
        self.text = text
        textColor = color
        numberOfLines = 0
        accessibilityTraits = .header
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            font = switch style {
            case .title3: UKFont.sectionTitle(traitCollection)
            case .headline: UKFont.preferred(.headline, traits: traitCollection)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { ceil(sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height) }
}

extension UKColumnView {
    /// A column of `views`.
    convenience init(views: [UIView], spacing: CGFloat) {
        self.init(spacing: spacing)
        setViews(views)
    }
}

/// A direction G module (`module()`): a translucent dark tint with 26 pt continuous corners and padding around one view.
@MainActor
final class UKDirectionGModuleView: UIView, UKGridMeasuring {
    private let content: UIView
    private let padding: CGFloat

    init(content: UIView, padding: CGFloat, density: ModuleDensity = .thin) {
        self.content = content
        self.padding = padding
        super.init(frame: .zero)
        backgroundColor = UKInk.module(density, reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)
        layer.cornerRadius = HassTokens.Radius.module
        layer.cornerCurve = .continuous
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let inner = max(0, width - 2 * padding)
        let height = (content as? UKGridMeasuring)?.gridHeight(forWidth: inner) ?? ceil(content.sizeThatFits(CGSize(width: inner, height: CGFloat.greatestFiniteMagnitude)).height)
        return height + 2 * padding
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = bounds.insetBy(dx: padding, dy: padding)
    }
}

/// Views in one row at their natural sizes, scrolling sideways when they overflow.
@MainActor
final class UKHorizontalRow: UIScrollView, UKGridMeasuring {
    private let views: [UIView]
    private let spacing: CGFloat
    private let centered: Bool

    init(views: [UIView], spacing: CGFloat, centered: Bool = false) {
        self.views = views
        self.spacing = spacing
        self.centered = centered
        super.init(frame: .zero)
        showsHorizontalScrollIndicator = false
        views.forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var sizes: [CGSize] {
        views.map { $0.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)) }
            .enumerated().map { index, size in
                let intrinsic = views[index].intrinsicContentSize
                return CGSize(width: size.width > 0 && size.width < 100_000 ? size.width : intrinsic.width,
                              height: size.height > 0 && size.height < 100_000 ? size.height : intrinsic.height)
            }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { sizes.map(\.height).max() ?? 0 }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        let sizes = sizes
        let height = sizes.map(\.height).max() ?? 0
        for (view, size) in zip(views, sizes) {
            view.frame = CGRect(x: x, y: centered ? (height - size.height) / 2 : 0, width: size.width, height: size.height)
            x += size.width + spacing
        }
        contentSize = CGSize(width: max(0, x - spacing), height: height)
    }
}

/// The stand-in for the house photo: warm lit windows over a dusk sky, under G's scrim, so the gallery shows the worst case the scrim is
/// tuned for without a server.
@MainActor
final class UKGalleryWallpaperView: UIView {
    private let sky = CAGradientLayer()
    private let scrim = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        sky.colors = [UIColor(red: 0.42, green: 0.55, blue: 0.70, alpha: 1), UIColor(red: 0.86, green: 0.70, blue: 0.45, alpha: 1),
                      UIColor(red: 0.30, green: 0.36, blue: 0.26, alpha: 1), UIColor(red: 0.16, green: 0.18, blue: 0.14, alpha: 1)].map(\.cgColor)
        scrim.colors = HouseBackdropStyle.scrimOpacities.map { UIColor.black.withAlphaComponent($0.value).cgColor }
        scrim.locations = HouseBackdropStyle.scrimOpacities.map { NSNumber(value: $0.location) }
        for layer in [sky, scrim] {
            layer.startPoint = CGPoint(x: 0.5, y: 0)
            layer.endPoint = CGPoint(x: 0.5, y: 1)
            self.layer.addSublayer(layer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        sky.frame = bounds
        scrim.frame = bounds
    }
}

/// A status chip as the Home rail draws it (`StatusChipButton`): a capsule with a glyph, a title and a summary. Active chips fill with
/// their family's chip colour (or a computed tint) and a slight top highlight; neutral ones sit on the thin module.
@MainActor
final class UKGalleryChipView: UIControl {
    private let fillTint: ChipTint?
    private let capsule = UIView()
    private let highlight = CAGradientLayer()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let symbol: String

    init(title: String, summary: String, symbol: String, family: ColorFamily?, isActive: Bool, tint: ChipTint?) {
        fillTint = StatusChipStyle.fillTint(family, isActive: isActive, tint: tint)
        self.symbol = symbol
        super.init(frame: .zero)
        capsule.isUserInteractionEnabled = false
        capsule.backgroundColor = fillTint.map { UIColor(rgb: $0.fill) } ?? UKInk.moduleThin
        highlight.colors = [UIColor.white.withAlphaComponent(ChipTint.highlight).cgColor, UIColor.clear.cgColor]
        highlight.startPoint = CGPoint(x: 0.5, y: 0)
        highlight.endPoint = CGPoint(x: 0.5, y: 0.5)
        highlight.isHidden = fillTint == nil
        capsule.layer.addSublayer(highlight)
        capsule.layer.masksToBounds = true
        titleLabel.text = title
        titleLabel.textColor = .white
        summaryLabel.text = summary
        summaryLabel.textColor = fillTint != nil ? .white : UIColor(HassTokens.RGB.Surface.secondaryOnModule)
        iconView.contentMode = .center
        iconView.tintColor = fillTint.map { UIColor(rgb: $0.glyph) } ?? UIColor(HassTokens.RGB.Surface.secondaryOnModule)
        for view in [titleLabel, summaryLabel, iconView] as [UIView] { view.isAccessibilityElement = false }
        addSubview(capsule)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(summaryLabel)
        isAccessibilityElement = true
        accessibilityLabel = "\(title), \(summary)"
        accessibilityHint = "Opens its details"
        accessibilityTraits = .button
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            iconView.image = UKFont.symbol(self.symbol, style: .body, weight: .semibold, filled: fillTint != nil, traits: traitCollection)
            titleLabel.font = UKFont.rowTitle(traitCollection)
            summaryLabel.font = UKFont.preferred(.subheadline, monospacedDigit: true, traits: traitCollection)
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func layoutValues(width: CGFloat) -> (size: CGSize, icon: CGRect, title: CGRect, summary: CGRect) {
        let leading = HassTokens.Spacing.m, trailing = HassTokens.Spacing.l
        let icon = iconView.image?.size ?? .zero
        let textX = leading + icon.width + HassTokens.Spacing.s
        let available = max(1, width - textX - trailing)
        let titleSize = titleLabel.sizeThatFits(CGSize(width: available, height: CGFloat.greatestFiniteMagnitude))
        let summarySize = summaryLabel.sizeThatFits(CGSize(width: available, height: CGFloat.greatestFiniteMagnitude))
        let textHeight = ceil(titleSize.height) + ceil(summarySize.height)
        let height = max(48, textHeight + 2 * HassTokens.Spacing.xs)
        let textWidth = ceil(max(titleSize.width, summarySize.width))
        let y = (height - textHeight) / 2
        return (CGSize(width: min(width, textX + textWidth + trailing), height: height),
                CGRect(x: leading, y: (height - icon.height) / 2, width: icon.width, height: icon.height),
                CGRect(x: textX, y: y, width: ceil(titleSize.width), height: ceil(titleSize.height)),
                CGRect(x: textX, y: y + ceil(titleSize.height), width: ceil(summarySize.width), height: ceil(summarySize.height)))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { layoutValues(width: size.width.isFinite && size.width < 100_000 ? size.width : 10_000).size }
    override var intrinsicContentSize: CGSize { sizeThatFits(CGSize(width: 10_000, height: 0)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let values = layoutValues(width: bounds.width)
        capsule.frame = bounds
        capsule.layer.cornerRadius = bounds.height / 2
        capsule.layer.cornerCurve = .continuous
        highlight.frame = capsule.bounds
        iconView.frame = values.icon
        titleLabel.frame = values.title
        summaryLabel.frame = values.summary
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { alpha = isHighlighted ? 0.8 : 1 } }
    }
}

/// A screen's one primary action (`PrimaryButton`): a 50 pt capsule filled with G's `#0071E3` and a white label, or an owner's family
/// colour with dark text. The controls lane ports the real one; this stands in for the gallery.
@MainActor
final class UKGalleryPrimaryButton: UIControl, UKGridMeasuring {
    private let label = UILabel()
    private let iconView = UIImageView()
    private let symbol: String?

    init(title: String, symbol: String?, family: ColorFamily?) {
        self.symbol = symbol
        super.init(frame: .zero)
        let fill = family.map { UIColor(rgb: $0.spec.glyph) } ?? UIColor(rgb: HassTokens.Palette.tintFill)
        let ink = family == nil ? UIColor.white : UIColor(rgb: HassTokens.Palette.sheetGround)
        backgroundColor = fill
        label.text = title
        label.textColor = ink
        label.numberOfLines = 0
        label.textAlignment = .center
        iconView.tintColor = ink
        iconView.contentMode = .center
        for view in [label, iconView] as [UIView] { view.isAccessibilityElement = false; addSubview(view) }
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            label.font = UKFont.bodyEmphasis(traitCollection)
            iconView.image = symbol.flatMap { UKFont.symbol($0, style: .body, weight: .semibold, traits: self.traitCollection) }
            setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func layoutValues(width: CGFloat) -> (height: CGFloat, icon: CGRect, label: CGRect) {
        let pad = HassTokens.Spacing.xl
        let icon = iconView.image?.size ?? .zero
        let gap: CGFloat = icon.width > 0 ? HassTokens.Spacing.s : 0
        let available = max(1, width - 2 * pad - icon.width - gap)
        let text = label.sizeThatFits(CGSize(width: available, height: CGFloat.greatestFiniteMagnitude))
        let height = max(PrimaryButtonStyle.height, ceil(text.height) + 2 * HassTokens.Spacing.s)
        let total = icon.width + gap + ceil(text.width)
        let x = (width - total) / 2
        return (height, CGRect(x: x, y: (height - icon.height) / 2, width: icon.width, height: icon.height),
                CGRect(x: x + icon.width + gap, y: (height - ceil(text.height)) / 2, width: ceil(text.width), height: ceil(text.height)))
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { layoutValues(width: width).height }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let values = layoutValues(width: bounds.width)
        layer.cornerRadius = bounds.height / 2
        layer.cornerCurve = .continuous
        iconView.frame = values.icon
        label.frame = values.label
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { alpha = isHighlighted ? HassTokens.ControlState.pressedOpacity : 1 } }
    }
}

// MARK: - Gallery copy

private extension TileFinish {
    /// The gallery's name for the finish.
    var title: String {
        switch self {
        case .solid: "Solid (Reduce Transparency)"
        case .tintedGlass: "Tinted Glass"
        }
    }

    /// A one-line description for the gallery.
    var summary: String {
        switch self {
        case .solid: "Opaque family fill, thin dark module when off. Used with Reduce Transparency or Increase Contrast."
        case .tintedGlass: "Family tint at 78% over the wallpaper, lit hairline, soft top light."
        }
    }
}

private extension TileLayout {
    /// A short name for the gallery.
    var title: String {
        switch self {
        case .row: "Row"
        case .anchoredBottom: "Anchored Bottom"
        case .centeredStack: "Centred Stack"
        case .stackedTop: "Stacked Top (Before)"
        }
    }
}
#endif
