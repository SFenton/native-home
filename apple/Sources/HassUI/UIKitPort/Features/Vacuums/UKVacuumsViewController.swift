#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Robot Vacuums and Auto-Clean on the wallpaper (`VacuumsPage`, direction G mockup n6-vacuums): a one-line summary under the large
/// title, the robots as `.cleaning` tiles, and Auto-Clean as an inset list of switches. One column on phones, folded or portrait;
/// where a split is allowed (unfolded Duo and iPad in landscape) Robot Vacuums leads and Auto-Clean sits beside it.
@MainActor
final class UKVacuumsViewController: UKPageViewController {
    private let autoClean: VacuumAutoCleanController
    private let makeSheet: (VacuumConfig) -> UKVacuumSheetViewController
    private let initialVacuum: VacuumConfig?

    private let host = UIView()
    private let summary = UILabel.uk(.subheadline, monospacedDigit: true, ink: UKInk.onDarkSecondary)
    private let robotsColumn = UIStackView()
    private let autoCleanSection = UIStackView()
    private var grid: UKDynamicGridView!
    private var gridHost: UKMeasuredView<UKDynamicGridView>!
    private var tiles: [UKGlassTileView] = []
    private var toggles: [(control: Vacuums.AutoCleanControl, row: UKModuleToggleRow, failed: Bool)] = []
    private var isSplit: Bool?
    private weak var splitDivider: UIView?
    private var scrolls: [UIScrollView] = []
    private var resetScrolls = Set<ObjectIdentifier>()
    private var presented: Bool
    private var sheetOpen = false

    /// Creates the page.
    /// - Parameters:
    ///   - initialVacuum: A vacuum whose sheet opens at once (gallery).
    ///   - sheet: Builds a vacuum's sheet.
    init(context: UKContext, caller: any HassServiceCalling, scheduler: any RevertScheduler = TaskRevertScheduler(), initialVacuum: VacuumConfig? = nil,
         sheet: @escaping (VacuumConfig) -> UKVacuumSheetViewController) {
        autoClean = VacuumAutoCleanController(store: context.store, caller: caller, scheduler: scheduler)
        makeSheet = sheet
        self.initialVacuum = initialVacuum
        presented = initialVacuum == nil
        super.init(context: context, title: "Vacuums")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: View

    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .page }

