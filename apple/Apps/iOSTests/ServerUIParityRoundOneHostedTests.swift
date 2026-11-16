@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Parity round one: layout defects against the reference

/// Hosted checks for the native defects the first parity round found (settings rows at 1 pt, a missing tab badge, a double inset on the
/// chip rail, a duplicated error line on the suggestions carousel).
///
/// Every case hosts in a window of the family's own width (`HostedPage.show` with the raw size, not `inScene`, which clamps to the
/// simulator's scene): iPhone 390, folded Duo 466, unfolded Duo 868 and iPad 744 points.
@MainActor
final class ServerUIParityRoundOneHostedTests: XCTestCase {
    private static let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678),
                                CGSize(width: 868, height: 678), CGSize(width: 744, height: 1133)]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Settings rows keep their height

    private func settingsAtoms() -> [UKServerUISettingsAtom] {
        let toggle = UKRowView(UKRowContent("Vacation Mode"), accessory: UISwitch())
        let slider = UKRowView(UKRowContent("Background Blur"))
        slider.setBody(UISlider())
        let label = UILabel()
        label.numberOfLines = 0
        label.text = "Settings footnote that is long enough to wrap onto a second line at the narrowest family width."
        return [(toggle, "settings-vacation"), (slider, "settings-blur"), (label, "settings-note")].map { view, id in
            let atom = UKServerUISettingsAtom()
            atom.install(view, identifier: id)
            return atom
        }
    }

    private func hostList(_ atoms: [UIView], size: CGSize) -> (UKServerUIFittingView, UIWindow) {
        let holder = UKServerUIFittingView.wrapping(UKModuleListView(.thin, hasGlyphs: false, rows: atoms))
        let controller = UIViewController()
        controller.view.addSubview(holder)
        let width = size.width - 2 * HassTokens.Spacing.l
        holder.frame = CGRect(x: HassTokens.Spacing.l, y: 60, width: width, height: holder.gridHeight(forWidth: width))
        let window = HostedPage.show(controller, size: size)
        for _ in 0..<3 { HostedPage.wait(0.05); window.layoutIfNeeded(); holder.layoutIfNeeded() }
        return (holder, window)
    }

    func testSettingsRowsInAModuleListAreNotCollapsedAtAnyFamilyWidth() {
        for size in Self.sizes {
            let atoms = settingsAtoms()
            let (holder, window) = hostList(atoms, size: size)
            defer { window.isHidden = true }
            let width = size.width - 2 * HassTokens.Spacing.l
            XCTAssertGreaterThanOrEqual(holder.gridHeight(forWidth: width), 3 * 40, "\(size): the list measures every row")
            for atom in atoms {
                XCTAssertGreaterThanOrEqual(atom.frame.height, 20, "\(size): \(atom.content?.accessibilityIdentifier ?? "") is not a sliver: \(atom.frame)")
                XCTAssertEqual(atom.content?.frame.height ?? 0, atom.frame.height, accuracy: 0.5, "\(size): the child fills its atom")
            }
            XCTAssertGreaterThanOrEqual(atoms[0].frame.height, 44, "\(size): a switch row is a touch target tall")
            XCTAssertGreaterThanOrEqual(atoms[1].frame.height, 60, "\(size): a slider row holds its title and the slider")
        }
    }

    /// The accessibility check of the settings rows. It reads the row's own `accessibilityElements` (an override, so it needs no
    /// accessibility runtime): `UISwitch.isAccessibilityElement` reads false in the hosted runner, where the framework that supplies it
    /// for UIKit's controls is not loaded, which is why the first version of this check failed. The defect was found as 350x1
    /// accessibility frames, so each element's window frame must also be taller than a sliver.
    func testSettingsRowElementsAreReachableNamedAndNotSquashedAtAnyFamilyWidth() throws {
        for size in Self.sizes {
            let atoms = settingsAtoms()
            let (_, window) = hostList(atoms, size: size)
            defer { window.isHidden = true }
            XCTAssertEqual(atoms.compactMap { $0.content?.accessibilityIdentifier }, ["settings-vacation", "settings-blur", "settings-note"])
            let toggleRow = try XCTUnwrap(atoms[0].content as? UKRowView)
            let sliderRow = try XCTUnwrap(atoms[1].content as? UKRowView)
            let toggle = try XCTUnwrap(HostedPage.descendants(of: toggleRow).compactMap { $0 as? UISwitch }.first)
            let slider = try XCTUnwrap(HostedPage.descendants(of: sliderRow).compactMap { $0 as? UISlider }.first)
            for (row, control, title, minimum) in [(toggleRow, toggle as UIView, "Vacation Mode", CGFloat(44)),
                                                   (sliderRow, slider as UIView, "Background Blur", CGFloat(28))] {
                let elements = try XCTUnwrap(row.accessibilityElements as? [UIView], "\(size): \(title) lists its elements")
                XCTAssertTrue(elements.contains { $0 === control }, "\(size): \(title)'s \(type(of: control)) is a reachable element")
                XCTAssertEqual(elements.first?.accessibilityLabel, title, "\(size): the first element is named for the row")
                for element in elements {
                    let frame = element.convert(element.bounds, to: nil)
                    XCTAssertGreaterThan(frame.height, 20, "\(size): \(title): \(type(of: element)) is drawn, not squashed: \(frame)")
                }
                let rowFrame = row.convert(row.bounds, to: nil)
                XCTAssertGreaterThanOrEqual(rowFrame.height, minimum, "\(size): \(title) row is tall enough: \(rowFrame)")
            }
        }
    }

    // MARK: Chip rail inset on a composed page

    private func homeJSON(sidePadding: String) throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIHomeFixture.json")))
        for side in ["leading", "trailing"] {
            json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/layout/padding/\(side)",
                                                       to: .object(["type": .string("token"), "name": .string(sidePadding)]))
        }
        return json
    }

    /// The first chip's leading edge, in the page's scroll content, for a page whose sides are padded by `sidePadding` (a spacing token).
    private func firstChipLeading(sidePadding: String, size: CGSize) throws -> (chip: CGFloat, row: CGFloat) {
        let publication = try ServerUICompositionPublication.decode(JSONEncoder().encode(homeJSON(sidePadding: sidePadding)))
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "light.demo_study", state: "off")])
        let reader = ServerUIWeatherReader(entityIds: ["weather.demo_forecast"]) { entity, _ in
            .object([entity: .object(["forecast": .array([])])])
        }
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop(), weatherReader: reader)
        let window = HostedPage.show(host, size: size)
        defer { window.isHidden = true }
        let page = try XCTUnwrap(host.stacks[.initial]?.viewControllers.first as? UKServerUIPage)
        for _ in 0..<3 { HostedPage.wait(0.05); window.layoutIfNeeded() }
        HostedPage.layoutTracked()
        let body = try XCTUnwrap(page.body)
        let rail = try XCTUnwrap(page.nodes["fixture-rail"]?.view as? UKChipRailView)
        let chip = try XCTUnwrap(page.nodes["fixture-chip"]?.view)
        let weather = try XCTUnwrap(page.nodes["fixture-summary"]?.view)
        XCTAssertEqual(rail.window?.bounds.width ?? 0, size.width, accuracy: 0.5, "the page is hosted at the family width")
        return (chip.convert(chip.bounds, to: body).minX, weather.convert(weather.bounds, to: body).minX)
    }

    /// Deleting the page line that sets the rail's `edgeInset` puts the first chip one gutter further in on a padded page (32 pt).
    func testChipRailOnAComposedPageStartsOneGutterFromThePageEdgeAtEveryFamilyWidth() throws {
        for size in Self.sizes {
            let padded = try firstChipLeading(sidePadding: "l", size: size)
            XCTAssertEqual(padded.row, HassTokens.Spacing.l, accuracy: 0.5, "\(size): the page's other rows start at the page padding")
            XCTAssertEqual(padded.chip, padded.row, accuracy: 0.5, "\(size): a padded page adds no second gutter before the chips")
            let bleed = try firstChipLeading(sidePadding: "zero", size: size)
            XCTAssertEqual(bleed.row, 0, accuracy: 0.5, "\(size): the unpadded page's rows are edge to edge")
            XCTAssertEqual(bleed.chip, HassTokens.Spacing.l, accuracy: 0.5, "\(size): an unpadded page keeps the rail's own gutter")
            HostedPage.hideTracked()
        }
    }

    func testChipRailEdgeInsetTakesOnlyWhatThePageLacks() {
        XCTAssertEqual(UKChipRailView.edgeInset(pagePadding: HassTokens.Spacing.l), 0)
        XCTAssertEqual(UKChipRailView.edgeInset(pagePadding: 0), HassTokens.Spacing.l)
        XCTAssertEqual(UKChipRailView.edgeInset(pagePadding: 4), HassTokens.Spacing.l - 4)
        XCTAssertEqual(UKChipRailView.edgeInset(pagePadding: 40), 0)
    }

    // MARK: Tab badge

    private static let badgeEntity = "sensor.demo_bath_temperature"

    /// A tab badge that reads an entity's state as a number (`missing: unavailable`).
    private func badgeJSON(_ badge: JSONValue?) throws -> JSONValue {
        var json = try ServerUIRendererFixture.json()
        if let badge {
            json = try ServerUIRendererFixture.changing(json, path: "document/navigation/tabs/0/badge",
                                                       to: .object(["type": .string("value"), "value": badge]))
        }
        let sources = try XCTUnwrap(json["document"]?["dataSources"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "document/dataSources", to: .array(sources + [
            .object(["id": .string("badge-count"), "kind": .string("ha-entity"),
                     "entityId": .object(["type": .string("literal"), "value": .string(Self.badgeEntity)])]),
        ]))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities + (badge == nil ? [] : ["sh.badges@1", "sh.operands@1"])
        return try ServerUIRendererFixture.changing(json, path: "capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
    }

    private var countOperand: JSONValue {
        .object(["type": .string("read"),
                 "from": .object(["type": .string("source"), "sourceId": .string("badge-count"), "path": .array([.string("state")])]),
                 "as": .string("number"), "missing": .string("unavailable")])
    }

    private func badgeHost(_ json: JSONValue, size: CGSize, store: EntityStore) throws -> (UKServerUIRenderer, UIWindow) {
        let renderer = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(json),
                                              context: UKContext(store: store, caller: HostedCaller()),
                                              backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(renderer, size: size)
        HostedPage.layoutTracked()
        return (renderer, window)
    }

    private func flyoutRow(_ renderer: UKServerUIRenderer, _ id: String) -> UKFlyoutRow? {
        HostedPage.descendants(of: renderer.view).compactMap { $0 as? UKFlyoutRow }.first { $0.accessibilityIdentifier == id }
    }

    /// The tab item and the flyout row of "Canvas", as `(badge, item label, item value, row badge, row label)`.
    private func shown(_ renderer: UKServerUIRenderer) throws -> (String?, String?, String?, String?, String?) {
        let item = try XCTUnwrap(renderer.stacks[.tab("tab-alpha")]?.tabBarItem)
        let row = try XCTUnwrap(flyoutRow(renderer, "tab-alpha"), "the flyout lists the tab")
        return (item.badgeValue, item.accessibilityLabel, item.accessibilityValue, row.destination.badge, row.accessibilityLabel)
    }

    func testAnAuthoredTabBadgeReachesTheTabItemAndTheFlyoutAtEveryFamilyWidth() throws {
        let json = try badgeJSON(.object(["type": .string("literal"), "value": .string("11")]))
        for size in Self.sizes {
            let (renderer, window) = try badgeHost(json, size: size, store: EntityStore())
            defer { window.isHidden = true }
            XCTAssertEqual(window.bounds.width, size.width, "the renderer is hosted at the family width")
            let value = try shown(renderer)
            XCTAssertEqual(value.0, "11", "\(size): the tab draws its authored badge")
            XCTAssertEqual(value.1, "Canvas", "\(size): the item's label stays the tab's name")
            XCTAssertEqual(value.2, "11", "\(size): the count is the item's spoken value, once")
            XCTAssertEqual(value.3, "11", "\(size): the flyout row draws the badge")
            XCTAssertEqual(value.4, "Canvas, 11", "\(size): the flyout row is one element, so its label carries the count")
            XCTAssertNil(renderer.stacks[.tab("tab-beta")]?.tabBarItem.badgeValue, "\(size): a tab with no badge draws none")
            XCTAssertEqual(renderer.stacks[.tab("tab-beta")]?.tabBarItem.accessibilityLabel, "Shelf")
            XCTAssertNil(renderer.stacks[.tab("tab-beta")]?.tabBarItem.accessibilityValue)
            HostedPage.hideTracked()
        }
    }

    func testSpokenTabLabelNamesTheBadgeOnlyWhenThereIsOne() {
        XCTAssertEqual(UKServerUIRenderer.spokenTabLabel("Chores", badge: "11"), "Chores, 11")
        XCTAssertEqual(UKServerUIRenderer.spokenTabLabel("Chores", badge: nil), "Chores")
    }

    /// The badge follows the entity in place and obeys the contract's rule (`ServerUILayoutRules.badge`): a count of 0, and a value
    /// that is unavailable, draw no badge on the tab item or the flyout row; a later count draws it again.
    func testALiveTabBadgeFollowsTheEntityAndHidesForZeroAndUnavailableAtEveryFamilyWidth() throws {
        let json = try badgeJSON(countOperand)
        for size in Self.sizes {
            let store = EntityStore()
            store.replaceAll([EntityState(entityId: Self.badgeEntity, state: "3")])
            let (renderer, window) = try badgeHost(json, size: size, store: store)
            defer { window.isHidden = true }
            func wait(_ badge: String?) -> Bool {
                HostedPage.until { (try? self.shown(renderer))?.0 == badge && (try? self.shown(renderer))?.3 == badge }
            }
            XCTAssertTrue(wait("3"), "\(size): the first count shows: \(String(describing: try? shown(renderer)))")
            store.apply([EntityState(entityId: Self.badgeEntity, state: "0")])
            XCTAssertTrue(wait(nil), "\(size): 0 draws no badge")
            var cleared = try shown(renderer)
            XCTAssertEqual(cleared.1, "Canvas"); XCTAssertNil(cleared.2, "\(size): and no spoken count"); XCTAssertEqual(cleared.4, "Canvas")
            store.apply([EntityState(entityId: Self.badgeEntity, state: "5")])
            XCTAssertTrue(wait("5"), "\(size): a later count shows again")
            store.apply([EntityState(entityId: Self.badgeEntity, state: "unavailable")])
            XCTAssertTrue(wait(nil), "\(size): an unavailable value draws no badge")
            cleared = try shown(renderer)
            XCTAssertNil(cleared.2); XCTAssertEqual(cleared.4, "Canvas")
            HostedPage.hideTracked()
        }
    }

    /// A republish that removes the authored badge clears it from the tab item and the flyout row.
    func testRepublishingWithoutTheBadgeClearsTheTabItemAndTheFlyout() throws {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: Self.badgeEntity, state: "4")])
        let backdrop = try ServerUIRendererFixture.backdrop()
        let (renderer, window) = try badgeHost(badgeJSON(countOperand), size: Self.sizes[0], store: store)
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until { (try? self.shown(renderer))?.0 == "4" })
        try renderer.apply(publication: ServerUIRendererFixture.publication(badgeJSON(nil)), backdrop: backdrop)
        XCTAssertTrue(HostedPage.until { (try? self.shown(renderer))?.0 == nil && (try? self.shown(renderer))?.3 == nil },
                      "the removed badge leaves both: \(String(describing: try? shown(renderer)))")
        let value = try shown(renderer)
        XCTAssertNil(value.2)
        XCTAssertEqual(value.4, "Canvas")
    }

    // MARK: Suggestions carousel

    private func carouselJSON(emptyText: String? = nil) throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fragment = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIRecordsFixture.json")))
        let components = try XCTUnwrap(fragment["components"]?.array).filter { $0["type"]?.string != "recipe-part" }
        var json = try ServerUIRendererFixture.json()
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components))
        json = try ServerUIRendererFixture.changing(json, path: "/document/navigation/chrome/groups/1/items/0/priority", to: .string("normal"))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components/0/props/template", to: .string("carousel"))
        if let emptyText {
            json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components/0/props/emptyText", to: .string(emptyText))
        }
        return try ServerUIRendererFixture.changing(json, path: "/capabilities",
            to: .array((ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.grid@1" }
                + ["sh.collection@1", "sh.form@1", "sh.pinned-actions@1"]).sorted().map(JSONValue.string)))
    }

    private func carouselLabels(_ json: JSONValue, source: CarouselSource, size: CGSize) throws -> [String] {
        let renderer = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(json),
            context: UKContext(store: EntityStore()), backdrop: ServerUIRendererFixture.backdrop(),
            records: UKServerUIRecords(collections: ["demo-items": source], forms: ["demo-edit": UKServerUIFormFactory(
                fields: ["name": .text, "enabled": .toggle], selectionOnly: false, open: {
                    try ServerUIValueForm(identity: .init(ownerId: "demo", recordId: "idle"),
                        fields: [.text("name", "Name", "Original", required: true), .toggle("enabled", "Enabled", false)]) { _ in }
                })]))
        let window = HostedPage.show(renderer, size: size)
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(renderer)
        let collection = try XCTUnwrap(page.nodes["record-list"]?.view as? UKServerUICollectionView)
        HostedPage.wait(0.2)
        defer { HostedPage.hideTracked() }
        return HostedPage.labels(in: collection)
    }

    func testAFailedSuggestionsCarouselShowsItsOwnStateAndNoDuplicateErrorLine() throws {
        let json = try carouselJSON()
        for size in Self.sizes {
            let labels = try carouselLabels(json, source: CarouselSource(error: "Unable to load recipes."), size: size)
            XCTAssertFalse(labels.contains("Unable to load recipes."), "\(size): the carousel's own failed state is the only notice: \(labels)")
            XCTAssertTrue(labels.contains("Suggestions Unavailable"), "\(size): the failed state stays: \(labels)")
        }
    }

    func testAnEmptySuggestionsCarouselShowsTheAuthoredEmptyTextOnce() throws {
        let json = try carouselJSON(emptyText: "Nothing is suggested today")
        for size in Self.sizes {
            let labels = try carouselLabels(json, source: CarouselSource(error: nil), size: size)
            XCTAssertEqual(labels.filter { $0 == "Nothing is suggested today" }.count, 1, "\(size): the authored text shows once: \(labels)")
            XCTAssertEqual(labels.filter { $0 == "No Suggestions Yet" }.count, 1, "\(size): under the empty state's own title: \(labels)")
            XCTAssertFalse(labels.contains("There's nothing to suggest right now. Check back later."), "\(size): the default message gives way: \(labels)")
        }
    }
}

/// A suggestions source that has read and has nothing, or whose read failed.
@MainActor
private final class CarouselSource: UKServerUICollectionSource {
    let template = ServerUICompositionDocument.Collection.Template.carousel
    let error: String?
    init(error: String?) { self.error = error }
    var records: [UKServerUIRecord] { [] }
    var loading: Bool { false }
    var hasPendingIntent: Bool { false }
    var hasMore: Bool { false }
    var searchText = ""
    func load() async throws {}
    func loadMore() async throws {}
    func select(_ record: UKServerUIRecord) throws {}
}
