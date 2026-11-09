#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// "Advanced Controls" (`ClimateSheet`): Rooms, Automation and Tracking tabs with detail pages pushed inside the sheet (Back
/// returns to the tab, like the web's in-sheet back). Direction G: dark system forms (the sheet's ground and cells) with the tabs on
/// a glass segmented control at the bottom. Pattern: modal-sheet.
@MainActor
enum UKClimateSheet {
    /// The sheet, opened on `request`'s tab and, when it names a route, with that detail page pushed on it.
    /// - Parameter accessory: Shown under the tab bar (the gallery's last-call line).
    static func make(controller: ClimateController, context: UKContext, request: ClimateSheetRequest, accessory: UIView? = nil) -> UKHassModalController {
        let sheetContext = context.with { $0.surface = .sheet }
        let host = UKClimateSheetHost(controller: controller, context: sheetContext, tab: request.route?.tab ?? request.tab)
        let bar = host.tabBar.inset()
        var barView: UIView = bar
        if let accessory {
            let stack = UIStackView(arrangedSubviews: [bar, accessory])
            stack.axis = .vertical
            barView = stack
        }
        let root = UKSheetPinnedBarPage(content: host, bar: barView)
        var options = UKHassModalOptions(title: ClimateConfig.sheetTitle, fitKey: "ClimateSheet")
        options.height = .full
        options.width = .page
        let modal = UKHassModalController(root: root, options: options)
        host.scrollersChanged = { [weak root] scrolls in root?.setScrollers(scrolls) }
        host.open = { [weak modal, weak host] route in
            guard let modal, let host else { return }
            modal.push(host.detail(route), animated: true)
        }
        if let route = request.route {
            let page = host.detail(route)
            UKHassModal.applyChrome(to: page, options: options, dismiss: nil, isRoot: false)
            modal.pushViewController(page, animated: false)
        }
        return modal
    }
}

/// The three tabs, all kept alive and only the selected one shown, so leaving a tab keeps its scroll position and edits (owner,
/// 2026-10-26). A hidden tab is out of hit testing and the accessibility tree.
@MainActor
final class UKClimateSheetHost: UKPaneViewController {
    let controller: ClimateController
    let sheetContext: UKContext
    var open: (ClimateRoute) -> Void = { _ in }
    /// The shown tab's scroller, named to the sheet's page so the header fade and scroll to top follow the tab.
    var scrollersChanged: ([UIScrollView]) -> Void = { _ in }
    private(set) var currentTab: ClimateConfig.Tab
    private var tabViews: [ClimateConfig.Tab: UIViewController] = [:]
    private(set) lazy var tabBar = UKModalTabBar(
        tabs: ClimateConfig.Tab.allCases, label: "Thermostat sections", title: { $0.title }, symbol: { ModalTabSymbols.symbol(for: $0) },
        selection: currentTab, identifier: "climate.sheet.tabs") { [weak self] in self?.select($0) }

    init(controller: ClimateController, context: UKContext, tab: ClimateConfig.Tab) {
        self.controller = controller
        sheetContext = context
        self.currentTab = tab
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        for each in ClimateConfig.Tab.allCases {
            let page = makeTab(each)
            addChild(page)
            page.view.frame = view.bounds
            page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(page.view)
            page.didMove(toParent: self)
            page.view.isHidden = each != currentTab
            tabViews[each] = page
        }
        reportScroller()
    }

    private func reportScroller() {
        if let scroll = (tabViews[currentTab] as? UKPageViewController)?.contentScrollView { scrollersChanged([scroll]) }
    }

    private func select(_ next: ClimateConfig.Tab) {
        guard next != currentTab else { return }
        currentTab = next
        for (each, page) in tabViews { page.view.isHidden = each != next }
        reportScroller()
    }

    private func makeTab(_ tab: ClimateConfig.Tab) -> UIViewController {
        switch tab {
        case .rooms: UKClimateRoomsTab(controller: controller, context: sheetContext) { [weak self] in self?.open(.room($0)) }
        case .automation: UKClimateAutomationTab(controller: controller) { [weak self] in self?.open($0) }
        case .tracking: UKClimateTrackingTab(controller: controller) { [weak self] in self?.open($0) }
        }
    }

