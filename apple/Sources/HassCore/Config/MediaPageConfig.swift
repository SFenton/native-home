import Foundation

/// The Media page (web route `/at-a-glance/media`): every TV and media source in the house, by room.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx` `MediaPage` (lines 2749-2867), its
/// sections `src/constants/portedDashboard.ts` `MEDIA_SECTIONS` (827-842) and the Music Room's source cards
/// `src/constants/roomPages.ts` (352-408). Copy from `src/i18n/locales/en/pages/media.json`.
public enum MediaPageConfig {
    /// One tile on the page.
    public struct Card: Hashable, Sendable, Identifiable, Codable {
        /// Title, entity, icon, action, active states and labels, drawn like a remote's device tile.
        public var device: MediaRemoteDevice
        /// The remote the tile opens (web `hash`), or `nil` when it runs ``MediaRemoteDevice/action``.
        public var remoteId: String?
        /// Takes the whole row (web `span: 'full'`).
        public var isFullWidth: Bool
        /// Icon while off, unavailable or unknown (web `stateIcons`).
        public var offIcon: String?
        /// The section the card sits in, so ids stay unique.
        public var section: String

        public var id: String { "\(section).\(device.title)" }

        /// The remote this tile opens.
        public var remote: MediaRemoteConfig? { remoteId.flatMap(MediaRemotes.config(id:)) }
    }

    /// One room on the page. The first card leads on its own row; the rest share a grid (web `lead-row`).
    public struct Section: Hashable, Sendable, Identifiable, Codable {
        public var title: String
        public var cards: [Card]
        public var id: String { title }

        /// The card on the lead row.
        public var lead: Card? { cards.first }
        /// The cards under the lead.
        public var followUps: [Card] { Array(cards.dropFirst()) }
    }

    /// The page's sections in the document's order.
    public static var sections: [Section] { HouseConfigSource.active.read { $0.media.pageSections } ?? [] }

    /// Every card, in page order.
    public static var cards: [Card] { sections.flatMap(\.cards) }
}
