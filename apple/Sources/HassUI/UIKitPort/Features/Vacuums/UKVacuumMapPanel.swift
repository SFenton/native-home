#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A list-row button with the accessibility the vacuum rows set explicitly (label, value, hint, toggle trait).
@MainActor
final class UKVacuumRowButton: UKRowButton {
    var spokenLabel: String?
    var spokenValue: String?
    var spokenHint: String?
    var isToggle = false

    override var accessibilityLabel: String? {
        get { spokenLabel ?? super.accessibilityLabel }
        set { spokenLabel = newValue }
    }

    override var accessibilityValue: String? {
        get { spokenValue }
        set { spokenValue = newValue }
    }

    override var accessibilityHint: String? {
        get { spokenHint }
        set { spokenHint = newValue }
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get {
            var traits: UIAccessibilityTraits = isToggle ? [.button, .toggleButton] : .button
            if !isEnabled { traits.insert(.notEnabled) }
            return traits
        }
        set {}
    }
}

/// What the sheet shows of the map for one sheet: the tab and mode on screen, which the map reads (the web's `content.swap.displayed`).
@MainActor
@Observable
final class UKVacuumSheetState {
    /// The tab the reader picked; the content follows after its fade.
    var requestedTab: VacuumTab
    /// What the tab column draws: a tab in a runtime mode.
    var displayed: VacuumSheetContent.Key

    init(tab: VacuumTab, controller: VacuumController) {
        requestedTab = tab
        displayed = VacuumSheetContent.key(requested: tab, controller: controller)
    }

    /// The tab the control shows as selected: the reader's pick at once.
    func selection(in tabs: [VacuumTab]) -> VacuumTab { tabs.contains(requestedTab) ? requestedTab : displayed.tab }
}

// MARK: - Map panel

/// The map card with its Locate button, loading and unavailable states.
@MainActor
final class UKVacuumMapFrame: UIView {
    struct Presentation {
        var height: CGFloat = 300
        var runtimeHeight: CGFloat = 460
        var label: String?
        var loadingText: String?
        var unavailableText: String?
        var showsLocate = true
        var autoCleanOverlay: Bool?
    }
    /// The map's height limit: it grows while a run is going, when the controls below collapse to one card.
    static func maxHeight(_ mode: VacuumRuntimeMode) -> CGFloat { mode == .minimal ? 460 : 300 }

    private let controller: VacuumController
    private let mapState: VacuumMapState
    private let state: UKVacuumSheetState
    private let map = UKValetudoMapView()
    private let fallback = UIStackView()
    private let locate = UIControl()
    private let bag = UKObservationBag()
    private var capConstraint: NSLayoutConstraint!
    private var aspectConstraint: NSLayoutConstraint?
    private var aspectRatio: Double = 0
    private let presentation: Presentation
    private let onLocate: (() -> Void)?
    private let onRoomTap: ((String, UIViewController) -> Void)?

