import Foundation
import Testing
@testable import HassCore

struct AskableIndexTests {
    @Test func askableRuleKeepsSubjectsAndDropsPlumbing() {
        var states = AskDemoHouse.states
        states.append(AskDemoHouse.state("number.demo_brightness", "50", name: "Demo Brightness"))
        states.append(AskDemoHouse.state("button.demo_restart", "unknown", name: "Demo Restart"))
        let index = AskDemoHouse.index(states: states)
        #expect(index.entry("light.demo_kitchen_light")?.askable == true)
        #expect(index.entry("number.demo_brightness")?.askable != true)
        #expect(index.entry("button.demo_restart")?.askable != true)
    }

    @Test func roomComesFromTheAreaThenTheName() {
        let index = AskDemoHouse.index()
        #expect(index.entry("light.demo_kitchen_light")?.roomKey != nil)
        #expect(index.entry("light.demo_kitchen_light")?.roomKey == index.entry("sensor.demo_kitchen_temperature")?.roomKey)
        #expect(index.entry("light.demo_kitchen_light")?.roomKey != index.entry("light.demo_office_light")?.roomKey)
    }

    @Test func aDeviceInheritsItsAreaWhenTheEntityHasNone() {
        var registry = AskDemoHouse.registry
        registry.append(AskRegistryEntity(entityId: "light.demo_hall", deviceId: "dev1"))
        var states = AskDemoHouse.states
        states.append(AskDemoHouse.state("light.demo_hall", "off", name: "Demo Hall Light"))
        let house = AskHouse(
            name: "Demo Home", states: states, registry: registry, devices: [AskDevice(id: "dev1", areaId: "office")], areas: AskDemoHouse.areas,
            floors: AskDemoHouse.floors, document: AskDemoHouse.document(states), now: AskDemoHouse.now, timeZone: AskDemoHouse.utc
        )
        let index = AskableIndex(house: house)
        #expect(index.entry("light.demo_hall")?.roomKey == index.entry("light.demo_office_light")?.roomKey)
    }

    @Test func disabledAndHiddenRegistryRowsAreNotSubjects() {
        var registry = AskDemoHouse.registry
        registry[0].hiddenBy = "user"
        registry[1].disabledBy = "user"
        let hidden = AskableIndex(
            house: AskHouse(name: "Demo Home", states: AskDemoHouse.states, registry: registry, areas: AskDemoHouse.areas, floors: AskDemoHouse.floors, document: AskDemoHouse.document(AskDemoHouse.states), now: AskDemoHouse.now, timeZone: AskDemoHouse.utc)
        )
        #expect(hidden.entry("light.demo_kitchen_light")?.askable != true)
        #expect(hidden.entry("light.demo_kitchen_counter")?.askable != true)
    }

    @Test func theRegistryFreeFallbackStillFindsSubjects() {
        let index = AskDemoHouse.index(registry: false)
        #expect(index.hadRegistry == false)
        #expect(index.entry("light.demo_kitchen_light")?.askable == true)
        #expect(AskResolver(index: index).resolve("is the kitchen light on").entityIds == ["light.demo_kitchen_light"])
    }

    @Test func aliasesAndConfiguredNamesAreVariants() {
        var registry = AskDemoHouse.registry
        registry[0].aliases = ["the corner light"]
        var configuration = AskConfiguration()
        configuration.entityNames = ["lock.demo_back_door": ["patio lock"]]
        let house = AskHouse(name: "Demo Home", states: AskDemoHouse.states, registry: registry, areas: AskDemoHouse.areas, floors: AskDemoHouse.floors, document: AskDemoHouse.document(AskDemoHouse.states), now: AskDemoHouse.now, timeZone: AskDemoHouse.utc)
        let resolver = AskResolver(index: AskableIndex(house: house, configuration: configuration))
        #expect(resolver.resolve("is the corner light on").entityIds == ["light.demo_kitchen_light"])
        #expect(resolver.resolve("is the patio lock locked").entityIds == ["lock.demo_back_door"])
    }

    @Test func roomNicknamesAreScopes() {
        var configuration = AskConfiguration()
        configuration.roomNicknames = ["Living Room": ["den"]]
        let resolver = AskResolver(index: AskDemoHouse.index(configuration: configuration))
        #expect(resolver.resolve("is the tv playing in the den").entityIds == ["media_player.demo_tv"])
    }

    @Test func refreshingKeepsTheStructureAndTakesNewStates() {
        let index = AskDemoHouse.index()
        var states = AskDemoHouse.states
        states[0] = AskDemoHouse.state("light.demo_kitchen_light", "off", name: "Demo Kitchen Light")
        let next = index.refreshing(states: states, now: AskDemoHouse.now)
        #expect(next.entry("light.demo_kitchen_light")?.state.state == "off")
        #expect(next.rooms.keys == index.rooms.keys)
    }
}
