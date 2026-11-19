import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - The generic parts

/// Hosted UX and accessibility checks for the five generic part capabilities (TC3): options read from an entity
/// (`sh.bound-options-read@1`), a tile button that follows a rule (`sh.tile-disc-rules@1`), a grid's least columns
/// (`sh.grid-min-columns@1`), a toggle row's parts (`sh.bound-row-parts@1`) and the check face (`sh.check-face@1`).
///
/// Each test runs at the iPhone, iPhone Duo and iPad widths (a simulator narrower than a width draws it at the simulator's own, as the other
/// hosted layout tests do), so a part that only fits one family fails here. The documents are the Studio's own corpus cases, with
/// placeholder entity ids. What the parts replace is the old vacuum and climate atoms, so each test names the atom it must draw like.
@MainActor
final class ServerUIPartsHostedTests: XCTestCase {
    /// The widths of the three families: iPhone, folded Duo and iPad.
    private static let widths: [CGFloat] = [390, 744, 1024]
    /// The store of the page opened last.
    private var store = EntityStore()

    /// The windows the test opened: `HostedPage.show` keeps its window weakly, and a window that deallocates sends its page
    /// `viewDidDisappear`, which rests the page's node observations (`UKServerUIPage.restNodes()`), so it stops following the store.
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        HostedPage.hideTracked()
        windows.removeAll()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    /// The corpus case `file`, with the components of its third page moved onto the page the renderer opens first.
    private func publication(_ file: String, change: (inout [String: JSONValue]) -> Void = { _ in }) throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/\(file).json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[2]["components"]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        if case .object(var object) = json { change(&object); json = .object(object) }
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    /// Opens `file` at `width` over a store holding `entities`.
    private func page(_ file: String, width: CGFloat, entities: [EntityState] = [], caller: HostedCaller = HostedCaller(),
                      change: (inout [String: JSONValue]) -> Void = { _ in }) throws -> (UKServerUIRenderer, UKServerUIPage) {
        store = EntityStore()
        store.replaceAll(entities)
        let host = try UKServerUIRenderer(publication: publication(file, change: change), context: UKContext(store: store, caller: caller),
                                          backdrop: ServerUIRendererFixture.backdrop())
        windows.append(HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 1180))))
        HostedPage.wait(0.1)
        let root = try ServerUIRendererFixture.root(host)
        root.view.layoutIfNeeded()
        return (host, root)
    }

    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }

    private func all<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, in: $0) }
    }

    /// Every accessibility label under `view`, including elements a container hands out itself.
    private func spoken(_ view: UIView) -> [String] {
        var labels = [view.accessibilityLabel].compactMap { $0 }
        for element in view.accessibilityElements ?? [] {
            if let child = element as? UIView { labels += spoken(child) } else if let label = (element as? NSObject)?.accessibilityLabel { labels.append(label) }
        }
        for child in view.subviews { labels += spoken(child) }
        return labels
    }

    private func robot(_ state: String, attributes: [String: JSONValue] = [:]) -> EntityState {
        EntityState(entityId: "vacuum.demo_robot", state: state, attributes: attributes)
    }

    // MARK: Tile button rules (the Start/Pause disc and its label)

    /// The old `VacuumActions` start/pause: Pause while cleaning or returning, Resume when paused, Start otherwise, and Dock beside it.
    func testStartPauseDiscFollowsTheRobotAndNamesTheTileAtEveryFamilyWidth() throws {
        let expected: [(state: String, symbol: String, verb: String)] = [
            ("cleaning", "pause.fill", "Pause"), ("returning", "pause.fill", "Pause"), ("paused", "play.fill", "Resume"), ("docked", "play.fill", "Start"),
        ]
        for width in Self.widths {
            let (_, root) = try page("parts-disc-all-three", width: width, entities: [robot("docked")])
            let tile = try XCTUnwrap(root.nodes["main-floor"]?.view as? UKGlassTileView, "width \(width)")
            for step in expected {
                store.apply([robot(step.state)])
                let landed = tile.model.actions.first { $0.id == "disc:start-pause" }
                let reached = HostedPage.until(2) { tile.model.actions.first { $0.id == "disc:start-pause" }?.verb == step.verb }
                XCTAssertTrue(reached, "\(step.state) at \(width): \(String(describing: landed))")
                let disc = try XCTUnwrap(tile.model.actions.first { $0.id == "disc:start-pause" })
                XCTAssertEqual(disc.symbol, step.symbol, "\(step.state) at \(width)")
                XCTAssertNil(disc.label, "a disc that names its tile leaves the label to the tile's title")
                root.view.layoutIfNeeded()
                let words = spoken(tile)
                XCTAssertTrue(words.contains("\(step.verb) Main Floor"), "VoiceOver reads the verb then the tile: \(words)")
            }
            let dock = try XCTUnwrap(tile.model.actions.first { $0.id == "disc:dock" })
            XCTAssertEqual(dock.verb, "Dock")
            XCTAssertEqual(dock.symbol, "house.fill")
            XCTAssertTrue(spoken(tile).contains("Dock Main Floor"))
            HostedPage.hideTracked()
        }
    }

    func testDiscsAreAtLeast44PointsAtEveryFamilyWidthAndAtTheLargestTextSize() throws {
        for width in Self.widths {
            for large in [false, true] {
                let (_, root) = try page("parts-disc-all-three", width: width, entities: [robot("cleaning")])
                if large { root.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge }
                root.view.layoutIfNeeded()
                let tile = try XCTUnwrap(root.nodes["main-floor"]?.view as? UKGlassTileView)
                let discs = all(UKTileActionDisc.self, in: tile)
                XCTAssertEqual(discs.count, 2, "width \(width)")
                for disc in discs {
                    XCTAssertGreaterThanOrEqual(disc.bounds.width, 44, "width \(width) large \(large)")
                    XCTAssertGreaterThanOrEqual(disc.bounds.height, 44, "width \(width) large \(large)")
                    XCTAssertTrue(disc.accessibilityTraits.contains(.button))
                }
                HostedPage.hideTracked()
            }
        }
    }

    func testASymbolNamedByTheEntityIsDrawnAndAnUnknownOneFallsBack() throws {
        for width in Self.widths {
            let named = robot("docked", attributes: ["button_icon": .string("stop.fill")])
            let (_, root) = try page("parts-disc-symbol-from-entity", width: width, entities: [named])
            let tile = try XCTUnwrap(root.nodes["main-floor"]?.view as? UKGlassTileView)
            XCTAssertTrue(HostedPage.until(2) { tile.model.actions.first?.symbol == "stop.fill" }, "width \(width)")
            HostedPage.hideTracked()
            let (_, bare) = try page("parts-disc-symbol-from-entity", width: width, entities: [robot("docked")])
            let plain = try XCTUnwrap(bare.nodes["main-floor"]?.view as? UKGlassTileView)
            XCTAssertEqual(plain.model.actions.first?.symbol, "play.fill", "no symbol to read: the authored one stands")
            HostedPage.hideTracked()
        }
    }

    func testADiscThatDoesNotNameTheTileSaysItsWholeWords() throws {
        let (_, root) = try page("parts-disc-label-by-expression", width: 390, entities: [robot("paused")])
        let tile = try XCTUnwrap(root.nodes["main-floor"]?.view as? UKGlassTileView)
        XCTAssertTrue(HostedPage.until(2) { tile.model.actions.first?.label == "Resume" })
        XCTAssertTrue(spoken(tile).contains("Resume"), "the words are the whole label: \(spoken(tile))")
    }

    // MARK: A grid's least columns (the vacuum's two across)

    private func frames(of ids: [String], in root: UKServerUIPage) throws -> [CGRect] {
        try ids.map { try XCTUnwrap(root.nodes[$0]?.view, $0).convert(XCTUnwrap(root.nodes[$0]?.view).bounds, to: root.view) }
    }

    /// A column floor sets the track count and never caps a tile's span (owner: a tile "is never squeezed to keep a column count"):
    /// a robot card wider than a track takes the tracks its content needs, so it takes the row at 350 and 390 (the folded Duo and the
    /// phone) and sits beside the other where the cards fit one track (the unfolded Duo, the iPad).
    func testARobotCardTakesTheRowWhenNarrowAndSitsBesideTheOtherWhenItFitsAtEveryFamilyWidth() throws {
        for width in [350] + Self.widths {
            let (_, root) = try page("parts-columns-two-robots-across", width: width, entities: [robot("docked")])
            let tiles = try frames(of: ["main-floor", "upstairs"], in: root)
            let minimum = try XCTUnwrap(root.nodes["main-floor"]?.view as? UKGlassTileView).gridMinimumWidth
            XCTAssertGreaterThanOrEqual(tiles[0].width + 0.5, minimum, "a card is never squeezed below its content at \(width)")
            XCTAssertLessThanOrEqual(tiles[1].maxX, root.view.bounds.width + 1)
            // A simulator narrower than the family's width draws it at its own, so the page's real width decides.
            let drawn = root.view.bounds.width
            if drawn < 500 {
                XCTAssertLessThan(tiles[0].maxY, tiles[1].minY + 1, "one robot card per row at \(drawn)")
                XCTAssertEqual(tiles[0].width, tiles[1].width, accuracy: 1, "each takes the row at \(drawn)")
            } else {
                XCTAssertEqual(tiles[0].minY, tiles[1].minY, accuracy: 1, "the cards share a row at \(drawn)")
                XCTAssertLessThan(tiles[0].maxX, tiles[1].minX + 1, "side by side at \(drawn)")
            }
            HostedPage.hideTracked()
        }
    }

    func testAColumnFloorGivesUpAtAccessibilityTextSizes() throws {
        let (_, large) = try page("parts-columns-two-robots-across", width: 390, entities: [robot("docked")])
        large.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        large.view.layoutIfNeeded()
        HostedPage.wait(0.2)
        let tiles = try frames(of: ["main-floor", "upstairs"], in: large)
        XCTAssertLessThan(tiles[0].maxY, tiles[1].minY + 1, "at accessibility sizes the floor yields: one column")
    }

    func testTheGridKeepsDocumentOrderForVoiceOver() throws {
        for width in Self.widths {
            let (_, root) = try page("parts-columns-two-robots-across", width: width, entities: [robot("docked")])
            let first = try XCTUnwrap(root.nodes["main-floor"]?.view), second = try XCTUnwrap(root.nodes["upstairs"]?.view)
            XCTAssertTrue(spoken(first).contains { $0.contains("Main Floor") }, "width \(width)")
            XCTAssertTrue(spoken(second).contains { $0.contains("Upstairs") }, "width \(width)")
            let grid = try XCTUnwrap(root.nodes["robots"]?.view as? UKDynamicGridView)
            XCTAssertEqual(grid.items.map(\.view), [first, second])
            HostedPage.hideTracked()
        }
    }

    // MARK: The robot's glyph follows its state

    /// The glyph the tile draws for `name`: the style's where this OS draws it, else the tile's own authored symbol (here `fan`).
    private func drawn(_ name: String) -> String { UIImage(systemName: name) != nil ? name : "fan" }

    func testTheRobotGlyphIsTheHouseWhileDockedAndTheRobotOtherwiseAtEveryFamilyWidth() throws {
        for width in Self.widths {
            let (_, root) = try page("parts-columns-two-robots-across", width: width, entities: [robot("docked")])
            let tile = try XCTUnwrap(root.nodes["main-floor"]?.view as? UKGlassTileView)
            XCTAssertTrue(HostedPage.until(2) { tile.model.symbol == self.drawn("house") }, "docked draws the house at \(width)")
            XCTAssertEqual(tile.model.look?.icon, drawn("house"), "the look names the same glyph at \(width)")
            for state in ["cleaning", "returning", "paused", "idle", "error"] {
                store.apply([robot(state)])
                XCTAssertTrue(HostedPage.until(2) { tile.model.symbol == self.drawn("robotic.vacuum") }, "\(state) draws the robot at \(width)")
            }
            store.apply([robot("unavailable")])
            XCTAssertTrue(HostedPage.until(2) { tile.model.symbol == self.drawn("robotic.vacuum") },
                          "an unavailable robot draws the robot, not the house, at \(width)")
            store.apply([robot("docked")])
            XCTAssertTrue(HostedPage.until(2) { tile.model.symbol == self.drawn("house") }, "docked again draws the house at \(width)")
            HostedPage.hideTracked()
        }
    }

    /// The glyph is decoration: VoiceOver reads the title and the state words, never the glyph's name, and the discs keep their verbs.
    func testTheRobotGlyphChangesNothingVoiceOverReadsAtEveryFamilyWidth() throws {
        for width in Self.widths {
            let (_, root) = try page("parts-columns-two-robots-across", width: width, entities: [robot("docked")])
            let tile = try XCTUnwrap(root.nodes["main-floor"]?.view as? UKGlassTileView)
            XCTAssertEqual(tile.accessibilityLabel, "Main Floor", "width \(width)")
            let docked = tile.accessibilityValue ?? ""
            XCTAssertFalse(docked.localizedCaseInsensitiveContains("house") || docked.localizedCaseInsensitiveContains("robotic"),
                           "the value is the state words, not a glyph name (\(docked))")
            store.apply([robot("unavailable")])
            XCTAssertTrue(HostedPage.until(2) { tile.accessibilityValue != docked }, "the value follows the state at \(width)")
            XCTAssertFalse((tile.accessibilityValue ?? "").localizedCaseInsensitiveContains("robotic"), "width \(width)")
            XCTAssertEqual(tile.model.actions.first?.verb, "Start", "the disc keeps its verb at \(width)")
            HostedPage.hideTracked()
        }
    }

    // MARK: Options read from an entity (the fan speed choice)

    private func speed(_ state: String, options: JSONValue? = nil) -> EntityState {
        EntityState(entityId: "select.demo_fan_speed", state: state, attributes: options.map { ["options": $0] } ?? [:])
    }

    func testAChoiceDrawsTheEntitysOptionsTitleCasedAndChoosesTheCurrentOne() throws {
        for width in Self.widths {
            let list: JSONValue = .array([.string("quiet"), .string("turbo"), .string("max_power")])
            let (_, root) = try page("parts-options-from-attribute", width: width, entities: [speed("turbo", options: list)])
            let node = try XCTUnwrap(root.nodes["speed-choice"]?.view as? UKServerUILocalControl, "width \(width)")
            let choice = try XCTUnwrap(find(UKSegmentedChoice<String>.self, in: node), "three options is a segmented choice")
            XCTAssertEqual(choice.options, ["quiet", "turbo", "max_power"], "width \(width)")
            XCTAssertEqual(choice.selection, "turbo")
            let titles = all(UISegmentedControl.self, in: node).first.map { control in (0..<control.numberOfSegments).compactMap { control.titleForSegment(at: $0) } }
            XCTAssertEqual(titles, ["Quiet", "Turbo", "Max Power"])
            HostedPage.hideTracked()
        }
    }

    func testChoosingAnOptionSendsThatItemAndTheListFollowsTheEntity() async throws {
        let caller = HostedCaller()
        let list: JSONValue = .array([.string("quiet"), .string("turbo"), .string("max_power")])
        let (host, root) = try page("parts-options-from-attribute", width: 390, entities: [speed("quiet", options: list)], caller: caller)
        let node = try XCTUnwrap(root.nodes["speed-choice"]?.view as? UKServerUILocalControl)
        let choice = try XCTUnwrap(find(UKSegmentedChoice<String>.self, in: node))
        let control = try XCTUnwrap(find(UISegmentedControl.self, in: choice))
        control.selectedSegmentIndex = 2
        control.sendActions(for: .valueChanged)
        await host.callRunner.waitForCalls()
        XCTAssertEqual(caller.calls, ["select.select_option"])
        XCTAssertEqual(caller.data.first?["option"] as? String, "max_power", "the call carries the item as the entity holds it")
        // A new list arrives: the control follows it, in place.
        store.apply([speed("quiet", options: .array([.string("low"), .string("high")]))])
        // An async test suspends to let the observation's main-actor hop land; a spinning wait would starve it.
        let followed = await HostedPage.settle {
            guard let again = self.find(UKSegmentedChoice<String>.self, in: node) else { return false }
            return again.options == ["low", "high"]
        }
        XCTAssertTrue(followed, "the control follows the entity's new list")
    }

    func testAListWithFewerThanTwoUsableItemsKeepsTheAuthoredOptions() throws {
        for list in [JSONValue.array([.string("only")]), .array([]), .string("not a list")] {
            let (_, root) = try page("parts-options-from-attribute", width: 390, entities: [speed("quiet", options: list)])
            let node = try XCTUnwrap(root.nodes["speed-choice"]?.view as? UKServerUILocalControl)
            let choice = try XCTUnwrap(find(UKSegmentedChoice<String>.self, in: node))
            XCTAssertEqual(choice.options, ["quiet", "standard"], "the authored options are the fallback, never an empty control")
            HostedPage.hideTracked()
        }
    }

    func testTheChoiceTargetIsAtLeast44PointsAtTheLargestTextSize() throws {
        let list: JSONValue = .array([.string("quiet"), .string("turbo"), .string("max_power")])
        for width in Self.widths {
            let (_, root) = try page("parts-options-from-attribute", width: width, entities: [speed("turbo", options: list)])
            root.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            root.view.layoutIfNeeded()
            let node = try XCTUnwrap(root.nodes["speed-choice"]?.view)
            for control in all(UIControl.self, in: node) where !control.isHidden && control.bounds.width > 0 {
                XCTAssertGreaterThanOrEqual(control.bounds.height, 44, "width \(width)")
            }
            HostedPage.hideTracked()
        }
    }

    // MARK: A toggle row's parts (the Auto-Clean row)

    private func autoClean(_ state: String) -> EntityState { EntityState(entityId: "input_boolean.demo_auto_clean", state: state) }

    private func row(_ root: UKServerUIPage, _ id: String = "auto-clean-row") throws -> UKModuleToggleRow {
        let node = try XCTUnwrap(root.nodes[id]?.view as? UKServerUILocalControl)
        return try XCTUnwrap(node.drawnControl as? UKModuleToggleRow, "the row with parts is the module toggle row")
    }

    /// The old Auto-Clean row (`UKServerUIVacuumView.autoClean`): a clock glyph in the cleaning tint, the title, the state under it and a switch.
    func testTheAutoCleanRowDrawsItsGlyphSubtitleHintAndAMeetingTargetAtEveryFamilyWidth() throws {
        for width in Self.widths {
            let (_, root) = try page("parts-row-auto-clean-row", width: width, entities: [autoClean("on")])
            let row = try self.row(root)
            XCTAssertEqual(row.row.rowContent.title, "Auto-Clean", "width \(width)")
            XCTAssertEqual(row.row.rowContent.symbol, "clock.arrow.circlepath")
            XCTAssertEqual(row.row.rowContent.subtitle, "Paused")
            XCTAssertEqual(row.row.rowContent.glyph, UIColor(red: 175 / 255, green: 82 / 255, blue: 222 / 255, alpha: 1))
            XCTAssertEqual(row.row.rowContent.style, .module)
            XCTAssertTrue(row.isOn)
            XCTAssertEqual(row.accessibilityHint, "Turns automatic cleaning on or off.")
            XCTAssertTrue(row.accessibilityTraits.contains(.toggleButton), "a switch to VoiceOver")
            XCTAssertEqual(row.accessibilityLabel, "Auto-Clean")
            XCTAssertEqual(row.accessibilityValue, "1")
            root.view.layoutIfNeeded()
            XCTAssertGreaterThanOrEqual(row.bounds.height, 60, "the module row with a subtitle is 60 pt")
            XCTAssertGreaterThanOrEqual(row.bounds.width, min(width, root.view.bounds.width) - 40, "the whole row is the target")
            HostedPage.hideTracked()
        }
    }

    func testTheSubtitleAndSwitchFollowTheEntityInPlace() throws {
        let (_, root) = try page("parts-row-auto-clean-row", width: 390, entities: [autoClean("off")])
        let row = try self.row(root)
        XCTAssertEqual(row.row.rowContent.subtitle, "Off")
        XCTAssertFalse(row.isOn)
        store.apply([autoClean("on")])
        XCTAssertTrue(HostedPage.until(2) { row.row.rowContent.subtitle == "Paused" && row.isOn })
        XCTAssertTrue(try self.row(root) === row, "the row is updated in place, never rebuilt")
        XCTAssertEqual(row.accessibilityValue, "1")
    }

    func testTapAnywhereOnTheRowSendsTheOppositeAndTheRowKeepsWhatItShowed() async throws {
        let caller = HostedCaller()
        let (host, root) = try page("parts-row-auto-clean-row", width: 390, entities: [autoClean("off")], caller: caller)
        let row = try self.row(root)
        row.sendActions(for: .touchUpInside)
        await host.callRunner.waitForCalls()
        XCTAssertEqual(caller.calls, ["input_boolean.toggle"])
        XCTAssertFalse(row.isOn, "Home Assistant has not said otherwise: the row keeps what it showed")
    }

    func testAnUnavailableEntityDimsTheGlyphSaysSoAndReadsNotEnabled() throws {
        for width in Self.widths {
            let (_, root) = try page("parts-row-auto-clean-row", width: width, entities: [autoClean("unavailable")])
            let row = try self.row(root)
            XCTAssertEqual(row.row.rowContent.subtitle, "Unavailable", "width \(width)")
            XCTAssertEqual(row.row.rowContent.glyphOpacity, 0.4, accuracy: 0.001)
            XCTAssertFalse(row.isEnabled)
            XCTAssertTrue(row.accessibilityTraits.contains(.notEnabled))
            XCTAssertEqual(row.accessibilityHint, "Unavailable", "the unavailable words replace the hint")
            HostedPage.hideTracked()
        }
    }

    func testAFailedCallSaysSoUnderTheRowThenClears() async throws {
        let caller = HostedCaller()
        caller.fails = true
        let (host, root) = try page("parts-row-auto-clean-row", width: 390, entities: [autoClean("off")], caller: caller)
        let row = try self.row(root)
        row.sendActions(for: .touchUpInside)
        await host.callRunner.waitForCalls()
        let node = try XCTUnwrap(root.nodes["auto-clean-row"]?.view)
        let landed = await HostedPage.settle { self.spoken(node).contains("Automatic cleaning did not respond.") }
        let captions = all(UILabel.self, in: node).compactMap(\.text)
        XCTAssertTrue(landed, "the failure words show: \(spoken(node)); labels \(captions); calls \(caller.calls); failed \(host.callRunner.isFailed(node: "auto-clean-row"))")
        XCTAssertTrue(captions.contains("Automatic cleaning did not respond."), "the caption is drawn under the row")
    }

    /// A toggle that carries the node icon and no row part is the plain switch row it always was: no glyph column, no module row.
    func testAToggleWithAnIconAndNoPartKeepsThePlainSwitchRow() throws {
        let (_, root) = try page("parts-check-explicit-switch-face", width: 390, entities: [autoClean("on")])
        let node = try XCTUnwrap(root.nodes["auto-clean-row"]?.view as? UKServerUILocalControl)
        XCTAssertNil(find(UKModuleToggleRow.self, in: node), "no module row")
        XCTAssertTrue(node.drawnControl is UKControllerToggle, "the plain switch row: \(String(describing: node.drawnControl))")
    }

    func testTheGlyphTintFollowsARuleAndFormMetricsDrawTheFormRow() throws {
        let (_, root) = try page("parts-row-glyph-by-rule", width: 390, entities: [autoClean("on")])
        let green = UIColor(red: 48 / 255, green: 209 / 255, blue: 88 / 255, alpha: 1)
        let tinted = try row(root)
        XCTAssertEqual(tinted.row.rowContent.glyph, green)
        HostedPage.hideTracked()
        let (_, form) = try page("parts-row-form-metrics", width: 390, entities: [autoClean("on")])
        let formRow = try row(form)
        XCTAssertEqual(formRow.row.rowContent.style, .form)
        XCTAssertGreaterThanOrEqual(formRow.bounds.height, 44)
    }

    func testARowAtTheLargestTextSizeStaysReadable() throws {
        for width in Self.widths {
            let (_, root) = try page("parts-row-auto-clean-row", width: width, entities: [autoClean("on")])
            root.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            root.view.layoutIfNeeded()
            let row = try self.row(root)
            XCTAssertGreaterThanOrEqual(row.bounds.height, 60, "width \(width)")
            XCTAssertLessThanOrEqual(row.frame.maxX, root.view.bounds.width + 1)
            HostedPage.hideTracked()
        }
    }

    // MARK: The check face (the climate check rows and `UKCheckRow`)

    private func roomRow(_ root: UKServerUIPage) throws -> UKCheckRow {
        let node = try XCTUnwrap(root.nodes["room-check"]?.view as? UKServerUILocalControl)
        return try XCTUnwrap(find(UKCheckRow.self, in: node), "the check face draws a check row")
    }

    private func room(_ state: String) -> EntityState { EntityState(entityId: "input_boolean.demo_room", state: state) }

    func testACheckFaceDrawsACheckCircleWithNoSwitchAndTheActionTint() throws {
        for width in Self.widths {
            let (_, root) = try page("parts-check-room-row", width: width, entities: [room("on")])
            let check = try roomRow(root)
            XCTAssertEqual(check.rowContent.check?.isChecked, true, "width \(width)")
            XCTAssertEqual(check.rowContent.check?.checkedTint, UKInk.action, "checkTint action is the climate rows' blue")
            XCTAssertNil(check.rowContent.symbol, "a check face has no icon")
            XCTAssertNil(check.rowContent.subtitle)
            let node = try XCTUnwrap(root.nodes["room-check"]?.view)
            XCTAssertTrue(all(UISwitch.self, in: node).isEmpty, "no switch")
            HostedPage.hideTracked()
        }
    }

    func testTheCheckRowIsASelectedButtonWithItsHintAndAFullTarget() throws {
        for width in Self.widths {
            let (_, root) = try page("parts-check-room-row", width: width, entities: [room("on")])
            let check = try roomRow(root)
            XCTAssertEqual(check.toggle.accessibilityLabel, "Master Bedroom")
            XCTAssertEqual(check.toggle.accessibilityHint, "Includes the room in the cycle.")
            XCTAssertTrue(check.toggle.accessibilityTraits.contains(.selected), "width \(width)")
            XCTAssertTrue(check.toggle.accessibilityTraits.contains(.button))
            root.view.layoutIfNeeded()
            XCTAssertGreaterThanOrEqual(check.toggle.bounds.height, 44)
            HostedPage.hideTracked()
            let (_, off) = try page("parts-check-room-row", width: width, entities: [room("off")])
            let unchecked = try roomRow(off)
            XCTAssertFalse(unchecked.toggle.accessibilityTraits.contains(.selected))
            HostedPage.hideTracked()
        }
    }

    func testTheCheckRowFollowsTheEntityAndSendsTheOpposite() async throws {
        let caller = HostedCaller()
        let (host, root) = try page("parts-check-room-row", width: 390, entities: [room("off")], caller: caller)
        let check = try roomRow(root)
        check.toggle.sendActions(for: .touchUpInside)
        await host.callRunner.waitForCalls()
        XCTAssertEqual(caller.calls, ["homeassistant.toggle"])
        store.apply([room("on")])
        let checked = await HostedPage.settle { check.rowContent.check?.isChecked == true }
        XCTAssertTrue(checked, "the entity going on checks the row")
    }

    func testAnUnavailableCheckRowReadsNotEnabledWithTheUnavailableWordsAsItsHint() throws {
        let (_, root) = try page("parts-check-room-row", width: 390, entities: [room("unavailable")])
        let check = try roomRow(root)
        XCTAssertTrue(check.toggle.accessibilityTraits.contains(.notEnabled))
        XCTAssertEqual(check.toggle.accessibilityHint, "Unavailable")
        XCTAssertFalse(check.toggle.isEnabled)
    }

    func testTheSuccessTintDrawsTheGreen() throws {
        let (_, root) = try page("parts-check-success-tint", width: 390, entities: [room("on")])
        let check = try roomRow(root)
        XCTAssertEqual(check.rowContent.check?.checkedTint, UKDesignInk.success)
    }

    // MARK: Screenshots

    /// Saves each part as a PNG when `FENTON_PARTS_SHOTS` names a directory (the owner's screenshot set); skipped otherwise. The documents are
    /// corpus placeholders, never house data.
    func testSavesPartsScreenshotsWhenAsked() async throws {
        guard let directory = ProcessInfo.processInfo.environment["FENTON_PARTS_SHOTS"], !directory.isEmpty else { throw XCTSkip("no screenshot directory") }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let list: JSONValue = .array([.string("quiet"), .string("turbo"), .string("max_power")])
        let shots: [(String, String, [EntityState])] = [
            ("01-start-pause-disc-cleaning", "parts-disc-all-three", [robot("cleaning")]),
            ("02-start-pause-disc-docked", "parts-disc-all-three", [robot("docked")]),
            ("03-two-robots-across", "parts-columns-two-robots-across", [robot("docked")]),
            ("04-choice-options-from-the-entity", "parts-options-from-attribute", [speed("turbo", options: list)]),
            ("05-auto-clean-row-on", "parts-row-auto-clean-row", [autoClean("on")]),
            ("06-auto-clean-row-unavailable", "parts-row-auto-clean-row", [autoClean("unavailable")]),
            ("07-check-row-checked", "parts-check-room-row", [room("on")]),
            ("08-check-row-unchecked", "parts-check-room-row", [room("off")]),
            ("09-check-row-success-tint", "parts-check-success-tint", [room("on")]),
        ]
        for (name, file, entities) in shots {
            let (_, root) = try page(file, width: 390, entities: entities)
            HostedPage.wait(0.4)
            let view = try XCTUnwrap(root.view.window ?? root.view)
            let image = UIGraphicsImageRenderer(bounds: CGRect(x: 0, y: 0, width: view.bounds.width, height: 380)).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            HostedPage.hideTracked()
        }
    }

    // MARK: A bed-shaped authored state tile (generic: a state-tile over a Home Assistant sensor)

    /// The bed-shaped tile is no native concept: a `state-tile` over a sensor whose `line` attribute is the subtitle, with each state's longest line
    /// as its style rule's text (the sizing declaration) and a `present` action. These tests pin what that authored shape does in the grid, per
    /// family, with generic names ("Bed A", "Room X") and placeholder ids.
    private func bedPage(width: CGFloat, entities: [EntityState]? = nil) throws -> (UKServerUIRenderer, UKServerUIPage) {
        store = EntityStore()
        store.replaceAll(entities ?? [AuthoredBedShapedTile.sensor("a", state: "heating"), AuthoredBedShapedTile.sensor("b", state: "off")])
        let host = try UKServerUIRenderer(publication: AuthoredBedShapedTile.publication(), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        windows.append(HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 1180))))
        HostedPage.wait(0.1)
        let root = try ServerUIRendererFixture.root(host)
        root.view.layoutIfNeeded()
        return (host, root)
    }

    private func bedTile(_ side: String, in root: UKServerUIPage) throws -> UKGlassTileView {
        try XCTUnwrap(root.nodes["bed-\(side)"]?.view as? UKGlassTileView, "tile \(side)")
    }

    /// The two tiles stack where one track cannot hold the minimum and are never squeezed below it; they share a row only where both fit.
    func testBedShapedTilesStackOrShareByTheirMinimumAtEveryFamilyWidth() throws {
        for width in AuthoredBedShapedTile.familyWidths {
            let (_, root) = try bedPage(width: width)
            let tiles = try ["a", "b"].map { try bedTile($0, in: root) }
            let minimum = tiles[0].gridMinimumWidth
            let rects = try frames(of: ["bed-a", "bed-b"], in: root)
            let drawn = root.view.bounds.width
            print("BEDSHAPE width=\(width) drawn=\(drawn) minimum=\(minimum) frames=\(rects.map { "\($0.minX),\($0.minY) \($0.width)x\($0.height)" })")
            XCTAssertGreaterThan(minimum, DynamicGridMetrics.tileMinWidth, "the longest line asks for more than one 150 pt track (width \(width))")
            XCTAssertEqual(minimum, tiles[1].gridMinimumWidth, accuracy: 0.5, "both sides declare the same words (width \(width))")
            for frame in rects { XCTAssertGreaterThanOrEqual(frame.width + 0.5, minimum, "never squeezed below its minimum at \(drawn)") }
            let shareRow = abs(rects[0].minY - rects[1].minY) < 1
            if shareRow {
                XCTAssertLessThanOrEqual(2 * minimum + HassTokens.Spacing.m, drawn + 1, "two tiles share a row only where both minimums fit (\(drawn))")
            }
            if drawn < 500 { XCTAssertFalse(shareRow, "one bed tile per row at \(drawn)") }
            HostedPage.hideTracked()
        }
    }

    /// A live flip across every state word, with the line each state has, leaves the grid minimum where it was.
    func testALiveFlipAcrossEveryStateWordLeavesTheGridMinimumUnchanged() async throws {
        for width in AuthoredBedShapedTile.familyWidths {
            let (_, root) = try bedPage(width: width)
            let tile = try bedTile("a", in: root)
            let resting = tile.gridMinimumWidth
            var seen: [String] = []
            for state in AuthoredBedShapedTile.states {
                let line = AuthoredBedShapedTile.liveLines[state] ?? ""
                store.apply([AuthoredBedShapedTile.sensor("a", state: state, line: line)])
                let landed = await HostedPage.settle { tile.model.subtitle == line }
                XCTAssertTrue(landed, "\(state) shows its line at \(width): \(String(describing: tile.model.subtitle))")
                XCTAssertEqual(tile.gridMinimumWidth, resting, accuracy: 0.01, "\(state) keeps the minimum at \(width)")
                seen.append(state)
            }
            XCTAssertEqual(seen, AuthoredBedShapedTile.states)
            // The sensor going unavailable is one more state: the minimum holds there too.
            store.apply([EntityState(entityId: AuthoredBedShapedTile.sensorId("a"), state: "unavailable")])
            let unknown = await HostedPage.settle { tile.model.isUnavailable }
            XCTAssertTrue(unknown, "width \(width)")
            XCTAssertEqual(tile.gridMinimumWidth, resting, accuracy: 0.01, "unavailable keeps the minimum at \(width)")
            HostedPage.hideTracked()
        }
    }

    /// The gap the research named: a live line longer than every declared word is appended to the tile's sizing candidates
    /// (`UKServerUIStateTileParts.apply`), so the minimum grows with it and the grid re-spans. The desired behaviour is expected to fail until
    /// the explicit-lines follow-up lands; when it does this test fails as an unexpected pass, and the expectation goes.
    func testALiveLineLongerThanEveryDeclaredWordDoesNotChangeTheMinimum() async throws {
        let (_, root) = try bedPage(width: 390)
        let tile = try bedTile("a", in: root)
        let resting = tile.gridMinimumWidth
        let long = "Both Sides • Heating • +10 • Check The Unit Water Level"
        store.apply([AuthoredBedShapedTile.sensor("a", state: "heating", line: long)])
        let landed = await HostedPage.settle { tile.model.subtitle == long }
        XCTAssertTrue(landed)
        print("BEDSHAPE longLine resting=\(resting) afterLongLine=\(tile.gridMinimumWidth)")
        XCTExpectFailure("a live subtitle longer than the declared words re-spans the grid (explicit-lines follow-up)") {
            XCTAssertEqual(tile.gridMinimumWidth, resting, accuracy: 0.01)
        }
    }

    /// Tapping the body presents the authored modal; the tile has no disc of its own.
    func testTappingABedShapedTilePresentsTheAuthoredModalAtEveryFamilyWidth() async throws {
        for width in AuthoredBedShapedTile.familyWidths {
            let (host, root) = try bedPage(width: width)
            let tile = try bedTile("a", in: root)
            XCTAssertTrue(tile.model.actions.isEmpty, "no disc: the body is the whole control (width \(width))")
            XCTAssertEqual(tile.model.behavior, .navigate)
            tile.sendActions(for: .touchUpInside)
            let opened = HostedPage.until(8) { host.modal?.topViewController is UKServerUIPage }
            XCTAssertTrue(opened, "the authored modal opened at \(width)")
            HostedPage.settlePresentations(of: host)
            HostedPage.hideTracked()
        }
    }

    /// VoiceOver reads the title, then the line; the tile is one element, at least 44 pt tall, and its line is one line at the minimum.
    func testABedShapedTileIsSpokenAsTitleAndLineAndAtLeast44PointsTallAtEveryFamilyWidth() async throws {
        for width in AuthoredBedShapedTile.familyWidths {
            let (_, root) = try bedPage(width: width)
            let tile = try bedTile("a", in: root)
            XCTAssertEqual(tile.accessibilityLabel, "Bed A", "width \(width)")
            XCTAssertTrue((tile.accessibilityValue ?? "").contains("Heating • +3"), "the value carries the line: \(tile.accessibilityValue ?? "nil") (width \(width))")
            // The tile is a container of its body element (and the line's); the body is the button that opens the modal.
            let body = (tile.accessibilityElements ?? []).compactMap { $0 as? UIAccessibilityElement }.first { $0.accessibilityIdentifier == "bed-a" }
            XCTAssertTrue(try XCTUnwrap(body, "the body element (width \(width))").accessibilityTraits.contains(.button), "a tile that opens something is a button (width \(width))")
            XCTAssertEqual(body?.accessibilityLabel, "Bed A")
            XCTAssertGreaterThanOrEqual(tile.bounds.height, 44, "touch height at \(width)")
            store.apply([AuthoredBedShapedTile.sensor("a", state: "view_only", line: "Hold · View Only")])
            let moved = await HostedPage.settle { (tile.accessibilityValue ?? "").contains("Hold · View Only") }
            XCTAssertTrue(moved, "the spoken value follows the live line at \(width)")
            XCTAssertEqual(tile.accessibilityLabel, "Bed A")
            HostedPage.hideTracked()
        }
    }

    /// An unavailable sensor reads Unavailable, dims through the unknown class and keeps its title.
    func testAnUnavailableBedShapedTileDimsAndSaysSoAtEveryFamilyWidth() async throws {
        for width in AuthoredBedShapedTile.familyWidths {
            let (_, root) = try bedPage(width: width)
            let tile = try bedTile("a", in: root)
            store.apply([EntityState(entityId: AuthoredBedShapedTile.sensorId("a"), state: "unavailable")])
            let dimmed = await HostedPage.settle { tile.model.isUnavailable }
            XCTAssertTrue(dimmed, "width \(width)")
            XCTAssertEqual(tile.model.look?.stateClass, .unknown, "the unknown class draws the dim face (width \(width))")
            XCTAssertEqual(tile.gridFace, .unavailable)
            XCTAssertTrue((tile.accessibilityValue ?? "").contains("Unavailable"), "VoiceOver says Unavailable: \(tile.accessibilityValue ?? "nil")")
            XCTAssertEqual(tile.accessibilityLabel, "Bed A")
            HostedPage.hideTracked()
        }
    }

    /// The countdown reads the second clock only while the state is boost and the sensor carries an end: no other state ticks.
    func testTheBedCountdownTicksOnlyWhileBoostHolds() async throws {
        let (host, root) = try bedPage(width: 390)
        let source = host.bindings.appState
        let tile = try bedTile("a", in: root)
        let appeared = await HostedPage.settle { root.presence.isOnScreen }
        XCTAssertTrue(appeared)
        for state in ["heating", "cooling", "idle", "off", "view_only"] {
            store.apply([AuthoredBedShapedTile.sensor("a", state: state, line: AuthoredBedShapedTile.liveLines[state] ?? "")])
            _ = await HostedPage.settle(passes: 40) { false }
            XCTAssertFalse(source.isSecondTicking, "\(state) has no countdown to tick")
        }
        XCTAssertEqual(source.secondTicks, 0, "no second tick was ever published")
        let end = ServerUIAppState.clock(at: Date().addingTimeInterval(3_600)).now
        store.apply([AuthoredBedShapedTile.sensor("a", state: "boost", line: "Boost Mode • Cooling", endsAt: end)])
        let counting = await HostedPage.settle { source.isSecondTicking && (tile.model.subtitle ?? "").hasSuffix(" Remaining") }
        XCTAssertTrue(counting, "boost with an end counts down: \(String(describing: tile.model.subtitle)) (ticking \(source.isSecondTicking))")
        let first = tile.model.subtitle
        let moved = await HostedPage.settle { tile.model.subtitle != first }
        XCTAssertTrue(moved, "the countdown moves with the second clock: \(String(describing: first)) -> \(String(describing: tile.model.subtitle))")
        // Boost with no end falls back to the line's own words and reads no clock.
        store.apply([AuthoredBedShapedTile.sensor("a", state: "boost", line: "Boost Mode • Cooling")])
        let fallback = await HostedPage.settle { tile.model.subtitle == "Boost Mode • Cooling" }
        XCTAssertTrue(fallback, "no end: \(String(describing: tile.model.subtitle))")
        // Back to heating: the tick stops within a tick or two and nothing publishes after.
        store.apply([AuthoredBedShapedTile.sensor("a", state: "heating")])
        let stopped = await HostedPage.settle(passes: 500) { !source.isSecondTicking }
        XCTAssertTrue(stopped, "heating again: the tick stops")
        let ticks = source.secondTicks
        _ = await HostedPage.settle(passes: 100) { source.isSecondTicking }
        XCTAssertEqual(source.secondTicks, ticks, "nothing publishes once the countdown is gone")
    }
}

