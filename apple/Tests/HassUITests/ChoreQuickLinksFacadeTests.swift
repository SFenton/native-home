@testable import HassCore
import HassDesign
@testable import HassUI
import HassTestSupport
import Testing

/// The Chores quick links match a page by its id, so a page from the house document keeps its colour and glyph even
/// when another field differs from the demo page.
@MainActor
@Suite(.demoHouse)
struct ChoreQuickLinksFacadeTests {
    @Test func aDocumentPageKeepsItsColourAndGlyph() throws {
        let original = try #require(ChoresConfig.quickLinks.first { $0.resident == .resident1 })
        var page = original.page
        page.emptyTitle = "Changed by the document"
        #expect(page != original.page)
        let link = ChoresConfig.QuickLink(title: "First Tasks", page: page, color: (0, 0, 0), resident: .resident1)
        #expect(ChoreQuickLinks.family(for: link) == ChoreQuickLinks.family(for: original))
        #expect(ChoreQuickLinks.symbol(for: link) == "person.crop.circle.fill")

        var unassigned = ChoresConfig.unassignedChores
        unassigned.emptyTitle = "Changed"
        let tray = ChoresConfig.QuickLink(title: "Unassigned", page: unassigned, color: (0, 0, 0))
        #expect(ChoreQuickLinks.symbol(for: tray) == "tray.circle.fill")
    }
}
