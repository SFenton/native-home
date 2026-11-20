import HassDesign
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
    /// What the renderer reported through `onError` since ``formHost(homed:homedOn:formOnPage:)`` built it.
    private var reported: [UKServerUIRendererError] = []
    /// The speed of the hosted window's layer tree (1 is real time): below 1 every animation, including an alert's presentation and dismissal, takes proportionally longer.
    private var animationSpeed: Float = 1

    override func tearDown() async throws {
        reported = []
        animationSpeed = 1
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    private static let modal = "modal-swatch"
    private static let echo = "page-echo"
    private static let tab = ServerUINavigationState.Root.tab("tab-alpha")

    /// The corpus' two-level sheet, with a Quick Links and Profile header on the app's trailing group.
    ///
    /// `homed` maps a page to the tab its authored route names (`extensions.routes[].tabId`); `hideBeta` hides `tab-beta` behind a rule that is false.
    private func fixture(adaptive: Bool = false, form: Bool = false, homed: [String: String] = [:], hideBeta: Bool = false) throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = apple.appendingPathComponent("Tests/HassCoreTests/GlobalChromeCorpus/accept/global-chrome-levels-two-levels.json")
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
        if !homed.isEmpty {
            let routes = homed.sorted { $0.key < $1.key }.map { page, tab in
                JSONValue.object(["id": .string("route-\(page)"), "path": .string(page), "pageId": .string(page), "tabId": .string(tab),
                                  "title": .string(page), "summary": .string("Opens \(page)"), "icon": .string("house.fill")])
            }
            root = try ServerUIRendererFixture.changing(root, path: "/document/extensions", to: .object([
                "type": .string("native-extensions@1"), "watch": .string("stub@1"), "routes": .array(routes), "cameras": .array([])]))
            capabilities.append("sh.native-extensions@1")
        }
        if hideBeta {
            let rule = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"viewer","isAdmin":true}"#.utf8))
            root = try ServerUIRendererFixture.changing(root, path: "/document/navigation/tabs/1/visibleWhen", to: rule)
            root = try ServerUIRendererFixture.changing(root, path: "/document/navigation/tabs/1/whenUnknown", to: .string("hide"))
            capabilities.append("sh.visible-when@1")
        }
        return try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(Set(capabilities).sorted().map(JSONValue.string)))
    }

    private func publication(adaptive: Bool = false, homed: [String: String] = [:], hideBeta: Bool = false) throws -> ServerUICompositionPublication {
        let json = try fixture(adaptive: adaptive, homed: homed, hideBeta: hideBeta)
        do { return try ServerUIGlobalChrome.$understood.withValue(true) { try ServerUIRendererFixture.publication(json) } }
        catch let error as ServerUICompositionError where error.code == .capabilityManifestMismatch {
            // Replacing the corpus' Alerts button with the header drops the only badge, and with it the badges and operands capabilities.
            let kept = try XCTUnwrap(json["capabilities"]?.array).filter { $0.string != "sh.badges@1" && $0.string != "sh.operands@1" }
            let trimmed = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(kept))
            return try ServerUIGlobalChrome.$understood.withValue(true) { try ServerUIRendererFixture.publication(trimmed) }
        }
    }

    private func host(adaptive: Bool = false, homed: [String: String] = [:], hideBeta: Bool = false) throws -> (UKServerUIRenderer, UIWindow) {
        let source = UKServerUIShellHeaderSource(state: {
            .init(profileName: "Example Person", attentionCount: 0, isOffline: false, reconnectingPresent: false, reconnectingLit: false)
        })
        let renderer = try UKServerUIRenderer(publication: publication(adaptive: adaptive, homed: homed, hideBeta: hideBeta), context: UKContext(store: EntityStore()),
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

    /// A host with an editable form and the palette tile; `homed` homes `page-echo` on `tab-beta`.
    ///
    /// The form sits in the sheet, or with `formOnPage` on the first tab's root page (the tab a link leaves), leaving the sheet the tile alone.
    private func formHost(homed: Bool = false, homedOn: String = "tab-beta", formOnPage: Bool = false) throws -> (UKServerUIRenderer, ServerUIValueForm) {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fragment = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIRecordsFixture.json")))
        let components = try XCTUnwrap(fragment["components"]?.array).filter { $0["type"]?.string != "recipe-part" }
        var json = try ServerUIRendererFixture.json()
        let tile = try XCTUnwrap(json["document"]?["modals"]?.array?.first?["components"]?.array?.first { $0["id"]?.string == "node-palette-local" })
        let form = try XCTUnwrap(components.first { $0["type"]?.string == "form" })
        let pageComponents = formOnPage ? components : components.filter { $0["type"]?.string != "form" }
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(pageComponents))
        json = try ServerUIRendererFixture.changing(json, path: "/document/navigation/chrome/groups/1/items/0/priority", to: .string("normal"))
        json = try ServerUIRendererFixture.changing(json, path: "/document/modals/0/components", to: .array(formOnPage ? [tile] : [form, tile]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/levels", to: .array([]))
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(
            (ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.grid@1" }
                + ["sh.collection@1", "sh.form@1", "sh.pinned-actions@1", ServerUIGlobalChrome.sheetLevels]).sorted().map(JSONValue.string)))
        let draft = try ServerUIValueForm(identity: .init(ownerId: "demo", recordId: "item"),
            fields: [.text("name", "Name", "Original", required: true), .toggle("enabled", "Enabled", false)]) { _ in }
        let records = UKServerUIRecords(collections: ["demo-items": ServerUIShellRendererTests.ShellRecordSource()], forms: [
            "demo-edit": .init(fields: ["name": .text, "enabled": .toggle], selectionOnly: false, open: { draft }),
        ])
        if homed {
            json = try ServerUIRendererFixture.changing(json, path: "/document/extensions", to: .object([
                "type": .string("native-extensions@1"), "watch": .string("stub@1"), "cameras": .array([]),
                "routes": .array([.object(["id": .string("route-echo"), "path": .string("echo"), "pageId": .string(Self.echo), "tabId": .string(homedOn),
                                           "title": .string("Echo"), "summary": .string("Opens echo"), "icon": .string("house.fill")])])]))
            let kept = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string) + ["sh.native-extensions@1"]
            json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(Set(kept).sorted().map(JSONValue.string)))
        }
        let document = json
        let publication = try ServerUIGlobalChrome.$understood.withValue(true) { try ServerUIRendererFixture.publication(document) }
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
            backdrop: ServerUIRendererFixture.backdrop(), records: records)
        host.onError = { [weak self] in self?.reported.append($0) }
        let window = HostedPage.show(host)
        window.layer.speed = animationSpeed
        HostedPage.wait(0.1)
        return (host, draft)
    }

    /// What blocks an intent right now, for an assertion message: the presented controllers, the pending alert, the forms the link leaves, the
    /// selected tab and its stack, and the error the discard replay swallowed.
    private func guardState(_ host: UKServerUIRenderer, page: UKServerUIPage, link: ServerUICompositionDocument.Action) -> String {
        func name(_ controller: UIViewController?) -> String { controller.map { String(describing: type(of: $0)) + ($0.isBeingPresented ? "(presenting)" : $0.isBeingDismissed ? "(dismissing)" : "") } ?? "none" }
        let forms = host.exitForms(link, from: page).map { "needsDiscard=\($0.needsDiscard) blocksExit=\($0.blocksExit)" }
        return "page.presented=\(name(page.presentedViewController)) modal.presented=\(name(host.modal?.presentedViewController)) "
            + "activeAlert=\(name(host.activeAlert)) exitForms=\(forms) selection=\(host.navigation.snapshot.selection) "
            + "stacks=\(host.navigation.snapshot.stacks) presentations=\(host.navigation.snapshot.presentations.count) modal=\(host.modal != nil) "
            + "replayError=\(String(describing: host.lastDiscardReplayError)) reported=\(reported.map(\.description))"
    }

    /// Answers a "Discard changes?" alert with Discard and waits for the replayed `link` to land; the one place every discard-replay test
    /// asserts, so a failure prints the guard state and the replay's error (``guardState(_:page:link:)``).
    /// - Parameters:
    ///   - settled: Wait for the alert to finish presenting before answering it (a person cannot tap an alert that is not up yet).
    ///   - landed: What the replay must have done.
    @discardableResult
    private func discardAndExpect(_ host: UKServerUIRenderer, alert: UIAlertController, from page: UKServerUIPage, link: ServerUICompositionDocument.Action,
                                  settled: Bool = true, _ message: String, file: StaticString = #filePath, line: UInt = #line,
                                  until landed: () -> Bool) throws -> Bool {
        if settled { XCTAssertTrue(spin({ !HostedPage.isTransitioning(page) }), "The alert finished presenting", file: file, line: line) }
        let discard = try XCTUnwrap(alert.actions.first { $0.style == .destructive }?.title)
        FeatureHost.answer(alert, discard, dismissing: false)
        let done = spin(landed)
        XCTAssertTrue(done, message + " | " + guardState(host, page: page, link: link), file: file, line: line)
        return done
    }

    func testAFormWithUnsavedChangesAsksBeforeTheSheetCloses() throws {
        let (host, draft) = try formHost()
        let sheet = try openSheet(host, from: ServerUIRendererFixture.root(host))
        let session = spin({ sheet.formView?.session === draft })
        XCTAssertTrue(session)
        try draft.set(.string("Edited"), group: "item", field: "name")
        let link = push(Self.echo)
        host.activate(link, from: sheet)
        let asked = spin({ sheet.presentedViewController is UIAlertController })
        XCTAssertTrue(asked, "Unsaved changes ask before the sheet closes")
        XCTAssertNotNil(host.modal)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit"])
        // Keeping the edit leaves everything as it was. The alert is answered once it has finished presenting and the answer waits for it
        // to be gone: a dismissal asked of a presentation still in flight lands late on a loaded machine.
        let alert = try XCTUnwrap(sheet.presentedViewController as? UIAlertController)
        XCTAssertTrue(spin({ !HostedPage.isTransitioning(sheet) }), "The first alert finished presenting")
        let keep = try XCTUnwrap(alert.actions.first { $0.style == .cancel }?.title)
        FeatureHost.answer(alert, keep)
        XCTAssertTrue(spin({ sheet.presentedViewController == nil && !HostedPage.isTransitioning(sheet) }), "Keep Editing closed the first alert")
        HostedPage.wait(0.3)
        XCTAssertNotNil(host.modal)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit"])
        // Discarding it lets the same link go through.
        host.activate(link, from: sheet)
        let again = spin({ sheet.presentedViewController is UIAlertController })
        XCTAssertTrue(again, "The same link asks again")
        try discardAndExpect(host, alert: try XCTUnwrap(sheet.presentedViewController as? UIAlertController), from: sheet, link: link, "The link lands on the page") {
            self.settledOnPage(host, Self.echo)
        }
    }

    // MARK: Room navigation

    /// A room chosen in a level of the sheet leaves the sheet like any page link: room navigation reaches `perform` without `activate`.
    func testARoomChosenInALevelClosesTheSheetAndLandsOnTheSectionStack() throws {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let corpus = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent(
            "Tests/HassCoreTests/GlobalChromeCorpus/accept/global-chrome-levels-two-levels.json")))
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

    // MARK: Home tab

    private static let beta = ServerUINavigationState.Root.tab("tab-beta")
    private static let homeEcho = ["page-echo": "tab-beta"]

    /// The selected tab as the bar shows it: the controller's selection, the item VoiceOver reads, and the stack on top.
    private func assertHomeSelected(_ host: UKServerUIRenderer, _ page: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(host.navigation.snapshot.selection, Self.beta, file: file, line: line)
        XCTAssertTrue(host.tabController.selectedViewController === host.stacks[Self.beta], "The tab bar selects Home", file: file, line: line)
        XCTAssertEqual(host.tabController.selectedViewController?.tabBarItem.title, "Shelf", "The selected item reads as Home", file: file, line: line)
        XCTAssertEqual((host.stacks[Self.beta]?.topViewController as? UKServerUIPage)?.surfaceID, page, file: file, line: line)
    }

    func testAHomedPageLinkedFromASheetLandsOnItsHomeTabAndLeavesTheOtherTabAlone() throws {
        let (host, _) = try host(homed: Self.homeEcho)
        let sheet = try openSheet(host, from: ServerUIRendererFixture.root(host))
        host.activate(push(Self.echo), from: sheet)
        let landed = spin({ host.modal == nil && host.navigation.snapshot.presentations.isEmpty && host.navigation.snapshot.selection == Self.beta })
        XCTAssertTrue(landed, "The sheet closed and the home tab is showing")
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.beta], ["page-lattice", Self.echo], "On top of the home tab's stack")
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit"], "The tab it came from keeps its stack")
        assertHomeSelected(host, Self.echo)
    }

    func testAHomedPagePushedFromAPageLandsOnItsHomeTabAndALaterLinkReusesIt() throws {
        let (host, _) = try host(homed: Self.homeEcho)
        let root = try ServerUIRendererFixture.root(host)
        try host.perform(push(Self.echo), from: root)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.beta], ["page-lattice", Self.echo])
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit"])
        assertHomeSelected(host, Self.echo)
        // Back to the first tab, then the same link again: the page is reused, not pushed twice.
        try host.perform(.selectTab(tabId: "tab-alpha"), from: try XCTUnwrap(host.stacks[Self.beta]?.topViewController as? UKServerUIPage))
        XCTAssertEqual(host.navigation.snapshot.selection, Self.tab)
        try host.perform(push(Self.echo), from: root)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.beta], ["page-lattice", Self.echo])
        assertHomeSelected(host, Self.echo)
    }

    func testAnUnhomedPageAndAPageOnTheTabShowingOpenWhereTheLinkIs() throws {
        let (plain, _) = try host()
        let sheet = try openSheet(plain, from: ServerUIRendererFixture.root(plain))
        plain.activate(push(Self.echo), from: sheet)
        XCTAssertTrue(settledOnPage(plain, Self.echo))
        XCTAssertEqual(plain.navigation.snapshot.selection, Self.tab)
        XCTAssertEqual(plain.navigation.snapshot.stacks[Self.tab], ["page-orbit", Self.echo])
        XCTAssertEqual(plain.navigation.snapshot.stacks[Self.beta], ["page-lattice"])
        HostedPage.hideTracked()
        let (here, _) = try host(homed: [Self.echo: "tab-alpha"])
        try here.perform(push(Self.echo), from: ServerUIRendererFixture.root(here))
        XCTAssertEqual(here.navigation.snapshot.selection, Self.tab, "A page homed on the tab showing is a plain push")
        XCTAssertEqual(here.navigation.snapshot.stacks[Self.tab], ["page-orbit", Self.echo])
    }

    func testCancellingTheExitPromptKeepsTheSheetAndTheTabWhenThePageIsHomedElsewhere() throws {
        let (host, draft) = try formHost(homed: true)
        let sheet = try openSheet(host, from: ServerUIRendererFixture.root(host))
        let session = spin({ sheet.formView?.session === draft })
        XCTAssertTrue(session)
        try draft.set(.string("Edited"), group: "item", field: "name")
        host.activate(push(Self.echo), from: sheet)
        let asked = spin({ sheet.presentedViewController is UIAlertController })
        XCTAssertTrue(asked, "Unsaved changes ask before the sheet closes and the tab changes")
        let alert = try XCTUnwrap(sheet.presentedViewController as? UIAlertController)
        FeatureHost.answer(alert, try XCTUnwrap(alert.actions.first { $0.style == .cancel }?.title))
        HostedPage.wait(0.3)
        XCTAssertNotNil(host.modal, "Cancel keeps the sheet")
        XCTAssertEqual(host.navigation.snapshot.selection, Self.tab, "Cancel keeps the tab")
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.beta], ["page-lattice"])
    }

    // MARK: Unsaved changes on the tab being left

    /// The first tab's root page with a dirty form, and the sheet over it.
    private func dirtyLeavingTab(homedOn: String = "tab-beta") throws -> (UKServerUIRenderer, UKServerUIPage, UKServerUIPage, ServerUIValueForm) {
        let (host, draft) = try formHost(homed: true, homedOn: homedOn, formOnPage: true)
        let root = try ServerUIRendererFixture.root(host)
        let session = spin({ root.formView?.session === draft })
        XCTAssertTrue(session, "The root page opened the form")
        try draft.set(.string("Edited"), group: "item", field: "name")
        return (host, root, try openSheet(host, from: root), draft)
    }

    private func askedAlert(from page: UKServerUIPage) throws -> UIAlertController {
        let asked = spin({ page.presentedViewController is UIAlertController })
        XCTAssertTrue(asked, "Unsaved changes on the tab being left ask first")
        return try XCTUnwrap(page.presentedViewController as? UIAlertController)
    }

    /// Cancel keeps the sheet, the tab and the edit; Discard lets the link through to the home tab.
    private func assertAsksThenLands(_ host: UKServerUIRenderer, alert: UIAlertController, draft: ServerUIValueForm, sheetOpen: Bool) throws {
        FeatureHost.answer(alert, try XCTUnwrap(alert.actions.first { $0.style == .cancel }?.title))
        HostedPage.wait(0.3)
        XCTAssertEqual(host.modal != nil, sheetOpen, "Cancel keeps the sheet as it was")
        XCTAssertEqual(host.navigation.snapshot.selection, Self.tab, "Cancel keeps the tab")
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.beta], ["page-lattice"])
        XCTAssertTrue(draft.hasChanges, "Cancel keeps the edit")
    }

    func testADirtyFormOnTheLeavingTabAsksBeforeASheetLinkReachesAnotherTabsPage() throws {
        let (host, root, sheet, draft) = try dirtyLeavingTab()
        host.activate(push(Self.echo), from: sheet)
        try assertAsksThenLands(host, alert: try askedAlert(from: sheet), draft: draft, sheetOpen: true)
        host.activate(push(Self.echo), from: sheet)
        let alert = try askedAlert(from: sheet)
        try discardAndExpect(host, alert: alert, from: sheet, link: push(Self.echo), "Discard closes the sheet and lands on the home tab") {
            host.modal == nil && host.navigation.snapshot.presentations.isEmpty && host.navigation.snapshot.selection == Self.beta
        }
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.beta], ["page-lattice", Self.echo])
        XCTAssertFalse(draft.hasChanges, "The leaving tab's edit was discarded")
        XCTAssertNotNil(root.view)
    }

    func testADirtyFormOnTheLeavingTabAsksBeforeAPushReachesAnotherTabsPage() throws {
        let (host, draft) = try formHost(homed: true, formOnPage: true)
        let root = try ServerUIRendererFixture.root(host)
        let session = spin({ root.formView?.session === draft })
        XCTAssertTrue(session)
        try draft.set(.string("Edited"), group: "item", field: "name")
        host.activate(push(Self.echo), from: root)
        try assertAsksThenLands(host, alert: try askedAlert(from: root), draft: draft, sheetOpen: false)
        host.activate(push(Self.echo), from: root)
        let alert = try askedAlert(from: root)
        try discardAndExpect(host, alert: alert, from: root, link: push(Self.echo), "Discard lands on the home tab and the page") {
            host.navigation.snapshot.selection == Self.beta && host.navigation.snapshot.stacks[Self.beta] == ["page-lattice", Self.echo]
        }
        XCTAssertFalse(draft.hasChanges)
    }

    /// The same Discard with every animation slowed to a tenth, and the alert answered the moment it is up: the replay must still land
    /// once the alert's dismissal finishes, however long that takes.
    func testDiscardOnASlowlyDismissedAlertStillLandsTheLink() throws {
        animationSpeed = 0.1
        let (host, draft) = try formHost(homed: true, formOnPage: true)
        let root = try ServerUIRendererFixture.root(host)
        let session = spin({ root.formView?.session === draft })
        XCTAssertTrue(session)
        try draft.set(.string("Edited"), group: "item", field: "name")
        host.activate(push(Self.echo), from: root)
        let alert = try askedAlert(from: root)
        try discardAndExpect(host, alert: alert, from: root, link: push(Self.echo), settled: false, "A slow Discard lands on the home tab and the page") {
            host.navigation.snapshot.selection == Self.beta && host.navigation.snapshot.stacks[Self.beta] == ["page-lattice", Self.echo]
        }
    }

    /// The control: a page homed on the tab showing, or on no tab, is a same-tab push and keeps the leaving form out of the exit.
    func testADirtyFormOnTheTabShowingDoesNotAskForASameTabLink() throws {
        let (host, root, sheet, draft) = try dirtyLeavingTab(homedOn: "tab-alpha")
        host.activate(push(Self.echo), from: sheet)
        let landed = settledOnPage(host, Self.echo)
        XCTAssertTrue(landed, "The sheet closed with no prompt")
        XCTAssertEqual(host.navigation.snapshot.selection, Self.tab)
        XCTAssertTrue(draft.hasChanges, "The tab was not left, so its edit stays")
        XCTAssertNil(root.presentedViewController)
        let (flat, flatDraft) = try formHost(homed: true, homedOn: "tab-alpha", formOnPage: true)
        let flatRoot = try ServerUIRendererFixture.root(flat)
        let opened = spin({ flatRoot.formView?.session === flatDraft })
        XCTAssertTrue(opened)
        try flatDraft.set(.string("Edited"), group: "item", field: "name")
        try flat.perform(push(Self.echo), from: flatRoot)
        XCTAssertEqual(flat.navigation.snapshot.stacks[Self.tab], ["page-orbit", Self.echo], "A push on the tab showing needs no prompt")
    }

    func testBackFromTheLandedPagePopsWithinHomeAndSettingsKeepsItsPageWithNoSheet() throws {
        let (host, _) = try host(homed: Self.homeEcho)
        let sheet = try openSheet(host, from: ServerUIRendererFixture.root(host))
        host.activate(push(Self.echo), from: sheet)
        let landed = spin({ host.modal == nil && host.navigation.snapshot.selection == Self.beta })
        XCTAssertTrue(landed)
        let page = try XCTUnwrap(host.stacks[Self.beta]?.topViewController as? UKServerUIPage)
        try host.perform(.back, from: page)
        let popped = spin({ host.navigation.snapshot.stacks[Self.beta] == ["page-lattice"] })
        XCTAssertTrue(popped, "Back pops within Home's stack")
        XCTAssertEqual(host.navigation.snapshot.selection, Self.beta, "Back does not return to the tab the link was tapped on")
        try host.perform(.selectTab(tabId: "tab-alpha"), from: try XCTUnwrap(host.stacks[Self.beta]?.topViewController as? UKServerUIPage))
        XCTAssertEqual(host.navigation.snapshot.selection, Self.tab)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit"], "Settings shows the page the sheet opened over")
        XCTAssertTrue(host.navigation.snapshot.presentations.isEmpty)
        XCTAssertNil(host.modal, "with the sheet closed")
    }

    func testAHomedPageAlreadyInHomesStackIsPoppedToAndTheLandingIsAnnounced() throws {
        let (host, _) = try host(homed: Self.homeEcho)
        var spoken: [String] = []
        Announcer.sink = { spoken.append($0) }
        defer { Announcer.sink = nil }
        let root = try ServerUIRendererFixture.root(host)
        try host.perform(push(Self.echo), from: root)
        XCTAssertTrue(spoken.contains { $0.hasPrefix("screenChanged") }, "VoiceOver is told the screen changed")
        let echo = try XCTUnwrap(host.stacks[Self.beta]?.topViewController as? UKServerUIPage)
        try host.perform(push("page-orbit"), from: echo)
        let deeper = spin({ host.navigation.snapshot.stacks[Self.beta] == ["page-lattice", Self.echo, "page-orbit"] })
        XCTAssertTrue(deeper)
        try host.perform(.selectTab(tabId: "tab-alpha"), from: try XCTUnwrap(host.stacks[Self.beta]?.topViewController as? UKServerUIPage))
        try host.perform(push(Self.echo), from: root)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.beta], ["page-lattice", Self.echo], "Popped to the page, not pushed again")
        assertHomeSelected(host, Self.echo)
    }

    func testAHiddenHomeTabFallsBackToTheTabShowing() throws {
        let (host, _) = try host(homed: Self.homeEcho, hideBeta: true)
        XCTAssertFalse(host.isTabShown("tab-beta"), "The home tab's rule is false")
        let sheet = try openSheet(host, from: ServerUIRendererFixture.root(host))
        host.activate(push(Self.echo), from: sheet)
        let landed = settledOnPage(host, Self.echo)
        XCTAssertTrue(landed)
        XCTAssertEqual(host.navigation.snapshot.selection, Self.tab)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit", Self.echo])
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.beta], ["page-lattice"])
    }

    func testAnAdaptiveColumnIsRemovedWhenAHomedPageLeavesForItsHomeTab() throws {
        let (host, _) = try host(adaptive: true, homed: Self.homeEcho)
        host.columnGeometryChanged()
        let root = try ServerUIRendererFixture.root(host)
        try host.perform(.present(modalId: Self.modal, arguments: .init(), ifPresented: .reject), from: root)
        let opened = spin({ (root.columns?.entries.last?.controller as? UKServerUIPage)?.presentationID != nil })
        XCTAssertTrue(opened, "The adaptive sheet opens as a column")
        let column = try XCTUnwrap(root.columns?.entries.last?.controller as? UKServerUIPage)
        host.activate(push(Self.echo), from: column)
        let landed = spin({ host.navigation.snapshot.presentations.isEmpty && host.navigation.snapshot.selection == Self.beta })
        XCTAssertTrue(landed)
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.beta], ["page-lattice", Self.echo])
        XCTAssertEqual(host.navigation.snapshot.stacks[Self.tab], ["page-orbit"])
        XCTAssertFalse(root.columns?.entries.contains { ($0.controller as? UKServerUIPage)?.presentationID != nil } == true, "The column is gone from the tab it left")
        assertHomeSelected(host, Self.echo)
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
