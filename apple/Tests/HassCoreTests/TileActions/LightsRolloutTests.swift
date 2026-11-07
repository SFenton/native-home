import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Lane L of the tile rollout: the Home overview Lights room power disc (item 12), the catalog's classes for lights, Custom Lights and
/// Quick Links (items 9 to 11 and 17), and the Quick Links Security System disc.
@Suite(.demoHouse)
struct RoomLightsPowerActionsTests {
    let kitchen = RoomGroups.allLights.first { $0.room == "Kitchen" }!
    let gym = RoomGroups.allLights.first { $0.room == "Gym" }!

    func read(on: Set<String> = [], unavailable: Set<String> = [], missing: Bool = false) -> RoomOverview.Read {
        { id in
            if missing { return nil }
            return EntityState(entityId: id, state: unavailable.contains(id) ? "unavailable" : (on.contains(id) ? "on" : "off"))
        }
    }

    @Test func anyLightOnOffersTurnOffAndTurnsTheRoomsGroupLightOff() throws {
        let provider = RoomLightsPowerActions(kitchen)
        let spec = try #require(provider.actions(read: read(on: ["light.demo_kitchen_light_1"])).first)
        #expect(spec.id == "power" && spec.verb == "Turn Off" && spec.symbol == "power" && spec.isOn == true)
        #expect(spec.label == "Turn Off Kitchen lights" && spec.phase == .ready && spec.feedback == .optimistic)
        #expect(spec.call == ServiceCall("light", "turn_off", target: "light.demo_kitchen_item_1"), "the call the room's lights sheet makes for the whole room")
        #expect(spec.confirmation == nil, "a light is never asked about")
    }

    @Test func noLightOnOffersTurnOnAndNeverToggles() throws {
        let spec = try #require(RoomLightsPowerActions(kitchen).actions(read: read()).first)
        #expect(spec.verb == "Turn On" && spec.isOn == false)
        #expect(spec.call == ServiceCall("light", "turn_on", target: "light.demo_kitchen_item_1"))
        for state in [read(), read(on: ["light.demo_kitchen_item_1"])] {
            #expect(RoomLightsPowerActions(kitchen).actions(read: state).first?.call?.service != "toggle")
        }
    }

    @Test func theGroupLightOnAloneReadsOnAsTheCardDoes() {
        let provider = RoomLightsPowerActions(kitchen)
        #expect(provider.isOn(read: read(on: ["light.demo_kitchen_item_1"])) == RoomOverview.isActive(.lights, kitchen, read: read(on: ["light.demo_kitchen_item_1"])))
        #expect(provider.isOn(read: read(on: ["light.demo_kitchen_item_1"])))
    }

    @Test func theOptimisticValuesCoverTheGroupAndEveryLightOnceEach() throws {
        let provider = RoomLightsPowerActions(kitchen)
        #expect(provider.entityIds.first == "light.demo_kitchen_item_1" && Set(provider.entityIds) == Set(["light.demo_kitchen_item_1"] + kitchen.items.map(\.entityId)))
        #expect(provider.entityIds.count == Set(provider.entityIds).count)
        let off = try #require(provider.actions(read: read(on: ["light.demo_kitchen_light_3"])).first)
        #expect(Set(off.optimistic.map(\.entityId)) == Set(provider.entityIds) && off.optimistic.allSatisfy { $0.value == "off" })
        let on = try #require(provider.actions(read: read()).first)
        #expect(on.optimistic.allSatisfy { $0.value == "on" })
    }

    @Test func aSingleLightRoomListsItsLightOnce() {
        let provider = RoomLightsPowerActions(gym)
        #expect(provider.entityIds == ["light.demo_gym_light_item_1"], "the group light and the one light are the same entity")
        #expect(provider.targetEntityId == "light.demo_gym_light_item_1")
    }

    @Test func aRoomWhoseLightsAllStoppedAnsweringDimsInPlace() throws {
        let allGone = Set(kitchen.items.map(\.entityId))
        let dim = try #require(RoomLightsPowerActions(kitchen).actions(read: read(unavailable: allGone)).first)
        #expect(dim.phase == .unavailable && dim.verb == "Turn On")
        let some = try #require(RoomLightsPowerActions(kitchen).actions(read: read(unavailable: ["light.demo_kitchen_light_3"])).first)
        #expect(some.phase == .ready, "one dead bulb does not block the room")
        #expect(try #require(RoomLightsPowerActions(kitchen).actions(read: read(missing: true)).first).phase == .unavailable)
    }

