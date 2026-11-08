#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Tiles

/// The household tiles (`HouseholdToggleTile`, `GlassStateTile`, the admin openers), each bound to the controller through a
/// bag: a change to one entity redraws that tile only.
@MainActor
enum UKHouseholdTiles {
    /// How the tile reads: the Settings green with On / Off, or the Home page's guest-stay words in the occupancy family.
    enum Face { case settings, guest }

    /// The state line: On / Off (when the tile shows state), "Didn't Respond" while failed, "Unavailable"; a guest says who stays
    /// (`HouseholdActionTile.subtitle`).
    static func subtitle(_ tile: HouseholdSettingsConfig.Tile, _ display: HouseholdSettingsController.ToggleDisplay, face: Face) -> String? {
        if face == .guest {
            return HouseholdTileActions.guestStateText(isOn: display.isOn, isUnavailable: display.isUnavailable, isFailed: display.isFailed)
        }
        return tile.showsState || display.isFailed ? display.subtitle : nil
    }

    /// A switch as an action tile, *text, disc* (rollout lane S, audit items 18 to 20, 22 to 24; `HouseholdActionTile`): the body and the
    /// disc both send the explicit `turn_on` / `turn_off` the controller picks from what the tile shows. A tile with a `confirmation` asks
    /// before flipping (High AQI Mode changes every purifier): the alert for the state the flip would produce is the disc's own
    /// confirmation, so the body and the disc ask the same question (`<tile-id>.confirm` / `.cancel`).
    static func toggleModel(_ tile: HouseholdSettingsConfig.Tile, _ display: HouseholdSettingsController.ToggleDisplay, face: Face = .settings,
                            confirmation: ((Bool) -> AlertCopy.Spec)? = nil) -> UKGlassTileModel {
        var specs = HouseholdTileActions.specs(for: tile, isOn: display.isOn, isUnavailable: display.isUnavailable)
        if let confirmation { specs = specs.map { $0.with(confirmation: TileActionSpec.Confirmation(confirmation(!display.isOn))) } }
        let isGuest = face == .guest
        var model = UKGlassTileModel(
            title: tile.title,
            subtitle: subtitle(tile, display, face: face),
            symbol: specs.first?.symbol ?? "power",
            tint: isGuest ? nil : UKHouseholdTint.settingsSwitch,
            family: isGuest ? .occupancy : nil,
            isActive: display.isOn,
            isUnavailable: display.isUnavailable,
            isError: display.isFailed,
            behavior: TileBehavior(HouseholdTileActions.classification(of: tile), primary: PowerToggleActions.actionId),
            actions: specs.items,
            identifier: (isGuest ? "guest.tile." : "household.tile.") + tile.entityId,
            // The controller's onFailure speaks the sentence.
            announcesFailure: false)
        model.stateCandidates = isGuest ? ["Guests staying", "No guests", "Unavailable", "Didn't Respond"] : HouseholdTileActions.stateTextCandidates
        return model
    }

    /// An on/off tile for one entity.
    static func toggle(_ tile: HouseholdSettingsConfig.Tile, controller: HouseholdSettingsController, environment: UKTileEnvironment,
                       bag: UKObservationBag, face: Face = .settings, confirmation: ((Bool) -> AlertCopy.Spec)? = nil) -> UKGlassTileView {
        func model() -> UKGlassTileModel { toggleModel(tile, controller.toggle(tile.entityId), face: face, confirmation: confirmation) }
        let view = UKGlassTileView(model: model(), environment: environment)
        UKRoomsBind.tile(view, bag: bag, environment: environment, action: {}, perform: { _ in
            controller.flip(tile.entityId, title: tile.title)
        }, model: model)
        return view
    }

