#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A control that sizes itself by Auto Layout when a grid asks `sizeThatFits`.
class UKSelfFittingControl: UIControl {
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let unbounded = size.width >= CGFloat.greatestFiniteMagnitude / 2
        let target = CGSize(width: unbounded ? UIView.layoutFittingCompressedSize.width : size.width, height: UIView.layoutFittingCompressedSize.height)
        return systemLayoutSizeFitting(target, withHorizontalFittingPriority: unbounded ? .fittingSizeLevel : .required, verticalFittingPriority: .fittingSizeLevel)
    }
}

/// A tab's panel: a vertical stack that draws a snapshot of the state it shows and draws it again only when the snapshot changes.
@MainActor
class UKVacuumPanel<Snapshot: Equatable>: UIStackView {
    let controller: VacuumController
    let environment: UKTileEnvironment
    let bag = UKObservationBag()
    private var shown: Snapshot?

    init(controller: VacuumController, environment: UKTileEnvironment) {
        self.controller = controller
        self.environment = environment
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Starts following the state. Subclasses call it last in `init`.
    func start() {
        bag.observe { [weak self] in
            guard let self else { return }
            let next = self.snapshot()
            guard next != self.shown else { return }
            self.shown = next
            self.arrangedSubviews.forEach { self.removeArrangedSubview($0); $0.removeFromSuperview() }
            self.rebuild(next)
        }
    }

    /// Reads the observable state the panel draws.
    func snapshot() -> Snapshot { fatalError("subclasses override") }
    /// Draws `snapshot` into the arranged subviews.
    func rebuild(_ snapshot: Snapshot) {}
}

// MARK: - Controls

/// What the Controls tab draws.
struct UKVacuumControlsSnapshot: Equatable {
    var mode: VacuumRuntimeMode
    var setup: Bool
    var areaMode: Bool
    var rows: [VacuumCleaningSettingRow]
    var runtimeTiles: [VacuumCommandTile]
    var cleanError: String?
    var supportsArea: Bool
    var hasRooms: Bool
    var rooms: [String]
    var spokenRooms: String
    var cleanAction: VacuumController.Action
    var areaCleanAction: VacuumController.Action
    var targetDisabled: Bool
    var mapReady: Bool
    var editDisabled: Bool
    var areaSize: String?
    var previewScript: String?
    var stateTitle: String
    var stateIssue: String?
    var showsStateCard: Bool
    var showsUnavailableNotice: Bool
}

/// Cleaning target, cleaning settings, the Clean button and the run's commands (`VacuumControlsTab`; the decided design is
/// `.agents/design/mockups/proposals/vacuum-sheet-redesign`). While a run is going the setup collapses to Pause and Stop as action tiles,
/// with no state header and no text under them.
@MainActor
final class UKVacuumControlsTab: UKVacuumPanel<UKVacuumControlsSnapshot> {
    typealias Snapshot = UKVacuumControlsSnapshot

    private let mapState: VacuumMapState
    private let mode: VacuumRuntimeMode
    private let onOpenRooms: () -> Void
    private let onEditArea: () -> Void
    /// Kept across rebuilds, so a Water or Fan row coming or going animates instead of the card being redrawn.
    private lazy var settingsGroup = UKVacuumSettingsGroup { [controller] setting, option in controller.select(setting.entityId, option: option) }
    private var lastAreaMode: Bool?

