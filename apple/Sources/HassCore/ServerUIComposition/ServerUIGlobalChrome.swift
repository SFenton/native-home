import Foundation

// MARK: - Global chrome contract

/// The contract additions of the global-chrome rule: sheet levels, a page's own chrome hides, a page's wide-window open and the tab bar's visibility.
///
/// Sheet levels shipped with their runtime (``ServerUIIngestedCapabilities/sheetLevels``). For the other three the compiler holds the decode and validation
/// rules, but a shipped build refuses a publication that uses them as `unsupported_capability`: they are not in
/// ``ServerUICompositionPublication/supportedCapabilities``, the list the app tells the server it can draw, and no runtime draws them yet. The rules run only
/// inside ``understood`` (a test scope). An id moves from ``all`` to ``ServerUIIngestedCapabilities`` in the change that lands its runtime (the owner's
/// capability rule), `capabilities.json` is regenerated then, and the scope goes with the last id.
public enum ServerUIGlobalChrome {
    /// Whether the compiler accepts the ids in ``all``. False everywhere but a test scope: `ServerUIGlobalChrome.$understood.withValue(true) { ... }`.
    @TaskLocal static var understood = false

    /// Top-level `levels[]`: surfaces a sheet's `push` reaches without leaving the sheet. Published: see ``ServerUIIngestedCapabilities/sheetLevels``.
    public static let sheetLevels = "sh.sheet-levels@1"
    /// `pages[].hides`: chrome a page hides for itself.
    public static let pageChromeHide = "sh.page-chrome-hide@1"
    /// `pages[].wideOpen`: how a page opens in a window wide enough for two columns.
    public static let pageWideOpen = "sh.page-wide-open@1"
    /// `navigation.tabsVisibility`: whether the tab bar shows on every page or only on a root page.
    public static let tabsVisibility = "sh.tabs-visibility@1"

    /// The ids the compiler understands and the app does not yet publish.
    public static let all: [String] = [pageChromeHide, pageWideOpen, tabsVisibility]
}

// MARK: - Model

extension ServerUICompositionDocument {
    /// A surface a sheet's `push` reaches inside the sheet (`sh.sheet-levels@1`).
    ///
    /// A level is not a page: no tab, route, `initialPageId` or `present` names it, and a `push` to it is valid only from a modal or another level.
    public struct Level: Equatable, Sendable {
        /// The level's content: identity, title, layout, toolbar and components.
        public internal(set) var surface: Surface
        /// The level's id, unique across pages, modals and levels.
        public var id: String { surface.id }
    }

    /// What a page hides of the app's chrome while it is the top page (`sh.page-chrome-hide@1`).
    ///
    /// Hiding is the only direction: a page cannot show what the app hides.
    public struct PageHides: Equatable, Sendable {
        /// Whether the tab bar is hidden.
        public let tabs: Bool
        /// Ids of the app's `button` and `shell-header` chrome items to drop, in the order written.
        public let items: [String]
    }

    /// How a page opens in a window wide enough for two columns (`sh.page-wide-open@1`).
    public enum WideOpen: String, Sendable {
        /// Beside the page it came from when that page shows in columns, otherwise full width.
        case automatic
        /// The whole window.
        case full
        /// Beside the page it came from.
        case beside
    }

    /// Whether the tab bar shows on every page or only on a root page (`sh.tabs-visibility@1`).
    public enum TabsVisibility: String, Sendable {
        /// The tab bar shows on every page.
        case always
        /// The tab bar shows on a root page only.
        case rootOnly = "root-only"
    }
}

extension ServerUICompositionDocument.Navigation {
    /// The tab bar's visibility: what the document wrote, or ``ServerUICompositionDocument/TabsVisibility/always`` when it wrote nothing.
    public var effectiveTabsVisibility: ServerUICompositionDocument.TabsVisibility { tabsVisibility ?? .always }
}

// MARK: - Validation

extension ServerUICompositionCompiler {
    /// Reads a page's `hides` and `wideOpen`, and notes the capability each one needs.
    mutating func pageChrome(_ p: Cursor) throws -> (hides: D.PageHides?, wideOpen: D.WideOpen?) {
        var hides: D.PageHides?
        if let held = p.value["hides"] {
            require("page-chrome-hide")
            let items = (held["items"]?.array ?? []).compactMap(\.string)
            var seen: Set<String> = []
            for (index, id) in items.enumerated() where !seen.insert(id).inserted {
                add(.duplicateID, p.path("hides") + "/items/\(index)")
            }
            hides = D.PageHides(tabs: held["tabs"]?.bool ?? false, items: items)
        }
        var wideOpen: D.WideOpen?
        if p.value["wideOpen"] != nil {
            require("page-wide-open")
            wideOpen = try p.e("wideOpen")
        }
        return (hides, wideOpen)
    }

    /// Checks every page's `hides` against the app's chrome: an item must be a `button` or `shell-header` of the shell's groups, the shell menu's id is refused,
    /// and a page that replaces the toolbar may hide tabs but no items (it has no inherited items).
    mutating func validateHides(_ document: D) {
        var hideable: Set<String> = []
        var menus: Set<String> = []
        for item in document.navigation.chrome.groups.flatMap(\.items) {
            if case .shellMenu = item { menus.insert(item.id) } else { hideable.insert(item.id) }
        }
        for (index, page) in document.pages.enumerated() {
            guard let hides = page.hides else { continue }
            let base = "/document/pages/\(index)/hides"
            // A page with its own toolbar has no inherited items to drop; it may still hide the tab bar.
            if case .replace = page.surface.toolbar, !hides.items.isEmpty { add(.invalidCombination, base + "/items") }
            for (offset, id) in hides.items.enumerated() where !hideable.contains(id) {
                add(menus.contains(id) ? .invalidCombination : .invalidReference, base + "/items/\(offset)")
            }
        }
    }
}