    /// Car Doors as an action tile with the lock disc (`VehicleDoorsTile`, `LockActions`, tracked): Unlock while locked, Lock while
    /// unlocked or jammed. A tap shows the lock's own transitional state ("Unlocking") until it reports, and a rejected call shows
    /// "Didn't Respond" (the Security page's lock tile rules, on the Settings blue).
    static func doors(_ tile: HouseholdSettingsConfig.Tile, controller: HouseholdSettingsController, environment: UKTileEnvironment,
                      bag: UKObservationBag) -> UKGlassTileView {
        var actions: OptimisticActions?
        func shown() -> EntityState? { controller.store.entity(tile.entityId).state.map { $0.showing(actions?.shown(tile.entityId)) } }
        func model() -> UKGlassTileModel {
            let shown = shown()
            let value = shown?.state
            let unavailable = shown?.isUnavailable ?? true
            let failed = actions?.isFailed(tile.entityId) ?? false
            let specs = HouseholdTileActions.doors.actions(for: shown)
            var model = UKGlassTileModel(
                title: tile.title, subtitle: unavailable ? "Unavailable" : failed ? "Didn't Respond" : SecurityConfig.stateText(value),
                symbol: specs.first?.symbol ?? "lock.fill", tint: UKHouseholdTint.settingsControl, isActive: LockActions.isFilled(value),
                isUnavailable: unavailable, isError: value == "jammed" || failed,
                behavior: TileBehavior(HouseholdTileActions.classification(of: tile), primary: LockActions.actionId), actions: specs.items,
                identifier: "household.tile.\(tile.entityId)")
            model.stateCandidates = HouseholdTileActions.doors.stateTextCandidates
            return model
        }
        let view = UKGlassTileView(model: model(), environment: environment)
        UKRoomsBind.tile(view, bag: bag, environment: environment, action: {}, perform: { id in
            guard let spec = HouseholdTileActions.doors.actions(for: shown()).first(where: { $0.id == id }), let call = spec.call else { return }
            // Runs the lock call; the lock's own "locking" / "unlocking" shows until any live change.
            let run = actions ?? OptimisticActions(store: controller.store, rules: [tile.entityId: .liveChange], caller: controller.caller)
            actions = run
            run.perform(call, showing: [OptimisticIntent(tile.entityId, value: call.service == "lock" ? "locking" : "unlocking")])
        }, model: model)
        return view
    }

    /// A read-only entity tile (web `EntityActionCard` with no action): not a button, never dimmed. It speaks On or Off when the
    /// entity shows no state text, and draws the word when Differentiate Without Color is on.
    static func readOnly(_ tile: HouseholdSettingsConfig.Tile, controller: HouseholdSettingsController, environment: UKTileEnvironment,
                         bag: UKObservationBag) -> UKGlassTileView {
        func model() -> UKGlassTileModel {
            let display = controller.readOnly(tile)
            let spoken = GlassStateTile.spokenValue(subtitle: display.subtitle, isActive: display.isActive, isUnavailable: display.isUnavailable)
            return UKGlassTileModel(
                title: tile.title,
                subtitle: display.subtitle ?? (UIAccessibility.shouldDifferentiateWithoutColor ? spoken : nil),
                symbol: SymbolMap.symbol(for: tile.icon),
                tint: UKHouseholdTint.settingsControl,
                isActive: display.isActive,
                isUnavailable: display.isUnavailable,
                kind: .state,
                identifier: "household.tile.\(tile.entityId)",
                spokenValue: spoken)
        }
        let view = UKGlassTileView(model: model(), environment: environment)
        bag.observe { [weak view] in
            view?.configure(model(), environment: environment)
            view?.superview?.setNeedsLayout()
        }
        return view
    }

    /// A wide tile that opens a sheet (web `ModalOpenerRow`).
    static func opener(title: String, symbol: String, identifier: String, environment: UKTileEnvironment, open: @escaping () -> Void) -> UKGlassTileView {
        UKGlassTileView(
            model: UKGlassTileModel(title: title, symbol: SymbolMap.symbol(for: symbol), tint: UKHouseholdTint.settingsSwitch,
                                    isActive: true, kind: .navigate, identifier: identifier),
            environment: environment, action: open)
    }

    /// A grid of tiles that narrows with Dynamic Type (`HouseholdTileGrid`).
    static func grid(minWidth: CGFloat = DynamicGridMetrics.tileMinWidth, maxColumns: Int = DynamicGridMetrics.maxTileColumns,
                     _ tiles: [UIView]) -> UKFlexGridView {
        let grid = UKFlexGridView(minWidth: minWidth, maxColumns: maxColumns)
        grid.setItems(tiles)
        return grid
    }
}

// MARK: - Page