    init(controller: VacuumController, environment: UKTileEnvironment, mapState: VacuumMapState, mode: VacuumRuntimeMode,
         onOpenRooms: @escaping () -> Void, onEditArea: @escaping () -> Void) {
        self.mapState = mapState
        self.mode = mode
        self.onOpenRooms = onOpenRooms
        self.onEditArea = onEditArea
        super.init(controller: controller, environment: environment)
        spacing = HassTokens.Spacing.xl
        start()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func snapshot() -> Snapshot {
        let setup = controller.showsCleaningSetup(in: mode)
        let ready = mapState.isReady
        let areaMode = controller.areaSelection != nil && controller.supportsAreaCleaning
        let size = controller.areaSelection.flatMap { area in
            mapState.scene.map { VacuumFormat.areaSize(area, pixelSize: $0.interactionGeometry.pixelSize) }
        }
        let tiles = mode == controller.runtimeMode ? controller.runtimeTiles : []
        return Snapshot(
            mode: mode, setup: setup, areaMode: areaMode, rows: controller.settingRows(in: mode), runtimeTiles: tiles,
            cleanError: controller.cleanError, supportsArea: controller.supportsAreaCleaning, hasRooms: !controller.vacuum.zones.isEmpty,
            rooms: controller.selectedZones.map(\.title), spokenRooms: controller.selectedRoomsSpokenValue, cleanAction: controller.cleanAction,
            areaCleanAction: controller.areaCleanAction(mapReady: ready, selectionAllowed: mapState.allows(controller.areaSelection)),
            targetDisabled: controller.normalCommandsDisabled || !ready, mapReady: ready, editDisabled: controller.normalCommandsDisabled || !ready,
            areaSize: size, previewScript: controller.services != nil && !controller.areaServiceReady ? controller.vacuum.areaCleaning?.script : nil,
            stateTitle: VacuumFormat.state(controller.state),
            stateIssue: controller.status.currentIssue.raw.map(VacuumFormat.issue) ?? "Home Assistant does not have a current status for the vacuum.",
            showsStateCard: !controller.status.primaryAvailable || controller.status.currentIssue.status == .present,
            showsUnavailableNotice: !setup && controller.runtimeActions.isEmpty)
    }

    override func rebuild(_ s: Snapshot) {
        if s.setup { addArrangedSubview(s.areaMode ? areaTarget(s) : roomsTarget(s)) }
        if !s.rows.isEmpty {
            // Mode changes animate the Water and Fan rows in place; the rest of the tab is rebuilt around the same group view.
            settingsGroup.update(rows: s.rows, animated: lastAreaMode != nil)
            addArrangedSubview(UKVacuumSection("Cleaning Settings", footer: VacuumSheetCopy.settingsFooter, content: [settingsGroup]))
        }
        if s.setup { addArrangedSubview(cleanButton(s)) }
        if !s.runtimeTiles.isEmpty {
            let views = s.runtimeTiles.map { tile in
                UKVacuumActionTile(tile, environment: environment) { [controller] in controller.run(tile.action.kind) } as UIView
            }
            addArrangedSubview(ukVacuumTileRow(views))
        }
        if let error = s.cleanError {
            let alert = UKInlineAlertView(error, severity: .error)
            alert.accessibilityIdentifier = "vacuum.cleanError"
            addArrangedSubview(.ukInset(alert, horizontal: HassTokens.Spacing.l))
        }
        if s.showsUnavailableNotice, s.showsStateCard {
            let text = UILabel.uk(.body, ink: UKDesignInk.primary)
            text.text = s.stateIssue
            addArrangedSubview(UKVacuumSection(s.stateTitle, content: [UKVacuumGroupCard(text)]))
        }
        lastAreaMode = s.areaMode
    }

    private func cleanButton(_ s: Snapshot) -> UIView {
        if s.areaMode {
            return UKVacuumActionButton(action: s.areaCleanAction, showsDetail: false) { [controller, mapState] in
                controller.run(.cleanArea, pixelSize: mapState.scene?.interactionGeometry.pixelSize)
            }
        }
        return UKVacuumActionButton(action: s.cleanAction, showsDetail: false) { [controller] in controller.run(.clean) }
    }

    // MARK: Target

    private func pick(_ target: VacuumCleanTarget, snapshot s: Snapshot) {
        switch VacuumCleanTarget.outcome(picking: target, areaDrawn: s.areaMode, roomsSelected: !s.rooms.isEmpty, mapReady: s.mapReady) {
        case .openRooms: onOpenRooms()
        case .openAreaEditor: onEditArea()
        case .confirmRooms: confirm(.toRooms)
        case .confirmArea: confirm(.toArea)
        case .none: break
        }
    }

    private func confirm(_ confirmation: VacuumControlsTab.Confirmation) {
        guard let presenter = ukOwningController else { return }
        UKAlerts.alert(confirmation.spec, from: presenter) { [weak self] in
            guard let self else { return }
            switch confirmation {
            case .toRooms:
                self.controller.areaSelection = nil
                self.onOpenRooms()
            case .toArea:
                self.controller.clearRoomsForArea()
                self.onEditArea()
            }
        }
    }

    // MARK: Rooms target

    private func roomsTarget(_ s: Snapshot) -> UIView {
        var blocks: [UIView] = []
        if s.hasRooms {
            // Selected Rooms has no glyph, so the hairline under it would start at its text.
            blocks.append(UKModuleListView(hasGlyphs: false, surface: .sheet, rows: [selectedRooms(s)]))
        }
        if s.supportsArea {
            blocks.append(UKVacuumActionTile(
                title: "Use Area", symbol: "rectangle.dashed", identifier: "vacuum.target.area", isUnavailable: s.targetDisabled,
                spokenValue: s.mapReady ? nil : "Area drawing needs the live map.", environment: environment) { [weak self] in
                self?.pick(.area, snapshot: s)
            })
        }
        return UKVacuumSection("Cleaning Target", footer: s.hasRooms ? VacuumSheetCopy.roomsTargetFooter : nil,
                               content: [ukVStack(blocks, spacing: HassTokens.Spacing.s)])
    }

    /// The selected rooms as numbered chips, or the Full Clean warning; opens the Rooms section. It has no chevron: it switches to a
    /// section of the same sheet, it does not push (disclosure-indicators decision).
    private func selectedRooms(_ s: Snapshot) -> UIView {
        let rooms = s.rooms
        let control = UKSelfFittingControl()
        let title = UILabel.uk(.subheadline, weight: .semibold, ink: UKDesignInk.secondary)
        title.text = rooms.isEmpty ? "Full Clean" : "Selected Rooms"
        var views: [UIView] = [title]
        if rooms.isEmpty {
            views.append(UKInlineAlertView("No rooms are selected, and no areas are drawn. If you begin cleaning, the robot vacuum will attempt to clean every mapped area."))
        } else {
            let flow = UKFlowView(spacing: 6)
            flow.setChildren(rooms.enumerated().map { UKVacuumOrderChip(order: $0 + 1, title: $1) })
            views.append(UKMeasuredView(flow))
        }
        let stack = ukVStack(views, spacing: HassTokens.Spacing.s)
        stack.isUserInteractionEnabled = false
        control.addSubview(stack)
        stack.ukPin(to: control, insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l))
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        control.addAction(UIAction { [weak self] _ in self?.onOpenRooms() }, for: .touchUpInside)
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = rooms.isEmpty ? "Full Clean" : "Selected Rooms"
        control.accessibilityValue = s.spokenRooms
        control.accessibilityHint = "Opens the Rooms section."
        control.accessibilityIdentifier = "vacuum.selectedRooms"
        return control
    }