    /// The page a route pushes.
    func detail(_ route: ClimateRoute) -> UIViewController {
        let page: UIViewController
        switch route {
        case let .room(key):
            page = ClimateConfig.room(key: key).map { UKClimateRoomDetail(controller: controller, context: sheetContext, room: $0) }
                ?? UKStatePageViewController(title: route.title, state: UKStateMessageView(symbol: "thermometer.medium.slash", title: "Room Unavailable",
                                                                                           message: "This room is not part of the climate setup.", identifier: "climate.room.unavailable"))
        case .predictive: page = UKPredictiveComfortDetail(controller: controller)
        case let .eco(option): page = UKEcoOptionDetail(controller: controller, option: option)
        case let .tracking(tracking): page = UKTrackingRoomsDetail(controller: controller, page: tracking)
        }
        page.title = route.title
        page.navigationItem.title = route.title
        page.navigationItem.largeTitleDisplayMode = .never
        page.navigationItem.rightBarButtonItem = UKSheetItems.close { [weak self] in
            (self?.navigationController as? UKHassModalController)?.close()
        }
        return page
    }
}

// MARK: - Rows

/// A switch or input_boolean as a system switch, sending `homeassistant.toggle` (`ClimateToggleRow`). What it does goes under it in
/// the section footer, and VoiceOver reads it as the hint.
@MainActor
final class UKClimateToggleRowView: UKRowView {
    private let bag = UKObservationBag()
    private let toggle: UKActionToggle

    init(controller: ClimateController, entityId: String, title: String, icon: String, detail: String?) {
        toggle = UKActionToggle(isOn: controller.isOn(entityId)) { controller.toggle(entityId) }
        super.init(.init(title, symbol: ClimateStyle.symbol(icon), style: .form), surface: .sheet)
        toggle.accessibilityLabel = title
        toggle.accessibilityHint = detail ?? ""
        toggle.accessibilityIdentifier = "climate.toggle.\(entityId)"
        setAccessory(toggle)
        isTextAccessible = false
        bag.observe { [weak self] in
            guard let self else { return }
            toggle.show(controller.isOn(entityId))
            let available = !controller.isUnavailable(entityId)
            toggle.isEnabled = available
            alpha = available ? 1 : 0.4
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

@MainActor
private enum UKClimateRows {
    /// `view` with the row's vertical padding, as a stack (a stack reports a finite fitted height; a bare holder view pinned
    /// around a stack reported an infinite one inside a list cell).
    static func padded(_ view: UIView) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [view])
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: HassTokens.Spacing.s, leading: 0, bottom: HassTokens.Spacing.s, trailing: 0)
        return stack
    }

    static func toggle(_ controller: ClimateController, entityId: String, title: String, icon: String, detail: String?) -> UKFormRowSpec {
        UKFormRowSpec(id: "toggle.\(entityId)") {
            UKClimateToggleRowView(controller: controller, entityId: entityId, title: title, icon: icon, detail: detail)
        }
    }

    static func toggleSection(_ controller: ClimateController, entityId: String, title: String, icon: String, detail: String, header: String? = nil) -> UKFormSectionSpec {
        UKFormSectionSpec(id: "section.\(entityId)", header: header, footer: detail,
                          rows: [toggle(controller, entityId: entityId, title: title, icon: icon, detail: detail)])
    }

    /// A row with a plain label.
    static func text(_ id: String, _ build: @escaping () -> UIView) -> UKFormRowSpec { UKFormRowSpec(id: id, build: build) }
}

// MARK: - Rooms

/// Every room as a colour tile like the Rooms grid (`RoomPalette`; owner, 2026-10-16: "standardise on room tiles across the app"):
/// the room's glyph, its name, and its temperature and occupancy under it. A tap opens the room's detail (`ClimateRoomsTab`).
@MainActor
final class UKClimateRoomsTab: UKSheetColumnViewController {
    private let controller: ClimateController
    private let onOpen: (String) -> Void
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
    private let tileBag = UKObservationBag()