/// A household Settings topic (`HouseholdSettingsPageView`): Admin Controls, Special Device Modes, Guest Controls or Car,
/// one scrolling column of titled sections, at most 840 pt wide.
@MainActor
final class UKHouseholdSettingsViewController: UKHouseholdColumnPage {
    let page: HouseholdSettingsPage
    let controller: HouseholdSettingsController
    private typealias Admin = HouseholdSettingsConfig.Admin

    init(page: HouseholdSettingsPage, controller: HouseholdSettingsController, context: UKContext, accessoryBar: UIView? = nil) {
        self.page = page
        self.controller = controller
        super.init(context: context, title: page.pageTitle, accessoryBar: accessoryBar)
    }

    /// The page on the context's store and caller (the connection when signed in, a gallery's recorder), or a placeholder
    /// when the context has no way to call services.
    static func make(page: HouseholdSettingsPage, context: UKContext, accessoryBar: UIView? = nil) -> UIViewController {
        guard let caller = context.caller ?? context.connection else { return UKPlaceholderViewController(title: page.rowTitle) }
        let controller = HouseholdSettingsController(store: context.store, caller: caller)
        // A failed tap reverts after two seconds; say why, since the tile alone just flips back.
        controller.onFailure = { Announcer.announce($0) }
        return UKHouseholdSettingsViewController(page: page, controller: controller, context: context, accessoryBar: accessoryBar)
    }

    private var environment: UKTileEnvironment { UKTileEnvironment(context: context) }

    override func viewDidLoad() {
        super.viewDidLoad()
        container.scrollView.accessibilityIdentifier = "household.\(page.rawValue)"
        switch page {
        case .admin: buildAdmin()
        case .specialDeviceModes: buildSpecialDeviceModes()
        case .guests: buildGuests()
        case .vehicle: buildVehicle()
        }
    }

    private func toggles(_ tiles: [HouseholdSettingsConfig.Tile], face: UKHouseholdTiles.Face = .settings,
                         confirmation: ((Bool) -> AlertCopy.Spec)? = nil) -> [UIView] {
        tiles.map { UKHouseholdTiles.toggle($0, controller: controller, environment: environment, bag: bag, face: face, confirmation: confirmation) }
    }

    private func section(_ copy: HouseholdSettingsConfig.SectionCopy, _ content: UIView) {
        section(title: copy.title, paragraphs: copy.paragraphs, content)
    }

    private func section(title: String, paragraphs: [String], _ content: UIView) {
        column.addArrangedSubview(UKSectionBlock.settings(title: title, paragraphs: paragraphs, content: content))
    }

    // MARK: Admin

    private func buildAdmin() {
        section(Admin.security, UKHouseholdTiles.grid(toggles(Admin.securityTiles)))

        let power = UKGlassTileView(model: powerModel(), environment: environment)
        UKRoomsBind.tile(power, bag: bag, environment: environment, action: {}, perform: { [controller] _ in controller.triggerPowerRecovery() },
                         model: { [weak self] in self?.powerModel() ?? UKGlassTileModel(title: "", symbol: "bolt.fill", isActive: true) })
        section(Admin.powerRecovery, UKHouseholdTiles.grid([power]))

        let warning = UKInlineAlertView(Admin.relayGuestModeWarning)
        warning.accessibilityIdentifier = "admin.relayWarning"
        bag.observe { [weak warning, controller] in warning?.isHidden = !controller.showsRelayGuestModeWarning }
        let relayStack = UIStackView.ukColumn([UKHouseholdTiles.grid(toggles(Admin.relayTiles)), warning],
                                              spacing: HassTokens.Spacing.m)
        section(Admin.relayControl, relayStack)

        let presence = UKHouseholdTiles.opener(title: Admin.presenceOpenerTitle, symbol: "mdi:lightbulb-auto", identifier: "admin.open.presenceOverrides",
                                               environment: environment) { [weak self] in self?.presentPresenceOverrides() }
        section(Admin.presenceOverrides, UKHouseholdTiles.grid([presence]))

        section(Admin.showSpecific, UKHouseholdTiles.grid(toggles(Admin.showSpecificTiles)))

        let autoReset = UKHouseholdTiles.opener(title: Admin.autoResetOpenerTitle, symbol: "mdi:autorenew", identifier: "admin.open.autoReset",
                                                environment: environment) { [weak self] in self?.presentAutoReset() }
        section(Admin.autoReset, UKHouseholdTiles.grid([autoReset]))
    }