    init(controller: VacuumController, mapState: VacuumMapState, state: UKVacuumSheetState, presentation: Presentation = .init(),
         onLocate: (() -> Void)? = nil, onRoomTap: ((String, UIViewController) -> Void)? = nil) {
        self.controller = controller
        self.mapState = mapState
        self.state = state
        self.presentation = presentation
        self.onLocate = onLocate
        self.onRoomTap = onRoomTap
        super.init(frame: .zero)
        backgroundColor = UKValetudoMapView.color(ValetudoMapScene.Palette.ground)
        layer.cornerRadius = HassTokens.Radius.module
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        buildMap()
        buildFallback()
        buildLocate()
        bag.observe { [weak self] in self?.render() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Applies the height limit of `mode` (inside the sheet's layout animation, so the map grows with the setup collapsing).
    func setMode(_ mode: VacuumRuntimeMode) {
        capConstraint.constant = mode == .minimal ? presentation.runtimeHeight : presentation.height
    }

    // MARK: Build

    private func buildMap() {
        map.isAccessibilityElement = true
        map.accessibilityLabel = presentation.label ?? "\(controller.vacuum.title) Valetudo map"
        map.accessibilityIdentifier = "vacuum.map"
        map.translatesAutoresizingMaskIntoConstraints = false
        addSubview(map)
        capConstraint = map.heightAnchor.constraint(lessThanOrEqualToConstant:
            state.displayed.mode == .minimal ? presentation.runtimeHeight : presentation.height)
        let fill = map.widthAnchor.constraint(equalTo: widthAnchor, constant: -2 * HassTokens.Spacing.m)
        fill.priority = UILayoutPriority(500)
        NSLayoutConstraint.activate([
            map.centerXAnchor.constraint(equalTo: centerXAnchor),
            map.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.m),
            map.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.m),
            map.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * HassTokens.Spacing.m),
            capConstraint, fill,
        ])
        map.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:))))
    }

    private func buildFallback() {
        fallback.axis = .vertical
        fallback.alignment = .center
        fallback.spacing = HassTokens.Spacing.s
        fallback.isLayoutMarginsRelativeArrangement = true
        fallback.layoutMargins = UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l)
        fallback.isAccessibilityElement = true
        fallback.accessibilityIdentifier = "vacuum.map.fallback"
        fallback.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallback)
        fallback.ukPin(to: self)
        fallback.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
    }

    private func buildLocate() {
        let glass = UKNavigationGlassView(shape: .circle)
        glass.isUserInteractionEnabled = false
        locate.addSubview(glass)
        glass.ukPin(to: locate)
        let icon = UIImageView(image: UIImage(systemName: "scope", withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.body, weight: .semibold))))
        icon.tintColor = UKDesignInk.primary
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        glass.contentView.addSubview(icon)
        icon.ukPin(to: glass.contentView)
        locate.translatesAutoresizingMaskIntoConstraints = false
        addSubview(locate)
        NSLayoutConstraint.activate([
            locate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HassTokens.Spacing.s),
            locate.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.s),
            locate.widthAnchor.constraint(equalToConstant: HassTokens.minTarget),
            locate.heightAnchor.constraint(equalToConstant: HassTokens.minTarget),
        ])
        locate.isAccessibilityElement = true
        locate.accessibilityLabel = "Locate"
        locate.accessibilityHint = "Asks the robot to play a sound."
        locate.accessibilityTraits = .button
        locate.accessibilityIdentifier = "vacuum.locate"
        locate.addAction(UIAction { [weak self] _ in
            UKTapFeedback.tap()
            guard let self else { return }
            if let onLocate = self.onLocate { onLocate() } else { self.controller.locate() }
        }, for: .touchUpInside)
    }

    // MARK: Render

    private var roomOrders: [String: Int] {
        controller.roomOrders
    }

    /// Rooms the coordinator skips on automatic cleans, as map zones (matched by title).
    private var skippedRooms: Set<String> {
        let titles = Set(controller.vacuum.autoCleanDisabledRooms.filter { controller.isAutoCleanDisabled($0) }.map(\.title))
        return Set(controller.vacuum.zones.filter { titles.contains($0.title) }.map(\.entityId))
    }

    private func render() {
        let scene = mapState.scene
        let primary = controller.status.primaryAvailable
        locate.isHidden = !primary || !presentation.showsLocate
        if let scene {
            let onAutoClean = presentation.autoCleanOverlay ?? (state.displayed.tab == .autoClean)
            let rooms = onAutoClean ? [:] : roomOrders
            let skipped = onAutoClean ? skippedRooms : []
            let area = controller.areaSelection
            if aspectConstraint == nil || aspectRatio != scene.aspectRatio {
                aspectConstraint?.isActive = false
                let constraint = map.widthAnchor.constraint(equalTo: map.heightAnchor, multiplier: max(scene.aspectRatio, 0.01))
                constraint.isActive = true
                aspectConstraint = constraint
                aspectRatio = scene.aspectRatio
            }
            map.scene = scene
            map.roomOrders = rooms
            map.skippedRooms = skipped
            map.area = area
            map.accessibilityValue = controller.selectedRoomsMapValue
            map.isHidden = false
            fallback.isHidden = true
        } else {
            map.isHidden = true
            fallback.isHidden = false
            renderFallback()
        }
    }

    private func renderFallback() {
        fallback.arrangedSubviews.forEach { fallback.removeArrangedSubview($0); $0.removeFromSuperview() }
        let unavailable = mapState.loader.failed || (!controller.status.primaryAvailable && mapState.loader.provenance == .none)
        if unavailable {
            let title = UILabel.uk(.headline, ink: UKDesignInk.onDark, alignment: .center)
            title.text = presentation.unavailableText ?? "Map Unavailable"
            let message = UILabel.uk(.subheadline, ink: UKDesignInk.onDark, alignment: .center)
            message.text = "Home Assistant cannot currently confirm the vacuum's map or position."
            fallback.addArrangedSubview(title)
            fallback.addArrangedSubview(message)
            fallback.accessibilityLabel = presentation.unavailableText ?? "Map Unavailable, Home Assistant cannot currently confirm the vacuum's map or position."
        } else {
            let spinner = UKArcSpinnerView(.page)
            spinner.color = UKDesignInk.onDark
            spinner.isAccessibilityElement = false
            let text = presentation.loadingText ?? (controller.status.primaryAvailable ? "Loading Current Map…" : "Loading Last Vacuum Map Position…")
            let label = UILabel.uk(.subheadline, ink: UKDesignInk.onDark, alignment: .center)
            label.text = text
            fallback.addArrangedSubview(spinner)
            fallback.addArrangedSubview(label)
            fallback.accessibilityLabel = text
        }
    }

    // MARK: Room taps

    private var roomsTappable: Bool {
        controller.vacuum.mapRoomSelection && controller.roomsEditable && mapState.loader.provenance == .live
    }

    @objc private func mapTapped(_ gesture: UITapGestureRecognizer) {
        guard roomsTappable, let scene = mapState.scene,
              let room = scene.room(at: gesture.location(in: map), size: map.bounds.size),
              let zone = controller.vacuum.zones.first(where: { $0.entityId == room.entityId }) else { return }
        if let onRoomTap, let presenter = ukOwningController { onRoomTap(zone.entityId, presenter); return }
        if controller.roomToggleNeedsConfirmation(zone), let presenter = ukOwningController {
            UKAlerts.alert(AlertCopy.switchToRooms, from: presenter) { [controller] in controller.toggleRoom(zone) }
        } else {
            controller.toggleRoom(zone)
        }
    }
}