    init(controller: ClimateController, context: UKContext, onOpen: @escaping (String) -> Void) {
        self.controller = controller
        self.onOpen = onOpen
        super.init(maxWidth: 720, spacing: HassTokens.Spacing.l, context: context)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.accessibilityIdentifier = "climate.sheet.rooms"
        var environment = UKTileEnvironment(context: context)
        // The Rooms grid's arrangement: glyph top-leading, name and state on the bottom lines, one height.
        environment.layout = .anchoredBottom
        environment.titleLines = 2
        let lookup = controller.lookup
        let items: [UKGridItem] = ClimateConfig.rooms.map { room in
            let icon = SymbolMap.symbol(for: RoomNavigation.item(for: room.key.replacingOccurrences(of: "_", with: "-"))?.icon ?? "mdi:home-thermometer")
            @MainActor func model() -> UKGlassTileModel {
                UKGlassTileModel(title: room.title,
                                 // Two lines, so a narrow tile never breaks the pair mid-way ("70.9°F ·" over "Occupied").
                                 subtitle: "\(ClimateLogic.roomTemperature(room, lookup))\n\(ClimateLogic.roomOccupancy(room, lookup))",
                                 symbol: icon, family: .neutral, fillRGB: RoomPalette.fill(at: RoomNavigation.paletteIndex(forPath: room.key.replacingOccurrences(of: "_", with: "-"))), isActive: false, kind: .navigate,
                                 identifier: "climate.room.\(room.key)")
            }
            let tile = UKGlassTileView(model: model(), environment: environment) { [weak self] in self?.onOpen(room.key) }
            tileBag.observe { [weak tile, weak self] in tile?.configure(model(), environment: environment, action: { [weak self] in self?.onOpen(room.key) }) }
            return UKGridItem(tile)
        }
        grid.setItems(items)
        grid.configuration.minCellWidth = UKFont.scaled(DynamicGridMetrics.tileMinWidth, relativeTo: .subheadline, traits: traitCollection)
        let host = UKGridHost(grid)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (tab: UKClimateRoomsTab, _) in
            tab.grid.configuration.minCellWidth = UKFont.scaled(DynamicGridMetrics.tileMinWidth, relativeTo: .subheadline, traits: tab.traitCollection)
            host.remeasure()
        }
        stack.addArrangedSubview(host)
        stack.addArrangedSubview(UKDeviceText.footnote(ClimateConfig.Tab.rooms.description))
    }
}

/// A room's dial, vents and away notice (`ClimateRoomDetail`). The vents are Vents-family tiles that fill while open and show
/// their position.
@MainActor
final class UKClimateRoomDetail: UKGroupedFormController {
    private let controller: ClimateController
    private let room: ClimateConfig.Room
    private let ventBag = UKObservationBag()
    private var notice: String?

    init(controller: ClimateController, context: UKContext, room: ClimateConfig.Room) {
        self.controller = controller
        self.room = room
        super.init(context: context)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.accessibilityIdentifier = "climate.detail"
        bag.observe { [weak self] in self?.rebuild() }
    }

