import Foundation
@testable import HassCore
import HassTestSupport
import Testing

@Suite(.demoHouse)
struct TileClassificationTests {
    @Test func classifyMatrix() {
        #expect(TileClassification.classify(hasDestination: false, actions: 0) == .state)
        #expect(TileClassification.classify(hasDestination: false, actions: 1) == .action(1))
        #expect(TileClassification.classify(hasDestination: false, actions: 3) == .action(3))
        #expect(TileClassification.classify(hasDestination: true, actions: 0) == .navigation(actionCount: 0))
        #expect(TileClassification.classify(hasDestination: true, actions: 2) == .navigation(actionCount: 2))
        #expect(TileClassification.classify(hasDestination: true, actions: -1) == .navigation(actionCount: 0))
    }

    @Test func specsOverloadCountsSpecs() {
        let specs = LockActions(entityId: "lock.demo_a").actions(for: nil)
        #expect(TileClassification.classify(hasDestination: false, actions: specs) == .action(1))
        #expect(TileClassification.classify(hasDestination: true, actions: specs) == .navigation(actionCount: 1))
    }

    @Test func buttonsAndInertAreExclusive() {
        for value in [TileClassification.state, .action(1), .navigation(actionCount: 0), .navigation(actionCount: 2)] {
            #expect(value.isButton != value.isInert)
        }
        #expect(TileClassification.action(2).actionCount == 2 && TileClassification.navigation(actionCount: 3).actionCount == 3)
        #expect(TileClassification.state.actionCount == 0)
    }

    // MARK: Configs

    @Test func everyConfiguredTileClassifiesAndAgreesWithItsEntry() {
        let entries = TileActionCatalog.allConfiguredTiles
        #expect(entries.count > 50)
        #expect(Set(entries.map(\.id)).count == entries.count, "entry ids are unique")
        for entry in entries {
            let expected = TileClassification.classify(hasDestination: entry.hasDestination, actions: entry.kind.restingActionCount)
            #expect(entry.classification == expected, "\(entry.id)")
            // No tile is both inert and a button, and an inert tile has neither a destination nor an action.
            #expect(entry.classification.isInert != entry.classification.isButton, "\(entry.id)")
            if entry.classification.isInert { #expect(!entry.hasDestination && entry.kind == .none, "\(entry.id)") }
            if case .action = entry.classification { #expect(!entry.hasDestination, "\(entry.id)") }
            if case .navigation = entry.classification { #expect(entry.hasDestination, "\(entry.id)") }
        }
    }

    @Test func roomCardsAgreeWithTheirInteraction() {
        for page in RoomsConfig.pages {
            for card in page.sections.flatMap(\.cards) {
                let result = TileActionCatalog.classification(of: card)
                // A card that does something classifies as a button; the only card with no sheet or action that still acts
                // is the garage door, whose control draws its own tile.
                if card.hasInteraction || card.control != nil {
                    #expect(result.isButton, "\(page.id) \(card.title)")
                } else {
                    #expect(result.isInert, "\(page.id) \(card.title)")
                }
                if card.sheet != nil { #expect(result == .navigation(actionCount: TileActionCatalog.kind(of: card).restingActionCount), "\(page.id) \(card.title)") }
            }
        }
    }

    @Test(.demoHouse) func knownRoomCards() {
        let cards = RoomsConfig.pages.flatMap(\.allCards)
        func classes(_ kind: RoomCardKind) -> [TileClassification] { cards.filter { $0.kind == kind }.map(TileActionCatalog.classification(of:)) }
        #expect(classes(.fan).contains(.navigation(actionCount: 2)))
        #expect(classes(.vent).allSatisfy { $0 == .navigation(actionCount: 0) } && !classes(.vent).isEmpty)
        #expect(classes(.vacuum).contains(.navigation(actionCount: 2)))
        #expect(classes(.media).contains(.navigation(actionCount: 1)))
        #expect(classes(.power).contains(.action(1)))
    }

    @Test func garageCardsAct() {
        let garage = RoomsConfig.page(id: "garage")!.allCards.filter { $0.control == .garageDoor }
        #expect(!garage.isEmpty)
        for card in garage { #expect(TileActionCatalog.classification(of: card) == .action(1)) }
    }

    @Test func securityTiles() {
        for tile in SecurityConfig.controlTiles + SecurityConfig.vehicleTiles {
            let expected: TileClassification = tile.kind == .alarm ? .navigation(actionCount: 0) : .action(1)
            #expect(TileActionCatalog.classification(of: tile) == expected, "\(tile.title)")
        }
    }

    @Test func mediaTiles() {
        for card in MediaPageConfig.cards {
            let result = TileActionCatalog.classification(of: card)
            if card.remote != nil { #expect(result == .navigation(actionCount: 1), "\(card.id)") } else { #expect(result.isButton == (card.device.action != nil), "\(card.id)") }
        }
        for remote in MediaRemotes.all {
            for device in remote.devices { #expect(TileActionCatalog.classification(of: device).isButton == (device.action != nil)) }
        }
    }

    @Test func guestTogglesAct() {
        for toggle in HomeConfig.guestToggles { #expect(TileActionCatalog.classification(of: toggle) == .action(1)) }
    }

    @Test func restingCountsMatchTheProviders() {
        #expect(TileActionKind.lock.restingActionCount == LockActions(entityId: "l").actions(for: nil).count)
        #expect(TileActionKind.garageDoor.restingActionCount == CoverActions(entityId: "c").actions(for: nil).count)
        #expect(TileActionKind.power.restingActionCount == PowerToggleActions.entity("switch.demo_a").actions(for: nil).count)
        #expect(TileActionKind.bathroomFan.restingActionCount == FanRailActions(config: BathroomFanConfig.all[0], lockState: nil).actions(for: nil).count)
        #expect(TileActionKind.vacuum.restingActionCount == VacuumActions(entityId: "v").actions(for: nil).count)
        let off = EntityState(entityId: MediaRemotes.config(id: "living-room-streamer")!.mediaEntityId, state: "off")
        #expect(TileActionKind.mediaRemote.restingActionCount == MediaTransportActions(config: MediaRemotes.config(id: "living-room-streamer")!).actions(for: off).count)
        #expect(TileActionKind.none.restingActionCount == 0)
    }
}