    @Test func aSwitchRoomUsesItsOwnDomain() throws {
        let entryway = try #require(RoomGroups.allLights.first { $0.room == "Entryway" })
        let spec = try #require(RoomLightsPowerActions(entryway).actions(read: read()).first)
        #expect(spec.call?.domain == "switch" && spec.call?.target == "switch.demo_entryway_light_1")
    }

    @Test func theStateLinesItCanShowAreCandidates() {
        for group in RoomGroups.allLights {
            let provider = RoomLightsPowerActions(group)
            for state in [read(), read(on: Set(group.items.map(\.entityId)))] {
                let line = RoomOverview.lightSubtitle(group, read: state)
                #expect(provider.stateTextCandidates.contains(line), "\(group.room): \(line)")
            }
        }
    }

    @Test func everyLightsRoomHasAGroupEntityToTarget() {
        for group in RoomGroups.allLights {
            #expect(group.entityId != nil && RoomLightsPowerActions(group).targetEntityId == group.entityId, Comment(rawValue: group.room))
        }
    }
}

@Suite(.demoHouse)
struct LightsRolloutCatalogTests {
    @Test func aLightIsAnActionTileUntilItOpensSomethingThenANavigationTileWithTheSameDisc() {
        #expect(TileActionCatalog.classification(ofLightOpensDetails: false) == .action(1), "items 9 and 10")
        #expect(TileActionCatalog.classification(ofLightOpensDetails: true) == .navigation(actionCount: 1), "item 11")
    }

    @Test func aLightsRoomCardIsANavigationTileWithTheRoomDisc() {
        for group in RoomGroups.allLights {
            #expect(TileActionCatalog.classification(ofLightsRoom: group) == .navigation(actionCount: 1), Comment(rawValue: group.room))
        }
    }

    @Test func onlySecuritySystemCarriesAnAlarmDiscAndEveryQuickLinkOpensSomething() {
        for link in QuickLinks.items {
            let expected: TileActionKind = link.id == "security-system" ? .alarmMode : .none
            #expect(TileActionCatalog.kind(of: link) == expected, Comment(rawValue: link.id))
            #expect(TileActionCatalog.classification(of: link) == .navigation(actionCount: expected.restingActionCount), Comment(rawValue: link.id))
        }
    }

    @Test func theConfiguredTilesNowIncludeTheLightsAndQuickLinks() {
        let entries = TileActionCatalog.allConfiguredTiles
        #expect(entries.filter { $0.id.hasPrefix("quicklinks.") }.count == QuickLinks.items.count)
        #expect(entries.filter { $0.id.hasPrefix("lights.overview.") }.count == RoomGroups.allLights.count)
        #expect(entries.filter { $0.id.hasPrefix("customLights.") }.count == CustomLightsConfig.lights.count)
        #expect(entries.first { $0.id == "quicklinks.security-system" }?.kind == .alarmMode)
        #expect(entries.filter { $0.id.hasPrefix("customLights.") }.allSatisfy { $0.classification == .navigation(actionCount: 1) })
    }
}

@Suite(.demoHouse)
struct SecuritySystemQuickLinkDiscTests {
    func spec(_ state: String?) -> TileActionSpec {
        AlarmModeActions().actions(for: state.map { EntityState(entityId: QuickLinks.securityEntityId, state: $0) })[0]
    }

    @Test func disarmedOffersArmHomeAndArmedOffersAConfirmedDisarm() {
        #expect(spec("disarmed").verb == "Arm Home" && spec("disarmed").confirmation == nil)
        #expect(spec("disarmed").call?.service == "alarm_arm_home" && spec("disarmed").call?.target == QuickLinks.securityEntityId)
        for armed in ["armed_home", "armed_away", "armed_night", "triggered"] {
            #expect(spec(armed).verb == "Disarm" && spec(armed).confirmation == AlarmModeActions.disarmConfirmation, Comment(rawValue: armed))
            #expect(spec(armed).call?.service == "alarm_disarm", Comment(rawValue: armed))
        }
    }

    @Test func onlyDisarmingIsInFlightAndUnavailableDims() {
        for delay in ["arming", "pending"] { #expect(spec(delay).phase == .ready, Comment(rawValue: delay)) }
        #expect(spec("disarming").phase == .inFlight)
        #expect(spec("arming").verb == "Disarm" && spec("disarming").verb == "Arm Home")
        #expect(spec(nil).phase == .unavailable && spec("unavailable").phase == .unavailable)
    }
}