    private func rebuild() {
        let notice = ClimateLogic.awayNotice(climateEntityId: room.climateEntityId, useEffectiveMode: false, controller.lookup)
        var sections: [UKFormSectionSpec] = []
        sections.append(UKFormSectionSpec(id: "dial", rows: [
            UKFormRowSpec(id: "dial", build: { [self] in
                let dial = UKClimateThermostatDial(context: context, entityId: room.climateEntityId, title: room.title, size: .modal, caller: controller.caller)
                dial.accessibilityIdentifier = nil
                let group = UIView()
                group.addSubview(dial)
                dial.ukPin(to: group)
                group.isAccessibilityElement = false
                group.accessibilityContainerType = .semanticGroup
                group.accessibilityIdentifier = "climate.roomDial"
                return group
            }, isClear: true),
        ]))
        if let notice {
            sections.append(UKFormSectionSpec(id: "notice", rows: [
                UKFormRowSpec(id: "notice.\(notice)") {
                    let icon = UIImageView(image: UIImage(systemName: "house", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.body))))
                    icon.tintColor = UKDesignInk.primary
                    icon.setContentHuggingPriority(.required, for: .horizontal)
                    icon.isAccessibilityElement = false
                    let label = UILabel.uk(.body, ink: UKDesignInk.primary)
                    label.text = notice
                    let row = UIStackView(arrangedSubviews: [icon, label])
                    row.axis = .horizontal
                    row.alignment = .firstBaseline
                    row.spacing = HassTokens.Spacing.s
                    let holder = UIView()
                    holder.addSubview(row)
                    row.ukPin(to: holder, insets: UIEdgeInsets(top: HassTokens.Spacing.s, left: 0, bottom: HassTokens.Spacing.s, right: 0))
                    holder.isAccessibilityElement = true
                    holder.accessibilityLabel = notice
                    holder.accessibilityIdentifier = "climate.roomAwayNotice"
                    return holder
                },
            ]))
        }
        sections.append(UKFormSectionSpec(id: "vents", header: room.ventSectionTitle, rows: [
            UKFormRowSpec(id: "vents", build: { [self] in ventGrid() }, isClear: true, fullBleed: true),
        ]))
        setSections(sections)
    }

    private func ventGrid() -> UIView {
        let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: UKFont.scaled(DynamicGridMetrics.tileMinWidth, relativeTo: .subheadline, traits: traitCollection),
                                                                         maxColumns: 4, equalRowHeights: true))
        ventBag.removeAll()
        let environment = UKTileEnvironment(context: context)
        let items: [UKGridItem] = room.ventEntityIds.enumerated().map { index, ventId in
            let box = context.store.entity(ventId)
            let title = room.ventTitle(at: index)
            @MainActor func model() -> UKGlassTileModel {
                let vent = box.state
                return UKGlassTileModel(title: title, subtitle: ClimateLogic.ventSubtitle(vent), symbol: ClimateStyle.symbol("mdi:fan"), family: .vents,
                                        isActive: ClimateLogic.isVentOpen(vent), isUnavailable: vent?.isUnavailable ?? true, kind: .state,
                                        identifier: "climate.vent.\(ventId)")
            }
            let tile = UKGlassTileView(model: model(), environment: environment)
            ventBag.observe { [weak tile] in tile?.configure(model(), environment: environment) }
            return UKGridItem(tile)
        }
        grid.setItems(items)
        return UKGridHost(grid)
    }
}

// MARK: - Automation

/// Automatic Thermostat, Eco Mode and Predictive Comfort (`ClimateAutomationTab`).
@MainActor
final class UKClimateAutomationTab: UKGroupedFormController {
    private let controller: ClimateController
    private let open: (ClimateRoute) -> Void

    init(controller: ClimateController, open: @escaping (ClimateRoute) -> Void) {
        self.controller = controller
        self.open = open
        super.init()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.accessibilityIdentifier = "climate.sheet.automation"
        bag.observe { [weak self] in self?.rebuild() }
    }

    private func rebuild() {
        let predictiveOn = controller.isOn(ClimateConfig.predictiveComfortEntityId)
        var predictiveRows = [UKFormRowSpec(id: "predictive") { [controller] in UKPredictiveToggleRow(controller: controller) }]
        if predictiveOn {
            predictiveRows.append(UKFormRowSpec(id: "predictive.open", build: { [open] in
                let row = UKFormLinkRow(title: "Current Prediction", identifier: "climate.predictive.open")
                row.accessibilityLabel = "Current Prediction"
                row.accessibilityHint = "Opens Predictive Comfort controls."
                return row
            }, action: { [open] in open(.predictive) }, accessories: [.disclosureIndicator()]))
        }
        setSections([
            UKClimateRows.toggleSection(controller, entityId: ClimateConfig.integrationEntityId, title: "Automatic Thermostat", icon: "mdi:thermostat",
                                        detail: ClimateConfig.Copy.integration),
            UKFormSectionSpec(id: "eco", header: "Eco Mode", footer: ClimateConfig.Copy.ecoMode,
                              rows: [UKClimateRows.toggle(controller, entityId: ClimateConfig.ecoModeEntityId, title: "Eco Mode", icon: "mdi:leaf",
                                                          detail: ClimateConfig.Copy.ecoMode)]
                                  + ClimateConfig.EcoOption.allCases.map { ecoRow($0) }),
            UKFormSectionSpec(id: "predictive", header: "Predictive Comfort", footer: ClimateConfig.Copy.predictiveComfort, rows: predictiveRows),
        ])
    }