    /// "Attempt to turn power back on" as a momentary action tile (audit item 21; `CommandActions.powerRecovery`): the `bolt.fill` disc and the
    /// body both run the automation; a rejected call keeps the red "Didn't Respond" face.
    private func powerModel() -> UKGlassTileModel {
        let specs = CommandActions.powerRecovery.actions(for: controller.store.entity(Admin.powerRecoveryAutomation).state)
        let unavailable = specs.first?.phase == .unavailable
        let failed = controller.powerRecoveryFailed && !unavailable
        var model = UKGlassTileModel(
            title: Admin.powerRecoveryTitle, subtitle: unavailable ? "Unavailable" : failed ? "Didn't Respond" : nil,
            symbol: specs.first?.symbol ?? "bolt.fill", tint: UKHouseholdTint.settingsSwitch, isActive: !unavailable,
            isUnavailable: unavailable, isError: failed,
            behavior: TileBehavior(HouseholdTileActions.powerRecoveryClassification, primary: CommandActions.powerRecovery.actionId),
            actions: specs.items, identifier: "admin.powerRecovery", announcesFailure: false)
        model.stateCandidates = CommandActions.powerRecovery.stateTextCandidates
        return model
    }

    // MARK: Other topics

    private func buildSpecialDeviceModes() {
        let config = HouseholdSettingsConfig.SpecialDeviceModes.self
        let tile = UKHouseholdTiles.toggle(config.highAqiTile, controller: controller, environment: environment, bag: bag,
                                           confirmation: { AlertCopy.highAqiMode(turningOn: $0) })
        section(config.highAqi, UKHouseholdTiles.grid([tile]))
    }

    private func buildGuests() {
        let config = HouseholdSettingsConfig.Guests.self
        // Web: two columns, up to three, cells at most 320 px; the app keeps growing (four or more on iPad).
        section(config.section, UKHouseholdTiles.grid(toggles(config.tiles, face: .guest)))
    }

    private func buildVehicle() {
        let config = HouseholdSettingsConfig.Vehicle.self
        // Doors is the one action tile (owner, 2026-10-27, item 25: the Security page's lock tile, same entity, same lock service).
        let tiles = config.tiles.map { tile in
            HouseholdTileActions.kind(of: tile) == .lock
                ? UKHouseholdTiles.doors(tile, controller: controller, environment: environment, bag: bag)
                : UKHouseholdTiles.readOnly(tile, controller: controller, environment: environment, bag: bag)
        }
        section(title: config.sectionTitle, paragraphs: [], UKHouseholdTiles.grid(tiles))
    }

    // MARK: Sheets

    /// The room grid; a room pushes its mode list inside the sheet (web `PresenceOverridesSheet`).
    private func presentPresenceOverrides() {
        let sheetEnvironment = { var environment = self.environment; environment.surface = .sheet; return environment }()
        let sheetBag = UKObservationBag()
        let tiles = Admin.presenceRooms.map { room in
            presenceRoomTile(room, environment: sheetEnvironment, bag: sheetBag) { [weak self] in
                guard let modal = self?.presentedViewController as? UKHassModalController, let self else { return }
                modal.push(self.presenceDetail(for: room, modal: modal))
            }
        }
        let grid = UKHouseholdTiles.grid(tiles)
        // The page sheet is centred and can cross the unfolded Duo's hinge: use the wider side of it.
        let root = UKHouseholdSheetContentController(
            content: UKHingeClearingView(content: UKHouseholdPaddedView(grid, insets: .ukAll(HassTokens.Spacing.l))), bag: sheetBag)
        let modal = UKHouseholdSheets.modal(root: root, title: Admin.presenceSheetTitle, closeIdentifier: "household.sheet.done",
                                            width: .page, height: .full, fitKey: "household.presence")
        modal.present(from: self)
    }

