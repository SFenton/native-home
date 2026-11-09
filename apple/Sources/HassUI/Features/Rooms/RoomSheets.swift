import HassCore
import HassDesign
import SwiftUI

// MARK: - Fallbacks

/// Generic tiles for a device sheet whose lane has not landed: the card's entities, read-only.
struct RoomDeviceFallback {
    var controller: RoomController
    var card: RoomCard

}

extension RoomDeviceFallback {
    /// A tile's title: Home Assistant's friendly name, or the entity's object id in words (`sensor.demo_status`
    /// reads "Demo Status"), never the raw id.
    static func title(friendlyName: String?, entityId: String) -> String {
        if let friendlyName, !friendlyName.isEmpty { return friendlyName }
        let object = entityId.split(separator: ".", maxSplits: 1).last.map(String.init) ?? entityId
        return StateText.titleCase(object, empty: entityId)
    }
}
