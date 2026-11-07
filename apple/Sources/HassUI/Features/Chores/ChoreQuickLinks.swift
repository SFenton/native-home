import HassCore
import HassDesign
import SwiftUI

/// Quick links to the Chores sub-pages with their open counts (web `ChoresIntro`, 2–3 columns). The grid grows to four
/// on iPad and stops there: four links fill four tracks and a wide Groceries closes the second row.
///
/// Each link is a navigation tile with the chevron in the list's own colour (rollout lane M, audit item 26; owner, 2026-10-27, pick A:
/// the open count moves into the state line, "3 open · 2 overdue", and the numeral is gone; ``ChoresConfig/openSubtitle(_:)``).
/// Groceries still closes the grid across two tracks (mockup n5-chores).
struct ChoreQuickLinks {
    /// Opens a sub-page.
    var open: (ChoresConfig.Page) -> Void


    /// The tile's accessibility identifier, `chores.link.<page>` (the journeys').
    static func identifier(for link: ChoresConfig.QuickLink) -> String { "chores.link.\(link.id)" }

    /// The web's links with Groceries moved last, where it spans the final row (mockup n5-chores).
    static var links: [ChoresConfig.QuickLink] { ChoresConfig.quickLinks.filter { !$0.countsGroceries } + ChoresConfig.quickLinks.filter(\.countsGroceries) }

    /// The link's colour: one family per page, so a link keeps its colour whoever is signed in. A resident's link takes that
    /// resident's family (read from the link, not from a page id tied to a person).
    static func family(for link: ChoresConfig.QuickLink) -> ColorFamily {
        if link.countsGroceries { return .groceries }
        if link.resident == .resident1 { return .choreResident1 }
        if link.resident == .resident2 { return .choreResident2 }
        return link.page.id == ChoresConfig.unassignedChores.id ? .choreUnassigned : .choreHome
    }

    /// The link's glyph: a person for a resident's chores, a tray for Unassigned, a hammer for Home Improvement and
    /// a cart for Groceries (mockup n5-chores).
    static func symbol(for link: ChoresConfig.QuickLink) -> String {
        if link.countsGroceries { return "cart.circle.fill" }
        if link.resident != nil { return "person.crop.circle.fill" }
        if link.page.id == ChoresConfig.unassignedChores.id { return "tray.circle.fill" }
        return "hammer.circle.fill"
    }
}
