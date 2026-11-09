import HassCore
import HassDesign
import SwiftUI

/// Dispatches a card to its tile (web `RoomSourceCard`). Lanes building device tiles replace their case here.
@MainActor
struct RoomCardView {
    var controller: RoomController
    var card: RoomCard
    /// The page's shared controller when this card is a bathroom fan.
    var fan: BathroomFanController?
    /// The page's beds, when its caller can read service responses.
    var bedroom: BedroomDevices?
    var onOpen: () -> Void

    /// The bed side a card shows, when the page has its controllers.
    static func bed(_ card: RoomCard, in bedroom: BedroomDevices?) -> BedSideController? {
        guard let bedroom, let sheet = card.sheet, let side = MasterBedroom.bed(id: sheet)?.side else { return nil }
        return bedroom.bed(side)
    }

    /// A bed side's tile face (``ThermostatTileFace/bedSide(action:level:isAvailable:)``).
    static func face(_ bed: BedSideController) -> RoomTileFace {
        let face = ThermostatTileFace.bedSide(action: bed.action, level: bed.displayedTarget, isAvailable: bed.sideAvailable)
        return RoomTileFace(family: face.family, isActive: face.isActive && !bed.scope.readOnly)
    }
    /// The Security garage door tile for a garage card, keeping the card's title and icon.
    static func garageTile(_ card: RoomCard) -> SecurityConfig.Tile? {
        guard var tile = SecurityConfig.controlTiles.first(where: { $0.kind == .garageDoor && $0.entityId == card.entityId })
        else { return nil }
        tile.title = card.title
        return tile
    }
}