    private func ecoRow(_ option: ClimateConfig.EcoOption) -> UKFormRowSpec {
        UKFormRowSpec(id: "eco.\(option.rawValue)", build: { [controller] in
            let row = UKFormLinkRow(title: option.title, symbol: ClimateStyle.symbol(option.icon), identifier: "climate.eco.\(option.rawValue)")
            row.bind { row in
                let options = ClimateLogic.selectOptions(controller.entity(option.entityId))
                let value = ClimateLogic.selectOption(controller.shown(option.entityId) ?? "")
                row.show(value: value)
                row.setEnabled(!options.isEmpty)
                row.accessibilityLabel = option.title
                row.accessibilityValue = value
                row.accessibilityHint = option.openerDescription
            }
            return row
        }, action: { [controller, open] in
            guard !ClimateLogic.selectOptions(controller.entity(option.entityId)).isEmpty else { return }
            open(.eco(option))
        }, accessories: [.disclosureIndicator()])
    }
}

/// Predictive Comfort's switch: the label keeps the recommendation ("On · Pre-Cool"); the switch reads on or off itself.
@MainActor
final class UKPredictiveToggleRow: UKRowView {
    private let bag = UKObservationBag()

    init(controller: ClimateController) {
        let id = ClimateConfig.predictiveComfortEntityId
        let toggle = UKControllerToggle(isOn: controller.isOn(id)) { controller.setSwitch(id, on: $0) }
        super.init(.init("Predictive Comfort", symbol: ClimateStyle.symbol("mdi:home-thermometer-outline"), style: .form), surface: .sheet)
        toggle.accessibilityHint = ClimateConfig.Copy.predictiveComfort
        toggle.accessibilityIdentifier = "climate.predictive"
        setAccessory(toggle)
        isTextAccessible = false
        bag.observe { [weak self, weak toggle] in
            let predictive = ClimateLogic.predictiveSubtitle(controller.lookup, shownState: controller.shown(id))
            toggle?.show(controller.isOn(id))
            toggle?.isEnabled = !controller.isUnavailable(id)
            toggle?.accessibilityLabel = "Predictive Comfort, \(predictive)"
            if let self {
                var content = self.rowContent
                content.subtitle = predictive
                self.update(content, accessory: self.accessory)
                self.alpha = controller.isUnavailable(id) ? 0.4 : 1
            }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Predictive Comfort's switches, Current Prediction metrics and reasons (`PredictiveComfortDetail`).
@MainActor
final class UKPredictiveComfortDetail: UKGroupedFormController {
    private let controller: ClimateController

    init(controller: ClimateController) {
        self.controller = controller
        super.init()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.accessibilityIdentifier = "climate.detail"
        bag.observe { [weak self] in self?.rebuild() }
    }

    private func rebuild() {
        let sensor = controller.entity(ClimateConfig.predictiveSensorEntityId)
        let bullets = ClimateLogic.predictiveReasonBullets(sensor)
        let recommendation = "Recommendation: \(ClimateLogic.predictiveState(ClimateLogic.predictiveRecommendation(controller.lookup)))"
        var sections: [UKFormSectionSpec] = [
            // The web shows the recommendation as the sheet subtitle.
            UKFormSectionSpec(id: "recommendation", rows: [
                UKFormRowSpec(id: "recommendation.\(recommendation)") {
                    let label = UILabel.uk(.headline, weight: .semibold, ink: UKDesignInk.primary)
                    label.text = recommendation
                    label.accessibilityIdentifier = "climate.predictive.recommendation"
                    return UKClimateRows.padded(label)
                },
            ]),
            UKFormSectionSpec(id: "controls", header: "Controls", footer: nil, rows: [
                UKClimateRows.toggle(controller, entityId: ClimateConfig.predictiveAutoAdjustEntityId, title: "Auto Setpoint Adjustments",
                                     icon: "mdi:thermostat-auto", detail: ClimateConfig.Copy.predictiveAutoAdjust),
                UKClimateRows.toggle(controller, entityId: ClimateConfig.predictiveHvacModeChangesEntityId, title: "HVAC Mode Changes",
                                     icon: "mdi:hvac", detail: ClimateConfig.Copy.predictiveHvacModeChanges),
                UKClimateRows.toggle(controller, entityId: ClimateConfig.predictiveAllowAwayEntityId, title: "Predictive Comfort While Away",
                                     icon: "mdi:home-export-outline", detail: ClimateConfig.Copy.predictiveAllowAway),
            ]),
            UKFormSectionSpec(id: "metrics", header: "Current Prediction", rows: ClimateLogic.predictiveMetrics(sensor).map { metric in
                UKFormRowSpec(id: "metric.\(metric.label).\(metric.value)") {
                    let title = UILabel.uk(.body, ink: UKDesignInk.primary)
                    title.text = metric.label
                    title.setContentHuggingPriority(.required, for: .horizontal)
                    let value = UILabel.uk(.body, monospacedDigit: true, ink: UKDesignInk.primary, alignment: .right)
                    value.text = metric.value
                    let row = UIStackView(arrangedSubviews: [title, value])
                    row.axis = .horizontal
                    row.alignment = .firstBaseline
                    row.spacing = HassTokens.Spacing.m
                    let holder = UKClimateRows.padded(row)
                    holder.isAccessibilityElement = true
                    holder.accessibilityLabel = "\(metric.label), \(metric.value)"
                    holder.accessibilityIdentifier = "climate.metric.\(metric.label)"
                    return holder
                }
            }),
        ]
        if !bullets.isEmpty {
            sections.append(UKFormSectionSpec(id: "reasons", header: "Why This Prediction", rows: [
                UKFormRowSpec(id: "reasons.\(bullets.joined(separator: "|"))") {
                    let labels = bullets.map { bullet -> UILabel in
                        let label = UILabel.uk(.body, ink: UKDesignInk.primary)
                        label.text = bullet
                        return label
                    }
                    let column = UIStackView(arrangedSubviews: labels)
                    column.axis = .vertical
                    column.spacing = HassTokens.Spacing.s
                    column.isAccessibilityElement = false
                    column.accessibilityContainerType = .semanticGroup
                    column.accessibilityIdentifier = "climate.predictive.reasons"
                    return UKClimateRows.padded(column)
                },
            ]))
        }
        setSections(sections)
    }
}

/// An Eco Mode select's choices, each with its description, the current one checked (`EcoOptionDetail`). HIG: Lists (a checkmark
/// marks the single choice).
@MainActor
final class UKEcoOptionDetail: UKGroupedFormController {
    private let controller: ClimateController
    private let option: ClimateConfig.EcoOption

    init(controller: ClimateController, option: ClimateConfig.EcoOption) {
        self.controller = controller
        self.option = option
        super.init()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.accessibilityIdentifier = "climate.detail"
        bag.observe { [weak self] in self?.rebuild() }
    }

    private func rebuild() {
        let options = ClimateLogic.selectOptions(controller.entity(option.entityId))
        if options.isEmpty {
            setSections([UKFormSectionSpec(id: "empty", rows: [
                UKFormRowSpec(id: "empty", build: { [option] in UKInlineAlertView(option.unavailableMessage) }, isClear: true),
            ])])
            return
        }
        setSections([UKFormSectionSpec(id: "options", footer: option.pageDescription, rows: options.map { choice in
            UKFormRowSpec(id: "option.\(choice.value)", build: { [controller, option] in
                let check = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.bodyEmphasis())))
                check.tintColor = UKInk.action
                check.setContentHuggingPriority(.required, for: .horizontal)
                check.isAccessibilityElement = false
                let row = UKFormLinkRow(title: choice.label, subtitle: choice.description, identifier: "climate.option.\(choice.value)")
                row.setAccessory(check)
                // Reads the choice and what it does ("Use Eco Away Targets, Use the wider away…").
                row.accessibilityLabel = [choice.label, choice.description].compactMap { $0 }.joined(separator: ", ")
                row.bind { row in
                    let isSelected = controller.shown(option.entityId) == choice.value
                    UKMotion.quick { check.alpha = isSelected ? 1 : 0 }
                    row.accessibilityTraits = isSelected ? [.button, .selected] : .button
                }
                return row
            }, action: { [controller, option] in controller.select(option.entityId, option: choice.value) })
        })])
    }
}

