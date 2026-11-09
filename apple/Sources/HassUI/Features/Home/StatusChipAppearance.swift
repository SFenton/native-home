import HassCore
import HassDesign
import SwiftUI

/// What a status chip draws, decided from live entities (pattern: `.agents/patterns/status-rail.md`, "Chip colours").
///
/// Pure, so every colour rule is tested without a view: the Home rail, Security's chips and the room rails all resolve
/// through here.
struct StatusChipAppearance: Equatable {
    /// The SF Symbol. Occupancy draws one `person` symbol that the chip fills while someone is detected.
    var symbol: String
    /// The family the chip draws in when it has no computed ``tint``.
    var family: ColorFamily?
    /// Whether the chip draws filled (in its family colour or its tint), rather than neutral.
    var isFilled: Bool
    /// A computed look that wins over ``family``: the temperature colour, the AQI colour, or the contact state.
    var tint: ChipTint?

    // MARK: - Symbols

    /// The occupancy chip's glyph: an outline person while clear, filled once someone is detected
    /// (owner, 2026-10-16; the chip fills the symbol while it draws filled).
    static let occupancySymbol = "person"
    /// A contact chip's glyphs.
    static let doorClosedSymbol = "door.left.hand.closed"
    static let doorOpenSymbol = "door.left.hand.open"
    /// The alert glyph on an open door while the system is armed.
    static let alertSymbol = "exclamationmark.triangle"

    // MARK: - Contact

    /// The tint for a contact chip state; nil while unavailable (the chip draws neutral).
    static func tint(for contact: ContactChipState) -> ChipTint? {
        switch contact {
        case .unavailable: nil
        case .allClosed: .contactClosed
        case .openHome: .contactOpenHome
        case .openAway: .contactOpenAway
        case .openArmed: .contactOpenArmed
        }
    }

    /// The glyph for a contact chip state.
    static func symbol(for contact: ContactChipState, fallback: String) -> String {
        switch contact {
        case .unavailable: fallback
        case .allClosed: doorClosedSymbol
        case .openHome, .openAway: doorOpenSymbol
        case .openArmed: alertSymbol
        }
    }

    /// A contact chip: filled in the colour of what the house is doing, or neutral while unavailable.
    static func contact(_ state: ContactChipState, fallbackSymbol: String) -> StatusChipAppearance {
        let tint = tint(for: state)
        return StatusChipAppearance(symbol: symbol(for: state, fallback: fallbackSymbol), family: .contact,
                                    isFilled: tint != nil, tint: tint)
    }

    // MARK: - Web colours

    /// The Climate chip's tint: the web's temperature colour, with the yellow thermometer where it reads.
    static func climate(_ color: RoomColor?) -> ChipTint? {
        color.map { ChipTint.fromWeb($0.rgb, preferredGlyph: ColorFamily.climate.spec.glyph) }
    }

    /// The Air Quality chip's tint: the AQI colour on fill and glyph.
    static func air(_ color: RoomColor) -> ChipTint {
        ChipTint.fromWeb(color.rgb)
    }

    // MARK: - Home

    /// A Home or Security chip.
    /// - Parameters:
    ///   - chip: The chip's config.
    ///   - read: Looks up an entity's current state.
    static func home(_ chip: HomeConfig.StatusChip, read: EntityLookup) -> StatusChipAppearance {
        let symbol = SymbolMap.symbol(for: chip.icon)
        let entity = read(chip.entityId)
        switch chip.tone {
        case .light:
            return StatusChipAppearance(symbol: symbol, family: .lights, isFilled: entity?.isActive ?? false)
        case .security:
            let family = ColorFamily.security(alarmState: entity?.state)
            return StatusChipAppearance(symbol: symbol, family: family, isFilled: family != nil)
        case .climate:
            let color = ChipWebColor.climate(colorText: chip.colorEntityId.flatMap { read($0)?.state }, rangeText: entity?.state)
            let tint = climate(color)
            return StatusChipAppearance(symbol: symbol, family: .climate, isFilled: true, tint: tint)
        case .presence:
            return StatusChipAppearance(symbol: occupancySymbol, family: .occupancy, isFilled: RoomFormat.isOccupied(entity))
        case .contact:
            let state = ContactChipState.current(isOpen: RoomOverview.openContactCount(read: read) > 0, read: read)
            return contact(state, fallbackSymbol: symbol)
        case .air:
            let color = ChipWebColor.airQuality(colorText: chip.colorEntityId.flatMap { read($0)?.state })
            return StatusChipAppearance(symbol: symbol, family: .air, isFilled: true, tint: air(color))
        }
    }

    // MARK: - Rooms

    /// A room rail chip.
    /// - Parameters:
    ///   - card: The overview card.
    ///   - chip: Its display, resolved by the room controller.
    static func room(_ card: RoomCard, chip: RoomChipDisplay) -> StatusChipAppearance {
        let symbol = SymbolMap.symbol(for: chip.icon)
        let family = card.kind.tone.family
        switch card.kind {
        case .occupancy:
            return StatusChipAppearance(symbol: occupancySymbol, family: family, isFilled: chip.isActive)
        case .contact:
            guard let state = chip.contact else { break }
            var appearance = contact(state, fallbackSymbol: symbol)
            appearance.family = family
            return appearance
        case .climate:
            if let color = chip.webColor {
                return StatusChipAppearance(symbol: symbol, family: family, isFilled: true, tint: climate(color))
            }
            return StatusChipAppearance(symbol: symbol, family: family, isFilled: true)
        case .air:
            return StatusChipAppearance(symbol: symbol, family: family, isFilled: true, tint: chip.webColor.map(air))
        default: break
        }
        return StatusChipAppearance(symbol: symbol, family: family, isFilled: isFilled(card.kind.tone, isActive: chip.isActive))
    }

    /// Whether a room chip of another kind draws filled: Climate and Air Quality always, the rest while active.
    static func isFilled(_ tone: RoomTone, isActive: Bool) -> Bool {
        switch tone {
        case .climate, .air: true
        default: isActive
        }
    }
}
