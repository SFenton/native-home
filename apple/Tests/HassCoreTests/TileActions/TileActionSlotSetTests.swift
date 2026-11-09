import Foundation
@testable import HassCore
import HassTestSupport
import Testing

@Suite(.demoHouse)
struct TileActionSlotSetTests {
    private func playing() -> [TileActionSpec] {
        let config = MediaRemotes.config(id: "living-room-streamer")!
        return MediaTransportActions(config: config).actions(for: EntityState(entityId: config.mediaEntityId, state: "playing"))
    }

    @Test func valueChangesKeepTheSameSet() {
        let config = MediaRemotes.config(id: "living-room-streamer")!
        let paused = MediaTransportActions(config: config).actions(for: EntityState(entityId: config.mediaEntityId, state: "paused"))
        // Different verb, symbol, emphasis and call on play_pause; the same shape.
        #expect(TileActionSlotSet(playing()) == TileActionSlotSet(paused))
        let dimmed = playing().map { $0.with(phase: .unavailable) }
        #expect(TileActionSlotSet(playing()) == TileActionSlotSet(dimmed))
    }

    @Test func lockStatesAreOneSet() {
        let sets = ["locked", "unlocked", "locking", "unlocking", "jammed", "unavailable"].map {
            TileActionSlotSet(LockActions(entityId: "lock.demo_a").actions(for: EntityState(entityId: "lock.demo_a", state: $0)))
        }
        #expect(Set(sets.map(\.ids)).count == 1 && sets.allSatisfy { $0 == sets[0] })
    }

    @Test func garageDoorKeepsOneSetAcrossRoles() {
        let attributes: [String: JSONValue] = ["supported_features": .number(11)]
        let states = ["closed", "opening", "open", "closing"].map {
            TileActionSlotSet(CoverActions(entityId: "cover.demo_a").actions(for: EntityState(entityId: "cover.demo_a", state: $0, attributes: attributes)))
        }
        #expect(states.allSatisfy { $0 == states[0] } && states[0].ids == ["door"])
    }

    @Test func offRemoteToPlayingRemoteChangesShape() {
        let config = MediaRemotes.config(id: "living-room-streamer")!
        let off = MediaTransportActions(config: config).actions(for: EntityState(entityId: config.mediaEntityId, state: "off"))
        #expect(TileActionSlotSet(off) != TileActionSlotSet(playing()))
        #expect(TileActionSlotSet(off).count == 1 && TileActionSlotSet(playing()).count == 3)
    }

    @Test func orderCountAndCustomMatter() {
        let specs = playing()
        #expect(TileActionSlotSet(specs) != TileActionSlotSet(specs.reversed()))
        #expect(TileActionSlotSet(specs) != TileActionSlotSet(Array(specs.dropLast())))
        #expect(TileActionSlotSet(specs, hasCustomControl: true) != TileActionSlotSet(specs))
        var custom = specs
        custom[0].call = nil
        #expect(TileActionSlotSet(custom).hasCustom && !TileActionSlotSet(specs).hasCustom)
        #expect(TileActionSlotSet([]).count == 0)
    }

    @Test func fanAndVacuumSetsAreStable() {
        let on = FanRailActions(config: BathroomFanConfig.all[0], lockState: EntityState(entityId: "x", state: "on")).actions(for: EntityState(entityId: "p", state: "on"))
        let off = FanRailActions(config: BathroomFanConfig.all[0], lockState: nil).actions(for: nil)
        #expect(TileActionSlotSet(on) == TileActionSlotSet(off))
        let vacuums = ["cleaning", "docked", "error", "unavailable"].map { TileActionSlotSet(VacuumActions(entityId: "v").actions(for: EntityState(entityId: "v", state: $0))) }
        #expect(vacuums.allSatisfy { $0 == vacuums[0] })
    }
}
