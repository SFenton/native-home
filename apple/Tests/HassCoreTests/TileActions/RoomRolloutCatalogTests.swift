import Foundation
@testable import HassCore
import Testing
import HassTestSupport

/// Lane R of the tile rollout: which room and Media page cards the catalog now classifies as navigation tiles with a power disc
/// (purifier, humidifier, beds), selection tiles (Music Room sources) and tracked power tiles (Switch, SHIELD), and the pure state
/// lines those tiles read.
@Suite(.demoHouse)
struct RoomRolloutCatalogTests {
    func cards(where match: (RoomCard) -> Bool) -> [(page: String, card: RoomCard)] {
        RoomsConfig.pages.flatMap { page in page.sections.flatMap(\.cards).filter(match).map { (page.id, $0) } }
    }

    // MARK: Navigation tiles with a power disc

    @Test func everyPurifierCardIsANavigationTileWithAPowerDiscOnItsFan() {
        let purifiers = cards { $0.title == "Air Purifier" }
        #expect(purifiers.count >= 5)
        for (page, card) in purifiers {
            #expect(TileActionCatalog.kind(of: card) == .power, "\(page)")
            #expect(TileActionCatalog.classification(of: card) == .navigation(actionCount: 1), "\(page)")
            let fan = TileActionCatalog.powerEntityId(of: card)
            #expect(fan?.hasPrefix("fan.") == true && fan?.hasSuffix("_purifier") == true, "\(page): \(fan ?? "nil")")
        }
    }

    @Test func theAirQualityChipsAreNotTiles() {
        for page in RoomsConfig.pages {
            for chip in page.overviewCards where chip.kind == .air {
                #expect(TileActionCatalog.powerEntityId(of: chip) == nil, "\(page.id)")
            }
        }
    }

    @Test func theHumidifierIsANavigationTileWithAPowerDiscOnItsSwitch() throws {
        let humidifier = try #require(cards { $0.kind == .humidifier }.first?.card)
        #expect(TileActionCatalog.powerEntityId(of: humidifier) == HumidifierConfig.all[0].powerEntityId)
        #expect(TileActionCatalog.classification(of: humidifier) == .navigation(actionCount: 1))
    }

    @Test func bothBedSidesAreNavigationTilesWithAPowerDisc() {
        let beds = cards { TileActionCatalog.bedSide(of: $0) != nil }
        #expect(beds.count == 2 && beds.allSatisfy { $0.page == "bedroom-1" })
        for (_, card) in beds {
            #expect(TileActionCatalog.kind(of: card) == .bedSidePower)
            #expect(TileActionCatalog.classification(of: card) == .navigation(actionCount: 1))
        }
        let wake = cards { $0.kind == .wakeLight }.first?.card
        #expect(wake.map { TileActionCatalog.bedSide(of: $0) } == .some(nil), "the wake light has no power disc")
    }

    @Test func ventsStayANavigationTileWithNoDisc() {
        let vents = cards { $0.kind == .vent }
        #expect(vents.count > 5)
        for (page, card) in vents {
            #expect(TileActionCatalog.classification(of: card) == .navigation(actionCount: 0), "\(page)")
            #expect(TileActionCatalog.powerEntityId(of: card) == nil)
        }
    }

    // MARK: Sources, Switch and SHIELD

    @Test func theMusicRoomSourcesChooseOnTheRoomPageAndTheMediaPage() {
        let roomSources = cards { $0.entityId == MediaRemotes.MusicRoom.activeMediaSourceEntityId }
        #expect(roomSources.map(\.card.title) == ["Game Console", "Server", "Computer"])
        for (_, card) in roomSources {
            #expect(TileActionCatalog.kind(of: card) == .sourceSelect)
            #expect(TileActionCatalog.classification(of: card) == .action(1))
        }
        let mediaSources = MediaPageConfig.cards.filter { TileActionCatalog.kind(of: $0) == .sourceSelect }
        #expect(mediaSources.map(\.device.title) == ["Game Console", "Server", "Computer", "Game"])
        #expect(Set(mediaSources.map(\.device.title)) == Set(SourceSelectActions.allMusicRoom.map(\.title)))
    }

    @Test func switchAndShieldArePowerActionTilesOnBothPages() {
        let room = cards { TileActionCatalog.kind(of: $0) == .scriptPower }
        #expect(room.map(\.card.title) == ["Handheld Console", "Media STREAMER"])
        for (_, card) in room { #expect(TileActionCatalog.classification(of: card) == .action(1)) }
        let media = MediaPageConfig.cards.filter { TileActionCatalog.kind(of: $0) == .scriptPower }
        #expect(media.map(\.device.title) == ["Handheld Console", "Media STREAMER"])
    }

    @Test func noRoomOrMediaTileIsLeftOnTheUndecidedCommandKind() {
        let leftover = TileActionCatalog.allConfiguredTiles.filter { ($0.id.hasPrefix("rooms.") || $0.id.hasPrefix("media.")) && $0.kind == .command }
        #expect(leftover.isEmpty, "\(leftover.map(\.id))")
    }

    // MARK: State lines

    @Test func aScriptDeviceReadsOnOffAndTurningWhileTheHoldWaits() {
        let provider = ScriptPowerActions.all[0]
        func live(_ state: String?) -> EntityState? { state.map { EntityState(entityId: provider.activeEntityId, state: $0) } }
        #expect(provider.stateText(live: live("on"), phase: .ready) == "On")
        #expect(provider.stateText(live: live("off"), phase: .ready) == "Off")
        #expect(provider.stateText(live: live("off"), phase: .inFlight) == "Turning On…")
        #expect(provider.stateText(live: live("on"), phase: .inFlight) == "Turning Off…")
        #expect(provider.stateText(live: live("unavailable"), phase: .unavailable) == "Unavailable")
        #expect(provider.stateText(live: nil, phase: .unavailable) == "Unavailable")
        #expect(provider.stateTextCandidates.contains("Turning On…") && provider.stateTextCandidates.contains("Turning Off…"))
    }

    @Test func aSourceSaysOnTheTVWhileChosenAndNothingWhileNot() {
        typealias M = MediaRemotes.MusicRoom
        let xbox = SourceSelectActions.musicRoom(.console), fortnite = SourceSelectActions.musicRoom(.launcher)
        #expect(xbox.stateText(for: M.Source.xbox) == "On the TV")
        #expect(xbox.stateText(for: M.Source.fortnite) == "On the TV", "with Fortnite active, Xbox reads chosen too")
        #expect(fortnite.stateText(for: M.Source.fortnite) == "On the TV")
        #expect(fortnite.stateText(for: M.Source.xbox) == nil, "Xbox active does not choose Fortnite")
        #expect(xbox.stateText(for: M.Source.server) == nil && xbox.stateText(for: M.Source.off) == nil)
        #expect(xbox.stateText(for: "unavailable") == "Unavailable" && xbox.stateText(for: nil) == "Unavailable")
        for candidate in ["On the TV", "Unavailable"] { #expect(xbox.stateTextCandidates.contains(candidate)) }
    }
}