// MARK: - The authored bed-shaped state tile

/// The Studio's bed-shaped tile as a document: a `room-section` of two `state-tile`s over generic sensors ("Bed A", "Bed B" in "Room X").
///
/// Each sensor's `state` is a state word, its `line` attribute the full subtitle and its `ends_at` the end of a timed mode. The style's rule texts
/// are each state's longest line (what sizes the tile); the subtitle is the sensor's line, or a countdown to `ends_at` while the state is
/// `boost`. No product code names a bed: nothing here is read by anything but the generic state-tile parts.
@MainActor
enum AuthoredBedShapedTile {
    /// The widths of the four families: iPhone, folded Duo, iPad and unfolded Duo.
    static let familyWidths: [CGFloat] = [390, 466, 744, 868]
    /// The state words the sensor takes, in the order the flip walks them.
    static let states = ["heating", "cooling", "idle", "off", "boost", "view_only"]
    /// Each state's longest line: the style rule text.
    static let longest: [String: String] = [
        "heating": "Both Sides • Heating • +10", "cooling": "Both Sides • Cooling • -10", "idle": "Both Sides • Idle • 0",
        "off": "Both Sides • Off", "boost": "Both Sides • Boost Mode • Cooling", "view_only": "Hold · View Only",
    ]
    /// The line each state shows live, at most as long as its declared words.
    static let liveLines: [String: String] = [
        "heating": "Heating • +3", "cooling": "Cooling • -5", "idle": "Idle • 0", "off": "Off",
        "boost": "Boost Mode • Cooling", "view_only": "Hold · View Only",
    ]

