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

    /// The state line: On / Off, "Didn't Respond" while failed, "Unavailable"; a guest says who stays
    /// (`HouseholdActionTile.subtitle`).
    static func subtitle(_ display: HouseholdSettingsController.ToggleDisplay, face: Face) -> String? {
        if face == .guest {
            return HouseholdTileActions.guestStateText(isOn: display.isOn, isUnavailable: display.isUnavailable, isFailed: display.isFailed)
        }
        return display.subtitle
    }

    /// A switch the document declares as an action tile, *text, disc* (rollout lane S, audit items 18 to 20, 22 to 24;
    /// `HouseholdActionTile`): the body and the disc both send the explicit `turn_on` / `turn_off` the controller picks from what the
    /// tile shows. The tile acts from the control's kind (a switch is a power disc), never from a house-configuration list, so a
    /// switch the lists do not name still acts. The tile face draws the authored `symbol`; the disc draws the action glyph (`power`,
    /// or the lock for the Auto-Lock role, `isAutoLock`).
    static func toggleModel(entityId: String, title: String, symbol: String, identifier: String, isAutoLock: Bool = false,
                            display: HouseholdSettingsController.ToggleDisplay, face: Face = .settings) -> UKGlassTileModel {
        let specs = HouseholdTileActions.specs(entityId: entityId, isAutoLock: isAutoLock, isOn: display.isOn, isUnavailable: display.isUnavailable)
        let isGuest = face == .guest
        return toggleModel(title: title, subtitle: subtitle(display, face: face),
                           symbol: symbol, tint: isGuest ? nil : UKHouseholdTint.settingsSwitch,
                           family: isGuest ? .occupancy : nil, display: display,
                           behavior: TileBehavior(HouseholdTileActions.classification(of: .toggle), primary: PowerToggleActions.actionId),
                           specs: specs, identifier: identifier,
                           stateCandidates: isGuest ? ["Guests staying", "No guests", "Unavailable", "Didn't Respond"]
                               : HouseholdTileActions.stateTextCandidates)
    }

    /// Builds the same face from authored values and a caller-supplied action; it reads no house configuration.
    static func toggleModel(title: String, subtitle: String?, symbol: String, tint: UIColor?, family: ColorFamily?,
                            display: HouseholdSettingsController.ToggleDisplay, behavior: TileBehavior,
                            specs: [TileActionSpec], identifier: String, stateCandidates: [String]) -> UKGlassTileModel {
        var model = UKGlassTileModel(
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            tint: tint,
            family: family,
            isActive: display.isOn,
            isUnavailable: display.isUnavailable,
            isError: display.isFailed,
            behavior: behavior,
            actions: specs.items,
            identifier: identifier,
            // The controller's onFailure speaks the sentence.
            announcesFailure: false)
        model.stateCandidates = stateCandidates
        return model
    }

    /// Car Doors as an action tile with the lock disc (`VehicleDoorsTile`, the lock style, tracked): Unlock while locked, Lock while
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
                symbol: specs.first?.symbol ?? "lock.fill", tint: UKHouseholdTint.settingsControl, isActive: !unavailable && value != "locked",
                isUnavailable: unavailable, isError: value == "jammed" || failed,
                behavior: TileBehavior(HouseholdTileActions.classification(of: tile), primary: StateStyle.lock.actionId), actions: specs.items,
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

#endif