    // MARK: Area target

    private func areaTarget(_ s: Snapshot) -> UIView {
        let edit = UKVacuumActionTile(title: "Edit Area", subtitle: s.areaSize, symbol: "pencil", identifier: "vacuum.area.edit",
                                      isUnavailable: s.editDisabled, environment: environment) { [onEditArea] in onEditArea() }
        let clear = UKVacuumActionTile(title: "Clear Area", symbol: "trash", identifier: "vacuum.area.clearSelection", environment: environment) { [controller] in
            controller.areaSelection = nil
        }
        var blocks: [UIView] = [
            ukVacuumTileRow([edit, clear]),
            UKVacuumActionTile(title: "Use Rooms", symbol: "square.split.2x2", identifier: "vacuum.target.rooms", environment: environment) { [weak self] in
                self?.pick(.rooms, snapshot: s)
            },
        ]
        if let script = s.previewScript {
            blocks.append(UKVacuumDescription("Local preview only: \(script) is not installed in Home Assistant, so starting an area clean is disabled."))
        }
        return UKVacuumSection("Cleaning Target", footer: VacuumSheetCopy.areaTargetFooter, content: [ukVStack(blocks, spacing: HassTokens.Spacing.s)])
    }
}

// MARK: - Rooms and Auto-Clean

/// The tiles of the Rooms and Auto-Clean sections (`VacuumChoiceGrid`): two columns, one at accessibility sizes, every tile in a row as
/// tall as the tallest. Each tile is created once and updated in place, so a pick animates the tile's face.
@MainActor
final class UKVacuumChoiceTab: UIStackView {
    struct Item {
        var id: String
        var tile: VacuumChoiceTile
        var identifier: String
        var toggle: (UIViewController?) -> Void
    }

