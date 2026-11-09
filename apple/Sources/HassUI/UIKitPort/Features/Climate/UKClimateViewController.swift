#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The Climate page (`ClimatePage`; web `ThermostatPage`; spec `.agents/pages/climate/spec.md`; direction G mockup n3). Whole Home's
/// dial straight on the wallpaper (no card) with the compact Thermostat Hub pill under it, any notices, open doors and windows,
/// then the three Advanced Controls rows that open the sheet on their tab.
///
/// Built without per-frame work: a scroll view of one stack, every value bound to the box it shows (the dial to its climate entity,
/// each tile to its sensor, the pill to the hub), and the page's shape (which notices and contact sensors show) re-read only when
/// the entities it depends on change.
@MainActor
final class UKClimateViewController: UKPageViewController, UIScrollViewDelegate {
    let controller: ClimateController
    /// Shown pinned below the page and below the sheet (the gallery's last-call line).
    var sheetAccessory: (() -> UIView)?
    private var pendingSheet: ClimateSheetRequest?

    private let scroll = UIScrollView()
    private let column = UIStackView()
    /// The sections in the two-column pose (partly folded); hidden, and its constraints off, in every other pose.
    private let foldView = UKFoldColumns(spacing: UKPageMetrics.section)
    private var flatConstraints: [NSLayoutConstraint] = []
    private var splitConstraints: [NSLayoutConstraint] = []
    private var sectionViews: [UIView] = []
    private var isSplit = false
    private let wholeHomeInner = UIStackView()
    private let dialHost = UIView()
    private var dial: UKClimateThermostatDial?
    private var dialEntityId: String?
    private let noticeStack = UIStackView()
    private var noticeSignature = ""
    private let contactsSection = UIStackView()
    private let contactGrid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
    private var contactGridHost: UKGridHost?
    private var contactSignature = ""
    private let contactBag = UKObservationBag()
    private let hubPill: UKThermostatHubPill

    /// How much of the Whole Home dial's empty bottom the hub pill reclaims.
    static let dialBottomOverlap: CGFloat = 36

    init(context: UKContext, controller: ClimateController, initialSheet: ClimateSheetRequest? = nil) {
        self.controller = controller
        pendingSheet = initialSheet
        hubPill = UKThermostatHubPill(controller: controller)
        super.init(context: context, title: "Climate")
    }

    convenience init(context: UKContext) {
        let caller: any HassServiceCalling = context.connection ?? context.caller ?? NoServiceCaller()
        self.init(context: context, controller: ClimateController(store: context.store, caller: caller))
    }

    /// The Whole Home commit rule: a range set on the global thermostat fans out to every room; the eco-away thermostat and
    /// single targets go to the dial's own entity (`ClimatePage.wholeHomeCommitIds`).
    static func wholeHomeCommitIds(dialEntityId: String, targets: ThermostatTargets) -> [String] {
        ClimatePage.wholeHomeCommitIds(dialEntityId: dialEntityId, targets: targets)
    }

