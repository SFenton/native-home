import Foundation

/// Classifies every configured tile (rooms, security, media, guest toggles) from what its config carries, using
/// ``TileClassification``. The mapping from entity or control to ``TileActionKind`` is the only knowledge added here.
public enum TileActionCatalog {
    /// One configured tile and what it is.
    public struct Entry: Equatable, Sendable, Identifiable {
        /// `rooms.living-room.Fan`, `security.cover.garage_left_door`, ...
        public var id: String
        public var hasDestination: Bool
        public var kind: TileActionKind
        public var classification: TileClassification
    }

    // MARK: - Mapping

    /// The provider kind of a room card: its control first, then its action, then its kind.
    public static func kind(of card: RoomCard) -> TileActionKind {
        switch card.control {
        case .bathroomFan?: return .bathroomFan
        case .garageDoor?: return .garageDoor
        case nil: break
        }
        switch card.action {
        case .flip?: return .power
        case .remote?:
            if card.kind == .power { return .power }
            // A Music Room source chooses (audit items 5 and 7).
            if card.entityId == MediaRemotes.MusicRoom.activeMediaSourceEntityId { return .sourceSelect }
            // Nintendo Switch and Cinema Streamer: a power disc tracked through a script (audit items 6 and 8).
            if ScriptPowerActions.all.contains(where: { $0.activeEntityId == card.entityId }) { return .scriptPower }
            return .command
        case nil: break
        }
        if card.kind == .vacuum { return .vacuum }
        // A purifier and a humidifier open their sheet and carry a power disc (audit items 1 and 2); a bed side opens its sheet and
        // carries a power disc with a confirmed off (item 4).
        if powerEntityId(of: card) != nil { return .power }
        if bedSide(of: card) != nil { return .bedSidePower }
        if card.kind == .media, let sheet = card.sheet, MediaRemotes.config(id: sheet) != nil { return .mediaRemote }
        return .none
    }

    /// The entity a purifier or humidifier card's power disc switches: the purifier's fan entity, the humidifier's power
    /// switch. Nil for every other card (an air quality chip reads a sensor and has no disc).
    public static func powerEntityId(of card: RoomCard) -> String? {
        if card.kind == .humidifier, card.sheet != nil { return card.entityId }
        guard card.kind == .air, card.sheet == "air-purifier", card.entityId.hasPrefix("select."), let sensor = card.modalEntityId else { return nil }
        guard let fan = AirPurifierConfig.forPM25Entity(sensor)?.fanEntityId, !fan.isEmpty else { return nil }
        return fan
    }

    /// The bed side a room card shows, when the card opens a bed sheet.
    public static func bedSide(of card: RoomCard) -> BedSideConfig? {
        card.sheet.flatMap(MasterBedroom.bed(id:))
    }

    /// The provider kind of a Security tile.
    public static func kind(of tile: SecurityConfig.Tile) -> TileActionKind {
        switch tile.kind {
        case .alarm: .none
        case .lock, .vehicle: .lock
        case .garageDoor: .garageDoor
        }
    }

    // MARK: - Classification

    /// A room card: a sheet is its destination.
    public static func classification(of card: RoomCard) -> TileClassification {
        .classify(hasDestination: card.sheet != nil, actions: kind(of: card).restingActionCount)
    }

    /// A Security tile: the alarm opens its sheet (its actions follow with the owner's go), locks and doors act.
    public static func classification(of tile: SecurityConfig.Tile) -> TileClassification {
        .classify(hasDestination: tile.kind == .alarm, actions: kind(of: tile).restingActionCount)
    }

    /// The provider kind of a Media page device tile (a Music Room source chooses; Switch and SHIELD are tracked power discs).
    public static func kind(of card: MediaPageConfig.Card) -> TileActionKind {
        if card.remote != nil { return .mediaRemote }
        guard card.device.action != nil else { return .none }
        if card.device.entityId == MediaRemotes.MusicRoom.activeMediaSourceEntityId { return .sourceSelect }
        if ScriptPowerActions.all.contains(where: { $0.activeEntityId == card.device.entityId }) { return .scriptPower }
        return .command
    }

    /// A Media page tile: a remote opens (and carries Power), a source runs its command, anything else shows state.
    public static func classification(of card: MediaPageConfig.Card) -> TileClassification {
        .classify(hasDestination: card.remote != nil, actions: kind(of: card).restingActionCount)
    }

    /// A device tile on a remote's Devices tab.
    public static func classification(of device: MediaRemoteDevice) -> TileClassification {
        .classify(hasDestination: false, actions: device.action == nil ? 0 : 1)
    }

