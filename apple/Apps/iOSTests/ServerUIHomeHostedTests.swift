import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Configured Home primitives

/// Synthetic, network-free journeys and AX semantics, executable unchanged on iPhone, Duo and iPad.
@MainActor
final class ServerUIHomeHostedTests: XCTestCase {
    private func json() throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIHomeFixture.json")))
    }

    private func publication(_ value: JSONValue? = nil) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(JSONEncoder().encode(value ?? json()))
    }

    private func makeHost(caller: any HassServiceCalling) throws -> (UKServerUIRenderer, UIWindow, UKServerUIPage) {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "light.demo_study", state: "off")])
        let host = try UKServerUIRenderer(publication: publication(), context: UKContext(store: store, caller: caller),
                                          backdrop: ServerUIRendererFixture.backdrop(), weatherReader: reader())
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: 390, height: 844)))
        let root = try XCTUnwrap(host.stacks[.initial]?.viewControllers.first as? UKServerUIPage)
        HostedPage.layoutTracked()
        return (host, window, root)
    }

    private func reader() -> ServerUIWeatherReader {
        ServerUIWeatherReader(entityIds: ["weather.demo_forecast"]) { entity, _ in
            .object([entity: .object(["forecast": .array([])])])
        }
    }

    func testIsolatedRendererRequiresScopedReaderAndKeepsRejectingCommandCaller() async throws {
        let caller = HomeRejectingCaller()
        let context = UKContext(store: EntityStore(), caller: caller)
        XCTAssertNil(context.connection)
        XCTAssertThrowsError(try UKServerUIRenderer(publication: publication(), context: context,
                                                    backdrop: ServerUIRendererFixture.backdrop())) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .unavailableSource)
        }
        let (host, window, _) = try makeHost(caller: caller)
        defer { window.isHidden = true }
        let source = try XCTUnwrap(host.bindings.weather["fixture-weather"])
        await source.driver.forecasts.settle()
        XCTAssertEqual(source.hourly.phase, .empty)
        XCTAssertEqual(source.daily.phase, .empty)
        XCTAssertNil(host.pageContext.connection)
        XCTAssertEqual(caller.attempts, 0, "Forecast reads never traverse the command caller.")
        let light = try XCTUnwrap(host.bindings.lights["fixture-light-source"])
        await (try light.perform(LightControl.power("light.demo_study", on: true))).value
        XCTAssertEqual(caller.attempts, 1, "The original rejecting command path is still installed.")
        let changed = try ServerUIRendererFixture.changing(json(),
            path: "/document/dataSources/1/inputs/weatherEntityId/value", to: .string("weather.demo_other"))
        XCTAssertThrowsError(try host.validateUpdate(publication(changed))) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .unavailableSource)
        }
        XCTAssertTrue(host.bindings.weather["fixture-weather"] === source)
    }

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    func testStatusOpensTheConfiguredOverviewPushesDetailAndReturnsWithoutSendingACommand() throws {
        let caller = HostedCaller(), (host, window, root) = try makeHost(caller: caller)
        defer { window.isHidden = true }
        let chip = try XCTUnwrap(root.nodes["fixture-chip"]?.view as? UKStatusChipView)
        XCTAssertEqual(chip.accessibilityLabel, "Study lights, All Off")
        XCTAssertTrue(chip.accessibilityTraits.contains(.button))
        chip.sendActions(for: .touchUpInside)
        HostedPage.until { host.modal?.presentingViewController != nil && host.modal?.transitionCoordinator == nil }
        let modal = try XCTUnwrap(host.modal)
        let overview = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
        let room = try XCTUnwrap(overview.nodes["fixture-room"]?.view as? UKGlassTileView)
        XCTAssertTrue(room.accessibilityActivate())
        HostedPage.until { modal.transitionCoordinator == nil }
        let detail = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
        XCTAssertEqual(detail.surfaceID, "fixture-detail")
        XCTAssertNotNil(detail.nodes["fixture-light"])
        XCTAssertTrue(detail.accessibilityPerformEscape())
        HostedPage.until { modal.transitionCoordinator == nil }
        XCTAssertTrue(modal.topViewController === overview)
        try host.perform(.dismiss(scope: .currentModal), from: overview)
        HostedPage.until { host.modal == nil }
        XCTAssertTrue(root.nodes["fixture-chip"]?.view === chip)
        XCTAssertTrue(caller.calls.isEmpty, "Navigation does not invoke a lighting intent")
    }

    func testLiveStatusAndAX5ReuseTheChipRailAndWeatherSource() throws {
        let (host, window, root) = try makeHost(caller: HostedCaller())
        defer { window.isHidden = true }
        let chip = try XCTUnwrap(root.nodes["fixture-chip"]?.view as? UKStatusChipView)
        let rail = try XCTUnwrap(root.nodes["fixture-rail"]?.view as? UKChipRailView)
        let source = try XCTUnwrap(host.bindings.weather["fixture-weather"])
        host.pageContext.store.apply([EntityState(entityId: "light.demo_study", state: "on")])
        HostedPage.until { chip.accessibilityLabel == "Study lights, 1 On" }
        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        HostedPage.layoutTracked()
        XCTAssertEqual(rail.mode, .wrap)
        XCTAssertTrue(root.nodes["fixture-chip"]?.view === chip)
        XCTAssertTrue(root.nodes["fixture-rail"]?.view === rail)
        host.bindings.apply(host.publication.document.dataSources)
        XCTAssertTrue(host.bindings.weather["fixture-weather"] === source)
        XCTAssertEqual(chip.accessibilityLabel, "Study lights, 1 On")
        XCTAssertGreaterThan(chip.frame.height, 0)
    }

    func testNetworkLifetimeBlocksControlRetargetAndTitleReplacementAfterOverlayExpiry() async throws {
        let caller = HomeHostedHeldCaller()
        let (host, window, _) = try makeHost(caller: caller)
        defer { window.isHidden = true; caller.finish() }
        let light = try XCTUnwrap(host.bindings.lights["fixture-light-source"])
        let task = try light.perform(LightControl.power("light.demo_study", on: true))
        await caller.waitForStart()
        light.actions.overlay.reset("light.demo_study")
        XCTAssertTrue(light.hasPendingIntent)
        for (path, replacement) in [
            ("/document/dataSources/2/inputs/entityId/value", "light.demo_other"),
            ("/document/pages/1/components/0/title", "Changed while in flight"),
        ] {
            let candidate = try publication(ServerUIRendererFixture.changing(json(), path: path, to: .string(replacement)))
            XCTAssertThrowsError(try host.validateUpdate(candidate)) {
                XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .interactionBlocked)
            }
        }
        caller.finish()
        await task.value
        XCTAssertEqual(caller.target, "light.demo_study")
    }

    func testPublicationReplacesAReusedIDWithItsNewControlFamilyAndRetainsUnchangedChildren() throws {
        let (host, window, root) = try makeHost(caller: HostedCaller())
        defer { window.isHidden = true }
        let oldRail = try XCTUnwrap(root.nodes["fixture-rail"]?.view as? UKChipRailView)
        let chip = try XCTUnwrap(root.nodes["fixture-chip"]?.view)
        let weather = try XCTUnwrap(root.nodes["fixture-summary"]?.view)
        var candidate = try json()
        var components = try XCTUnwrap(candidate["document"]?["pages"]?.array?.first?["components"]?.array)
        let movedRail = try ServerUIRendererFixture.changing(components[0], path: "/id", to: .string("moved-rail"))
        components[0] = .object([
            "id": .string("fixture-rail"), "title": .string("Replacement row"), "type": .string("row"),
            "layout": .object(["span": .number(1)]),
            "props": .object([
                "primary": .object(["type": .string("literal"), "value": .string("Replacement content")]),
                "secondary": .object(["type": .string("literal"), "value": .string("")]),
                "value": .object(["type": .string("literal"), "value": .string("Ready")]),
                "accessory": .string("none"), "loadingText": .string("Loading"),
                "unavailableText": .string("Unavailable"),
            ]),
        ])
        components.append(movedRail)
        candidate = try ServerUIRendererFixture.changing(candidate, path: "/document/pages/0/components", to: .array(components))
        let capabilities = (host.publication.capabilities + ["sh.rows@1"]).sorted().map(JSONValue.string)
        candidate = try ServerUIRendererFixture.changing(candidate, path: "/capabilities", to: .array(capabilities))
        candidate = try ServerUIRendererFixture.changing(candidate, path: "/revision", to: .number(2))
        try host.apply(publication: publication(candidate), backdrop: ServerUIRendererFixture.backdrop())
        HostedPage.layoutTracked()

        let row = try XCTUnwrap(root.nodes["fixture-rail"]?.view as? UKServerUIRow)
        XCTAssertTrue(HostedPage.labels(in: row).contains("Replacement content"))
        XCTAssertNil(oldRail.window)
        XCTAssertTrue(root.nodes["fixture-chip"]?.view === chip)
        XCTAssertTrue(root.nodes["fixture-summary"]?.view === weather)

        candidate = try ServerUIRendererFixture.changing(candidate,
            path: "/document/pages/0/components/0/props/primary/value", to: .string("Updated content"))
        candidate = try ServerUIRendererFixture.changing(candidate, path: "/revision", to: .number(3))
        try host.apply(publication: publication(candidate), backdrop: ServerUIRendererFixture.backdrop())
        XCTAssertTrue(root.nodes["fixture-rail"]?.view === row)
        XCTAssertTrue(HostedPage.labels(in: row).contains("Updated content"))
    }

    func testVisibleWeatherPoliciesCannotDiscardPagingStateDuringPublication() throws {
        let (host, window, _) = try makeHost(caller: HostedCaller())
        defer { window.isHidden = true }
        let value = try ServerUIRendererFixture.changing(json(), path: "/document/pages/0/components/1/props/compactHours", to: .number(4))
        XCTAssertThrowsError(try host.validateUpdate(publication(value))) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .interactionBlocked)
        }
    }

    func testExtractedWeatherCardSpeaksAuthoredEmptyCopyAndKeepsItsHeaderAction() throws {
        let card = UKWeatherCardContentView(isNarrow: false, onOpen: nil)
        card.emptyLabel = "No synthetic forecast"
        card.openLabel = "Inspect synthetic forecast."
        var opened = 0
        card.onOpen = { opened += 1 }
        let current = WeatherCurrent(entity: EntityState(entityId: "weather.demo_forecast", state: "rainy",
                                                        attributes: ["temperature": .number(18), "temperature_unit": .string("°C")]))
        card.apply(current: current, night: false, feed: WeatherForecastFeed(phase: .empty), today: nil, briefing: nil)
        let button = try XCTUnwrap(HostedPage.descendants(of: card).first { $0.accessibilityIdentifier == "home.weather.card" } as? UIControl)
        XCTAssertTrue(button.accessibilityTraits.contains(.button))
        XCTAssertTrue(button.accessibilityLabel?.contains("Inspect synthetic forecast.") == true)
        XCTAssertTrue(HostedPage.labels(in: card).contains("No synthetic forecast"))
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(opened, 1)
        card.onOpen = nil
        card.apply(current: current, night: false, feed: WeatherForecastFeed(phase: .empty), today: nil, briefing: nil)
        XCTAssertTrue(button.accessibilityTraits.contains(.staticText))
    }

    func testWeatherSourceRejectsMissingCallerInsteadOfShowingEndlessSuccessfulLoading() throws {
        let p = try publication()
        guard case .homeWeather(_, let configuration) = p.document.dataSources[1] else { return XCTFail("Weather fixture") }
        let source = UKServerUIWeatherSource(configuration: configuration, context: UKContext(store: EntityStore()))
        XCTAssertEqual(source.hourly.phase, .error)
        XCTAssertNotNil(source.hourly.error)
        let feed = WeatherForecastFeed(forecasts: [WeatherForecast(temperature: 18)], phase: .ready,
                                      updatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(source.isStale(feed, now: Date(timeIntervalSince1970: WeatherForecastStore.timeToLive + 1)))
        XCTAssertFalse(source.isStale(WeatherForecastFeed(), now: Date()))
    }
}

// MARK: - Held service

@MainActor
private final class HomeRejectingCaller: HassServiceCalling {
    private(set) var attempts = 0
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        attempts += 1
        throw NSError(domain: "PreviewCommandsRejected", code: 1)
    }
}

@MainActor
private final class HomeHostedHeldCaller: HassServiceCalling {
    private var completion: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var target: String?

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        target = data["entity_id"] as? String
        await withCheckedContinuation {
            completion = $0
            started?.resume()
            started = nil
        }
    }

    func waitForStart() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() { completion?.resume(); completion = nil }
}
