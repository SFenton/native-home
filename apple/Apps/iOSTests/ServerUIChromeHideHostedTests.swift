@testable import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - A page that hides the tabs or header buttons

/// Hosted UX and accessibility checks for `pages[].hides` and `navigation.tabsVisibility` (`sh.page-chrome-hide@1`, `sh.tabs-visibility@1`, global
/// chrome pick 4, 2026-11-18).
///
/// Every document is a case of the app's own global-chrome corpus (`GlobalChromeCorpus/`), decoded with the compiler's global-chrome rules on, with
/// the page's `hides` set in memory. The renderer decides by the window's size class, never by device, so each test sets the size class on the
/// renderer itself: the same code runs on the iPhone (floating bar), the Duo (rail or bar) and the iPad (top bar) simulators and checks every
/// style. Navigation is the fixture's own: `page-orbit` pushes `page-echo`, and `chrome-bell` is a header button every page shows.
@MainActor
final class ServerUIChromeHideHostedTests: XCTestCase {
    private enum Layout: CaseIterable { case stack, columns }
    private enum Style: CaseIterable { case bar, topBar }

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    private static let hiddenItem = "chrome-bell"
    private static let keptItem = "chrome-palette"

    /// The corpus case `hides-both`, with `page-echo` (the page the root pushes) hiding `echo`, `page-orbit` hiding `root`, and the document's
    /// `tabsVisibility` set to `visibility`; `columns` makes both pages navigation columns.
    private func publication(root: JSONValue? = nil, echo: JSONValue? = nil, visibility: String? = nil,
                              columns: Bool = false) throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/GlobalChromeCorpus/reject/pending-global-chrome-hides-both.json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        var capabilities = Set(json["capabilities"]?.array?.compactMap(\.string) ?? [])
        guard case .object(var envelope) = json, case .object(var document)? = envelope["document"],
              case .array(var pages)? = document["pages"] else { throw XCTSkip("Unexpected corpus shape") }
        func set(_ index: Int, _ hides: JSONValue?) {
            guard case .object(var page) = pages[index] else { return }
            page["hides"] = hides
            if columns { page["navigation"] = .object(["type": .string("navigation-columns"), "placeholder": .string("Select an Item"), "standalone": .bool(false)]) }
            pages[index] = .object(page)
        }
        set(0, root)
        set(2, echo)
        document["pages"] = .array(pages)
        // The manifest names a capability exactly when the document uses it.
        if root == nil, echo == nil { capabilities.remove("sh.page-chrome-hide@1") }
        if let visibility, case .object(var navigation)? = document["navigation"] {
            navigation["tabsVisibility"] = .string(visibility)
            document["navigation"] = .object(navigation)
            capabilities.insert("sh.tabs-visibility@1")
        }
        if columns { capabilities.insert("sh.navigation-columns@1") }
        envelope["document"] = .object(document)
        envelope["capabilities"] = .array(capabilities.sorted().map(JSONValue.string))
        json = .object(envelope)
        let data = try JSONEncoder().encode(json)
        return try ServerUIGlobalChrome.$understood.withValue(true) { try ServerUICompositionPublication.decode(data) }
    }

    private static func hides(tabs: Bool = false, items: [String] = []) -> JSONValue {
        .object(["tabs": .bool(tabs), "items": .array(items.map(JSONValue.string))])
    }

    /// A renderer in a window set up as `style` and `layout`, settled at its root page.
    private func host(_ publication: ServerUICompositionPublication, style: Style = .bar, layout: Layout = .stack) throws -> (UKServerUIRenderer, UIWindow) {
        let regular = style == .topBar
        var size = regular ? CGSize(width: 744, height: 1133) : CGSize(width: 390, height: 844)
        if layout == .columns { size = HostedPage.splitSize }
        let (renderer, window, _) = try ServerUIRendererFixture.host(publication: publication, size: size)
        renderer.traitOverrides.horizontalSizeClass = regular || layout == .columns ? .regular : .compact
        HostedPage.layoutTracked()
        HostedPage.wait(0.2)
        return (renderer, window)
    }

    private func push(_ renderer: UKServerUIRenderer) throws -> UKServerUIPage {
        let root = try ServerUIRendererFixture.root(renderer)
        guard case .grid(let grid) = root.definition.components[0], case .navigationTile(let tile) = grid.children[1] else {
            throw XCTSkip("Fixture navigation tile")
        }
        try renderer.perform(tile.action, from: root)
        XCTAssertTrue(HostedPage.until { renderer.navigation.snapshot.stacks[.tab("tab-alpha")]?.count == 2 })
        XCTAssertTrue(HostedPage.until { renderer.logicalStacks[.tab("tab-alpha")]?.count == 2 })
        HostedPage.wait(0.5)
        return try XCTUnwrap(renderer.logicalStacks[.tab("tab-alpha")]?.last)
    }

    private func back(_ renderer: UKServerUIRenderer, from page: UKServerUIPage) throws {
        try renderer.perform(.back, from: page)
        XCTAssertTrue(HostedPage.until { renderer.logicalStacks[.tab("tab-alpha")]?.count == 1 })
        HostedPage.wait(0.5)
    }

    private func identifiers(_ page: UKServerUIPage) -> Set<String> {
        Set(ServerUIRendererFixture.barItems(page).compactMap(\.accessibilityIdentifier))
    }

    private func barHidden(_ renderer: UKServerUIRenderer) -> Bool { renderer.tabBarIsHidden }

    // MARK: The rule, drawn

    /// A document that hides nothing draws as it did: bar shown and every item on the pushed page.
    func testADocumentWithoutHidesDrawsAsBefore() throws {
        for style in Style.allCases {
            let (renderer, window) = try host(publication(), style: style)
            defer { window.isHidden = true }
            XCTAssertFalse(barHidden(renderer), "\(style)")
            let echo = try push(renderer)
            XCTAssertFalse(barHidden(renderer), "\(style)")
            XCTAssertTrue(HostedPage.until { self.identifiers(echo).isSuperset(of: [Self.hiddenItem, Self.keptItem]) }, "\(style)")
            try back(renderer, from: echo)
            XCTAssertFalse(barHidden(renderer), "\(style)")
        }
    }

    /// `hides.tabs` hides the bar with the push and returns it with Back, in a stack and in columns, on the bar and the top bar.
    func testATabsHidingPageHidesTheBarWithThePushAndReturnsItWithBack() throws {
        for style in Style.allCases {
            for layout in Layout.allCases {
                let (renderer, window) = try host(publication(echo: Self.hides(tabs: true), columns: layout == .columns), style: style, layout: layout)
                defer { window.isHidden = true }
                XCTAssertFalse(barHidden(renderer), "the root shows the bar (\(style), \(layout))")
                let echo = try push(renderer)
                XCTAssertTrue(HostedPage.until { self.barHidden(renderer) }, "the hiding page hides the bar (\(style), \(layout))")
                XCTAssertTrue(identifiers(echo).contains(Self.hiddenItem), "tabs only drops no item (\(style), \(layout))")
                try back(renderer, from: echo)
                XCTAssertTrue(HostedPage.until { !self.barHidden(renderer) }, "Back returns the bar (\(style), \(layout))")
            }
        }
    }

    /// `hides.items` drops the named header button and keeps the bar.
    func testAnItemsHidingPageDropsTheButtonAndKeepsTheBar() throws {
        for style in Style.allCases {
            for layout in Layout.allCases {
                let (renderer, window) = try host(publication(echo: Self.hides(items: [Self.hiddenItem]), columns: layout == .columns), style: style, layout: layout)
                defer { window.isHidden = true }
                let root = try ServerUIRendererFixture.root(renderer)
                XCTAssertTrue(HostedPage.until { self.identifiers(root).contains(Self.hiddenItem) }, "the root keeps it (\(style), \(layout))")
                let echo = try push(renderer)
                XCTAssertFalse(barHidden(renderer), "items only keeps the bar (\(style), \(layout))")
                XCTAssertTrue(HostedPage.until { self.identifiers(echo).contains(Self.keptItem) }, "the other buttons stay (\(style), \(layout))")
                XCTAssertFalse(identifiers(echo).contains(Self.hiddenItem), "the named button is gone (\(style), \(layout))")
                try back(renderer, from: echo)
                XCTAssertTrue(identifiers(root).contains(Self.hiddenItem), "Back brings it back (\(style), \(layout))")
            }
        }
    }

    /// Both together hide the bar and the button.
    func testAPageThatHidesBothDropsTheBarAndTheButton() throws {
        for style in Style.allCases {
            let (renderer, window) = try host(publication(echo: Self.hides(tabs: true, items: [Self.hiddenItem])), style: style)
            defer { window.isHidden = true }
            let echo = try push(renderer)
            XCTAssertTrue(HostedPage.until { self.barHidden(renderer) }, "\(style)")
            XCTAssertFalse(identifiers(echo).contains(Self.hiddenItem), "\(style)")
            try back(renderer, from: echo)
            XCTAssertTrue(HostedPage.until { !self.barHidden(renderer) }, "\(style)")
        }
    }

    /// `tabsVisibility: root-only` shows the bar on the root and hides it on any pushed page, in a stack and in columns.
    func testRootOnlyHidesTheBarOnAPushedPage() throws {
        for style in Style.allCases {
            for layout in Layout.allCases {
                let (renderer, window) = try host(publication(visibility: "root-only", columns: layout == .columns), style: style, layout: layout)
                defer { window.isHidden = true }
                XCTAssertFalse(barHidden(renderer), "the root shows the bar (\(style), \(layout))")
                let echo = try push(renderer)
                XCTAssertTrue(HostedPage.until { self.barHidden(renderer) }, "a pushed page hides it (\(style), \(layout))")
                try back(renderer, from: echo)
                XCTAssertTrue(HostedPage.until { !self.barHidden(renderer) }, "Back returns it (\(style), \(layout))")
            }
        }
    }

    /// A root page may hide the tabs itself, and the pushed page then follows the app alone.
    func testARootPageThatHidesTheTabsHidesThemAtTheRootOnly() throws {
        let (renderer, window) = try host(publication(root: Self.hides(tabs: true)))
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until { self.barHidden(renderer) }, "the hiding root draws no bar")
        let echo = try push(renderer)
        XCTAssertTrue(HostedPage.until { !self.barHidden(renderer) }, "the next page follows the app")
        try back(renderer, from: echo)
        XCTAssertTrue(HostedPage.until { self.barHidden(renderer) })
    }

    /// An interactive Back swipe that is cancelled leaves the bar hidden, as the page still on top asks.
    func testACancelledBackSwipeKeepsTheBarHidden() throws {
        let (renderer, window) = try host(publication(echo: Self.hides(tabs: true)))
        defer { window.isHidden = true }
        let echo = try push(renderer)
        XCTAssertTrue(HostedPage.until { self.barHidden(renderer) })
        let nav = try XCTUnwrap(renderer.stacks[.tab("tab-alpha")])
        let motion = try XCTUnwrap((nav.delegate as? UKServerUIStackDelegate)?.motion)
        motion.beginSwipe()
        motion.updateSwipe(progress: 0.2)
        motion.endSwipe(progress: 0.2, velocity: 0, cancelled: true)
        XCTAssertTrue(HostedPage.until { nav.transitionCoordinator == nil })
        HostedPage.wait(0.3)
        XCTAssertTrue(nav.topViewController === echo)
        XCTAssertTrue(barHidden(renderer), "the page on top still hides the tabs")
    }

    /// Reduce Motion cuts the bar away instead of sliding it; the state is the same.
    func testReduceMotionStillHidesAndReturnsTheBar() throws {
        UKMotion.reduceMotionOverride = true
        let (renderer, window) = try host(publication(echo: Self.hides(tabs: true)))
        defer { window.isHidden = true }
        let echo = try push(renderer)
        XCTAssertTrue(HostedPage.until { self.barHidden(renderer) })
        try back(renderer, from: echo)
        XCTAssertTrue(HostedPage.until { !self.barHidden(renderer) })
    }

    // MARK: Accessibility

    /// A hidden header button is absent from the page's bar items, and Back stays: the stack keeps the root below the page and the page shows no
    /// replacement for the system Back button.
    func testHiddenItemsAreAbsentAndBackRemains() throws {
        for style in Style.allCases {
            let (renderer, window) = try host(publication(echo: Self.hides(tabs: true, items: [Self.hiddenItem])), style: style)
            defer { window.isHidden = true }
            let echo = try push(renderer)
            XCTAssertTrue(HostedPage.until { self.identifiers(echo).contains(Self.keptItem) }, "\(style)")
            XCTAssertFalse(identifiers(echo).contains(Self.hiddenItem), "\(style)")
            let nav = try XCTUnwrap(renderer.stacks[.tab("tab-alpha")])
            XCTAssertFalse(echo.navigationItem.hidesBackButton, "Back is never hidden (\(style))")
            XCTAssertEqual(nav.viewControllers.count, 2, "Back has a page to return to (\(style))")
            XCTAssertTrue(echo.accessibilityPerformEscape(), "VoiceOver Escape still goes back (\(style))")
            XCTAssertTrue(HostedPage.until { renderer.logicalStacks[.tab("tab-alpha")]?.count == 1 }, "\(style)")
        }
    }

    /// A page opened in a sheet never reads the page's hides: the sheet keeps its own chrome.
    func testASheetKeepsItsOwnChrome() throws {
        let (renderer, window) = try host(publication(echo: Self.hides(tabs: true, items: [Self.hiddenItem])))
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(renderer)
        let palette = renderer.publication.document.navigation.chrome.groups.flatMap(\.items).compactMap { item -> ServerUICompositionDocument.Action? in
            if case .button(let button) = item, button.id == Self.keptItem { return button.action }
            return nil
        }
        try renderer.perform(XCTUnwrap(palette.first), from: root)
        XCTAssertTrue(HostedPage.until { renderer.modal != nil })
        XCTAssertFalse(barHidden(renderer), "a sheet never hides the tabs")
    }
}