// MARK: - Status

/// The Status, Battery and Dock tiles and the notices under them (`VacuumStatusSummary`).
@MainActor
final class UKVacuumStatusSummary: UIStackView {
    private enum Item: Equatable {
        case tiles([VacuumStatusTile])
        case info(title: String, message: String)
        case alert(String)
    }

    private let controller: VacuumController
    private let mapState: VacuumMapState
    private let environment: UKTileEnvironment
    private let showsTiles: Bool
    private let bag = UKObservationBag()
    private var shown: [Item]?

    init(controller: VacuumController, mapState: VacuumMapState, environment: UKTileEnvironment, showsTiles: Bool = true) {
        self.controller = controller
        self.mapState = mapState
        self.environment = environment
        self.showsTiles = showsTiles
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
        spacing = HassTokens.Spacing.m
        bag.observe { [weak self] in self?.render() }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func items() -> [Item] {
        let status = controller.status
        let stateLabel = VacuumFormat.state(controller.statusState)
        let provenance = mapState.loader.provenance
        var items: [Item] = showsTiles ? [.tiles(controller.statusTiles)] : []
        if !status.primaryAvailable && provenance != .reported {
            items.append(.info(title: stateLabel, message: "Home Assistant does not have a current status for the vacuum."))
        }
        if status.primaryAvailable && status.currentIssue.status == .unknown {
            items.append(.alert("Error Source Unavailable: The current vacuum error status cannot be confirmed because its error source is unavailable."))
        }
        if status.currentIssue.status == .present, let raw = status.currentIssue.raw {
            items.append(.alert("Current Issue: \(VacuumFormat.issue(raw))"))
        }
        for condition in status.activeConditions {
            items.append(.info(title: "Home Assistant Condition", message: VacuumStatusResolver.conditionText(condition)))
        }
        if let last = status.lastIssue,
           !status.primaryAvailable || status.currentIssue.status == .unknown || status.policyReason == "source_unreadable" {
            items.append(.info(title: "Previous Issue",
                               message: "Previous Vacuum Issue · \(last.raw) · Observed \(last.reportedAt.formatted(date: .abbreviated, time: .shortened))"))
        }
        return items
    }

    private func render() {
        let items = items()
        guard items != shown else { return }
        shown = items
        arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
        for item in items {
            switch item {
            case let .tiles(tiles): addArrangedSubview(UKVacuumStatusTiles(tiles: tiles, environment: environment))
            case let .info(title, message): addArrangedSubview(UKInfoBoxView(title: title, message: message))
            case let .alert(message): addArrangedSubview(UKInlineAlertView(message))
            }
        }
        ukRemeasureContainers()
    }
}

// MARK: - Cleaning report

/// The coordinator's while-away report (`VacuumCleaningReport`): one row that opens the room details.
@MainActor
final class UKVacuumCleaningReport: UIStackView {
    private let controller: VacuumController
    private let onOpen: (VacuumOutcomeContract) -> Void
    private let bag = UKObservationBag()
    private var shown: VacuumWhileAway?
    private var legacyOpen = false
    private let authoredTitle: String?

