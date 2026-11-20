import Foundation
@testable import HassCore
import Testing

// MARK: - The chrome-hide rule

/// The pure rule behind `pages[].hides` and `navigation.tabsVisibility`: which header items a page drops and when the tab navigator hides.
///
/// Documents are the app's own global-chrome corpus, decoded with the compiler's global-chrome rules on.
@Suite(.timeLimit(.minutes(1)))
struct ServerUIChromeHideTests {
    typealias D = ServerUICompositionDocument

    private static func document(_ name: String) throws -> D {
        let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("GlobalChromeCorpus/reject", isDirectory: true)
        let data = try Data(contentsOf: corpus.appendingPathComponent("pending-global-chrome-\(name).json"))
        return try ServerUIGlobalChrome.$understood.withValue(true) { try ServerUICompositionPublication.decode(data) }.document
    }

    private static func ids(_ groups: [D.ChromeGroup]) -> [String] { groups.flatMap(\.items).map(\.id) }

    // MARK: Items

    @Test("a page that hides no item keeps every group")
    func noHides() throws {
        let document = try Self.document("hides-tabs")
        let groups = document.navigation.chrome.groups
        #expect(ServerUIChromeHide.groups(groups, applying: nil) == groups)
        #expect(ServerUIChromeHide.groups(groups, applying: document.pages[0].hides) == groups, "tabs only drops no item")
    }

    @Test("a hidden item leaves its group and the others stay in order")
    func itemsOnly() throws {
        let document = try Self.document("hides-items")
        let hides = try #require(document.pages[0].hides)
        #expect(hides.tabs == false)
        let groups = ServerUIChromeHide.groups(document.navigation.chrome.groups, applying: hides)
        let dropped = Set(hides.items)
        #expect(!dropped.isEmpty)
        #expect(Self.ids(groups) == Self.ids(document.navigation.chrome.groups).filter { !dropped.contains($0) })
    }

    @Test("tabs and items together drop the item and hide the tabs")
    func both() throws {
        let document = try Self.document("hides-both")
        let hides = try #require(document.pages[0].hides)
        #expect(ServerUIChromeHide.groups(document.navigation.chrome.groups, applying: hides).flatMap(\.items).map(\.id) == ["chrome-menu", "chrome-inspect", "chrome-bell"])
        #expect(ServerUIChromeHide.hidesTabs(hides: hides, visibility: nil, depth: 0))
    }

    @Test("a group left empty is dropped, and the shell menu is never dropped")
    func emptyGroup() throws {
        let document = try Self.document("hides-both")
        let groups = document.navigation.chrome.groups
        let all = D.PageHides(tabs: false, items: Self.ids(groups))
        let kept = ServerUIChromeHide.groups(groups, applying: all)
        #expect(kept.map(\.id) == ["chrome-navigation"])
        #expect(Self.ids(kept) == ["chrome-menu"])
    }

    // MARK: Tabs

    @Test("the tabs hide for the page's own hides at any depth, and a document that says nothing hides none")
    func tabs() {
        let hidesTabs = D.PageHides(tabs: true, items: [])
        let hidesItems = D.PageHides(tabs: false, items: ["x"])
        for depth in [0, 1, 3] {
            #expect(ServerUIChromeHide.hidesTabs(hides: hidesTabs, visibility: nil, depth: depth))
            #expect(!ServerUIChromeHide.hidesTabs(hides: hidesItems, visibility: nil, depth: depth))
            #expect(!ServerUIChromeHide.hidesTabs(hides: nil, visibility: nil, depth: depth))
            #expect(!ServerUIChromeHide.hidesTabs(hides: nil, visibility: .always, depth: depth))
        }
    }

    @Test("root-only hides the tabs on a pushed page and not on a root page")
    func rootOnly() {
        #expect(!ServerUIChromeHide.hidesTabs(hides: nil, visibility: .rootOnly, depth: 0))
        #expect(ServerUIChromeHide.hidesTabs(hides: nil, visibility: .rootOnly, depth: 1))
        #expect(ServerUIChromeHide.hidesTabs(hides: nil, visibility: .rootOnly, depth: 2))
    }

    @Test("root-only with a page that hides tabs, or items only")
    func rootOnlyAndPage() {
        #expect(ServerUIChromeHide.hidesTabs(hides: D.PageHides(tabs: true, items: []), visibility: .rootOnly, depth: 0), "the page hides them at the root too")
        #expect(!ServerUIChromeHide.hidesTabs(hides: D.PageHides(tabs: false, items: ["x"]), visibility: .rootOnly, depth: 0))
        #expect(ServerUIChromeHide.hidesTabs(hides: D.PageHides(tabs: false, items: ["x"]), visibility: .rootOnly, depth: 1))
    }

    @Test("a decoded root-only document carries the visibility the rule reads")
    func decodedRootOnly() throws {
        let document = try Self.document("tabs-visibility-root-only")
        #expect(document.navigation.effectiveTabsVisibility == .rootOnly)
        #expect(ServerUIChromeHide.hidesTabs(hides: document.pages[1].hides, visibility: document.navigation.tabsVisibility, depth: 1))
        let plain = try Self.document("tabs-visibility-always")
        #expect(!ServerUIChromeHide.hidesTabs(hides: plain.pages[1].hides, visibility: plain.navigation.tabsVisibility, depth: 1))
    }
}