    static func sensorId(_ side: String) -> String { side == "a" ? "sensor.demo_bed_a" : "sensor.demo_bed_b" }

    /// The sensor for `side` in `state`; the line defaults to the state's live line.
    static func sensor(_ side: String, state: String, line: String? = nil, endsAt: String? = nil) -> EntityState {
        var attributes: [String: JSONValue] = ["line": .string(line ?? liveLines[state] ?? "")]
        if let endsAt { attributes["ends_at"] = .string(endsAt) }
        return EntityState(entityId: sensorId(side), state: state, attributes: attributes)
    }

    private static func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    private static func read(_ source: String, _ path: String) -> String {
        #"{"type":"read","from":{"type":"source","sourceId":"\#(source)","path":[\#(path)]},"as":"string","missing":"unavailable"}"#
    }

    /// The tile's subtitle: the sensor's line, or `m:ss Remaining` to `ends_at` while the state is boost.
    private static func subtitle(_ source: String) -> String {
        """
        {"type":"expr","fallback":"Boost Mode • Cooling","value":{"type":"choose","otherwise":\(read(source, #""attributes","line""#)),
         "cases":[{"when":{"type":"compare","op":"eq","left":\(read(source, #""state""#)),"right":{"type":"literal","value":"boost"}},
         "then":{"type":"format","pattern":"{s} Remaining","args":{"s":{"type":"date","op":"seconds-between","from":{"type":"clock","part":"now-second"},
         "to":\(read(source, #""attributes","ends_at""#))}},"formats":{"s":{"duration":{"style":"minutes-seconds"}}}}}]}}
        """
    }

