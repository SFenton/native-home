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

    @Test func everySwitchIsAPowerActionTileAndTheReadingsStayFlat() {
        for tile in switches {
            #expect(HouseholdTileActions.kind(of: tile) == .power, Comment(rawValue: tile.entityId))
            #expect(HouseholdTileActions.classification(of: tile) == .action(1), Comment(rawValue: tile.entityId))
        }
        for tile in Config.MachE.tiles where tile.entityId != SecurityConfig.vehicleLockEntityId {
            #expect(HouseholdTileActions.kind(of: tile) == .none && HouseholdTileActions.classification(of: tile) == .state, Comment(rawValue: tile.title))
        }
        #expect(switches.count == 1 + 1 + 2 + 14 + 1, "Auto-Lock, Relay, two Show Specific, 14 Auto-Reset rooms, High AQI")
    }

    @Test func machEDoorsActsWithTheLockDiscAndPowerRecoveryIsMomentary() {
        let doors = Config.MachE.tiles.first { $0.title == "Doors" }!
        #expect(HouseholdTileActions.kind(of: doors) == .lock && HouseholdTileActions.classification(of: doors) == .action(1))
        #expect(HouseholdTileActions.doors.entityId == SecurityConfig.vehicleLockEntityId)
        #expect(HouseholdTileActions.powerRecoveryClassification == .action(1))
    }

    @Test func theCatalogListsEverySettingsTileOnce() {
        let entries = TileActionCatalog.allConfiguredTiles.filter { $0.id.hasPrefix("settings.") }
        #expect(entries.count == switches.count + Config.MachE.tiles.count + 1)
        #expect(entries.first { $0.id == "settings.\(Config.Admin.powerRecoveryAutomation)" }?.kind == .momentaryCommand)
        #expect(entries.first { $0.id == "settings.\(SecurityConfig.vehicleLockEntityId)" }?.kind == .lock)
        #expect(entries.filter { $0.kind == .power }.count == switches.count)
    }

    // MARK: Switch specs

    @Test func aSwitchOffersTurnOffWhileOnAndTurnOnWhileOffWithExplicitCalls() {
        let tile = Config.Admin.relayTiles[0]
        let on = HouseholdTileActions.specs(for: tile, isOn: true, isUnavailable: false)[0]
        #expect(on.verb == "Turn Off" && on.isOn == true && on.call?.service == "turn_off" && on.call?.target == tile.entityId)
        let off = HouseholdTileActions.specs(for: tile, isOn: false, isUnavailable: false)[0]
        #expect(off.verb == "Turn On" && off.isOn == false && off.call?.service == "turn_on")
        #expect(on.symbol == "power" && off.symbol == "power" && on.feedback == .optimistic && on.confirmation == nil)
    }

    @Test func anUnavailableSwitchDimsInPlace() {
        let spec = HouseholdTileActions.specs(for: Config.Admin.showSpecificTiles[0], isOn: true, isUnavailable: true)[0]
        #expect(spec.phase == .unavailable && spec.isOn == false)
    }

    @Test func frontDoorAutoLockDrawsTheLockItControls() {
        let tile = Config.Admin.securityTiles[0]
        #expect(tile.entityId == HouseholdTileActions.autoLockEntityId)
        #expect(HouseholdTileActions.specs(for: tile, isOn: true, isUnavailable: false)[0].symbol == "lock.fill")
        #expect(HouseholdTileActions.specs(for: tile, isOn: false, isUnavailable: false)[0].symbol == "lock.open")
        #expect(HouseholdTileActions.specs(for: tile, isOn: true, isUnavailable: true)[0].symbol == "lock.open")
        // Every other switch keeps the power glyph in both states.
        for other in switches where other.entityId != tile.entityId {
            #expect(HouseholdTileActions.symbol(for: other, isOn: true) == "power" && HouseholdTileActions.symbol(for: other, isOn: false) == "power")
        }
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