    private func presenceRoomTile(_ room: HouseholdSettingsConfig.PresenceRoom, environment: UKTileEnvironment, bag: UKObservationBag,
                                  open: @escaping () -> Void) -> UKGlassTileView {
        func model() -> UKGlassTileModel {
            let mode = controller.presence(room.presenceEntityId)
            // Unavailable rooms stay openable (full contrast); the detail explains and disables the choices.
            return UKGlassTileModel(title: room.title, subtitle: mode.summary, symbol: SymbolMap.symbol(for: "mdi:lightbulb-auto"),
                                    tint: UIColor(mode.tintToken), isActive: mode != .unavailable, kind: .navigate,
                                    identifier: "presence.room.\(room.presenceEntityId)")
        }
        let view = UKGlassTileView(model: model(), environment: environment, action: open)
        bag.observe { [weak view] in
            view?.configure(model(), environment: environment)
            view?.superview?.setNeedsLayout()
        }
        return view
    }

    /// A room's four modes as a single-choice list (`PresenceOverrideDetail`): one column on phones, two where there is room.
    private func presenceDetail(for room: HouseholdSettingsConfig.PresenceRoom, modal: UKHassModalController) -> UIViewController {
        let rows = PresenceOverrideState.choices.map { mode -> UKSelectableOptionRow in
            let row = UKSelectableOptionRow(title: mode.label, detail: mode.detail, symbol: SymbolMap.symbol(for: mode.icon),
                                            tint: UIColor(mode.tintToken), isSelected: false)
            row.accessibilityIdentifier = "presence.option.\(mode.rawValue)"
            row.onTap = { [controller] in controller.setPresence(room.presenceEntityId, to: mode) }
            return row
        }
        // Scales with the rows' text, so accessibility sizes keep one column.
        let grid = UKFlexGridView(minWidth: 300, maxColumns: 2, scaleStyle: .body, fill: .none)
        grid.setItems(rows)
        let failure = UKInlineAlertView("Couldn't change \(room.title). Check the connection.", severity: .error)
        failure.accessibilityIdentifier = "presence.failure"
        let unavailable = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
        unavailable.text = PresenceOverrideState.unavailable.detail
        let side = UIEdgeInsets(top: 0, left: HassTokens.Spacing.l, bottom: 0, right: HassTokens.Spacing.l)
        let content = UIStackView.ukColumn([
            UKHingeClearingView(content: UKHouseholdPaddedView(grid, insets: .ukAll(HassTokens.Spacing.l))),
            UKHouseholdPaddedView(failure, insets: side),
            UKHouseholdPaddedView(unavailable, insets: side),
        ], spacing: 0)
        let page = UKHouseholdSheetContentController(content: content)
        // Just the room: the bar also holds Back and Done, and "<Room> Presence Lighting" clipped at large text sizes.
        page.title = room.title
        page.navigationItem.largeTitleDisplayMode = .never
        page.navigationItem.rightBarButtonItem = UKSheetItems.close(identifier: "household.sheet.done") { [weak modal] in modal?.close() }
        page.view.accessibilityIdentifier = "presence.detail"
        var wasFailed = false
        page.bag.observe { [controller] in
            let shown = controller.presence(room.presenceEntityId)
            let failed = controller.presenceFailed(room.presenceEntityId)
            for (mode, row) in zip(PresenceOverrideState.choices, rows) {
                row.isSelectedChoice = shown == mode
                row.isDisabled = shown == .unavailable
            }
            failure.isHidden = !failed
            unavailable.isHidden = shown != .unavailable
            // Main announces the refusal (HouseholdSettingsController.onFailure); this adds the error haptic.
            if failed, !wasFailed { UKTapFeedback.failure() }
            wasFailed = failed
            grid.setNeedsLayout()
        }
        return page
    }

    /// The morning auto re-enable toggles, one per room (web `AutoResetSheet`).
    private func presentAutoReset() {
        var sheetEnvironment = environment
        sheetEnvironment.surface = .sheet
        let sheetBag = UKObservationBag()
        let tiles = Admin.autoResetTiles.map {
            UKHouseholdTiles.toggle($0, controller: controller, environment: sheetEnvironment, bag: sheetBag)
        }
        let grid = UKHouseholdTiles.grid(tiles)
        let root = UKHouseholdSheetContentController(
            content: UKHingeClearingView(content: UKHouseholdPaddedView(grid, insets: .ukAll(HassTokens.Spacing.l))), bag: sheetBag)
        let modal = UKHouseholdSheets.modal(root: root, title: Admin.autoResetSheetTitle, closeIdentifier: "household.sheet.done",
                                            width: .page, height: .fitted, fitKey: "household.autoReset")
        modal.present(from: self)
    }
}
#endif
