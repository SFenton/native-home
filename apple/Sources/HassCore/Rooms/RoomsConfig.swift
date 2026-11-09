import Foundation

/// The config-driven room pages: the server's document defines every page, card and sheet.
///
/// The pages once ported from `ha-sfenton-react-dash@9ac2a46:src/constants/roomPages.ts:156` (`ROOM_PAGE_CONFIGS`) now live
/// in the document, so the app compiles in no room, entity or title.
public enum RoomsConfig {
    /// Every room page in the document's order; none without a document.
    public static var pages: [RoomPage] { HouseConfigSource.active.read { $0.rooms.pages } ?? [] }

    /// The page for a web route path (`living-room`), if it is a room.
    public static func page(id: String) -> RoomPage? { pages.first { $0.id == id } }

    // MARK: - Shared ids

    /// The Master Bedroom wake light's sheet and titles, from the document.
    public enum WakeLight {
        public static var sheet: String { HouseConfigSource.active.read { $0.rooms.shared.wakeLightPage.sheet } ?? "" }
        public static var title: String { HouseConfigSource.active.read { $0.rooms.shared.wakeLightPage.title } ?? "" }
        public static var sectionTitle: String { HouseConfigSource.active.read { $0.rooms.shared.wakeLightPage.sectionTitle } ?? "" }
    }

    /// The dishwasher's program select, which marks the dishwasher card (web `isDishwasherSourceCard`).
    public static var dishwasherProgramEntityId: String { HouseConfigSource.active.read { $0.rooms.shared.dishwasherProgramEntityId } ?? "" }
}

// MARK: - Kitchen groceries

public extension RoomsConfig {
    /// The Kitchen page's Groceries section (web `KitchenGroceriesSection`, `DashboardViewPage.tsx:1823`).
    enum Groceries {
        /// The grocery to-do list (`TODO_PAGES.groceries.lists[0]`, `portedDashboard.ts:458`).
        public static var listEntityId: String { ChoresConfig.groceryEntityId }
        public static let listTitle = "Grocery List"
        /// The grocery tile's wash.
        public static let listBackground = RoomColor(155, 67, 72, opacity: 0.72)

        /// "3 items", or "No groceries listed" (web `groceryCountSubtitle`).
        public static func subtitle(count state: String?) -> String {
            let count = state.flatMap(Double.init).map { Int($0) } ?? 0
            guard count > 0 else { return "No groceries listed" }
            return "\(count) \(count == 1 ? "item" : "items")"
        }
    }
}
