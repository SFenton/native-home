@testable import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - A page link in a sheet closes the sheet

/// Hosted, synthetic-only checks of the global-chrome sheet rule (`sh.sheet-levels@1`, owner 2026-11-18): a `push` to a page, activated from inside a
/// sheet, closes every level of the sheet and lands on the section stack, where Quick Links and Profile draw; a push to a level stays in the sheet.
/// Run unchanged on iPhone, iPhone Duo and iPad.
@MainActor
final class ServerUISheetOriginHostedTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    private static let modal = "modal-swatch"
    private static let echo = "page-echo"
    private static let tab = ServerUINavigationState.Root.tab("tab-alpha")

    /// The corpus' two-level sheet, with a Quick Links and Profile header on the app's trailing group.
    private func fixture(adaptive: Bool = false, form: Bool = false) throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/global-chrome-levels-two-levels.json")
        var root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        let present = JSONValue.object(["type": .string("present"), "modalId": .string(Self.modal), "arguments": .object([:]), "ifPresented": .string("reject")])
        root = try ServerUIRendererFixture.changing(root, path: "/document/navigation/chrome/groups/1/items", to: .array([.object([
            "id": .string("native-header"), "type": .string("shell-header"), "visibility": .string("always"),
            "quickLinksAction": present, "profileAction": present])]))
        var capabilities = try XCTUnwrap(root["capabilities"]?.array).compactMap(\.string) + ["sh.shell-header@1"]
        if adaptive {
            for index in try XCTUnwrap(root["document"]?["pages"]?.array).indices {
                root = try ServerUIRendererFixture.changing(root, path: "/document/pages/\(index)/navigation", to: .object([
                    "type": .string("navigation-columns"), "placeholder": .string("Select an Item"), "standalone": .bool(false), "onDemand": .bool(true)]))
            }
            root = try ServerUIRendererFixture.changing(root, path: "/document/modals/0/presentation/adaptive", to: .bool(true))
            capabilities += ["sh.navigation-columns@1", "sh.adaptive-presentation@1"]
        }
        return try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(Set(capabilities).sorted().map(JSONValue.string)))
    }

    private func publication(adaptive: Bool = false) throws -> ServerUICompositionPublication {
        let json = try fixture(adaptive: adaptive)
        do { return try ServerUIGlobalChrome.$understood.withValue(true) { try ServerUIRendererFixture.publication(json) } }
        catch let error as ServerUICompositionError where error.code == .capabilityManifestMismatch {
            // Replacing the corpus' Alerts button with the header drops the only badge, and with it the badges and operands capabilities.
            let kept = try XCTUnwrap(json["capabilities"]?.array).filter { $0.string != "sh.badges@1" && $0.string != "sh.operands@1" }
            let trimmed = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(kept))
            return try ServerUIGlobalChrome.$understood.withValue(true) { try ServerUIRendererFixture.publication(trimmed) }
        }
    }

    private func host(adaptive: Bool = false) throws -> (UKServerUIRenderer, UIWindow) {
        let source = UKServerUIShellHeaderSource(state: {
            .init(profileName: "Example Person", attentionCount: 0, isOffline: false, reconnectingPresent: false, reconnectingLit: false)
        })
        let renderer = try UKServerUIRenderer(publication: publication(adaptive: adaptive), context: UKContext(store: EntityStore()),
            backdrop: ServerUIRendererFixture.backdrop(), shellHeader: source)
        let window = HostedPage.show(renderer, size: adaptive ? HostedPage.splitSize : nil)
        if adaptive { renderer.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .regular), forChild: renderer.tabController) }
        HostedPage.wait(0.1)
        return (renderer, window)
    }

    private func push(_ id: String) -> ServerUICompositionDocument.Action {
        .push(.init(pageId: id, arguments: .init(), origin: .sender, duplicate: .reuseNearest))
    }

    private func hasHeader(_ page: UKServerUIPage) -> Bool {
        let items = ServerUIRendererFixture.barItems(page)
        return items.contains { $0.accessibilityIdentifier == "quickLinks.open" }
            && items.contains { $0.customView is UKProfileButtonView || $0.accessibilityIdentifier == "nav.profile" }
    }

    /// Whether the page draws Quick Links and Profile once its bar is built. A hosted window does not run the push transition that loads the
    /// pushed page's view (the journey does, on a device), so the view is loaded here.
    private func drawsHeader(_ page: UKServerUIPage) -> Bool {
        page.loadViewIfNeeded()
        return spin({ self.hasHeader(page) })
    }

    private func hasNoHeader(_ page: UKServerUIPage) -> Bool {
        !ServerUIRendererFixture.barItems(page).contains {
            $0.accessibilityIdentifier == "quickLinks.open" || $0.accessibilityIdentifier == "nav.profile" || $0.customView is UKProfileButtonView
        }
    }

    /// Spins the main run loop until `condition` holds: the pushes and dismissals here complete on it, as in the other renderer hosted tests.
    private func spin(_ condition: () -> Bool) -> Bool { HostedPage.until(8, condition) }

    private func openSheet(_ host: UKServerUIRenderer, from page: UKServerUIPage) throws -> UKServerUIPage {
        try host.perform(.present(modalId: Self.modal, arguments: .init(), ifPresented: .reject), from: page)
        let opened = spin({ host.modal?.topViewController is UKServerUIPage })
        XCTAssertTrue(opened)
        return try XCTUnwrap(host.modal?.topViewController as? UKServerUIPage)
    }

    private func topOfStack(_ host: UKServerUIRenderer) -> UKServerUIPage? {
        host.stacks[Self.tab]?.topViewController as? UKServerUIPage
    }

    private func settledOnPage(_ host: UKServerUIRenderer, _ id: String) -> Bool {
        spin({
            host.modal == nil && host.navigation.snapshot.presentations.isEmpty && self.topOfStack(host)?.surfaceID == id
        })
    }

    // MARK: Depth 0

    func testAPageLinkAtTheSheetRootClosesTheSheetAndLandsWithTheGlobalChrome() throws {
        let (host, _) = try host()
        let root = try ServerUIRendererFixture.root(host)
        XCTAssertTrue(hasHeader(root), "The page under the sheet carries Quick Links and Profile")
        let sheet = try openSheet(host, from: root)
        XCTAssertTrue(hasNoHeader(sheet), "The sheet draws no Quick Links or Profile")
        // The tile keeps its spoken hint: a page link adds no wording of its own (a later Designer verdict owns it).
        let tile = try XCTUnwrap(sheet.nodes["node-palette-local"]?.view as? UKGlassTileView)
        XCTAssertNil(tile.accessibilityHint)
        host.activate(push(Self.echo), from: sheet)
        let landed = settledOnPage(host, Self.echo)
        XCTAssertTrue(landed)
        let page = try XCTUnwrap(topOfStack(host))
        XCTAssertEqual(page.depth, 1)
        XCTAssertNil(page.presentationID)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit", Self.echo])
        let drawn = drawsHeader(page)
        XCTAssertTrue(drawn, "The landed page carries Quick Links and Profile")
    }

    // MARK: Depth 2

    func testAPageLinkTwoLevelsDeepClosesEveryLevelInOneDismissal() throws {
        let (host, _) = try host()
        let sheet = try openSheet(host, from: ServerUIRendererFixture.root(host))
        host.activate(push("level-one"), from: sheet)
        let modal = try XCTUnwrap(host.modal)
        let first = spin({ modal.viewControllers.count == 2 })
        XCTAssertTrue(first, "A push to a level stays in the sheet")
        let one = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
        XCTAssertEqual(one.surfaceID, "level-one")
        host.activate(push("level-two"), from: one)
        let second = spin({ modal.viewControllers.count == 3 })
        XCTAssertTrue(second)
        let two = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
        XCTAssertTrue(hasNoHeader(one) && hasNoHeader(two), "A level draws no Quick Links or Profile")
        XCTAssertNotNil(host.modal)
        host.activate(push(Self.echo), from: two)
        let landed = settledOnPage(host, Self.echo)
        XCTAssertTrue(landed)
        XCTAssertNil(host.modal, "Every level closed together")
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit", Self.echo], "The levels are not on the section stack")
        let landedPage = try XCTUnwrap(topOfStack(host))
        let drawn = drawsHeader(landedPage)
        XCTAssertTrue(drawn, "The landed page carries Quick Links and Profile")
    }

    // MARK: Already on the stack, and the page under the sheet

    func testAPageAlreadyOnTheStackIsPoppedToAndThePageUnderTheSheetJustCloses() throws {
        let (host, _) = try host()
        let root = try ServerUIRendererFixture.root(host)
        try host.perform(push(Self.echo), from: root)
        let pushed = spin({ self.topOfStack(host)?.surfaceID == Self.echo })
        XCTAssertTrue(pushed)
        let echo = try XCTUnwrap(topOfStack(host))
        let attached = spin({ echo.view.window != nil })
        XCTAssertTrue(attached)
        // The page under the sheet: closes only; the stack does not grow.
        var sheet = try openSheet(host, from: echo)
        host.activate(push(Self.echo), from: sheet)
        let stayed = settledOnPage(host, Self.echo)
        XCTAssertTrue(stayed)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit", Self.echo])
        XCTAssertTrue(topOfStack(host) === echo, "The page under the sheet is the same page")
        // A page already below it: popped to, not pushed again.
        sheet = try openSheet(host, from: echo)
        host.activate(push("page-orbit"), from: sheet)
        let popped = settledOnPage(host, "page-orbit")
        XCTAssertTrue(popped)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit"])
        let landedPage = try XCTUnwrap(topOfStack(host))
        let drawn = drawsHeader(landedPage)
        XCTAssertTrue(drawn, "The landed page carries Quick Links and Profile")
    }

    // MARK: Adaptive column

    func testAnAdaptiveColumnIsRemovedAndThePageOpensByTheColumnsRule() throws {
        let (host, _) = try host(adaptive: true)
        host.columnGeometryChanged()
        let root = try ServerUIRendererFixture.root(host)
        try host.perform(.present(modalId: Self.modal, arguments: .init(), ifPresented: .reject), from: root)
        let opened = spin({ (root.columns?.entries.last?.controller as? UKServerUIPage)?.presentationID != nil })
        XCTAssertTrue(opened, "The adaptive sheet opens as a column")
        let column = try XCTUnwrap(root.columns?.entries.last?.controller as? UKServerUIPage)
        XCTAssertNil(host.modal)
        XCTAssertTrue(hasNoHeader(column))
        host.activate(push(Self.echo), from: column)
        let landed = spin({
            host.navigation.snapshot.presentations.isEmpty && (root.columns?.entries.last?.controller as? UKServerUIPage)?.surfaceID == Self.echo
        })
        XCTAssertTrue(landed)
        let page = try XCTUnwrap(root.columns?.entries.last?.controller as? UKServerUIPage)
        XCTAssertNil(page.presentationID, "The page is on the section stack, not in a presentation")
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit", Self.echo])
        XCTAssertTrue(hasHeader(root), "The page that carries the bar keeps Quick Links and Profile")
    }

    // MARK: Unsaved changes

    func testAFormWithUnsavedChangesAsksBeforeTheSheetCloses() throws {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fragment = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIRecordsFixture.json")))
        let components = try XCTUnwrap(fragment["components"]?.array).filter { $0["type"]?.string != "recipe-part" }
        var json = try ServerUIRendererFixture.json()
        let tile = try XCTUnwrap(json["document"]?["modals"]?.array?.first?["components"]?.array?.first { $0["id"]?.string == "node-palette-local" })
        let form = try XCTUnwrap(components.first { $0["type"]?.string == "form" })
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components.filter { $0["type"]?.string != "form" }))
        json = try ServerUIRendererFixture.changing(json, path: "/document/navigation/chrome/groups/1/items/0/priority", to: .string("normal"))
        json = try ServerUIRendererFixture.changing(json, path: "/document/modals/0/components", to: .array([form, tile]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/levels", to: .array([]))
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(
            (ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.grid@1" }
                + ["sh.collection@1", "sh.form@1", "sh.pinned-actions@1", ServerUIGlobalChrome.sheetLevels]).sorted().map(JSONValue.string)))
        let draft = try ServerUIValueForm(identity: .init(ownerId: "demo", recordId: "item"),
            fields: [.text("name", "Name", "Original", required: true), .toggle("enabled", "Enabled", false)]) { _ in }
        let records = UKServerUIRecords(collections: ["demo-items": ServerUIShellRendererTests.ShellRecordSource()], forms: [
            "demo-edit": .init(fields: ["name": .text, "enabled": .toggle], selectionOnly: false, open: { draft }),
        ])
        let document = json
        let publication = try ServerUIGlobalChrome.$understood.withValue(true) { try ServerUIRendererFixture.publication(document) }
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
            backdrop: ServerUIRendererFixture.backdrop(), records: records)
        _ = HostedPage.show(host)
        HostedPage.wait(0.1)
        let sheet = try openSheet(host, from: ServerUIRendererFixture.root(host))
        let session = spin({ sheet.formView?.session === draft })
        XCTAssertTrue(session)
        try draft.set(.string("Edited"), group: "item", field: "name")
        host.activate(push(Self.echo), from: sheet)
        let asked = spin({ sheet.presentedViewController is UIAlertController })
        XCTAssertTrue(asked, "Unsaved changes ask before the sheet closes")
        XCTAssertNotNil(host.modal)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit"])
        // Keeping the edit leaves everything as it was.
        let alert = try XCTUnwrap(sheet.presentedViewController as? UIAlertController)
        let keep = try XCTUnwrap(alert.actions.first { $0.style == .cancel }?.title)
        let discard = try XCTUnwrap(alert.actions.first { $0.style == .destructive }?.title)
        FeatureHost.answer(alert, keep)
        HostedPage.wait(0.3)
        XCTAssertNotNil(host.modal)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit"])
        // Discarding it lets the same link go through.
        host.activate(push(Self.echo), from: sheet)
        let again = spin({ sheet.presentedViewController is UIAlertController })
        XCTAssertTrue(again, "The same link asks again")
        FeatureHost.answer(try XCTUnwrap(sheet.presentedViewController as? UIAlertController), discard, dismissing: false)
        let landed = settledOnPage(host, Self.echo)
        XCTAssertTrue(landed)
    }

    // MARK: Room navigation

    /// A room chosen in a level of the sheet leaves the sheet like any page link: room navigation reaches `perform` without `activate`.
    func testARoomChosenInALevelClosesTheSheetAndLandsOnTheSectionStack() throws {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let corpus = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent(
            "Tests/HassCoreTests/ContractCorpus/accept/global-chrome-levels-two-levels.json")))
        var level = try XCTUnwrap(corpus["document"]?["levels"]?.array?.first)
        level = try ServerUIRendererFixture.changing(level, path: "/components", to: .array([.object([
            "id": .string("room-grid-level"), "title": .string("Level rooms"), "type": .string("room-navigation-grid"),
            "layout": .object(["span": .number(1)]),
            "binding": .object(["sourceId": .string("source-room-navigation"), "projection": .string("room-navigation@1")]),
            "props": .object([:]),
        ])]))
        var json = try ServerUIRendererFixture.roomsJSON()
        json = try ServerUIRendererFixture.changing(json, path: "/document/levels", to: .array([level]))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string) + [ServerUIGlobalChrome.sheetLevels]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(Set(capabilities).sorted().map(JSONValue.string)))
        let (host, window, _) = try ServerUIRendererFixture.roomHost(json: json)
        defer { window.isHidden = true }
        let sheet = try openSheet(host, from: ServerUIRendererFixture.root(host))
        host.activate(push("level-one"), from: sheet)
        let inLevel = spin({ host.modal?.viewControllers.count == 2 })
        XCTAssertTrue(inLevel, "A push to a level stays in the sheet")
        let one = try XCTUnwrap(host.modal?.topViewController as? UKServerUIPage)
        let settled = spin({ host.modal?.transitionCoordinator == nil })
        XCTAssertTrue(settled)
        let grid = try XCTUnwrap(one.nodes["room-grid-level"]?.view as? UKServerUIRoomNavigationGrid)
        let room = try XCTUnwrap(grid.items.map(\.view).compactMap { $0 as? UKGlassTileView }
            .first { $0.accessibilityIdentifier == "room-grid-level.room-b" })
        XCTAssertTrue(room.accessibilityActivate())
        let landed = spin({ host.modal == nil && host.navigation.snapshot.presentations.isEmpty })
        XCTAssertTrue(landed, "The sheet closed")
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit", "page-lattice"], "The room page is on the section stack")
    }

    // MARK: Documents without the capability

    func testADocumentWithoutLevelsKeepsAPagePushInsideTheSheet() throws {
        let json = try ServerUIRendererFixture.json()
        let publication = try ServerUIRendererFixture.publication(json)
        XCTAssertFalse(publication.document.declaresSheetLevels)
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()), backdrop: ServerUIRendererFixture.backdrop())
        _ = HostedPage.show(host)
        HostedPage.wait(0.1)
        let sheet = try openSheet(host, from: ServerUIRendererFixture.root(host))
        host.activate(push(Self.echo), from: sheet)
        let stayed = spin({ host.modal?.viewControllers.count == 2 })
        XCTAssertTrue(stayed, "A lowered document's drill stays in the sheet, as on a build before the capability")
    }
}
