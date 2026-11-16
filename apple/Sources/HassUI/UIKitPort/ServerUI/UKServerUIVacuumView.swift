#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Atomic domain renderer

/// One configured atomic control. It owns neither a feature sheet nor a parallel map/state client.
@MainActor
final class UKServerUIVacuumView: UIView, UKGridMeasuring {
    typealias D = ServerUICompositionDocument
    private let column = UIStackView()
    private let error = UILabel.uk(.footnote, ink: UKDesignInk.primary)
    private let bag = UKObservationBag()
    private var definition: D.VacuumControl?
    private var source: UKServerUIVacuumSource?
    private var content: UIView?
    private var tracksMap = false
    private var tracksReport = false
    private var wasVisible = false
    private var areaHeight: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.s
        addSubview(column)
        column.ukPin(to: self)
        error.isHidden = true
        error.accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ value: D.VacuumControl, source: UKServerUIVacuumSource?, page: UKServerUIPage) {
        guard definition != value || self.source !== source else { return }
        if tracksMap { self.source?.mounted(self, visible: false) }
        bag.removeAll()
        definition = value
        self.source = source
        isHidden = false
        areaHeight?.isActive = false
        column.arrangedSubviews.forEach { column.removeArrangedSubview($0); $0.removeFromSuperview() }
        content = nil
        tracksMap = false
        tracksReport = false
        guard let source, let controller = source.controller else {
            let unavailable = UKInlineAlertView("The configured vacuum connection is unavailable.")
            column.addArrangedSubview(unavailable)
            return
        }
        let environment = UKTileEnvironment(context: page.context)
        func install(_ view: UIView) {
            let measured: UIView = view is UKGlassTileView || view is UKVacuumChoiceTile
                ? UKVacuumTileGrid(views: [view], minWidth: 150, maxColumns: 1) : view
            content = measured
            column.addArrangedSubview(measured)
        }
        switch value.primitive {
        case let .map(overlay, height, runtimeHeight, label, loading, unavailable, locate):
            tracksMap = true
            let state = UKVacuumSheetState(tab: overlay == .autoClean ? .autoClean : .controls, controller: controller)
            let frame = UKVacuumMapFrame(controller: controller, mapState: source.mapState, state: state,
                presentation: .init(height: height, runtimeHeight: runtimeHeight, label: label, loadingText: loading,
                    unavailableText: unavailable, showsLocate: locate, autoCleanOverlay: overlay == .autoClean),
                onLocate: { [weak source] in
                    guard let source, source.controller?.status.primaryAvailable == true,
                          source.controller?.services?.contains("vacuum.locate") == true else {
                        source?.fail("Locate is unavailable."); return
                    }
                    source.controller?.locate()
                }, onRoomTap: { [weak source] id, presenter in source?.choose(id, from: presenter) })
            install(frame)
            bag.observe { [weak frame] in
                frame?.setMode(controller.runtimeMode)
                frame?.ukRemeasureContainers()
            }
        case .settings(let labels):
            let group = UKVacuumSettingsGroup { [weak source] setting, option in
                guard let source, let current = source.controller?.settingRows(in: source.controller?.runtimeMode ?? .minimal)
                    .first(where: { $0.setting.entityId == setting.entityId })?.setting,
                      !current.isDisabled, current.options.contains(option),
                      source.controller?.services?.contains(String(setting.entityId.prefix(while: { $0 != "." })) + ".select_option") == true else {
                    source?.fail("The cleaning setting is no longer available."); return
                }
                source.controller?.select(setting.entityId, option: option)
            }
            install(group)
            var first = true
            var generation = page.context.store.reapplyGeneration
            var reappliedAt: ContinuousClock.Instant?
            bag.observe { [weak group, weak page] in
                let nextGeneration = page?.context.store.reapplyGeneration ?? generation
                if nextGeneration != generation { reappliedAt = .now; generation = nextGeneration }
                let isReapply = TileActionSetTransition.isReapply(elapsedSinceReapply: reappliedAt.map { $0.duration(to: .now) })
                let scrolling = page?.body?.isDragging == true || page?.body?.isDecelerating == true
                let available = controller.settingRows(in: controller.runtimeMode)
                let rows = labels.compactMap { label -> VacuumCleaningSettingRow? in
                    guard var row = available.first(where: { $0.role == label.role }) else { return nil }
                    row.setting.title = label.title
                    row.setting.detail = label.hint
                    return row
                }
                group?.update(rows: rows, animated: !first && !isReapply && !scrolling)
                group?.ukRemeasureContainers()
                first = false
            }
        case .choice(let id, .rooms):
            let tile = UKVacuumChoiceTile(tile: .room(title: value.node.title, icon: "", order: nil, editable: false),
                identifier: value.node.id, environment: environment, perform: {})
            install(tile)
            bag.observe { [weak tile, weak page] in
                guard var entry = controller.roomTiles.first(where: { $0.zone.entityId == id })?.tile else { return }
                entry.title = value.node.title
                entry.accessibilityLabel = entry.order.map { "\(value.node.title), cleaning order \($0)" } ?? value.node.title
                tile?.update(entry) { [weak source, weak page] in
                    guard let page else { return }
                    source?.choose(id, from: page)
                }
            }
        case .status(let metric):
            bag.observe { [weak self] in
                guard let self, var status = controller.statusTiles.first(where: { $0.kind.rawValue == metric.rawValue }) else { return }
                status.caption = value.node.title
                self.replace(UKVacuumStatusTiles(tiles: [status], environment: environment))
            }
        case .card, .autoClean, .choice(_, .autoClean):
            // Lowered at compile time onto generic parts (`ServerUIVacuumLowering`): a document never reaches the renderer with these.
            break
        case .notices:
            install(UKVacuumStatusSummary(controller: controller, mapState: source.mapState, environment: environment, showsTiles: false))
        case .command(let kind, let icon):
            if kind == .clean || kind == .cleanArea {
                let button = UKPrimaryButton(value.node.title, systemImage: icon.drawn) { [weak source] in source?.run(kind) }
                button.accessibilityIdentifier = value.node.id
                install(button)
                bag.observe { [weak self, weak button] in
                    let action = source.command(kind)
                    button?.isEnabled = action?.isDisabled == false
                    button?.accessibilityValue = action?.detail
                    self?.isHidden = action == nil
                    self?.ukRemeasureContainers()
                }
                break
            }
            let tile = UKGlassTileView(model: .init(title: value.node.title, symbol: icon.drawn, isActive: false), environment: environment)
            install(tile)
            bag.observe { [weak self, weak tile, weak source] in
                guard let source else { return }
                let action = source.command(kind)
                self?.isHidden = action == nil
                self?.ukRemeasureContainers()
                let spec = TileActionSpec(id: kind.rawValue, verb: value.node.title, symbol: icon.drawn,
                    phase: action?.isDisabled == false ? (controller.dockCommandPending ? .inFlight : .ready) : .unavailable,
                    feedback: .tracked)
                let model = UKGlassTileModel(title: value.node.title, subtitle: nil, symbol: icon.drawn, family: .cleaning,
                    isActive: [.stopDockClean, .stopDrying].contains(kind), isUnavailable: spec.phase == .unavailable,
                    behavior: .perform(spec.id), actions: [TileActionItem(spec)], identifier: value.node.id,
                    spokenValue: action?.detail ?? "This command is not available in the current state.")
                tile?.configure(model, environment: environment, perform: { [weak source] _ in source?.run(kind) })
            }
        case .target(let mode, let icon, let destination):
            let button = UKVacuumActionTile(title: value.node.title, symbol: icon.drawn, identifier: value.node.id,
                environment: environment) { [weak source, weak page] in
                guard let source, let page else { return }
                source.switchTarget(mode, from: page) { [weak page] in
                    guard let page else { return }; page.renderer?.activate(destination, from: page)
                }
            }
            install(button)
            bag.observe { [weak self, weak button] in
                self?.isHidden = !controller.showsCleaningSetup
                self?.ukRemeasureContainers()
                let ready = controller.roomsEditable && (mode == .rooms || source.mapState.isReady)
                let spec = TileActionSpec(id: "do", verb: value.node.title, symbol: icon.drawn,
                    phase: ready ? .ready : .unavailable, feedback: .momentary)
                button?.tile.configure(.init(title: value.node.title, symbol: icon.drawn, family: .cleaning,
                    isActive: false, isUnavailable: !ready, behavior: .perform(spec.id), actions: [TileActionItem(spec)], identifier: value.node.id))
            }
        case .clearArea(let icon):
            let button = UKVacuumActionTile(title: value.node.title, symbol: icon.drawn, identifier: value.node.id,
                environment: environment) { [weak source] in source?.clearArea() }
            install(button)
            bag.observe { [weak self, weak button] in
                self?.isHidden = !controller.showsCleaningSetup || controller.areaSelection == nil
                self?.ukRemeasureContainers()
                let ready = controller.roomsEditable && controller.areaSelection != nil
                let spec = TileActionSpec(id: "do", verb: value.node.title, symbol: icon.drawn,
                    phase: ready ? .ready : .unavailable, feedback: .momentary)
                button?.tile.configure(.init(title: value.node.title, symbol: icon.drawn, family: .cleaning,
                    isActive: false, isUnavailable: !ready, behavior: .perform(spec.id), actions: [TileActionItem(spec)], identifier: value.node.id))
            }
        case .consumable(let id):
            bag.observe { [weak self] in
                guard let self, let consumable = controller.vacuum.consumables.first(where: { $0.entityId == id }) else { return }
                let state = controller.store.entity(id).state?.state
                let visual = VacuumVisual.consumable(consumable, state: state)
                let text = VacuumFormat.consumable(consumable, state: state,
                    unit: controller.store.entity(id).state?.attributes["unit_of_measurement"]?.string)
                let label = UILabel.uk(.body, ink: UKVacuumInfoTab.tint(visual.tone))
                label.text = text
                let row = UKRowView(.init(value.node.title, symbol: UKVacuumStyle.symbol(consumable.icon)), accessory: label, surface: .sheet)
                row.isAccessibilityElement = true; row.accessibilityLabel = value.node.title; row.accessibilityValue = text
                self.replace(row)
            }
        case .report(let destination):
            install(UKVacuumCleaningReport(controller: controller, title: value.node.title) { [weak source, weak page] contract in
                source?.openReport(contract)
                guard let page else { return }; page.renderer?.activate(destination, from: page)
            })
        case .outcomes:
            tracksReport = true
            bag.observe { [weak self, weak source] in
                guard let self else { return }
                if let report = source?.report { self.replace(ukVacuumOutcomeRows(vacuum: controller.vacuum, contract: report)) }
                else { self.replace(UKInlineAlertView("Open a cleaning report to view its room outcomes.")) }
            }
        case .areaEditor(let height, let use, let discardLabel, let discard):
            tracksMap = true
            source.beginDraft()
            let editor = UKVacuumAreaEditorContent(vacuum: controller.vacuum, mapState: source.mapState,
                selection: { [source] in source.draft }, setSelection: { [source] in source.draft = $0 },
                onUse: { [weak source, weak page] in
                    guard source?.useDraft() == true, let page else { return }
                    page.renderer?.activate(use, from: page)
                })
            install(editor)
            areaHeight = editor.heightAnchor.constraint(equalToConstant: height)
            areaHeight?.isActive = true
            let cancel = UKPrimaryButton(discardLabel) { [weak source, weak page] in
                source?.discardDraft()
                guard let page else { return }; page.renderer?.activate(discard, from: page)
            }
            column.addArrangedSubview(cancel)
        }
        column.addArrangedSubview(error)
        bag.observe { [weak self, weak source] in
            guard let self else { return }
            let message = source?.failure ?? controller.cleanError
            self.error.text = message
            self.error.isHidden = message == nil
            self.ukRemeasureContainers(includingSelf: true)
        }
        if tracksMap { source.mounted(self, visible: window != nil) }
    }

    private func replace(_ view: UIView) {
        if let content { column.removeArrangedSubview(content); content.removeFromSuperview() }
        content = view
        column.insertArrangedSubview(view, at: 0)
        ukRemeasureContainers(includingSelf: true)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if tracksMap { source?.mounted(self, visible: window != nil) }
        if window != nil {
            wasVisible = true
            if case .areaEditor = definition?.primitive { source?.beginDraft() }
        }
        else if wasVisible {
            if tracksReport { source?.closeReport() }
            if case .areaEditor = definition?.primitive { source?.discardDraft() }
            wasVisible = false
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let visible = column.arrangedSubviews.filter { !$0.isHidden }
        let heights = visible.map { view -> CGFloat in
            if let measuring = view as? UKGridMeasuring { return measuring.gridHeight(forWidth: width) }
            return view.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        }
        return ceil(heights.reduce(0, +) + column.spacing * CGFloat(max(visible.count - 1, 0)))
    }
}
#endif