    private static func rule(_ states: [String], class stateClass: String, active: Bool, icon: String, text: String, rgb: (Int, Int, Int)?) -> String {
        let fill = rgb.map { #","fill":{"type":"solid-rgb","red":\#($0.0),"green":\#($0.1),"blue":\#($0.2)}"# } ?? ""
        let names = states.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"states":[\#(names)],"class":"\#(stateClass)","active":\#(active),"icon":"\#(icon)","text":"\#(text)"\#(fill)}"#
    }

    private static func tile(_ side: String, title: String) -> String {
        """
        {"id":"bed-\(side)","title":"\(title)","type":"state-tile","layout":{"span":1},
         "icon":{"type":"sf-symbol","name":"bed.double","rendering":"canonical","unavailable":"fallback"},
         "props":{"subtitle":\(subtitle("src-\(side)"))},
         "binding":{"entityId":"\(sensorId(side))","styleId":"bed-state"},
         "action":{"type":"present","modalId":"modal-swatch","arguments":{},"ifPresented":"reject"}}
        """
    }

    /// The synthetic fixture with the section, the style, the two sensors as sources and the capabilities they need.
    static func publication() throws -> ServerUICompositionPublication {
        var root = try ServerUIRendererFixture.json()
        var sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        for side in ["a", "b"] {
            sources.append(try json(#"{"id":"src-\#(side)","kind":"ha-entity","entityId":{"type":"literal","value":"\#(sensorId(side))"}}"#))
        }
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources", to: .array(sources))
        let rules = [
            rule(["heating"], class: "resting", active: true, icon: "flame.fill", text: longest["heating"] ?? "", rgb: (200, 90, 40)),
            rule(["cooling"], class: "resting", active: true, icon: "snowflake", text: longest["cooling"] ?? "", rgb: (40, 110, 200)),
            rule(["idle"], class: "resting", active: false, icon: "bed.double", text: longest["idle"] ?? "", rgb: nil),
            rule(["off"], class: "resting", active: false, icon: "bed.double", text: longest["off"] ?? "", rgb: nil),
            rule(["boost"], class: "in-progress", active: true, icon: "thermometer.snowflake", text: longest["boost"] ?? "", rgb: (40, 110, 200)),
            rule(["view_only"], class: "warning", active: false, icon: "eye", text: longest["view_only"] ?? "", rgb: nil),
            rule(["unavailable", "unknown"], class: "unknown", active: false, icon: "bed.double", text: "Unavailable", rgb: nil),
        ].joined(separator: ",")
        root = try ServerUIRendererFixture.changing(root, path: "/document/stateStyles", to: json(
            #"{"type":"state-styles@1","styles":[{"id":"bed-state","name":"Bed state","domain":"sensor","rules":[\#(rules)],"fallback":{"class":"unknown","active":false}}]}"#))
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: json(
            #"[{"id":"room-x","type":"room-section","title":"Room X","layout":{"span":1},"props":{"arrangement":"grid","leadJoinsAtRegularWidth":false},"children":[\#(tile("a", title: "Bed A")),\#(tile("b", title: "Bed B"))]}]"#))
        let needed = ["sh.room-section@1", "sh.state-style@1", "sh.state-style-fills@1", "sh.tile-parts@1", "sh.conditions@1", "sh.operands@1", "sh.rules@1",
                      "sh.countdown@1", "sh.duration-format@1", "sh.pipeline-operands@1"]
        let existing = try XCTUnwrap(root["capabilities"]?.array?.compactMap(\.string))
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(Set(existing + needed).sorted().map(JSONValue.string)))
        return try ServerUIRendererFixture.publication(root)
    }
}