    init(controller: VacuumController, title: String? = nil, onOpen: @escaping (VacuumOutcomeContract) -> Void) {
        self.controller = controller
        self.onOpen = onOpen
        authoredTitle = title
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
        bag.observe { [weak self] in self?.render(force: false) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func render(force: Bool) {
        let away = controller.whileAway
        guard force || away != shown else { return }
        shown = away
        arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
        let title = authoredTitle ?? "\(controller.vacuum.title) Cleaning Report"
        switch away {
        case .empty:
            break
        case let .typed(contract):
            let counts = VacuumOutcomeText.counts(contract)
            let visual = VacuumOutcomeText.overviewVisual(counts)
            let day = VacuumOutcomeText.day(contract.day)
            let overview = VacuumOutcomeText.overviewSubtitle(counts)
            let row = UKVacuumRowButton(UKRowView(
                .init("\(title) (\(contract.rooms.count))", subtitle: overview.isEmpty ? day : "\(day) · \(overview)",
                      symbol: VacuumStyle.symbol(visual.icon), glyph: UKVacuumStyle.color(visual.tone)), surface: .sheet)) { [onOpen] in onOpen(contract) }
            row.spokenLabel = "Open \(controller.vacuum.title) Automatic Cleaning Report for \(day)"
            row.spokenValue = overview
            row.accessibilityIdentifier = "vacuum.report"
            addArrangedSubview(UKVacuumSection(authoredTitle ?? "Cleaning Report", content: [UKModuleListView(surface: .sheet, rows: [row])]))
        case let .legacy(cleaned, issues):
            addArrangedSubview(UKVacuumSection(title, content: lists(cleaned: cleaned, issues: issues)))
        case let .protocolNotice(kind, cleaned, issues):
            let copy = VacuumOutcomeText.protocolTitle(kind)
            var content: [UIView] = [UKInlineAlertView("\(copy.title): \(copy.description)")]
            if !cleaned.isEmpty || !issues.isEmpty {
                content.append(.ukInset(disclosure(cleaned: cleaned, issues: issues), horizontal: HassTokens.Spacing.l))
            }
            addArrangedSubview(UKVacuumSection(title, content: content))
        }
    }

    private func lists(cleaned: [String], issues: [String]) -> [UIView] {
        var views: [UIView] = []
        if !cleaned.isEmpty { views.append(UKInfoBoxView(title: "Cleaned", message: cleaned.map { "• " + $0 }.joined(separator: "\n"), tone: .success)) }
        if !issues.isEmpty { views.append(UKInlineAlertView("Issues:\n" + issues.map { "• " + $0 }.joined(separator: "\n"))) }
        return views
    }

    /// "Unstructured Report Details": a disclosure that shows the lists.
    private func disclosure(cleaned: [String], issues: [String]) -> UIView {
        let header = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Unstructured Report Details"
        configuration.image = UIImage(systemName: legacyOpen ? "chevron.down" : "chevron.right")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = HassTokens.Spacing.s
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = UKDesignInk.action
        header.configuration = configuration
        header.contentHorizontalAlignment = .fill
        header.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        header.accessibilityLabel = "\(legacyOpen ? "Hide" : "Show") \(controller.vacuum.title) Unstructured Report Details"
        header.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.legacyOpen.toggle()
            self.render(force: true)
        }, for: .touchUpInside)
        var views: [UIView] = [header]
        if legacyOpen {
            views.append(UKVacuumDescription("These details may be inconsistent with the typed status."))
            views += lists(cleaned: cleaned, issues: issues)
        }
        return ukVStack(views, spacing: HassTokens.Spacing.s)
    }
}

// MARK: - Report detail

/// Read-only outcome rows over a pinned report value; both native and composed detail surfaces use them.
@MainActor
func ukVacuumOutcomeRows(vacuum: VacuumConfig, contract: VacuumOutcomeContract) -> UIView {
    let names = VacuumOutcomeText.roomNames(contract, vacuum: vacuum)
    let rows = contract.rooms.map { room -> UIView in
            let visual = VacuumOutcomeText.statusVisual(room.status)
            let detail = VacuumOutcomeText.detail(room, roomNames: names)
            let status = UILabel.uk(.subheadline, ink: UKDesignInk.secondary, alignment: .right)
            status.text = VacuumOutcomeText.statusTitle(room.status)
            let row = UKRowView(.init(room.roomName, subtitle: detail, symbol: VacuumStyle.symbol(visual.icon), glyph: UKVacuumStyle.color(visual.tone)),
                                      accessory: status, surface: .sheet)
            row.isAccessibilityElement = true
            row.accessibilityLabel = [room.roomName, detail, VacuumOutcomeText.statusTitle(room.status)].joined(separator: ", ")
            row.accessibilityIdentifier = "vacuum.outcome.\(room.roomId)"
            return row
        }
    return UKModuleListView(surface: .sheet, rows: rows)
}
#endif