    /// A guest-stay toggle on the Settings pages: one power action, no destination.
    public static func classification(of toggle: HomeConfig.GuestToggle) -> TileClassification {
        .classify(hasDestination: false, actions: TileActionKind.power.restingActionCount)
    }

    /// A light or switch tile (audit items 9, 10 and 11): a power disc on every one. Tapping the body flips power, or (a Custom Lights tile)
    /// opens the light's sheet, which makes it a navigation tile that keeps the disc beside its chevron.
    public static func classification(ofLightOpensDetails opensDetails: Bool) -> TileClassification {
        .classify(hasDestination: opensDetails, actions: TileActionKind.power.restingActionCount)
    }

    /// A Home overview Lights room card (audit item 12): opens the room's lights and carries the room power disc.
    public static func classification(ofLightsRoom group: RoomGroup) -> TileClassification {
        .classify(hasDestination: true, actions: TileActionKind.roomLightsPower.restingActionCount)
    }

    /// The provider kind of a Quick Links tile (audit item 17): Security System carries Arm Home / Disarm; the rest only open.
    public static func kind(of link: QuickLink) -> TileActionKind {
        link.id == "security-system" ? .alarmMode : .none
    }

    /// A Quick Links tile: every one opens a page or a detail (and carries the chevron), the alarm with its disc.
    public static func classification(of link: QuickLink) -> TileClassification {
        .classify(hasDestination: true, actions: kind(of: link).restingActionCount)
    }

    // MARK: - Whole configs

    /// Every tile in `RoomsConfig` (page sections; the overview chips are not tiles), `SecurityConfig`, the Media page,
    /// the media remotes, Quick Links, the Lights overview's room cards, the Custom Lights page and the guest toggles.
    public static var allConfiguredTiles: [Entry] {
        var entries: [Entry] = []
        for page in RoomsConfig.pages {
            for section in page.sections {
                for card in section.cards {
                    entries.append(Entry(id: "rooms.\(page.id).\(section.title).\(card.id)", hasDestination: card.sheet != nil,
                                         kind: kind(of: card), classification: classification(of: card)))
                }
            }
        }
        for tile in SecurityConfig.controlTiles + SecurityConfig.vehicleTiles {
            entries.append(Entry(id: "security.\(tile.entityId)", hasDestination: tile.kind == .alarm, kind: kind(of: tile),
                                 classification: classification(of: tile)))
        }
        for card in MediaPageConfig.cards {
            entries.append(Entry(id: "media.\(card.id)", hasDestination: card.remote != nil, kind: kind(of: card),
                                 classification: classification(of: card)))
        }
        for remote in MediaRemotes.all {
            for device in remote.devices {
                entries.append(Entry(id: "remote.\(remote.id).\(device.title)", hasDestination: false,
                                     kind: device.action == nil ? .none : .command, classification: classification(of: device)))
            }
        }
        for link in QuickLinks.items {
            entries.append(Entry(id: "quicklinks.\(link.id)", hasDestination: true, kind: kind(of: link), classification: classification(of: link)))
        }
        for group in RoomGroups.allLights {
            entries.append(Entry(id: "lights.overview.\(group.room)", hasDestination: true, kind: .roomLightsPower,
                                 classification: classification(ofLightsRoom: group)))
        }
        for light in CustomLightsConfig.lights {
            entries.append(Entry(id: "customLights.\(light.entityId)", hasDestination: true, kind: .power,
                                 classification: classification(ofLightOpensDetails: true)))
        }
        for toggle in HomeConfig.guestToggles {
            entries.append(Entry(id: "guest.\(toggle.entityId)", hasDestination: false, kind: .power, classification: classification(of: toggle)))
        }
        // The household Settings pages (audit items 18 to 25): Guest Controls reuses the guest toggles above.
        let settingsTiles = HouseholdSettingsConfig.Admin.securityTiles + HouseholdSettingsConfig.Admin.relayTiles
            + HouseholdSettingsConfig.Admin.showSpecificTiles + HouseholdSettingsConfig.Admin.autoResetTiles
            + [HouseholdSettingsConfig.SpecialDeviceModes.highAqiTile] + HouseholdSettingsConfig.MachE.tiles
        for tile in settingsTiles {
            entries.append(Entry(id: "settings.\(tile.entityId)", hasDestination: false, kind: HouseholdTileActions.kind(of: tile),
                                 classification: HouseholdTileActions.classification(of: tile)))
        }
        entries.append(Entry(id: "settings.\(HouseholdSettingsConfig.Admin.powerRecoveryAutomation)", hasDestination: false,
                             kind: .momentaryCommand, classification: HouseholdTileActions.powerRecoveryClassification))
        return entries
    }
}
