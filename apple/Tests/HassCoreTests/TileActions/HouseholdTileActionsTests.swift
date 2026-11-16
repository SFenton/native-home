import Foundation
@testable import HassCore
import Testing
import HassTestSupport

/// Rollout lane S: the household Settings tiles as action tiles (audit items 18 to 25).
@Suite(.demoHouse)
struct HouseholdTileActionsTests {
    typealias Config = HouseholdSettingsConfig

    private var switches: [Config.Tile] {
        Config.Admin.securityTiles + Config.Admin.relayTiles + Config.Admin.showSpecificTiles + Config.Admin.autoResetTiles
            + [Config.SpecialDeviceModes.highAqiTile]
    }

    // MARK: Mapping

    @Test func aSwitchIsAPowerActionTileFromItsControlKindAndTheReadingsStayFlat() {
        #expect(HouseholdTileActions.kind(of: .toggle) == .power)
        #expect(HouseholdTileActions.classification(of: .toggle) == .action(1))
        #expect(HouseholdTileActions.kind(of: .readOnly) == .none && HouseholdTileActions.classification(of: .readOnly) == .state)
        #expect(HouseholdTileActions.kind(of: .presence) == .none && HouseholdTileActions.classification(of: .presence) == .state)
        #expect(HouseholdTileActions.kind(of: .powerRecovery) == .momentaryCommand
                && HouseholdTileActions.classification(of: .powerRecovery) == HouseholdTileActions.powerRecoveryClassification)
        for tile in Config.Vehicle.tiles where tile.entityId != SecurityConfig.vehicleLockEntityId {
            #expect(HouseholdTileActions.kind(of: tile) == .none && HouseholdTileActions.classification(of: tile) == .state, Comment(rawValue: tile.title))
        }
        #expect(switches.count == 1 + 1 + 2 + 14 + 1, "Auto-Lock, Relay, two Show Specific, 14 Auto-Reset rooms, High AQI")
    }

    @Test func aToggleTheHouseListsDoNotNameIsStillAPowerSwitch() {
        // Synthetic entity and the lists empty: the control kind decides, so nothing here reads a house list.
        var house = DemoHouse.config
        house.household.securityTiles = []
        house.household.relayTiles = []
        house.household.showSpecificTiles = []
        house.household.presenceRooms = []
        let source = HouseConfigSource()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(HouseholdSettingsConfig.Admin.securityTiles.isEmpty && HouseholdSettingsConfig.Admin.relayTiles.isEmpty)
            let specs = HouseholdTileActions.specs(entityId: "switch.demo_unlisted", isOn: false, isUnavailable: false)
            #expect(specs.count == 1 && specs[0].symbol == "power" && specs[0].call?.service == "turn_on")
            #expect(HouseholdTileActions.classification(of: .toggle) == .action(1))
        }
    }

    @Test func vehicleDoorsActsWithTheLockDiscAndPowerRecoveryIsMomentary() {
        let doors = Config.Vehicle.tiles.first { $0.title == "Doors" }!
        #expect(HouseholdTileActions.kind(of: doors) == .lock && HouseholdTileActions.classification(of: doors) == .action(1))
        #expect(HouseholdTileActions.doors.entityId == SecurityConfig.vehicleLockEntityId)
        #expect(HouseholdTileActions.powerRecoveryClassification == .action(1))
    }

    @Test func theCatalogListsEverySettingsTileOnce() {
        let entries = TileActionCatalog.allConfiguredTiles.filter { $0.id.hasPrefix("settings.") }
        #expect(entries.count == switches.count + Config.Vehicle.tiles.count + 1)
        #expect(entries.first { $0.id == "settings.\(Config.Admin.powerRecoveryAutomation)" }?.kind == .momentaryCommand)
        #expect(entries.first { $0.id == "settings.\(SecurityConfig.vehicleLockEntityId)" }?.kind == .lock)
        #expect(entries.filter { $0.kind == .power }.count == switches.count)
    }

    // MARK: Switch specs

    @Test func aSwitchOffersTurnOffWhileOnAndTurnOnWhileOffWithExplicitCalls() {
        let tile = Config.Admin.relayTiles[0]
        let on = HouseholdTileActions.specs(entityId: tile.entityId, isOn: true, isUnavailable: false)[0]
        #expect(on.verb == "Turn Off" && on.isOn == true && on.call?.service == "turn_off" && on.call?.target == tile.entityId)
        let off = HouseholdTileActions.specs(entityId: tile.entityId, isOn: false, isUnavailable: false)[0]
        #expect(off.verb == "Turn On" && off.isOn == false && off.call?.service == "turn_on")
        #expect(on.symbol == "power" && off.symbol == "power" && on.feedback == .optimistic && on.confirmation == nil)
    }

    @Test func anUnavailableSwitchDimsInPlace() {
        let spec = HouseholdTileActions.specs(entityId: Config.Admin.showSpecificTiles[0].entityId, isOn: true, isUnavailable: true)[0]
        #expect(spec.phase == .unavailable && spec.isOn == false)
    }

    @Test func frontDoorAutoLockDrawsTheLockItControls() {
        let id = "switch.demo_lock"
        func symbol(_ isOn: Bool, _ unavailable: Bool, lock: Bool = true) -> String {
            HouseholdTileActions.specs(entityId: id, isAutoLock: lock, isOn: isOn, isUnavailable: unavailable)[0].symbol
        }
        #expect(symbol(true, false) == "lock.fill")
        #expect(symbol(false, false) == "lock.open")
        #expect(symbol(true, true) == "lock.open")
        for (on, unavailable) in [(true, false), (false, false), (true, true)] { #expect(symbol(on, unavailable, lock: false) == "power") }
    }

    // MARK: Guests, power recovery, Doors

    @Test func guestStateTextUsesTheHomePagesWords() {
        #expect(HouseholdTileActions.guestStateText(isOn: true, isUnavailable: false, isFailed: false) == "Guests staying")
        #expect(HouseholdTileActions.guestStateText(isOn: false, isUnavailable: false, isFailed: false) == "No guests")
        #expect(HouseholdTileActions.guestStateText(isOn: false, isUnavailable: false, isFailed: true) == "Didn't Respond")
        #expect(HouseholdTileActions.guestStateText(isOn: false, isUnavailable: true, isFailed: true) == "Unavailable")
    }

    @Test func powerRecoveryIsOneMomentaryCommandOnTheAutomation() {
        let spec = CommandActions.powerRecovery.actions(for: EntityState(entityId: Config.Admin.powerRecoveryAutomation, state: "on"))[0]
        #expect(spec.feedback == .momentary && spec.symbol == "bolt.fill" && spec.label == "Run power recovery")
        #expect(spec.call?.domain == "automation" && spec.call?.service == "trigger")
        #expect(spec.call?.target == Config.Admin.powerRecoveryAutomation && spec.phase == .ready)
    }

    @Test func theDoorsLockOffersUnlockWhenLockedAndLockWhenUnlockedOrJammed() {
        func spec(_ state: String) -> TileActionSpec {
            HouseholdTileActions.doors.actions(for: EntityState(entityId: SecurityConfig.vehicleLockEntityId, state: state))[0]
        }
        #expect(spec("locked").verb == "Unlock" && spec("locked").call?.service == "unlock")
        #expect(spec("unlocked").verb == "Lock" && spec("unlocked").call?.service == "lock" && spec("unlocked").isOn == true)
        #expect(spec("jammed").verb == "Lock" && spec("jammed").isError)
        #expect(spec("unlocking").phase == .inFlight && spec("unavailable").phase == .unavailable)
    }
}
