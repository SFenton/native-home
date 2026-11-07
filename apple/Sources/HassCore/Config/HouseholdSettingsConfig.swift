import Foundation

/// Entities and copy for the household Settings pages: Admin Controls, Special Device Modes, Guest Controls
/// and Mach-E (`.agents/pages/settings/household.md`).
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/portedDashboard.ts` (`ADMIN_*` 206-304,
/// `SETTINGS_PAGE_ITEMS` 306, `GUEST_CONTROL_ITEMS` 391, `CONTROL_PAGES['mach-e']` 718) and copy from
/// `src/i18n/locales/en/pages/{settings,admin,specialDeviceModes,guests}.json`.
public enum HouseholdSettingsConfig {
    // MARK: - Types

    /// One entity tile on a settings page.
    public struct Tile: Sendable, Hashable, Identifiable, Codable {
        /// Visible title.
        public var title: String
        /// The entity the tile shows and, for toggles, switches.
        public var entityId: String
        /// Web MDI icon name, mapped to an SF Symbol by `HassDesign`.
        public var icon: String
        /// Whether the subtitle shows the entity's state (web `showSubtitle`).
        public var showsState: Bool

        public var id: String { entityId }

        /// Creates a tile.
        public init(title: String, entityId: String, icon: String, showsState: Bool = true) {
            self.title = title
            self.entityId = entityId
            self.icon = icon
            self.showsState = showsState
        }
    }

    /// One room in the presence-based lighting grids.
    public struct PresenceRoom: Sendable, Hashable, Identifiable, Codable {
        /// Room name.
        public var title: String
        /// The Presence Based Lighting `…_presence_allowed` switch (`ADMIN_PRESENCE_OVERRIDE_ITEMS`).
        public var presenceEntityId: String
        /// The morning auto re-enable switch (`ADMIN_AUTO_REENABLE_ITEMS`).
        public var autoReenableEntityId: String

        public var id: String { presenceEntityId }
    }

    /// A settings page section: header, description paragraphs and its content.
    public struct SectionCopy: Sendable, Hashable {
        /// Section header.
        public var title: String
        /// Paragraphs, in order.
        public var paragraphs: [String]
    }

    // MARK: - Admin Controls

    /// Admin page copy (`admin.json`).
    public enum Admin {
        /// Page title (web route title "Admin").
        public static let pageTitle = "Admin"

        public static let security = SectionCopy(title: "Security Controls", paragraphs: [
            "Enables automatic locking of the front door. Turn this off temporarily when contractors are over or people are frequently entering and leaving the home.",
        ])
        public static let powerRecovery = SectionCopy(title: "Living Room Power Recovery", paragraphs: [
            "If the living room switch loses power and comes back with the relay off, run this to temporarily couple the top paddle, unlock the relay, turn power back on, relock it, and return the paddle to decoupled mode.",
        ])
        public static let relayControl = SectionCopy(title: "Relay Control Mode", paragraphs: [
            "Couples every smart-bulb wall switch to its own relay, so the paddles keep working even if Home Assistant, Zigbee2MQTT, or the host is down. This turns on automatically while Vacation Mode is active, so house-sitters always have a way to get light.",
            "While this is on, turning lights off at the wall cuts power to those bulbs, so presence-based lighting can't bring them back until the paddle is switched on again.",
        ])
        public static let presenceOverrides = SectionCopy(title: "Presence-Based Light Overrides", paragraphs: [
            "Choose whether each room's presence lighting is Enabled, Disabled, Paused, or Quieted. Paused stays fail-dark until resumed; Quieted rearms after the room clears.",
        ])
        public static let showSpecific = SectionCopy(title: "Show Specific Controls", paragraphs: [
            "Shows the outdoor faucets in our Home Assistant pages. Useful to disable during the winter, when we aren't using them.",
        ])
        public static let autoReset = SectionCopy(title: "Automatic Presence Setting Overrides", paragraphs: [
            "Sometimes, we disable automatic presence-based lighting in rooms that we'd otherwise want to wake up and have that presence-based lighting active.",
            "If a toggle here is enabled, it means that in the morning, before we usually wake up, if the room has been cleared for a sufficient amount of time during the night, we'll re-enable presence-based lighting in that room.",
        ])

        /// Shown under Relay Control Mode while it and Guest Room guest mode are both on (`warnings.relayGuestMode`).
        public static let relayGuestModeWarning = "Guest Room guest mode is active. Turning off Relay Control Mode keeps the Guest Room on direct wall control and Guest Bathroom presence lighting off. Turn off Guest Room in Guest Controls to restore normal behavior."

        /// `ADMIN_SECURITY_CONTROLS`: the server's document. Like every value here.
        public static var securityTiles: [Tile] { HouseConfigSource.active.read { $0.household.securityTiles } ?? [] }

        /// `RELAY_CONTROL_MODE_ENTITY_ID`.
        public static var relayControlEntityId: String { HouseConfigSource.active.read { $0.household.relayControlEntityId } ?? "" }
        /// `ADMIN_RELAY_CONTROL_ITEMS`.
        public static var relayTiles: [Tile] { HouseConfigSource.active.read { $0.household.relayTiles } ?? [] }

        /// `ADMIN_SHOW_SPECIFIC_CONTROLS`.
        public static var showSpecificTiles: [Tile] { HouseConfigSource.active.read { $0.household.showSpecificTiles } ?? [] }

        /// `LIVING_ROOM_POWER_RECOVERY_AUTOMATION` (DashboardViewPage.tsx:444), run with `automation.trigger`.
        public static var powerRecoveryAutomation: String { HouseConfigSource.active.read { $0.household.powerRecoveryAutomation } ?? "" }
        /// The power recovery button's title.
        public static let powerRecoveryTitle = "Attempt to turn power back on"

        /// Opener titles (`AdminHashButton`).
        public static let presenceOpenerTitle = "Open Presence-Based Overrides"
        public static let autoResetOpenerTitle = "Open Presence-Based Auto-Reset Configuration"
        /// Sheet titles. The web's "Presence-Based Overrides Auto-Reset" truncates in an inline bar at AX5,
        /// so the sheet uses a shorter title (HIG: Navigation bars, keep titles short); its opener and the
        /// section above keep the full name.
        public static let presenceSheetTitle = "Presence-Based Overrides"
        public static let autoResetSheetTitle = "Presence Auto-Reset"

        /// The 14 rooms, in the web's order.
        public static var presenceRooms: [PresenceRoom] { HouseConfigSource.active.read { $0.household.presenceRooms } ?? [] }

        /// The auto-reset sheet's toggles (`ADMIN_AUTO_REENABLE_ITEMS`, icon `mdi:autorenew`).
        public static var autoResetTiles: [Tile] {
            presenceRooms.map { Tile(title: $0.title, entityId: $0.autoReenableEntityId, icon: "mdi:autorenew") }
        }
    }

    // MARK: - Special Device Modes

    /// Special Device Modes copy and tiles (`specialDeviceModes.json`, `SPECIAL_DEVICE_MODE_ITEMS`).
    public enum SpecialDeviceModes {
        public static let pageTitle = "Special Device Modes"
        public static let highAqi = SectionCopy(title: "High AQI Mode", paragraphs: [
            "Toggling High AQI Mode sets all air purifiers in the house to their highest setting to ward off smoke and other inhalation hazards.",
        ])
        public static var highAqiTile: Tile { HouseConfigSource.active.read { $0.household.highAqiTile } ?? Tile(title: "", entityId: "", icon: "") }
    }

    // MARK: - Guest Controls

    /// Guest Controls copy (`guests.json`); its tiles are ``HomeConfig/guestToggles``.
    public enum Guests {
        public static let pageTitle = "Guest Controls"
        public static let section = SectionCopy(title: "Guest Controls", paragraphs: [
            "When guests stay over, toggle these controls on based on the rooms they're staying in to disable automations (like automatic vacuuming in the music room) and ensure that rooms are tracked for temperature monitoring and vent control.",
        ])

        /// `GUEST_CONTROL_ITEMS`: the same entities as the Home page's guest section.
        public static var tiles: [Tile] {
            HomeConfig.guestToggles.map { Tile(title: $0.title, entityId: $0.entityId, icon: $0.icon) }
        }
    }

    // MARK: - Mach-E

    /// Mach-E page (`CONTROL_PAGES['mach-e']`): read-only tiles, since the web gives them no action.
    /// Charge Status shows its value too (the web hides it, leaving a tile that says nothing; departure recorded
    /// in `.agents/pages/settings/household.md`).
    public enum MachE {
        public static let pageTitle = "Mach-E"
        public static let sectionTitle = "Charge Status"
        /// The page's tiles: the document's `household.vehicleTiles`.
        public static var tiles: [Tile] { HouseConfigSource.active.read { $0.household.vehicleTiles } ?? [] }
    }

    // MARK: - Every entity

    /// Every toggle entity across the pages, which take optimistic on/off values.
    public static var toggleEntityIds: [String] {
        (Admin.securityTiles + Admin.relayTiles + Admin.showSpecificTiles + Admin.autoResetTiles
            + [SpecialDeviceModes.highAqiTile] + Guests.tiles).map(\.entityId)
    }

    /// Every MDI icon the pages use, so a test can prove each maps to a real SF Symbol.
    public static var icons: Set<String> {
        let tiles = Admin.securityTiles + Admin.relayTiles + Admin.showSpecificTiles + Admin.autoResetTiles
            + [SpecialDeviceModes.highAqiTile] + Guests.tiles + MachE.tiles
        return Set(tiles.map(\.icon) + ["mdi:flash", "mdi:lightbulb-auto"] + PresenceOverrideState.allCases.map(\.icon))
    }
}