    private var views: [String: UKVacuumChoiceTile] = [:]
    private var order: [String] = []
    private var grid: UKVacuumTileGrid?
    private let environment: UKTileEnvironment
    private let items: () -> [Item]
    private let bag = UKObservationBag()

    init(title: String, footer: String, environment: UKTileEnvironment, items: @escaping () -> [Item]) {
        self.environment = environment
        self.items = items
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
        spacing = HassTokens.Spacing.m
        let first = items()
        var tiles: [UIView] = []
        for item in first {
            let view = UKVacuumChoiceTile(tile: item.tile, identifier: item.identifier, environment: environment) { [weak self] in item.toggle(self?.ukOwningController) }
            views[item.id] = view
            order.append(item.id)
            tiles.append(view)
        }
        let grid = UKVacuumTileGrid(views: tiles, minWidth: 150, maxColumns: 2)
        self.grid = grid
        addArrangedSubview(UKVacuumSection(title, footer: footer, content: [grid]))
        bag.observe { [weak self] in self?.render() }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func render() {
        for item in items() { views[item.id]?.update(item.tile) { [weak self] in item.toggle(self?.ukOwningController) } }
        grid?.remeasure()
    }
}

/// Ordered room choices (`VacuumRoomsTab`): the selection tile, chosen is the filled face with the numbered order disc, the rest are dark
/// with an empty ring; the footer sits under the grid.
@MainActor
func ukVacuumRoomsTab(controller: VacuumController, environment: UKTileEnvironment) -> UIView {
    let footer = (controller.vacuum.zoneDescription + [VacuumSheetCopy.roomsFooter, "Rooms can't be changed while cleaning."]).joined(separator: " ")
    return UKVacuumChoiceTab(title: "Rooms", footer: footer, environment: environment) { [weak controller] in
        guard let controller else { return [] }
        return controller.roomTiles.map { entry in
            .init(id: entry.zone.id, tile: entry.tile, identifier: "vacuum.room.\(entry.zone.entityId)") { presenter in
                if controller.roomToggleNeedsConfirmation(entry.zone), let presenter {
                    UKAlerts.alert(AlertCopy.switchToRooms, from: presenter) { controller.toggleRoom(entry.zone) }
                } else {
                    controller.toggleRoom(entry.zone)
                }
            }
        }
    }
}

/// Rooms the coordinator cleans on its own (`VacuumAutoCleanTab`): the selection tile with a check disc. Checked is included; unchecked says
/// "Skipped" and is hatched on the map.
@MainActor
func ukVacuumAutoCleanTab(controller: VacuumController, environment: UKTileEnvironment) -> UIView {
    UKVacuumChoiceTab(title: "Auto-Clean Rooms", footer: VacuumSheetCopy.autoCleanFooter, environment: environment) { [weak controller] in
        guard let controller else { return [] }
        return controller.autoCleanTiles.map { entry in
            .init(id: entry.room.id, tile: entry.tile, identifier: "vacuum.autoCleanRoom.\(entry.room.entityId)") { _ in controller.toggleAutoClean(entry.room) }
        }
    }
}

// MARK: - Dock

/// What the Dock tab draws.
struct UKVacuumActionsSnapshot: Equatable {
    var tiles: [VacuumCommandTile]
    var preparing: Bool
    var mopMissing: Bool
    var bridgeMissing: Bool
    var hasDock: Bool
    var showsSection: Bool
}

/// Dock controls (`VacuumActionsTab`): each command is an action tile, with what it does as a footer under it. Washing shows the tracked disc
/// while a cycle starts, and Clean Mop Dock becomes Stop Dock Clean on the filled face. The mop-pad and restart notices stay inline alerts.
@MainActor
final class UKVacuumActionsTab: UKVacuumPanel<UKVacuumActionsSnapshot> {
    typealias Snapshot = UKVacuumActionsSnapshot

