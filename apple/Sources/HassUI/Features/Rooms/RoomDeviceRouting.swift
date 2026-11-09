import HassCore
import HassDesign
import SwiftUI

// MARK: - Device sheets

/// A device sheet owned by another lane, presented on its own because it carries its own navigation stack
/// (`.agents/patterns/room-device-sheets.md`, `vacuum-sheet.md`). Cards whose device has no sheet here, or that
/// need the app's connection when there is none (the debug gallery), keep ``RoomCardSheet``'s generic tiles.
enum RoomDeviceModal: Identifiable {
    case vacuum(VacuumConfig)
    /// Shares the room tile's controller, so the tile's accessories and the sheet agree (web
    /// `BathroomFanCommandProvider`).
    case bathroomFan(BathroomFanController, powerEntityId: String)
    case airPurifier(AirPurifierConfig)
    case humidifier(HumidifierConfig)
    case grill
    /// The Master Bedroom's wake light (Bedroom lane), on the page's shared ``BedroomDevices``.
    case wakeLight(BedroomDevices, tab: WakeLightSheet.Tab)
    /// One Eight Sleep side, on the page's shared ``BedroomDevices``.
    case bed(BedroomDevices, side: BedSide, tab: BedSideSheet.Tab)

    var id: String {
        switch self {
        case let .vacuum(vacuum): "vacuum.\(vacuum.entityId)"
        case let .bathroomFan(_, powerEntityId): "fan.\(powerEntityId)"
        case let .airPurifier(purifier): "purifier.\(purifier.pm25EntityId)"
        case let .humidifier(humidifier): "humidifier.\(humidifier.powerEntityId)"
        case .grill: "grill"
        case .wakeLight: "wake-light"
        case let .bed(_, side, _): "bed.\(side.rawValue)"
        }
    }

    /// The sheet for a room device, if one is wired.
    /// - Parameters:
    ///   - device: What the card opens.
    ///   - hasConnection: Whether the app's connection is available (the vacuum and humidifier sheets need it).
    ///   - fan: The page's shared fan controller for a power switch.
    ///   - bedroom: The page's wake light and beds, when its caller can read service responses.
    @MainActor
    static func resolve(_ device: RoomDeviceSheet, hasConnection: Bool, fan: (String) -> BathroomFanController?,
                        bedroom: BedroomDevices? = nil) -> RoomDeviceModal? {
        switch device {
        case let .vacuum(entityId):
            guard hasConnection, let vacuum = Vacuums.all.first(where: { $0.entityId == entityId }) else { return nil }
            return .vacuum(vacuum)
        case let .bathroomFan(powerEntityId):
            return fan(powerEntityId).map { .bathroomFan($0, powerEntityId: powerEntityId) }
        case let .airQuality(pm25EntityId):
            return AirPurifierConfig.forPM25Entity(pm25EntityId).map { .airPurifier($0) }
        case let .humidifier(powerEntityId):
            guard hasConnection else { return nil }
            return HumidifierConfig.forPowerEntity(powerEntityId).map { .humidifier($0) }
        case .grill:
            return .grill
        case .wakeLight:
            return bedroom.map { .wakeLight($0, tab: .alarms) }
        case let .bed(sheet, _):
            guard let bedroom, let side = MasterBedroom.bed(id: sheet)?.side else { return nil }
            return .bed(bedroom, side: side, tab: .temperature)
        case .dishwasher:
            // Dishwasher lane: generic tiles until it lands.
            return nil
        }
    }
}