// MARK: - Tracking

/// Track Selected Rooms and the three room-rule openers, each with what it does under it (`ClimateTrackingTab`).
@MainActor
final class UKClimateTrackingTab: UKGroupedFormController {
    private let controller: ClimateController
    private let open: (ClimateRoute) -> Void

    init(controller: ClimateController, open: @escaping (ClimateRoute) -> Void) {
        self.controller = controller
        self.open = open
        super.init()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.accessibilityIdentifier = "climate.sheet.tracking"
        // The shape does not change with state: the rows bind their own subtitles.
        var sections = [UKClimateRows.toggleSection(controller, entityId: ClimateConfig.trackSelectedEntityId, title: "Track Selected Rooms",
                                                    icon: "mdi:home-thermometer", detail: ClimateConfig.Copy.trackSelected, header: "Room Tracking")]
        for page in ClimateConfig.TrackingPage.allCases {
            sections.append(UKFormSectionSpec(id: "page.\(page.rawValue)", header: page == ClimateConfig.TrackingPage.allCases.first ? "Room Rules" : nil,
                                              footer: page.openerDescription, rows: [trackingRow(page)]))
        }
        setSections(sections)
    }

    private func trackingRow(_ page: ClimateConfig.TrackingPage) -> UKFormRowSpec {
        UKFormRowSpec(id: "tracking.\(page.rawValue)", build: { [controller] in
            let row = UKFormLinkRow(title: page.title, symbol: ClimateStyle.symbol(page.icon), identifier: "climate.tracking.\(page.rawValue)")
            row.bind { row in
                let summary = controller.trackingSummary
                let subtitle = summary.subtitle(page)
                row.setSubtitle(subtitle)
                // Disabled, not unavailable: VoiceOver reads the subtitle ("Enable Track Selected Rooms first") and "dimmed".
                row.setEnabled(summary.isEnabled(page))
                row.accessibilityLabel = page.title
                row.accessibilityValue = subtitle
            }
            return row
        }, action: { [controller, open] in
            guard controller.trackingSummary.isEnabled(page) else { return }
            open(.tracking(page))
        }, accessories: [.disclosureIndicator()])
    }
}