    override init(controller: VacuumController, environment: UKTileEnvironment) {
        super.init(controller: controller, environment: environment)
        start()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func snapshot() -> Snapshot {
        let hasDock = controller.vacuum.dockControls != nil
        let tiles = controller.dockTiles
        return Snapshot(
            tiles: tiles, preparing: controller.dockPreparationActive && hasDock, mopMissing: hasDock && !controller.mopAttached,
            bridgeMissing: hasDock && controller.services != nil && !controller.dockBridgeAvailable, hasDock: hasDock,
            showsSection: !tiles.isEmpty || controller.dockPreparationActive)
    }

    override func rebuild(_ s: Snapshot) {
        guard s.showsSection else { return }
        var blocks: [UIView] = []
        if s.preparing {
            blocks.append(UKVacuumDescription("The dock is washing the mop pads for the current cleaning session. To stop, use Cancel Cleaning Session on the Controls section."))
        }
        for tile in s.tiles {
            blocks.append(UKVacuumActionTile(tile, environment: environment) { [controller] in controller.run(tile.action.kind) })
        }
        if s.mopMissing { blocks.append(.ukInset(UKInlineAlertView("Attach the mop pads before cleaning or drying them at the dock."), horizontal: HassTokens.Spacing.l)) }
        if s.bridgeMissing {
            blocks.append(.ukInset(UKInlineAlertView("Dock cleaning and drying controls will be available after Home Assistant restarts."), horizontal: HassTokens.Spacing.l))
        }
        addArrangedSubview(UKVacuumSection("Dock Controls", content: [ukVStack(blocks, spacing: HassTokens.Spacing.l)]))
    }
}

// MARK: - Info

/// One row of the Info tab.
struct UKVacuumInfoRow: Equatable {
    var title: String
    var symbol: String
    var tint: UIColor
    var value: String
}

/// What the Info tab draws.
struct UKVacuumInfoSnapshot: Equatable {
    var bins: [UKVacuumInfoRow]
    var consumables: [UKVacuumInfoRow]
}

/// Bin state and consumables (`VacuumInfoTab`): rows with the value trailing, orange when it is soon and red when it is due.
@MainActor
final class UKVacuumInfoTab: UKVacuumPanel<UKVacuumInfoSnapshot> {
    typealias Row = UKVacuumInfoRow
    typealias Snapshot = UKVacuumInfoSnapshot

    override init(controller: VacuumController, environment: UKTileEnvironment) {
        super.init(controller: controller, environment: environment)
        spacing = HassTokens.Spacing.xl
        start()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func row(_ consumable: VacuumConfig.Consumable) -> Row {
        let entity = controller.store.entity(consumable.entityId).state
        let visual = VacuumVisual.consumable(consumable, state: entity?.state)
        let value = VacuumFormat.consumable(consumable, state: entity?.state, unit: entity?.attributes["unit_of_measurement"]?.string)
        return Row(title: consumable.title, symbol: UKVacuumStyle.symbol(visual.icon), tint: Self.tint(visual.tone), value: value)
    }

    override func snapshot() -> Snapshot {
        Snapshot(bins: controller.vacuum.consumables.filter { $0.valueKind == .status }.map(row),
                 consumables: controller.vacuum.consumables.filter { $0.valueKind == .duration }.map(row))
    }

    override func rebuild(_ s: Snapshot) {
        for (title, rows) in [("Bin State", s.bins), ("Consumables", s.consumables)] where !rows.isEmpty {
            let views = rows.map { item -> UIView in
                let value = UILabel.uk(.body, monospacedDigit: true, ink: item.tint, alignment: .right)
                value.text = item.value
                let view = UKRowView(.init(item.title, symbol: item.symbol, glyph: item.tint), accessory: value, surface: .sheet)
                view.isAccessibilityElement = true
                view.accessibilityLabel = item.title
                view.accessibilityValue = item.value
                view.accessibilityTraits = .staticText
                return view
            }
            addArrangedSubview(UKVacuumSection(title, content: [UKModuleListView(surface: .sheet, rows: views)]))
        }
    }

    /// Soon is orange and due is red; everything else, OK included, stays neutral.
    static func tint(_ tone: VacuumTone) -> UIColor {
        switch tone {
        case .warning, .danger: UKVacuumStyle.color(tone)
        default: UKDesignInk.secondary
        }
    }
}
#endif
