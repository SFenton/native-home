@testable import HassCore
import HassDesign
import Observation
import UIKit
import XCTest
@testable import HassUI

// MARK: - Shared shell journeys

@MainActor @Observable
private final class ShellPresentationState {
    var title = "Guest Summary"
    var header = "Checklist"
    var footer = ""
    var detail = "1 of 3"
    var visible = true
    var enabled = false
    var busy = false
}

/// Hosted, synthetic-only journeys; run unchanged on the parent's iPhone, Duo and iPad destinations.
@MainActor
final class ServerUIShellRendererTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func fixture(pinned: Bool = false, header: Bool = false, atoms: Bool = false, coordinated: Bool = false) throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shell = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIShellFixture.json")))
        var root = try ServerUIRendererFixture.json()
        root = try ServerUIRendererFixture.changing(root, path: "/document/navigation/chrome/groups/1/items/0/priority", to: .string("normal"))
        root = try ServerUIRendererFixture.changing(root, path: "/document/localState", to: XCTUnwrap(shell["localState"]))
        let original = try XCTUnwrap(root["document"]?["pages"]?.array?.first?["components"]?.array)
        var components = try XCTUnwrap(shell["components"]?.array)
        if pinned {
            guard case .object(var section) = components[0], case .array(let children)? = section["children"],
                  case .object(var tabs) = children[5], case .object(var props)? = tabs["props"],
                  case .array(let panels)? = tabs["tabs"] else { throw ServerUIRecordFailure.invalidField }
            props["pinned"] = .bool(true); props["resetOnPresentation"] = .bool(true)
            tabs["props"] = .object(props)
            tabs["tabs"] = .array(try panels.map { panel in
                guard case .object(var panel) = panel else { throw ServerUIRecordFailure.invalidField }
                panel["icon"] = root["document"]?["pages"]?.array?.first?["icon"]
                return .object(panel)
            })
            section["children"] = .array(Array(children.prefix(5)) + Array(children.dropFirst(6)))
            components = [.object(section), .object(tabs)]
        }
        if atoms {
            let values = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIShellAtomsFixture.json")))
            components += try XCTUnwrap(values.array)
        }
        if coordinated {
            let addition = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIPresentationFixture.json")))
            components += try XCTUnwrap(addition["components"]?.array)
            let state = try XCTUnwrap(shell["localState"]?.array) + XCTUnwrap(addition["localState"]?.array)
            root = try ServerUIRendererFixture.changing(root, path: "/document/localState", to: .array(state))
            root = try ServerUIRendererFixture.changing(root, path: "/document/modals/0/presentation/fullScreen", to: .bool(true))
        }
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(original + components))
        if header {
            let modalID = try XCTUnwrap(root["document"]?["modals"]?.array?.first?["id"])
            let action = JSONValue.object(["type": .string("present"), "modalId": modalID, "arguments": .object([:]), "ifPresented": .string("reject")])
            root = try ServerUIRendererFixture.changing(root, path: "/document/navigation/chrome/groups/1/items",
                to: .array([.object(["id": .string("native-header"), "type": .string("shell-header"), "visibility": .string("always"),
                                    "quickLinksAction": action, "profileAction": action])]))
        }
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities + [
            "sh.section@1", "sh.rows@1", "sh.local-tabs@1", "sh.local-state@1",
            "sh.local-controls@1", "sh.primary-button@1", "sh.row-collection@1"
        ] + (pinned ? ["sh.pinned-tabs@1"] : []) + (header ? ["sh.shell-header@1"] : [])
          + (atoms ? ["sh.info-box@1", "sh.status-pill@1", "sh.paged-row@1"] : [])
          + (coordinated ? ["sh.presentation-providers@1", "sh.section-grid@1", "sh.pinned-form-actions@1",
                             "sh.pinned-actions@1", "sh.collection@1", "sh.full-screen-modal@1",
                             "sh.settings-link@1", "sh.module-settings-rows@1"] : [])
        return try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
    }

    func testNativeBackAndAncestorMenuWaitForSingleUseApproval() {
        let root = UIViewController(), detail = UIViewController(), leaf = UIViewController()
        let nav = UKNativeExitNavigationController(rootViewController: root)
        nav.setViewControllers([root, detail, leaf], animated: false)
        var approval: (() -> Void)?
        var leaving: [UIViewController] = []
        nav.requestPop = { leaving = $0; approval = $1 }
        XCTAssertNil(nav.popViewController(animated: false))
        XCTAssertTrue(nav.topViewController === leaf)
        XCTAssertEqual(leaving, [leaf])
        let firstApproval = approval
        approval?()
        XCTAssertTrue(nav.topViewController === detail)
        approval?()
        XCTAssertTrue(nav.topViewController === detail)
        XCTAssertNil(nav.popToRootViewController(animated: false))
        XCTAssertEqual(leaving, [detail])
        XCTAssertTrue(nav.topViewController === detail)
        approval?()
        XCTAssertTrue(nav.topViewController === root)
        nav.setViewControllers([root, detail], animated: false)
        XCTAssertNil(nav.popViewController(animated: false))
        nav.setViewControllers([root, detail, leaf], animated: false)
        approval?()
        XCTAssertTrue(nav.topViewController === leaf, "An old approval must not remove a newly pushed page")
        firstApproval?()
        XCTAssertTrue(nav.topViewController === leaf, "A used approval cannot pop the same controller after it is pushed again")
        XCTAssertNil(nav.popToRootViewController(animated: false))
        XCTAssertEqual(leaving, [detail, leaf], "Ancestor admission includes every page being removed")
    }

    func testScopedGuestPanelsDoNotRequireOrMountPersonalProvidersAndKeepLiveFormFocus() async throws {
        for width in [390.0, 744.0, 1024.0] {
            let state = ShellPresentationState()
            let records = UKServerUIRecords(
                sections: ["live-section": { .init(header: state.header, footer: state.footer, detail: state.detail, visible: state.visible) }],
                tabScopes: ["summary": .init(allowedTabIDs: ["profile"], initialTabID: "profile", title: { state.title })],
                actionStates: ["save-state": { .init(enabled: state.enabled, busy: state.busy) }])
            let publication = try ServerUIRendererFixture.publication(fixture(coordinated: true))
            let rows = ServerUIRowCollection()
            let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
                backdrop: ServerUIRendererFixture.backdrop(), collections: ["sample-items": rows], records: records)
            let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 900)))
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(host)
            XCTAssertEqual(host.localState.values["summary-panel"], .string("profile"))
            XCTAssertNil(page.nodes["personal-items"], "A guest must never mount a personal task provider")
            XCTAssertEqual(page.title, "Guest Summary")
            let pinnedHeight = page.additionalSafeAreaInsets.bottom
            XCTAssertGreaterThan(pinnedHeight, 0)
            XCTAssertLessThan(pinnedHeight, page.view.bounds.height)
            for _ in 0..<3 {
                page.view.setNeedsLayout()
                page.view.layoutIfNeeded()
                XCTAssertEqual(page.additionalSafeAreaInsets.bottom, pinnedHeight, accuracy: 0.5,
                               "A pinned form must not measure its own safe-area inset as content.")
            }
            let section = try XCTUnwrap(page.nodes["live-section"]?.view)
            let grid = try XCTUnwrap(page.nodes["section-grid"]?.view as? UKDynamicGridView)
            page.view.layoutIfNeeded()
            grid.layoutIfNeeded()
            let minimum = UKFont.scaled(340, relativeTo: .body, traits: grid.traitCollection)
            if grid.bounds.width >= minimum * 2 + HassTokens.Spacing.xl {
                XCTAssertEqual(grid.items.count, 2)
                for item in grid.items { XCTAssertGreaterThanOrEqual(item.view.bounds.width, minimum - 0.5) }
                XCTAssertEqual(grid.items[0].view.frame.minY, grid.items[1].view.frame.minY, accuracy: 0.5)
            } else {
                XCTAssertGreaterThan(grid.items[1].view.frame.minY, grid.items[0].view.frame.minY)
            }
            let control = try XCTUnwrap(page.nodes["shell-name"]?.view)
            let field = try XCTUnwrap(HostedPage.descendants(of: control).compactMap { $0 as? UITextField }.first)
            field.becomeFirstResponder()
            let save = try XCTUnwrap(HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "form-save" } as? UKPrimaryButton)
            XCTAssertFalse(save.isEnabled)
            state.header = "Updated Checklist"; state.footer = "Updated Footer"; state.detail = "2 of 3"
            state.enabled = true
            for _ in 0..<4 { await Task.yield() }
            XCTAssertTrue(save.isEnabled)
            XCTAssertTrue(field.isFirstResponder)
            let text = HostedPage.descendants(of: section).compactMap { ($0 as? UILabel)?.text }
            XCTAssertTrue(text.contains("Updated Checklist") && text.contains("Updated Footer") && text.contains("2 of 3"))
            state.busy = true; state.visible = false
            for _ in 0..<4 { await Task.yield() }
            XCTAssertFalse(save.isEnabled)
            XCTAssertTrue(save.isBusy)
            XCTAssertFalse(grid.items.contains { $0.view === section })
            state.visible = true
            for _ in 0..<4 { await Task.yield() }
            XCTAssertTrue(grid.items.contains { $0.view === section })
            XCTAssertTrue(page.nodes["live-section"]?.view === section)
            HostedPage.hideTracked()
        }
    }

    func testWideColumnExitUsesTheDomainAdmissionRatherThanDiscardingItDirectly() throws {
        let (host, page, _) = try host()
        var dirty = true, canDiscard = true, requested = false, exited = false
        var approval: (() -> Void)?
        host.nativeExitGate = .init(blocksExit: { _ in dirty }, request: { _, completion in
            requested = true; approval = completion
        }, canDiscard: { _ in canDiscard })
        XCTAssertEqual(page.columnPopDecision, .confirmDiscard)
        page.requestColumnExit { exited = true }
        XCTAssertTrue(requested)
        XCTAssertFalse(exited)
        canDiscard = false
        XCTAssertEqual(page.columnPopDecision, .block)
        dirty = false
        approval?()
        XCTAssertTrue(exited)
    }

    private func host() throws -> (UKServerUIRenderer, UKServerUIPage, ServerUIRowCollection) {
        let rows = ServerUIRowCollection()
        try rows.apply([.init(id: "first", title: "First", value: "Ready")], phase: .ready)
        let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(fixture()),
                                          context: UKContext(store: EntityStore()), backdrop: ServerUIRendererFixture.backdrop(),
                                          collections: ["sample-items": rows])
        _ = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: 390, height: 844)))
        return (host, try ServerUIRendererFixture.root(host), rows)
    }

    func testNativePreflightRejectsUnregisteredCollectionsRatherThanDrawingAPlaceholder() throws {
        let publication = try ServerUIRendererFixture.publication(fixture())
        XCTAssertThrowsError(try UKServerUIRenderer.preflight(publication)) { error in
            XCTAssertEqual((error as? UKServerUIRendererError)?.code, .unavailableSource)
        }
    }

    func testLocalEditsAndLastGoodCollectionSurviveCompatiblePublicationWithoutReplacingNodes() throws {
        let (host, page, rows) = try host()
        let rowNode = try XCTUnwrap(page.nodes["shell-rows"]?.view as? UKServerUIRowCollection)
        let first = try XCTUnwrap(rowNode.rows["first"])
        try host.perform(.setLocal(stateId: "enabled", value: .boolean(true)), from: page)
        try rows.apply(nil, phase: .failed)
        HostedPage.wait(0.05)
        XCTAssertTrue(rowNode.rows["first"] === first)
        var candidate = try fixture()
        candidate = try ServerUIRendererFixture.changing(candidate, path: "/revision", to: .number(2))
        try host.apply(publication: ServerUIRendererFixture.publication(candidate), backdrop: ServerUIRendererFixture.backdrop())
        XCTAssertEqual(host.localState.values["enabled"], .boolean(true))
        XCTAssertTrue(page.nodes["shell-rows"]?.view === rowNode)
        XCTAssertTrue(rowNode.rows["first"] === first)
    }

    func testAccessibilityAndFocusGuardAtAX5AndRTL() throws {
        let (host, page, _) = try host()
        host.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge),
                                        forChild: host.tabController)
        page.view.semanticContentAttribute = .forceRightToLeft
        page.view.layoutIfNeeded()
        let toggle = try XCTUnwrap(find(UISwitch.self, in: XCTUnwrap(page.nodes["shell-toggle"]?.view)))
        XCTAssertEqual(toggle.accessibilityLabel, "Enabled")
        let stepper = try XCTUnwrap(find(UIStepper.self, in: XCTUnwrap(page.nodes["shell-stepper"]?.view)))
        XCTAssertEqual(stepper.accessibilityLabel, "Count")
        XCTAssertEqual(stepper.accessibilityValue, "2")
        let button = try XCTUnwrap((page.nodes["shell-button"]?.view as? UKServerUIPrimaryButton)?.button)
        XCTAssertEqual(button.accessibilityLabel, "Enable sample")
        XCTAssertEqual(button.accessibilityIdentifier, "shell-button")
        XCTAssertTrue(button.accessibilityTraits.contains(.button))
        let field = try XCTUnwrap(find(UITextField.self, in: XCTUnwrap(page.nodes["shell-name"]?.view)))
        XCTAssertEqual(field.accessibilityLabel, "Name")
        XCTAssertTrue(field.becomeFirstResponder())
        XCTAssertThrowsError(try host.validateUpdate(host.publication)) { error in
            XCTAssertEqual((error as? UKServerUIRendererError)?.code, .interactionBlocked)
        }
        XCTAssertTrue(field.isFirstResponder)
        field.resignFirstResponder()
    }

    func testLocalTabSwapRetainsNodesAndExcludesHiddenPanelsFromAccessibility() throws {
        let (host, page, _) = try host()
        let panels = try XCTUnwrap(page.nodes["shell-panels"]?.view as? UKServerUILocalTabs)
        let swap = try XCTUnwrap(find(UKSmoothContentSwapView<String>.self, in: panels))
        swap.timing.fadeOut = 0
        swap.timing.fadeIn = 0
        let details = try XCTUnwrap(page.nodes["shell-details"]?.view)
        let choice = try XCTUnwrap(page.nodes["shell-choice"]?.view)
        XCTAssertNotNil(details.window)
        XCTAssertNil(choice.window)
        XCTAssertGreaterThan(panels.gridHeight(forWidth: 320), 44)
        try host.perform(.setLocal(stateId: "panel", value: .string("options")), from: page)
        HostedPage.wait(0.1)
        XCTAssertNil(details.window)
        XCTAssertNotNil(choice.window)
        XCTAssertTrue(page.nodes["shell-details"]?.view === details)
        XCTAssertTrue(page.nodes["shell-choice"]?.view === choice)
    }

    func testPinnedTabMenuRetainsSelectionAndAccessibleHeightAtAllFamilyWidths() throws {
        for width in [390.0, 744.0, 1024.0] {
            let rows = ServerUIRowCollection()
            try rows.apply([], phase: .ready)
            let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(fixture(pinned: true)),
                context: UKContext(store: EntityStore()), backdrop: ServerUIRendererFixture.backdrop(), collections: ["sample-items": rows])
            _ = HostedPage.show(host, size: .init(width: width, height: 1180))
            let page = try ServerUIRendererFixture.root(host)
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            page.view.layoutIfNeeded()
            func menu(in view: UIView) -> UIView? {
                if view.accessibilityIdentifier == "shell-panels.tabs" { return view }
                return view.subviews.lazy.compactMap { menu(in: $0) }.first
            }
            let bar = try XCTUnwrap(menu(in: page.view))
            XCTAssertGreaterThanOrEqual(bar.bounds.height, 44)
            try host.perform(.setLocal(stateId: "panel", value: .string("options")), from: page)
            HostedPage.wait(0.1)
            XCTAssertEqual(host.localState.values["panel"], .string("options"))
            XCTAssertEqual(bar.accessibilityValue, "Options")
            let menuButton = try XCTUnwrap(bar as? UIButton)
            XCTAssertEqual(menuButton.configuration?.title, "Options")
            XCTAssertEqual(menuButton.menu?.children.compactMap { $0 as? UIAction }
                .filter { $0.state == .on }.map(\.title), ["Options"])
            XCTAssertTrue(HostedPage.until(2) { page.nodes["shell-choice"]?.view.window != nil })
            HostedPage.hideTracked()
        }
    }

    func testNativeShellHeaderRequiresReadProviderAndUpdatesCountAndReconnectState() throws {
        let publication = try ServerUIRendererFixture.publication(fixture(header: true))
        let rows = ServerUIRowCollection()
        try rows.apply([], phase: .ready)
        XCTAssertThrowsError(try UKServerUIRenderer.preflight(publication, collections: ["sample-items": rows]))
        let state = ShellRecordSource()
        let source = UKServerUIShellHeaderSource(state: {
            .init(profileName: "Example Person", attentionCount: state.items.count, isOffline: state.failure != nil,
                  reconnectingPresent: state.failure != nil, reconnectingLit: state.failure != nil)
        })
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
            backdrop: ServerUIRendererFixture.backdrop(), collections: ["sample-items": rows], shellHeader: source)
        _ = HostedPage.show(host, size: .init(width: 390, height: 844))
        let page = try ServerUIRendererFixture.root(host)
        func trailingItems() -> [UIBarButtonItem] {
            let grouped = page.navigationItem.trailingItemGroups.flatMap(\.barButtonItems)
            return grouped.isEmpty ? page.navigationItem.rightBarButtonItems ?? [] : grouped
        }
        let before = trailingItems().count
        let profile = try XCTUnwrap(trailingItems().first {
            $0.customView is UKProfileButtonView || $0.accessibilityIdentifier == "nav.profile"
        })
        // VoiceOver reads the profile button inside the bar item's view (the view itself is not an element).
        func spokenValue() -> String? {
            (profile.customView?.accessibilityElements?.first as? UIView)?.accessibilityValue
                ?? profile.customView?.accessibilityValue ?? profile.accessibilityValue
        }
        let beforeValue = spokenValue()
        XCTAssertNotNil(beforeValue)
        state.items = []
        state.failure = "Offline"
        HostedPage.wait(0.1)
        XCTAssertGreaterThan(trailingItems().count, before)
        XCTAssertNotEqual(spokenValue(), beforeValue)
        XCTAssertTrue(spokenValue()?.contains("Offline") == true, "VoiceOver hears the reconnect state")
    }

    func testExternalRouteUsesTheAuthoredCatalogAndRejectsAnUnknownPage() throws {
        let (host, _, _) = try host()
        let tab = try XCTUnwrap(host.publication.document.navigation.tabs.first)
        let destination = host.publication.document.pages[1].id
        try host.routeExternal(tabID: tab.id, pageID: destination)
        XCTAssertEqual(host.navigation.snapshot.stacks[.tab(tab.id)]?.last, destination)
        XCTAssertThrowsError(try host.routeExternal(tabID: tab.id, pageID: "not-in-the-publication"))
    }

    func testNativePagingNoticesAndStatusRemainMeasuredAccessibleAndRetained() throws {
        for width in [390.0, 744.0, 1024.0] {
            let rows = ServerUIRowCollection()
            try rows.apply([], phase: .ready)
            let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(fixture(atoms: true)),
                context: UKContext(store: EntityStore()), backdrop: ServerUIRendererFixture.backdrop(), collections: ["sample-items": rows])
            _ = HostedPage.show(host, size: .init(width: width, height: 1180))
            let page = try ServerUIRendererFixture.root(host)
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            let pager = try XCTUnwrap(page.nodes["shell-pages"]?.view as? UKServerUIPagedRow)
            XCTAssertGreaterThan(pager.gridHeight(forWidth: width - 32), 44)
            page.view.layoutIfNeeded()
            let row = try XCTUnwrap(find(UKPagedRowView.self, in: pager))
            XCTAssertEqual(row.perPage, 1)
            let notice = try XCTUnwrap(page.nodes["shell-notice"]?.view as? UKServerUIInfoBox)
            XCTAssertGreaterThan(notice.gridHeight(forWidth: width - 32), 44)
            let pill = try XCTUnwrap(page.nodes["shell-pill-a"]?.view as? UKStatusPillView)
            XCTAssertEqual(pill.accessibilityLabel, "Controller")
            XCTAssertEqual(pill.accessibilityValue, "Ready")
            var updated = try fixture(atoms: true)
            updated = try ServerUIRendererFixture.changing(updated, path: "/revision", to: .number(2))
            try host.apply(publication: ServerUIRendererFixture.publication(updated), backdrop: ServerUIRendererFixture.backdrop())
            XCTAssertTrue(find(UKPagedRowView.self, in: pager) === row)
            XCTAssertTrue(page.nodes["shell-pill-a"]?.view === pill)
            let components = try XCTUnwrap(updated["document"]?["pages"]?.array?.first?["components"]?.array)
            let index = try XCTUnwrap(components.firstIndex { $0["id"]?.string == "shell-pages" })
            let children = try XCTUnwrap(components[index]["children"]?.array)
            updated = try ServerUIRendererFixture.changing(updated, path: "/document/pages/0/components/\(index)/children",
                to: .array(Array(children.reversed())))
            updated = try ServerUIRendererFixture.changing(updated, path: "/revision", to: .number(3))
            try host.apply(publication: ServerUIRendererFixture.publication(updated), backdrop: ServerUIRendererFixture.backdrop())
            XCTAssertEqual(find(UKPagedRowView.self, in: pager)?.firstVisible, 1)
            XCTAssertTrue(page.nodes["shell-pill-a"]?.view === pill)
            HostedPage.hideTracked()
        }
    }

    func testScheduleDraftUsesNativeBoundedPickersAtAllFamilyWidths() async throws {
        for width in [390.0, 744.0, 1024.0] {
            var fixture = try recordFixture()
            let fields: [JSONValue] = ["start", "end"].map { .object([
                "key": .string($0), "label": .string($0.capitalized), "control": .string("schedule-date-time"),
            ]) }
            fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/pages/0/components/1/props/fields", to: .array(fields))
            let capabilities = try XCTUnwrap(fixture["capabilities"]?.array)
            fixture = try ServerUIRendererFixture.changing(fixture, path: "/capabilities",
                to: .array((capabilities.compactMap(\.string) + ["sh.schedule-date-fields@1"]).sorted().map(JSONValue.string)))
            var end = ServerUIFormValue.number("end", "End", 1_800_000_060, minimum: 1_700_000_000, maximum: 1_900_000_000, control: .scheduleDateTime)
            end.enabled = false
            let session = try ServerUIValueForm(identity: .init(ownerId: "schedule", recordId: "range"), fields: [
                .number("start", "Start", 1_800_000_000, minimum: 1_700_000_000, maximum: 1_900_000_000, control: .scheduleDateTime), end,
            ]) { _ in }
            let records = UKServerUIRecords(collections: ["demo-items": ShellRecordSource()], forms: [
                "demo-edit": .init(fields: ["start": .scheduleDateTime, "end": .scheduleDateTime], selectionOnly: false, open: { session }),
            ])
            let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(fixture), context: UKContext(store: EntityStore()),
                backdrop: ServerUIRendererFixture.backdrop(), records: records)
            _ = HostedPage.show(host, size: .init(width: width, height: 1180))
            for _ in 0..<10 { await Task.yield() }
            let page = try ServerUIRendererFixture.root(host)
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            let form = try XCTUnwrap(page.formView)
            XCTAssertGreaterThan(form.gridHeight(forWidth: width - 32), 44)
            let picker = try XCTUnwrap(find(UIDatePicker.self, in: form))
            XCTAssertEqual(picker.minimumDate, Date(timeIntervalSince1970: 1_700_000_000))
            XCTAssertEqual(picker.maximumDate, Date(timeIntervalSince1970: 1_900_000_000))
            try session.set(.number(1_800_000_120), group: "range", field: "start")
            XCTAssertTrue(session.hasChanges)
            XCTAssertEqual(session.values["end"], .number(1_800_000_060))
            HostedPage.hideTracked()
        }
    }

    func testRealFormDraftCollectionIdentityAndAccessibilityAtAllFamilyWidths() async throws {
        for width in [390.0, 744.0, 1024.0] {
            let source = ShellRecordSource()
            let form = try ServerUIValueForm(identity: .init(ownerId: "demo", recordId: "item"),
                fields: [.text("name", "Name", "Original", required: true), .toggle("enabled", "Enabled", false)]) { _ in }
            let records = UKServerUIRecords(collections: ["demo-items": source], forms: [
                "demo-edit": .init(fields: ["name": .text, "enabled": .toggle], selectionOnly: false, open: { form }),
            ])
            let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(recordFixture()),
                context: UKContext(store: EntityStore()), backdrop: ServerUIRendererFixture.backdrop(), records: records)
            _ = HostedPage.show(host, size: .init(width: width, height: 1180))
            for _ in 0..<10 { await Task.yield() }
            let page = try ServerUIRendererFixture.root(host)
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            page.view.layoutIfNeeded()
            let nativeForm = try XCTUnwrap(page.formView)
            XCTAssertTrue(nativeForm.session === form)
            var replacedFactory = records
            replacedFactory.forms["demo-edit"] = .init(fields: ["name": .text, "enabled": .toggle], selectionOnly: false) {
                throw ServerUIRecordFailure.staleSelection
            }
            XCTAssertThrowsError(try host.validateUpdate(host.publication, records: replacedFactory),
                                 "Even a pristine open form keeps the exact factory and target it opened.")
            XCTAssertTrue(host.records.collections["demo-items"] === source)
            XCTAssertTrue(nativeForm.session === form)
            XCTAssertGreaterThan(nativeForm.gridHeight(forWidth: width - 32), 44)
            let field = try XCTUnwrap(find(UITextField.self, in: nativeForm))
            XCTAssertEqual(field.accessibilityLabel, "Name")
            XCTAssertGreaterThan(field.bounds.height, 0)
            let collection = try XCTUnwrap(page.nodes["record-list"]?.view as? UKServerUICollectionView)
            let first = try XCTUnwrap(collection.rows["first"])
            source.items.reverse()
            await HostedPage.pump(passes: 3)
            XCTAssertTrue(collection.rows["first"] === first)
            source.failure = "Offline"
            source.items = []
            await HostedPage.pump(passes: 3)
            XCTAssertTrue(collection.rows["first"] === first)
            try form.set(.string("Unsaved"), group: "item", field: "name")
            XCTAssertThrowsError(try host.validateUpdate(host.publication))
            XCTAssertThrowsError(try host.perform(.selectTab(tabId: "tab-home"), from: page))
            XCTAssertThrowsError(try host.routeExternal(tabID: "tab-home"))
            XCTAssertEqual(form.values["name"], .string("Unsaved"))
            try form.discard()
            HostedPage.hideTracked()
        }
    }

    func testFormFactoryMismatchFailsClosedBeforeOpeningControls() async throws {
        let publication = try ServerUIRendererFixture.publication(recordFixture())
        XCTAssertThrowsError(try UKServerUIRenderer.preflight(publication))
        let source = ShellRecordSource()
        let bad = UKServerUIRecords(collections: ["demo-items": source], forms: [
            "demo-edit": .init(fields: ["name": .number], selectionOnly: false, open: {
                throw ServerUIRecordFailure.missingProvider
            }),
        ])
        XCTAssertThrowsError(try UKServerUIRenderer.preflight(publication, records: bad))
    }

    func testRecordRegistryReplacementIsAtomicAndKeepsTheCollectionHost() throws {
        var json = try recordFixture()
        let components = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
            .filter { $0["type"]?.string != "form" }
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).filter { $0.string != "sh.form@1" }
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities))
        let publication = try ServerUIRendererFixture.publication(json)
        let original = ShellRecordSource()
        let records = UKServerUIRecords(collections: ["demo-items": original])
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
            backdrop: ServerUIRendererFixture.backdrop(), records: records)
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        let collection = try XCTUnwrap(page.nodes["record-list"]?.view as? UKServerUICollectionView)
        let incoming = ShellRecordSource()
        incoming.items = [.init(id: "new", title: "Replacement")]
        var replacement = records
        replacement.collections["demo-items"] = incoming
        original.hasPendingIntent = true
        XCTAssertThrowsError(try host.apply(publication: publication, backdrop: ServerUIRendererFixture.backdrop(), records: replacement))
        XCTAssertTrue(host.records.collections["demo-items"] === original)
        XCTAssertNotNil(collection.rows["first"])
        original.hasPendingIntent = false
        try host.apply(publication: publication, backdrop: ServerUIRendererFixture.backdrop(), records: replacement)
        XCTAssertTrue(host.records.collections["demo-items"] === incoming)
        XCTAssertTrue(page.nodes["record-list"]?.view === collection)
        XCTAssertNil(collection.rows["first"])
        XCTAssertNotNil(collection.rows["new"])
    }

    func testChangedSummaryScopeRetainsAllowedSelectionAndDropsRevokedPanel() throws {
        let publication = try ServerUIRendererFixture.publication(fixture(coordinated: true))
        let state = try ServerUILocalState(fields: publication.document.localState)
        let tabs = UKServerUILocalTabs()
        let definition = try XCTUnwrap(publication.document.pages.first?.surface.components.compactMap { component -> ServerUICompositionDocument.LocalTabs? in
            if case .localTabs(let value) = component, value.scopeProviderId == "summary" { return value }
            return nil
        }.first)
        let resident = UKServerUITabScope(allowedTabIDs: ["profile", "personal"], initialTabID: "profile")
        try tabs.prepareScope(resident, stateID: "summary-panel", state: state)
        XCTAssertEqual(state.values["summary-panel"], .string("profile"))
        try state.set(.string("personal"), for: "summary-panel")
        XCTAssertEqual(try tabs.resolveSelection(resident, stored: "personal", value: definition), "personal")
        try tabs.prepareScope(resident, stateID: "summary-panel", state: state)
        XCTAssertEqual(state.values["summary-panel"], .string("personal"))
        let guest = UKServerUITabScope(allowedTabIDs: ["profile"], initialTabID: "profile")
        try tabs.prepareScope(guest, stateID: "summary-panel", state: state)
        XCTAssertEqual(state.values["summary-panel"], .string("profile"))
        XCTAssertEqual(try tabs.resolveSelection(guest, stored: "profile", value: definition), "profile")
    }

    func testScannerRetriesOnlyRefreshAfterTheItemWasAdded() async throws {
        let server = EverShelfFixtureServer.sample()
        server.latency = .zero
        let model = ScanItemModel(space: .pantry, client: EverShelfClient(caller: server))
        var refreshes = 0
        let draft = UKServerUIScanForm(sourceID: "demo-inventory", model: model,
            camera: ScanCameraController(source: .unavailable)) {
            refreshes += 1
            if refreshes == 1 { throw ServerUIRecordFailure.unavailable("Offline") }
        }
        model.enterNameManually()
        model.setName("Demo Oats")
        model.goToReviewStep()
        XCTAssertTrue(draft.canSave)
        do { try await draft.save(); XCTFail("Expected refresh failure") }
        catch { XCTAssertEqual(error as? ServerUIRecordFailure, .unavailable("Offline")) }
        XCTAssertEqual(model.addStatus, .added)
        XCTAssertTrue(draft.canSave)
        XCTAssertFalse(draft.hasChanges)
        let writes = server.calls.filter { $0.hasPrefix("evershelf.add_scanned_item") }.count
        XCTAssertEqual(writes, 1)
        try await draft.save()
        XCTAssertEqual(refreshes, 2)
        XCTAssertEqual(server.calls.filter { $0.hasPrefix("evershelf.add_scanned_item") }.count, writes)
        XCTAssertFalse(draft.canSave)
        XCTAssertNil(draft.error)
    }

    func testInventoryUsesCanonicalGroupsAndDefaultResetWithoutWritingLivePreferences() async throws {
        let server = EverShelfFixtureServer.sample()
        server.latency = .zero
        let model = InventoryListModel(space: .pantry, client: EverShelfClient(caller: server))
        await model.load()
        let provider = try InventoryCompositionProvider(sourceID: "demo-inventory", space: .pantry, model: model)
        let source = UKServerUIInventoryCollection(provider)
        let draft = try await source.preferencesFactory(sort: true).open()
        try draft.set(.string(InventorySortMode.expiry.rawValue), group: "sort", field: "sort")
        XCTAssertEqual(model.sortMode, .title)
        try await draft.save()
        XCTAssertEqual(model.sortMode, .expiry)
        XCTAssertEqual(source.sections.map(\.title), InventorySections.make(provider.items, sort: .expiry, calendar: model.calendar).map(\.title))
        let reset = try await source.preferencesFactory(sort: true).open()
        try reset.reset()
        XCTAssertEqual(model.sortMode, .expiry)
        XCTAssertTrue(reset.hasChanges)
        try await reset.save()
        XCTAssertEqual(model.sortMode, .title)
    }

    func testColumnRoutesKeepTheSamePagesAndPathWhenTheWindowNarrows() async throws {
        var fixture = try ServerUIRendererFixture.json()
        let pages = try XCTUnwrap(fixture["document"]?["pages"]?.array)
        for index in pages.indices {
            fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/pages/\(index)/navigation", to: .object([
                "type": .string("navigation-columns"), "placeholder": .string("Select an Item"), "standalone": .bool(false),
            ]))
        }
        let capabilities = try XCTUnwrap(fixture["capabilities"]?.array)
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/capabilities",
            to: .array((capabilities.compactMap(\.string) + ["sh.navigation-columns@1"]).sorted().map(JSONValue.string)))
        let publication = try ServerUIRendererFixture.publication(fixture)
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
            backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host, size: HostedPage.splitSize)
        host.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .regular), forChild: host.tabController)
        await FeatureHost.settleAsync(0.1)
        let root = try ServerUIRendererFixture.root(host)
        let destination = try XCTUnwrap(publication.document.pages.first { $0.id != root.surfaceID }?.id)
        try host.perform(.push(.init(pageId: destination, arguments: .init(), origin: .sender, duplicate: .reuseNearest)), from: root)
        await FeatureHost.settleAsync(0.5)
        let columns = try XCTUnwrap(root.columns)
        XCTAssertTrue(columns.isWide)
        let detail = try XCTUnwrap(columns.entries.last?.controller as? UKServerUIPage)
        let snapshot = host.navigation.snapshot
        window.frame.size = HostedPage.inScene(.init(width: 744, height: 1100))
        host.view.setNeedsLayout()
        window.layoutIfNeeded()
        await FeatureHost.settleAsync(0.2)
        host.columnGeometryChanged()
        XCTAssertFalse(columns.isWide, "window \(window.bounds.size), renderer \(host.view.bounds.size), navigation \(String(describing: host.stacks[root.root]?.view.bounds.size))")
        XCTAssertEqual(host.navigation.snapshot, snapshot)
        XCTAssertTrue(host.stacks[root.root]?.topViewController === detail)
    }

    func testAdaptiveFormKeepsItsDraftAndInstanceAcrossSheetAndColumnHandoff() async throws {
        var fixture = try recordFixture()
        let components = try XCTUnwrap(fixture["document"]?["pages"]?.array?.first?["components"]?.array)
        var form = try XCTUnwrap(components.first { $0["type"]?.string == "form" })
        form = try ServerUIRendererFixture.changing(form, path: "/success", to: .object([
            "type": .string("dismiss"), "scope": .string("current-modal"),
        ]))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/pages/0/components",
            to: .array(components.filter { $0["type"]?.string != "form" }))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/pages/0/navigation", to: .object([
            "type": .string("navigation-columns"), "placeholder": .string("Select an Item"),
            "standalone": .bool(false), "onDemand": .bool(true),
        ]))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/modals/0/components", to: .array([form]))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/modals/0/presentation/adaptive", to: .bool(true))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/capabilities",
            to: .array(((try XCTUnwrap(fixture["capabilities"]?.array)).compactMap(\.string)
                + ["sh.navigation-columns@1", "sh.adaptive-presentation@1"]).sorted().map(JSONValue.string)))
        let draft = try ServerUIValueForm(identity: .init(ownerId: "demo", recordId: "item"),
            fields: [.text("name", "Name", "Original", required: true), .toggle("enabled", "Enabled", false)]) { _ in }
        let records = UKServerUIRecords(collections: ["demo-items": ShellRecordSource()], forms: [
            "demo-edit": .init(fields: ["name": .text, "enabled": .toggle], selectionOnly: false, open: { draft }),
        ])
        let publication = try ServerUIRendererFixture.publication(fixture)
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
            backdrop: ServerUIRendererFixture.backdrop(), records: records)
        let window = HostedPage.show(host, size: HostedPage.splitSize)
        host.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .regular), forChild: host.tabController)
        await FeatureHost.settleAsync(0.1)
        host.columnGeometryChanged()
        let root = try ServerUIRendererFixture.root(host)
        XCTAssertFalse(root.columns?.isWide == true)
        try host.perform(.present(modalId: publication.document.modals[0].id, arguments: .init(), ifPresented: .reject), from: root)
        let opened = await FeatureHost.settleAsync(until: {
            (root.columns?.entries.last?.controller as? UKServerUIPage)?.formView?.session === draft
        })
        XCTAssertTrue(opened, "Adaptive editor must finish opening before the geometry handoff.")
        let detail = try XCTUnwrap(root.columns?.entries.last?.controller as? UKServerUIPage)
        XCTAssertTrue(detail.formView?.session === draft)
        let instance = try XCTUnwrap(host.navigation.snapshot.presentations.first?.id)
        try draft.set(.string("Retained"), group: "item", field: "name")
        for size in [HostedPage.inScene(CGSize(width: 390, height: 844)), HostedPage.splitSize] {
            window.frame.size = size
            host.view.setNeedsLayout()
            window.layoutIfNeeded()
            host.columnGeometryChanged()
            let placed = await FeatureHost.settleAsync(until: {
                if size.width < size.height { return host.modal?.topViewController === detail }
                return host.modal == nil && root.columns?.entries.last?.controller === detail
            }, timeout: 3)
            XCTAssertTrue(placed, "window \(window.bounds.size), renderer \(host.view.bounds.size), navigation \(String(describing: host.stacks[root.root]?.view.bounds.size)), page \(root.view.bounds.size), wants columns \(root.wantsColumns), wide \(String(describing: root.columns?.isWide)), class \(root.traitCollection.horizontalSizeClass.rawValue)")
            XCTAssertTrue(detail.formView?.session === draft)
            XCTAssertEqual(draft.values["name"], .string("Retained"))
            XCTAssertEqual(host.navigation.snapshot.presentations.first?.id, instance)
            if size.width < size.height {
                let modal = try XCTUnwrap(host.modal)
                XCTAssertTrue(modal.topViewController === detail)
                try host.perform(.push(.init(pageId: "page-echo", arguments: .init(),
                    origin: .sender, duplicate: .reuseNearest)), from: detail)
                let pushed = await FeatureHost.settleAsync(until: {
                    guard let page = modal.topViewController as? UKServerUIPage else { return false }
                    return page.surfaceID == "page-echo" && host.isEnabled(.back, from: page)
                })
                XCTAssertTrue(pushed)
                XCTAssertNotNil(modal.popViewController(animated: true))
                let popped = await FeatureHost.settleAsync(until: {
                    modal.topViewController === detail && host.navigation.snapshot.presentations.first?.pages.isEmpty == true
                })
                XCTAssertTrue(popped, "A completed native modal pop must not return as a column on rotation.")
            }
            else { XCTAssertNil(host.modal); XCTAssertTrue(root.columns?.entries.last?.controller === detail) }
        }
        XCTAssertThrowsError(try host.perform(.dismiss(scope: .currentModal), from: detail))
        try draft.discard()
        try host.perform(.dismiss(scope: .currentModal), from: detail)
        let closed = await FeatureHost.settleAsync(until: { host.navigation.snapshot.presentations.isEmpty })
        XCTAssertTrue(closed)
        XCTAssertTrue(host.navigation.snapshot.presentations.isEmpty)
        XCTAssertFalse(root.columns?.isWide == true)
    }

    private func recordFixture() throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fragment = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIRecordsFixture.json")))
        let components = try XCTUnwrap(fragment["components"]?.array).filter { $0["type"]?.string != "recipe-part" }
        var root = try ServerUIRendererFixture.json()
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(components))
        root = try ServerUIRendererFixture.changing(root, path: "/document/navigation/chrome/groups/1/items/0/priority", to: .string("normal"))
        return try ServerUIRendererFixture.changing(root, path: "/capabilities",
            to: .array((ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.grid@1" }
                + ["sh.collection@1", "sh.form@1", "sh.pinned-actions@1"]).sorted().map(JSONValue.string)))
    }

    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        (view as? T) ?? view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }

    @MainActor @Observable
    final class ShellRecordSource: UKServerUICollectionSource {
        let template = ServerUICompositionDocument.Collection.Template.rows
        var items = [ServerUIRowItem(id: "first", title: "First"), ServerUIRowItem(id: "second", title: "Second")]
        var failure: String?
        var searchText = ""
        var records: [UKServerUIRecord] { items.map(UKServerUIRecord.row) }
        var loading: Bool { false }
        var error: String? { failure }
        var hasPendingIntent = false
        var hasMore: Bool { false }
        func load() async throws {}
        func loadMore() async throws {}
        func select(_ record: UKServerUIRecord) throws {}
    }
}