/// One room switch per room, checked while on (`TrackingRoomsDetail`).
@MainActor
final class UKTrackingRoomsDetail: UKGroupedFormController {
    private let controller: ClimateController
    private let page: ClimateConfig.TrackingPage

    init(controller: ClimateController, page: ClimateConfig.TrackingPage) {
        self.controller = controller
        self.page = page
        super.init()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.accessibilityIdentifier = "climate.detail"
        bag.observe { [weak self] in self?.rebuild() }
    }

    private func rebuild() {
        let summary = controller.trackingSummary
        if !summary.isEnabled(page) {
            let message = page == .selectedRooms ? ClimateConfig.Copy.selectedRoomsDisabled : ClimateConfig.Copy.criticalDisabled
            setSections([UKFormSectionSpec(id: "disabled", rows: [UKFormRowSpec(id: "disabled", build: { UKInlineAlertView(message) }, isClear: true)])])
            return
        }
        let rooms = ClimateLogic.rooms(for: page, state: controller.shown)
        setSections([UKFormSectionSpec(id: "rooms", footer: page.pageDescription, rows: rooms.map { room in
            let id = page.entityId(for: room)
            // The shared check row (`UKCheckRow`, pattern `check-row.md`, owner 2026-10-30): the circle leads, as on the chores and
            // vacation checklists, and the row carries its own margin (full bleed in the cell).
            return UKFormRowSpec(id: "room.\(room.key)", build: { [controller, page] in
                let title = UILabel.uk(.body, ink: UKDesignInk.primary)
                title.text = room.title
                let row = UKCheckRow(content: title)
                row.toggle.accessibilityLabel = room.title
                row.toggle.accessibilityIdentifier = "climate.track.\(page.rawValue).\(room.key)"
                row.onToggle = { if !controller.isUnavailable(id) { controller.toggle(id) } }
                row.bag.observe { [weak row] in
                    guard let row else { return }
                    let isOn = controller.isOn(id)
                    let unavailable = controller.isUnavailable(id)
                    row.setChecked(isOn, checkedTint: UKInk.action, uncheckedTint: UKDesignSurface.secondaryInSheet, dimmed: unavailable)
                    row.toggle.isEnabled = !unavailable
                    // One signal for a checklist row: the selected trait. "On" as well said the same thing twice.
                    row.toggle.accessibilityTraits = unavailable ? [.button, .notEnabled] : (isOn ? [.button, .selected] : .button)
                }
                return row
            }, fullBleed: true)
        })])
    }
}
#endif
