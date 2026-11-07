import HassCore
import HassDesign
import SwiftUI

// MARK: - Colors

extension RoomTone {
    /// The tint for an active tile of this tone (web `GlassTile` tone colors).
    var color: Color {
        switch self {
        case .light: HassTokens.Tint.light
        case .air: HassTokens.Tint.air
        case .climate: HassTokens.Tint.climate
        case .presence: HassTokens.Tint.presence
        case .contact: HassTokens.Tint.contact
        case .vacuum: HassTokens.Tint.vacuum
        case .media: RemoteStyle.media
        case .power: HassTokens.Tint.presence
        case .warning: HassTokens.Tint.warning
        case .neutral: HassTokens.Tint.slate
        }
    }
}

extension RoomTone {
    /// The tone's direction G colour family (`.agents/design/direction-g.md`, Colour families); nil when it has none.
    var family: ColorFamily? {
        switch self {
        case .light: .lights
        case .air: .air
        case .climate: .climate
        case .presence: .occupancy
        case .contact: .contact
        case .vacuum: .cleaning
        case .media: .media
        case .power: .power
        case .warning, .neutral: nil
        }
    }
}

extension RoomColor {
    /// The SwiftUI color, alpha included.
    var color: Color { Color(token) }

    /// The colour as raw sRGB, alpha included.
    var token: HassRGB { HassRGB(red: red, green: green, blue: blue, alpha: opacity) }
}

// MARK: - Colour families

/// A room tile's direction G face: the device's colour family and whether the tile draws on
/// (`.agents/design/direction-g.md`, Colour families). Pure, so the mapping is tested apart from the drawing.
///
/// Off tiles stay dark with the glyph in the family colour; on tiles fill with it, and lights use the warm lit tile.
struct RoomTileFace: Equatable {
    var family: ColorFamily
    var isActive: Bool

    /// Light cards that are really power devices (the towel rack's heat wave): bright yellow, not the lit tile.
    static let powerIcons: Set<String> = ["mdi:heat-wave"]

    /// The family a kind of card belongs to. Thermostats and bed sides change family with their action
    /// (``resolve(_:entity:display:running:)``);
    /// `.neutral` here is only what an unavailable climate card draws.
    static func family(_ kind: RoomCardKind, icon: String) -> ColorFamily {
        switch kind {
        case .light, .wakeLight: powerIcons.contains(icon) ? .power : .lights
        case .air, .fan: .air
        case .vent: .vents
        case .humidifier: .water
        case .climate: .neutral
        case .occupancy: .occupancy
        case .contact: .contact
        case .vacuum, .appliance, .laundry: .cleaning
        case .media: .media
        case .power: .power
        case .grill: .cooking
        }
    }

    /// The face for a card in its current state.
    /// - Parameters:
    ///   - card: The room card.
    ///   - entity: The entity the card shows now (``RoomController/displayEntity(_:)``).
    ///   - display: The controller's display for the card; a toggle keeps its on/off reading so VoiceOver's value
    ///     and the face agree.
    ///   - running: The card shows its running alternate (the dishwasher mid-cycle).
    static func resolve(_ card: RoomCard, entity: EntityState?, display: RoomCardDisplay, running: Bool = false) -> RoomTileFace {
        let family = family(card.kind, icon: card.icon)
        if case .toggle = display.semantics { return RoomTileFace(family: family, isActive: !display.isOff) }
        guard !display.isUnavailable else { return RoomTileFace(family: family, isActive: false) }
        let on = running || RoomFormat.isActive(entity) || entity.map { card.activeStates.contains($0.state) } == true
        switch card.kind {
        case .light, .fan, .media, .power, .grill:
            return RoomTileFace(family: family, isActive: !display.isOff)
        case .air:
            // The purifier card reads its fan mode, set whenever it runs; the air quality card is a reading.
            return RoomTileFace(family: family, isActive: entity?.domain != "sensor" && entity?.state != "off")
        case .climate:
            // Heating and cooling fill with the dial's colours (web `climateActionTone`); idle and off stay dark but
            // keep a family glyph: Heating in heat mode, else Cooling (`ThermostatTileFace`).
            let action = entity.map { $0.attributes["hvac_action"]?.string ?? $0.state } ?? ""
            let face = ThermostatTileFace.thermostat(action: action, mode: entity?.state)
            return RoomTileFace(family: face.family, isActive: face.isActive)
        case .occupancy:
            return RoomTileFace(family: family, isActive: RoomFormat.isOccupied(entity))
        case .vacuum:
            return RoomTileFace(family: family, isActive: on || entity?.state == "cleaning")
        case .wakeLight:
            // Fills while a wake is running (ramping, holding, snoozed), not whenever an alarm is armed.
            return RoomTileFace(family: family, isActive: WakeLight.fillsTile(statusState: entity?.state))
        case .vent, .humidifier, .contact, .appliance, .laundry:
            return RoomTileFace(family: family, isActive: on)
        }
    }
}