    // MARK: View

    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .page }

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (page: UKClimateViewController, _) in page.decideSplit() }
        scroll.delegate = self
        scroll.accessibilityIdentifier = "climate.scroll"
        install(scrollView: scroll)

        column.axis = .vertical
        column.spacing = UKPageMetrics.section
        column.alignment = .fill
        column.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(column)
        let fill = column.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -UKPageMetrics.side * 2)
        fill.priority = UILayoutPriority(999)
        flatConstraints = [
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: UKPageMetrics.top),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -UKPageMetrics.bottom),
            column.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            fill,
        ]
        NSLayoutConstraint.activate(flatConstraints)

        column.addArrangedSubview(buildWholeHome())
        column.addArrangedSubview(buildContacts())
        column.addArrangedSubview(buildAdvancedControls())
        sectionViews = column.arrangedSubviews
        installFoldColumns()

        for (index, view) in column.arrangedSubviews.enumerated() {
            UKArrivalMotion.apply(to: view, shell: context.shell, kind: .rise, index: index, bag: bag)
        }

        // The page's shape: the dial's entity and the notices follow the home / away state; the contact sensors follow the doors.
        bag.observe { [weak self] in
            guard let self else { return }
            foldView.hinge = context.shell?.windowHinge
            decideSplit()
            view.setNeedsLayout()
        }
        bag.observe { [weak self] in self?.refreshWholeHome() }
        contactBag.observe { [weak self] in self?.refreshContacts() }
    }

    // MARK: Fold columns

    /// Whole Home leads; the open contact sensors and Advanced Controls trail (`.agents/design/section-sides.md`).
    private func installFoldColumns() {
        foldView.translatesAutoresizingMaskIntoConstraints = false
        foldView.isHidden = true
        foldView.sideInset = UKPageMetrics.side
        foldView.splitIdentifier = "climate.columns.split"
        foldView.isRegular = { [weak self] in self?.traitCollection.horizontalSizeClass == .regular }
        foldView.offeredHeight = { [weak self] in self?.scroll.bounds.height ?? 0 }
        scroll.addSubview(foldView)
        splitConstraints = [
            foldView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: UKPageMetrics.top),
            foldView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -UKPageMetrics.bottom),
            foldView.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            foldView.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ]
    }

    /// The pose is decided where the hinge, the size or the size class changes, never in a layout pass: the hinge observer, the first
    /// appearance, a size transition and a trait change call ``decideSplit(width:)``, and a layout pass that finds the decision out of
    /// date only asks for one a turn later. A change moves the sections from the stack to the columns (or back) starting from the
    /// frames they had, so ``UKReflow`` slides them instead of re-fading.
    private func decideSplit(width: CGFloat? = nil) {
        let split = foldView.hinge != nil && foldView.geometry(width: width ?? scroll.bounds.width) != nil
        if split != isSplit { apply(split: split) }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        decideSplit()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        decideSplit(width: size.width)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        inLayoutPass = true
        defer { inLayoutPass = false }
        // Layout only places views from the decision already taken; a size change nobody announced is decided one turn later.
        let split = foldView.hinge != nil && foldView.geometry(width: scroll.bounds.width) != nil
        if split != isSplit { DispatchQueue.main.async { [weak self] in self?.decideSplit() } }
    }

    /// True while ``viewDidLayoutSubviews()`` runs, so a pose decided inside it is counted (`UKFoldColumns.splitWritesInLayout`).
    private var inLayoutPass = false

    private func apply(split: Bool) {
        if inLayoutPass { UKFoldColumns.splitWritesInLayout += 1 }
        UKLayoutCensus.note("climate \(isSplit ? "split" : "flat") -> \(split ? "split" : "flat")\(inLayoutPass ? " IN LAYOUT" : "")")
        isSplit = split
        let old = sectionViews.map { $0.superview == nil ? CGRect.zero : $0.convert($0.bounds, to: scroll) }
        if split {
            for view in sectionViews {
                column.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            NSLayoutConstraint.deactivate(flatConstraints)
            NSLayoutConstraint.activate(splitConstraints)
            foldView.isHidden = false
            let sides: [FoldSide] = [.leading, .trailing, .trailing]
            foldView.setSections(zip(sectionViews, sides).map { UKFoldColumns.Section($0, side: $1) })
            // The container was hidden and has no width of its own yet: decide its pose for the page's width now, not in its layout.
            foldView.updateSplit(width: scroll.bounds.width)
            for (view, frame) in zip(sectionViews, old) {
                view.translatesAutoresizingMaskIntoConstraints = true
                view.frame = foldView.convert(frame, from: scroll)
            }
        } else {
            foldView.setSections([])
            foldView.isHidden = true
            NSLayoutConstraint.deactivate(splitConstraints)
            NSLayoutConstraint.activate(flatConstraints)
            for view in sectionViews { column.addArrangedSubview(view) }
        }
        scroll.setNeedsLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let request = pendingSheet, presentedViewController == nil {
            pendingSheet = nil
            openSheet(request)
        }
    }

    // MARK: Sections

    private func section(_ title: String, _ content: UIView) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [UKGridHost(UKPageSectionHeaderView(title)), content])
        stack.axis = .vertical
        stack.spacing = UKPageMetrics.sectionHeader
        return stack
    }

    /// Whole Home: the dial on the wallpaper, the hub pill and the notices.
    private func buildWholeHome() -> UIView {
        wholeHomeInner.axis = .vertical
        wholeHomeInner.spacing = HassTokens.Spacing.m
        wholeHomeInner.alignment = .fill
        dialHost.accessibilityIdentifier = "climate.wholeHome"
        dialHost.isAccessibilityElement = false
        dialHost.accessibilityContainerType = .semanticGroup
        noticeStack.axis = .vertical
        noticeStack.spacing = HassTokens.Spacing.m
        noticeStack.isHidden = true
        wholeHomeInner.addArrangedSubview(dialHost)
        wholeHomeInner.addArrangedSubview(hubPill)
        wholeHomeInner.addArrangedSubview(noticeStack)
        // The 270° ring leaves the bottom of its square empty (about 14% of the side); the hub pill tucks into it instead of
        // sitting a ring's width below (owner, 2026-10-16: "takes up too much space").
        wholeHomeInner.setCustomSpacing(HassTokens.Spacing.m - Self.dialBottomOverlap, after: dialHost)
        wholeHomeInner.widthAnchor.constraint(lessThanOrEqualToConstant: 640).isActive = true
        // Centred; where the hinge crosses it (unfolded Duo, landscape) it moves to the leading region.
        return section("Whole Home", UKHingeAvoidingView(child: wholeHomeInner))
    }

    private func refreshWholeHome() {
        let lookup = controller.lookup
        let entityId = ClimateLogic.wholeHomeDialEntityId(lookup)
        if entityId != dialEntityId {
            dialEntityId = entityId
            dial?.removeFromSuperview()
            let newDial = UKClimateThermostatDial(
                context: context, entityId: entityId, title: "Whole Home",
                action: ClimateLogic.hvacAction(lookup(ClimateConfig.globalThermostatEntityId)), caller: controller.caller,
                commitEntityIds: { targets in Self.wholeHomeCommitIds(dialEntityId: entityId, targets: targets) })
            newDial.translatesAutoresizingMaskIntoConstraints = false
            dialHost.addSubview(newDial)
            newDial.ukPin(to: dialHost)
            dial = newDial
        } else {
            // `hvac_action` always comes from the global thermostat, whichever one the dial shows.
            dial?.action = ClimateLogic.hvacAction(lookup(ClimateConfig.globalThermostatEntityId))
        }
        var notices: [UIView] = []
        var signature = ""
        if let notice = ClimateLogic.awayNotice(climateEntityId: ClimateConfig.globalThermostatEntityId, useEffectiveMode: true, lookup) {
            notices.append(UKClimateNoticeView(text: notice, symbol: "house", identifier: "climate.awayNotice"))
            signature += "away:\(notice)|"
        }
        if ClimateLogic.showsIntegrationWarning(lookup) {
            notices.append(UKClimateNoticeView(text: ClimateConfig.Copy.integrationOffWarning, symbol: "exclamationmark.triangle", isWarning: true,
                                               identifier: "climate.integrationWarning"))
            signature += "warning"
        }
        guard signature != noticeSignature else { return }
        noticeSignature = signature
        noticeStack.ukSetArranged(notices)
        noticeStack.isHidden = notices.isEmpty
    }

    /// Open Contact Sensors: a tile per open door or window, hidden while none is open.
    private func buildContacts() -> UIView {
        contactGrid.followsFold = true
        contactGridHost = UKGridHost(contactGrid)
        contactsSection.axis = .vertical
        contactsSection.spacing = HassTokens.Spacing.s + 2
        contactsSection.addArrangedSubview(UKGridHost(UKPageSectionHeaderView("Open Contact Sensors")))
        contactsSection.addArrangedSubview(contactGridHost!)
        contactsSection.isHidden = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKClimateViewController, _) in
            page.contactGrid.configuration.minCellWidth = UKFont.scaled(160, relativeTo: .subheadline, traits: page.traitCollection)
        }
        contactGrid.configuration.minCellWidth = UKFont.scaled(160, relativeTo: .subheadline, traits: traitCollection)
        return contactsSection
    }

    private var contactBindings = UKObservationBag()

    private func refreshContacts() {
        let open = ClimateLogic.openContactSensors(controller.lookup)
        let signature = open.map(\.entityId).joined(separator: ",")
        guard signature != contactSignature else { return }
        contactSignature = signature
        contactBindings.removeAll()
        let bindings = UKObservationBag()
        contactBindings = bindings
        let environment = UKTileEnvironment(context: context)
        let tiles: [UKGridItem] = open.map { sensor in
            let tile = UKGlassTileView(model: Self.contactModel(sensor, state: nil), environment: environment)
            let box = context.store.entity(sensor.entityId)
            bindings.observe { [weak tile] in
                tile?.configure(Self.contactModel(sensor, state: ClimateLogic.contactState(box.state)), environment: environment)
            }
            return UKGridItem(tile)
        }
        contactGrid.setItems(tiles)
        contactGridHost?.remeasure()
        contactsSection.isHidden = open.isEmpty
        foldView.setNeedsLayout()
    }

    private static func contactModel(_ sensor: ClimateConfig.ContactSensor, state: String?) -> UKGlassTileModel {
        UKGlassTileModel(title: sensor.title, subtitle: state, symbol: ClimateStyle.symbol(sensor.isWindow ? "mdi:window-open" : "mdi:door-open"),
                         family: .contact, isActive: true, kind: .state, identifier: "climate.contact.\(sensor.entityId)")
    }

    private func buildAdvancedControls() -> UIView {
        let rows = ClimateConfig.Tab.allCases.map { tab in
            UKClimateEntryRow(tab: tab) { [weak self] in self?.openSheet(ClimateSheetRequest(tab: tab)) }
        }
        return section("Advanced Controls", UKModuleListView(rows: rows))
    }

    // MARK: Sheet

    private func openSheet(_ request: ClimateSheetRequest) {
        let modal = UKClimateSheet.make(controller: controller, context: context, request: request, accessory: sheetAccessory?())
        modal.present(from: self)
    }

    // MARK: Scroll telemetry

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { FrameMonitor.shared.beginScroll(page: "Climate") }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { FrameMonitor.shared.endScroll(page: "Climate") }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { FrameMonitor.shared.endScroll(page: "Climate") }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        FrameMonitor.shared.endScroll(page: "Climate")
    }
}

/// Where service calls go when nothing is attached (never in the app: the shell always supplies the connection).
private final class NoServiceCaller: HassServiceCalling {
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {}
}
#endif
