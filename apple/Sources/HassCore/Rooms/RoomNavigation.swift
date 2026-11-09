import Foundation

// MARK: - Room grid

/// One tile in the room navigation grid (web `RoomNavigationConfig`).
public struct RoomNavigationItem: Hashable, Sendable, Identifiable, Codable {
    public var title: String
    /// The room page's web path.
    public var path: String
    /// Web MDI icon.
    public var icon: String
    public var color: RoomColor
    /// The key the room-access increment script counts under.
    public var accessKey: String
    /// The counter that ranks the grid.
    public var accessCounterEntityId: String

    public var id: String { path }
}

/// The Rooms grid in Quick Links, ranked by how often each room is opened.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/atAGlance.ts:324` (`AREA_ITEMS`),
/// `src/components/hass/RoomNavigationGrid.tsx`, `roomAccessRanking.ts`.
public enum RoomNavigation {
    /// The script that counts a room visit (`ROOM_ACCESS_INCREMENT_SCRIPT_ENTITY_ID`).
    public static var accessIncrementScript: String {
        HouseConfigSource.active.read { $0.rooms.grid.accessIncrementScript } ?? ""
    }

    /// Rooms in configured order: the server's document.
    public static var items: [RoomNavigationItem] { HouseConfigSource.active.read { $0.rooms.grid.items } ?? [] }

    /// The room's position in the document's room list: the index ``RoomPalette`` colours it by. Nil for a path that is not a room.
    public static func paletteIndex(forPath path: String) -> Int? { items.firstIndex { $0.path == path } }

    /// The grid item for a room path.
    public static func item(for path: String) -> RoomNavigationItem? { items.first { $0.path == path } }

    /// A counter's visit count: a non-negative whole-number state ("3" or "3.0", like JavaScript's `Number`), else 0
    /// (web `roomAccessCount`).
    public static func accessCount(_ state: String?) -> Int {
        guard let text = state?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let value = Double(text), value >= 0, value <= 9_007_199_254_740_991, value.rounded() == value else { return 0 }
        return Int(value)
    }

    /// Rooms most-visited first; ties keep configured order (web `rankRoomsByAccess`).
    /// - Parameter counterState: Reads a counter entity's state.
    public static func ranked(counterState: (String) -> String?) -> [RoomNavigationItem] {
        items.enumerated()
            .map { (index: $0.offset, count: accessCount(counterState($0.element.accessCounterEntityId)), item: $0.element) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.index < $1.index }
            .map(\.item)
    }

    /// The call that counts a visit when a room is opened from the grid (web `RoomNavigationGrid.handleNavigate`).
    public static func accessIncrementCall(for item: RoomNavigationItem) -> ServiceCall {
        ServiceCall("script", "turn_on", target: accessIncrementScript,
                    data: ["variables": .object(["room": .string(item.accessKey)])])
    }
}

// MARK: - Quick Links

/// One Quick Links tile (web `QuickAccessConfig`).
public struct QuickLink: Hashable, Sendable, Identifiable, Codable {
    /// What the tile does.
    public enum Action: Hashable, Sendable, Codable {
        /// Opens a page inside the Quick Links sheet.
        case detail(Detail)
        /// Navigates to a web route path.
        case navigate(String)
    }

    /// In-sheet pages (web `QuickAccessModalPage`).
    public enum Detail: String, Hashable, Sendable, Codable {
        case rooms
        case securitySystem = "security-system"
    }

    /// How the subtitle is computed (web `status`).
    public enum Status: Hashable, Sendable, Codable {
        /// The entity's compact state.
        case entityState
        /// The pantry summary (Food lane).
        case allFood
    }

    public var id: String
    public var title: String
    public var icon: String
    public var tone: RoomTone
    public var action: Action
    public var entityId: String?
    public var status: Status?
    /// Shown only while this entity is `on`.
    public var visibilityEntityId: String?
    /// A fixed background wash (Food).
    public var backgroundColor: RoomColor?
}

/// The Quick Links sheet's tiles, in web order.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/atAGlance.ts:220-279` (`QUICK_ACCESS_ITEMS`) and
/// `src/components/shell/GlobalQuickLinksAction.tsx`.
public enum QuickLinks {
    /// The sheet's title (`shell.json` `quickLinks.title`).
    public static let title = "Quick Links"
    /// The alarm panel the Security System tile reflects.
    public static var securityEntityId: String { SecurityConfig.alarmEntityId }

    /// The tiles: the server's document (none without one).
    public static var items: [QuickLink] { HouseConfigSource.active.read { $0.rooms.quickLinks } ?? [] }

    /// `FOOD_CARD_BACKGROUND_COLOR` (`everShelfFood.ts:10`).
    public static let foodBackground = RoomColor(155, 110, 64, opacity: 0.72)

    // MARK: Subtitles

    /// EverShelf counters (`everShelfFood.ts:11-21`).
    /// Computed, never `static let`: each follows the food section of the house document, which can change after launch.
    public static var totalItemsEntityId: String { FoodConfig.totalItemsEntityId }
    public static var expiringSoonEntityId: String { FoodConfig.expiringSoonEntityId }
    public static var foodSpaceEntityIds: [String] { FoodConfig.spaces.map(\.entityId) }

    /// "12 Items • 2 Expiring Soon" (web `allFoodSubtitle`): the total counter, else the sum of the spaces.
    public static func allFoodSubtitle(state: (String) -> String?) -> String {
        func count(_ id: String) -> Int { state(id).flatMap(Double.init).map { Int($0) } ?? 0 }
        let total = count(totalItemsEntityId)
        let items = total != 0 ? total : foodSpaceEntityIds.map(count).reduce(0, +)
        let expiring = count(expiringSoonEntityId)
        return "\(items) \(items == 1 ? "Item" : "Items") • \(expiring) Expiring Soon"
    }

    /// The Security System tile's look for an alarm state (web `securityState.ts`).
    public static func securityAppearance(_ state: String?) -> (icon: String, color: RoomColor) {
        switch state {
        case "armed_away": ("mdi:shield", RoomColor(229, 57, 53))
        case "armed_home": ("mdi:shield-home", RoomColor(30, 136, 229))
        case "armed_night": ("mdi:shield-moon", RoomColor(142, 36, 170))
        case "disarmed": ("mdi:shield-off", RoomColor(67, 160, 71))
        case "triggered": ("mdi:shield-alert", RoomColor(229, 57, 53))
        default: ("mdi:shield-outline", RoomColor(84, 110, 122))
        }
    }

    /// Tiles shown for the current states: those without a visibility entity, or whose entity is `on`.
    public static func visible(state: (String) -> String?) -> [QuickLink] {
        items.filter { item in item.visibilityEntityId.map { state($0) == "on" } ?? true }
    }
}
