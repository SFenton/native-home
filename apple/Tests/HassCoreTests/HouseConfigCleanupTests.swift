import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The values that used to freeze a facade at first use now follow the document, and repeated server data never traps.
/// Every test scopes its own ``HouseConfigSource``.
@MainActor
struct HouseConfigCleanupTests {
    private static func scoped<T>(_ house: HouseConfig?, _ body: () -> T) -> T {
        let source = HouseConfigSource()
        source.set(house)
        return HouseConfigSource.$scoped.withValue(source, operation: body)
    }

    // MARK: - Frozen values

    @Test func theQuickLinkFoodSubtitleCountersFollowTheDocument() {
        var changed = DemoHouse.config
        changed.food.totalItemsEntityId = "sensor.demo_total"
        changed.food.expiringSoonEntityId = "sensor.demo_expiring"
        changed.food.spaces = Array(changed.food.spaces.prefix(1))
        Self.scoped(changed) {
            #expect(QuickLinks.totalItemsEntityId == "sensor.demo_total")
            #expect(QuickLinks.expiringSoonEntityId == "sensor.demo_expiring")
            #expect(QuickLinks.foodSpaceEntityIds == changed.food.spaces.map(\.entityId))
            #expect(QuickLinks.allFoodSubtitle { ["sensor.demo_total": "9", "sensor.demo_expiring": "4"][$0] } == "9 Items • 4 Expiring Soon")
        }
        Self.scoped(nil) {
            #expect(QuickLinks.totalItemsEntityId.isEmpty)
            #expect(QuickLinks.foodSpaceEntityIds.isEmpty)
        }
    }

    @Test func theGroceryListAndTheClimateVacationSwitchFollowTheDocument() {
        var changed = DemoHouse.config
        changed.chores.groceryEntityId = "todo.demo_grocery"
        changed.vacation.modeEntityId = "input_boolean.demo_vacation"
        Self.scoped(changed) {
            #expect(RoomsConfig.Groceries.listEntityId == "todo.demo_grocery")
            #expect(ClimateConfig.vacationModeEntityId == "input_boolean.demo_vacation")
        }
        Self.scoped(nil) {
            #expect(RoomsConfig.Groceries.listEntityId.isEmpty)
            #expect(ClimateConfig.vacationModeEntityId.isEmpty)
        }
    }

    // MARK: - Repeated server data

    @Test func aRepeatedGuestToggleKeepsOneRuleInsteadOfTrapping() {
        var edited = DemoHouse.config
        let toggle = edited.home.guestToggles[0]
        edited.home.guestToggles = [toggle, toggle]
        Self.scoped(edited) {
            #expect(HomeConfig.guestToggleRules.count == 1)
            #expect(HomeConfig.guestToggleRules[toggle.entityId] == .confirmation)
        }
        Self.scoped(nil) {
            #expect(HomeConfig.guestToggleRules.isEmpty)
        }
    }

    @Test func aRepeatedVacuumZoneKeepsItsFirstOrderInsteadOfTrapping() throws {
        let zones = try #require(DemoHouse.config.vacuums.vacuums.first { $0.zones.count > 1 }?.zones)
        let zone = zones[0], other = zones[1]
        let orders = VacuumController.roomOrders(for: [zone, other, zone])
        #expect(orders == [zone.entityId: 1, other.entityId: 2])
        #expect(VacuumController.roomOrders(for: []).isEmpty)
    }
}