    override func viewDidLoad() {
        super.viewDidLoad()
        host.accessibilityIdentifier = "vacuums.layout.single"
        contentView.addSubview(host)
        host.ukPin(to: contentView)
        buildStructure()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKVacuumsViewController, _) in page.rescaleGrid() }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (page: UKVacuumsViewController, _) in page.updateDivider() }
        // The single column stands in from the start so the large title tracks its scroll view; the first layout may swap it.
        applyLayout(initial: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !presented, let initialVacuum {
            presented = true
            open(initialVacuum)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyLayout()
        // A new scroll view starts at its content's top, below the large title.
        for scroll in scrolls where !resetScrolls.contains(ObjectIdentifier(scroll)) && scroll.adjustedContentInset.top > 0 {
            resetScrolls.insert(ObjectIdentifier(scroll))
            scroll.contentOffset = CGPoint(x: 0, y: -scroll.adjustedContentInset.top)
        }
    }

    /// Holds the observations of the robots and Auto-Clean rows, which come from the house document, so a rebuild ends the old ones.
    private let structureBag = UKObservationBag()

    /// Builds the summary, the robot tiles and the Auto-Clean rows from the house document. Called from `viewDidLoad` and again by
    /// ``houseLayoutDidChange()``, which empties the two columns first.
    private func buildStructure() {
        structureBag.removeAll()
        for column in [robotsColumn, autoCleanSection] {
            for view in column.arrangedSubviews {
                column.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }
        toggles = []
        buildSummary()
        buildRobots()
        buildAutoClean()
    }

    override func houseLayoutDidChange() {
        buildStructure()
    }

    // MARK: Pieces

    /// "1 Cleaning · 1 Needs Attention" under the large title, or nothing when no robot reports.
    private func buildSummary() {
        summary.accessibilityIdentifier = "vacuums.summary"
        structureBag.observe { [weak self] in
            guard let self else { return }
            let line = VacuumPageFormat.summary(states: Vacuums.all.map { self.context.store.entity($0.entityId).state?.state })
            self.summary.text = line
            self.summary.isHidden = line == nil
        }
    }

    private func buildRobots() {
        let configuration = UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true)
        grid = UKDynamicGridView(configuration: configuration)
        grid.followsFold = true
        gridHost = UKMeasuredView(grid)
        let environment = UKTileEnvironment(context: context)
        tiles = Vacuums.all.map { @MainActor vacuum in
            let tile = UKGlassTileView(model: UKGlassTileModel(title: vacuum.title, symbol: "fan", isActive: false), environment: environment)
            // A robot is a navigation tile with the room page's two discs (rollout lane M, audit item 31; `VacuumRobotTile`): start / pause and
            // dock (`VacuumActions`, the same provider as the room page's vacuum tile), then the chevron; the body opens the sheet. A tap shows
            // the new state at once through `OptimisticActions` and a rejected call shows "Didn't Respond". The tile fills while the robot works
            // and shows the battery band while it cleans.
            var actions: OptimisticActions?
            @MainActor func shown() -> EntityState? { self.context.store.entity(vacuum.entityId).state.map { $0.showing(actions?.shown(vacuum.entityId)) } }
            @MainActor func model() -> UKGlassTileModel {
                let store = self.context.store
                let shown = shown()
                let failed = actions?.isFailed(vacuum.entityId) ?? false
                let face = VacuumPageFormat.tile(state: shown?.state, battery: store.entity(vacuum.batteryEntityId).state?.state,
                                                 error: store.entity(vacuum.errorEntityId).state?.state)
                let specs = VacuumActions(entityId: vacuum.entityId).actions(for: shown)
                var model = UKGlassTileModel(
                    title: vacuum.title, subtitle: failed ? "Didn't Respond" : face.subtitle, symbol: VacuumStyle.symbol(face.icon), family: .cleaning,
                    isActive: face.isActive, isError: face.isError || failed,
                    behavior: TileBehavior(.classify(hasDestination: true, actions: TileActionKind.vacuum.restingActionCount), primary: nil),
                    actions: specs.items, progress: face.progress, identifier: "vacuums.tile.\(vacuum.vacuumMapId)")
                model.stateCandidates = VacuumActions(entityId: vacuum.entityId).stateTextCandidates
                model.bodyHint = "Opens the vacuum controls and map."
                return model
            }
            structureBag.observe { [weak self, weak tile] in
                guard let self, let tile else { return }
                tile.configure(model(), environment: environment, action: { [weak self] in self?.open(vacuum) }, perform: { [weak self] id in
                    guard let self, let spec = VacuumActions(entityId: vacuum.entityId).actions(for: shown()).first(where: { $0.id == id }),
                          let caller = self.context.caller ?? self.context.connection else { return }
                    let run = actions ?? OptimisticActions(store: self.context.store, rules: [vacuum.entityId: .liveChange], caller: caller)
                    actions = run
                    run.perform(spec, failing: vacuum.entityId)
                })
                self.grid.invalidateLayout()
                self.gridHost.invalidate()
            }
            return tile
        }
        grid.setItems(tiles.map { UKGridItem($0) })
        rescaleGrid()
        robotsColumn.axis = .vertical
        robotsColumn.alignment = .fill
        robotsColumn.spacing = HassTokens.Spacing.m
        let section = ukVStack([UKMeasuredView(UKPageSectionHeaderView("Robot Vacuums")), gridHost], spacing: HassTokens.Spacing.s)
        robotsColumn.addArrangedSubview(summary)
        robotsColumn.addArrangedSubview(section)
    }

    /// `@ScaledMetric(relativeTo: .subheadline)` minimum tile width.
    private func rescaleGrid() {
        grid.configuration.minCellWidth = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 150, compatibleWith: traitCollection)
        gridHost.invalidate()
    }

    private func buildAutoClean() {
        autoCleanSection.axis = .vertical
        autoCleanSection.alignment = .fill
        autoCleanSection.spacing = HassTokens.Spacing.s
        let glyph = UIColor(ColorFamily.cleaning.glyphToken)
        let rows = Vacuums.autoCleanControls.map { control -> UIView in
            let row = UKModuleToggleRow(control.title, subtitle: nil, symbol: "clock.arrow.circlepath", glyph: glyph, isOn: false,
                                        hint: "Turns automatic cleaning on or off.") { [weak self] in self?.autoClean.toggle(control) }
            row.accessibilityIdentifier = "vacuums.autoClean.\(control.entityId)"
            toggles.append((control, row, false))
            return row
        }
        autoCleanSection.addArrangedSubview(UKMeasuredView(UKPageSectionHeaderView("Auto-Clean")))
        autoCleanSection.addArrangedSubview(UKModuleListView(rows: rows))
        structureBag.observe { [weak self] in self?.renderAutoClean() }
        // The divider shows where the panes meet at the midpoint (lying flat, iPad), not on the hinge band (partly folded).
        structureBag.observe { [weak self] in self?.updateDivider() }
    }

    private func updateDivider() {
        splitDivider?.isHidden = context.shell?.windowHinge != nil || traitCollection.accessibilityContrast != .high
    }

    private func renderAutoClean() {
        let glyph = UIColor(ColorFamily.cleaning.glyphToken)
        for index in toggles.indices {
            let control = toggles[index].control
            let row = toggles[index].row
            let display = autoClean.display(control)
            // Unavailable rows dim only the glyph; their text keeps full contrast.
            row.row.update(.init(control.title, subtitle: display.subtitle, symbol: "clock.arrow.circlepath", glyph: glyph, glyphOpacity: display.isUnavailable ? 0.4 : 1),
                           accessory: row.row.accessory)
            row.setOn(display.isEnabled)
            row.isEnabled = !display.isUnavailable
            if display.isFailed, !toggles[index].failed {
                UKTapFeedback.failure()
                UIAccessibility.post(notification: .announcement, argument: "\(control.title), didn't respond")
            }
            toggles[index].failed = display.isFailed
        }
    }

    // MARK: Layout

    private func applyLayout(initial: Bool = false) {
        let size = contentView.bounds.size
        guard size.width > 0 || initial else { return }
        let split = !initial && SplitPolicy.allowsSplit(size: size, isRegularWidth: traitCollection.horizontalSizeClass == .regular)
        guard split != isSplit else { return }
        isSplit = split
        host.subviews.forEach { $0.removeFromSuperview() }
        robotsColumn.removeFromSuperview()
        autoCleanSection.removeFromSuperview()
        host.accessibilityIdentifier = split ? "vacuums.layout.split" : "vacuums.layout.single"
        if split {
            // Robots end at the hinge and Auto-Clean starts after it on the unfolded Duo; the midpoint on an iPad.
            let left = scrollColumn([robotsColumn], spacing: 0)
            let right = scrollColumn([autoCleanSection], spacing: 0)
            let panes = UKHingedPanes(leading: left, trailing: right, shell: context.shell)
            host.addSubview(panes)
            panes.ukPin(to: host)
            // No drawn divider (split-view rule): a 1 pt hairline only under Increase Contrast, and only where the panes meet at the
            // midpoint (the hinge band is its own divider). It sits over the panes, not in the scroll view, so it never scrolls or
            // takes part in the scroll view's layout.
            let divider = UIView()
            divider.backgroundColor = UKDesignSurface.separator
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.isUserInteractionEnabled = false
            divider.isAccessibilityElement = false
            host.addSubview(divider)
            splitDivider = divider
            updateDivider()
            NSLayoutConstraint.activate([
                divider.leadingAnchor.constraint(equalTo: right.leadingAnchor),
                divider.topAnchor.constraint(equalTo: host.topAnchor), divider.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                divider.widthAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),
            ])
            scrolls = [left, right]
            setPageScrollView(left)
        } else {
            let scroll = scrollColumn([robotsColumn, autoCleanSection], spacing: UKPageMetrics.section)
            host.addSubview(scroll)
            scroll.ukPin(to: host)
            scrolls = [scroll]
            setPageScrollView(scroll)
        }
        view.setNeedsLayout()
    }

    /// A scroll view of `views` in the page body padding (``UKPageMetrics/padding``).
    private func scrollColumn(_ views: [UIView], spacing: CGFloat) -> UIScrollView {
        let scroll = UIScrollView()
        let stack = ukVStack(views, spacing: spacing)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let padding = UKPageMetrics.padding
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: padding.top),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -padding.bottom),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: padding.left),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -padding.right),
        ])
        return scroll
    }

    // MARK: Sheet

    private func open(_ vacuum: VacuumConfig) {
        guard !sheetOpen else { return }
        sheetOpen = true
        let sheet = makeSheet(vacuum)
        UKVacuumSheet.modal(for: sheet) { [weak self] in self?.sheetOpen = false }.present(from: self)
    }
}
#endif
