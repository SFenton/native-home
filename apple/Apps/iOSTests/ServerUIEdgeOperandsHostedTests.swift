import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - The edge operands, drawn

/// Hosted UX and accessibility checks for the edge operands (`sh.entity-time@1`, `sh.countdown@1`, `sh.duration-format@1`, `sh.math-truncate@1`).
///
/// Each test runs at the iPhone, iPhone Duo and iPad widths (a simulator narrower than a width draws it at the simulator's own, as the other hosted
/// layout tests do). The documents are the Studio's own corpus cases. A countdown text carries `updatesFrequently`, so VoiceOver does not announce
/// every second; a text that reads no second clock does not.
@MainActor
final class ServerUIEdgeOperandsHostedTests: XCTestCase {
    /// The widths of the three families: iPhone, folded Duo and iPad.
    private static let widths: [CGFloat] = [390, 744, 1024]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    /// The corpus case `file`, with the components of its third page moved onto the page the renderer opens first.
    private func publicationJSON(_ file: String) throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/\(file).json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    private func publication(_ file: String) throws -> ServerUICompositionPublication {
        var json = try publicationJSON(file)
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[2]["components"]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    /// The countdown case with a second text added whose `visibleWhen` compares the second clock: the document an author gets from a rule such as
    /// "show this after the countdown starts". Only the countdown text draws a value that changes each second.
    private func publicationWithClockRule() throws -> ServerUICompositionPublication {
        var json = try publicationJSON("countdown-clock-text")
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        var components = try XCTUnwrap(pages[2]["components"]?.array)
        let rule = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {"id":"rule","title":"rule","type":"text","layout":{"span":1},"props":{"value":{"type":"literal","value":"Plain"},"style":"body","unavailableText":"None"},
         "visibleWhen":{"type":"compare","op":"after","left":{"type":"clock","part":"now-second"},"right":{"type":"literal","value":"2000-01-01T00:00:00"}}}
        """#.utf8))
        components.append(rule)
        let capabilities = try XCTUnwrap(json["capabilities"]?.array) + [.string("sh.conditions@1"), .string("sh.visible-when@1")]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted { ($0.string ?? "") < ($1.string ?? "") }))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    private func open(_ file: String, width: CGFloat, entities: [EntityState], publication custom: ServerUICompositionPublication? = nil) async throws -> (UKServerUIRenderer, UKServerUIPage) {
        let store = EntityStore()
        store.replaceAll(entities)
        let host = try UKServerUIRenderer(publication: custom ?? publication(file), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        _ = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 1180)))
        HostedPage.wait(0.1)
        let root = try ServerUIRendererFixture.root(host)
        root.view.layoutIfNeeded()
        // UIKit reports the page on screen from its key window; nothing here calls an appearance method by hand.
        let appeared = await HostedPage.settle { root.presence.isOnScreen }
        XCTAssertTrue(appeared, "UIKit must report the page on screen (window \(String(describing: root.view.window)))")
        return (host, root)
    }

    private func texts(in view: UIView) -> [UKServerUIText] {
        ((view as? UKServerUIText).map { [$0] } ?? []) + view.subviews.flatMap { texts(in: $0) }
    }

    /// A fan whose timer finishes an hour from now, on the wall clock the app reads.
    private func fan() -> EntityState {
        let finish = ServerUIAppState.clock(at: Date().addingTimeInterval(3_600)).now
        return EntityState(entityId: "fan.demo_bath_fan", state: "on", attributes: ["finishes_at": .string(finish)])
    }

    // MARK: Tests

    func testACountdownTextUpdatesFrequentlyAtEveryWidth() async throws {
        for width in Self.widths {
            let (_, page) = try await open("countdown-clock-text", width: width, entities: [fan()])
            let text = try XCTUnwrap(texts(in: page.view).first { ($0.accessibilityLabel ?? "").hasPrefix("Off in ") }, "width \(width)")
            XCTAssertTrue(text.accessibilityTraits.contains(.updatesFrequently), "width \(width)")
            XCTAssertTrue(text.accessibilityTraits.contains(.staticText), "width \(width)")
            XCTAssertTrue(text.isAccessibilityElement, "width \(width)")
            HostedPage.hideTracked()
        }
    }

    func testACountdownTextCountsDownOncePerSecond() async throws {
        let (host, page) = try await open("countdown-clock-text", width: 390, entities: [fan()])
        let text = try XCTUnwrap(texts(in: page.view).first { ($0.accessibilityLabel ?? "").hasPrefix("Off in ") })
        let first = text.accessibilityLabel
        let source = host.bindings.appState
        let moved = await HostedPage.settle { text.accessibilityLabel != first }
        XCTAssertTrue(moved, "the text must move with the second clock (on screen \(page.presence.isOnScreen), ticking \(source.isSecondTicking), ticks \(source.secondTicks), window \(String(describing: page.view.window)), label \(String(describing: text.accessibilityLabel)))")
    }

    /// A rule that reads the second clock decides whether the node shows; it does not change what the node says each second.
    func testARuleThatReadsTheSecondClockDoesNotMarkItsNodeUpdatesFrequently() async throws {
        let (_, page) = try await open("countdown-clock-text", width: 390, entities: [fan()], publication: publicationWithClockRule())
        let all = texts(in: page.view)
        let plain = try XCTUnwrap(all.first { ($0.accessibilityLabel ?? "") == "Plain" }, "the node with the rule is drawn")
        let countdown = try XCTUnwrap(all.first { ($0.accessibilityLabel ?? "").hasPrefix("Off in ") })
        XCTAssertFalse(plain.accessibilityTraits.contains(.updatesFrequently), "a visibleWhen read of the second clock is not a changing value")
        XCTAssertTrue(countdown.accessibilityTraits.contains(.updatesFrequently), "the countdown text still carries the trait")
    }

    func testATextThatReadsNoSecondClockDoesNotUpdateFrequently() async throws {
        for width in Self.widths {
            let (_, page) = try await open("entity-time-since-line", width: width, entities: [])
            let all = texts(in: page.view)
            XCTAssertFalse(all.isEmpty, "width \(width)")
            XCTAssertTrue(all.allSatisfy { !$0.accessibilityTraits.contains(.updatesFrequently) }, "width \(width)")
            HostedPage.hideTracked()
        }
    }

    // MARK: The 1 Hz path

    /// No reader, no timer: a source nobody reads `now-second` from never schedules a tick, and the main thread does no per-second work for it.
    func testNoReaderMeansNoSecondTimer() async {
        let source = UKServerUIAppStateSource(push: nil, defaults: UserDefaults(suiteName: "edge-operands-no-reader") ?? .standard)
        XCTAssertFalse(source.isSecondTicking)
        XCTAssertNil(source.secondClock)
        // Nothing starts it: a pass of the run loop later it is still quiet.
        _ = await HostedPage.settle(passes: 60) { source.isSecondTicking }
        XCTAssertFalse(source.isSecondTicking)
        XCTAssertEqual(source.secondTicks, 0)
    }

    /// The first read starts the tick, each tick is a single write, and one tick after the last read it stops.
    func testTheSecondTickStartsOnReadAndStopsAfterTheLastRead() async {
        let source = UKServerUIAppStateSource(push: nil, defaults: UserDefaults(suiteName: "edge-operands-tick") ?? .standard)
        XCTAssertNotNil(source.secondClockForReading())
        XCTAssertTrue(source.isSecondTicking)
        let kept = await HostedPage.settle { source.secondTicks >= 2 }
        XCTAssertTrue(kept || source.secondTicks >= 1, "the clock publishes about once a second")
        // Nobody reads it again: it stops within a tick or two.
        let stopped = await HostedPage.settle(passes: 400) { !source.isSecondTicking }
        XCTAssertTrue(stopped, "a tick that finds no read since the last one stops")
    }

    /// A page in another tab or under a pushed page is away: its countdown reads keep no tick running, and the page coming back starts it again.
    func testAPageThatLeftTheScreenKeepsNoTickAndStartsItOnReturn() async throws {
        let (host, page) = try await open("countdown-clock-text", width: 390, entities: [fan()])
        let source = host.bindings.appState
        let text = try XCTUnwrap(texts(in: page.view).first { ($0.accessibilityLabel ?? "").hasPrefix("Off in ") })
        XCTAssertTrue(page.presence.isOnScreen)
        let ticking = await HostedPage.settle { source.isSecondTicking }
        XCTAssertTrue(ticking, "a visible countdown ticks (on screen \(page.presence.isOnScreen), ticks \(source.secondTicks))")
        // Another tab is selected, as a real tab switch.
        let tabs = host.tabController
        XCTAssertGreaterThan(tabs.viewControllers?.count ?? 0, 1, "the document has a second tab to select")
        let home = tabs.selectedIndex
        tabs.selectedIndex = (home + 1) % max(tabs.viewControllers?.count ?? 1, 1)
        let left = await HostedPage.settle { !page.presence.isOnScreen }
        XCTAssertTrue(left, "a page in an unselected tab is off screen (UIKit sent its disappearance)")
        let stopped = await HostedPage.settle(passes: 500) { !source.isSecondTicking }
        XCTAssertTrue(stopped, "no countdown on screen: the tick stops within a tick or two")
        let ticksAway = source.secondTicks
        _ = await HostedPage.settle(passes: 100) { source.isSecondTicking }
        XCTAssertEqual(source.secondTicks, ticksAway, "nothing publishes while the page is away")
        // The page returns: the countdown runs again, from the current time.
        tabs.selectedIndex = home
        let back = await HostedPage.settle { page.presence.isOnScreen }
        XCTAssertTrue(back, "selecting its tab again puts the page back on screen")
        let restarted = await HostedPage.settle { source.isSecondTicking }
        XCTAssertTrue(restarted, "coming back starts the tick")
        let label = text.accessibilityLabel
        let moved = await HostedPage.settle { text.accessibilityLabel != label }
        XCTAssertTrue(moved)
    }
}
