import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - All-family configured climate regression

@MainActor
final class UKHostedServerUIClimateTests: XCTestCase {
    private func publication() throws -> ServerUICompositionPublication {
        var json = try ServerUIRendererFixture.json()
        var sources = try XCTUnwrap(json["document"]?["dataSources"]?.array)
        sources += try JSONDecoder().decode([JSONValue].self, from: Data("""
            [{"id":"source-zone","kind":"model","model":"climate@1",
              "inputs":{"entityId":"climate.demo_zone","rangeCommitEntityIds":[]}},
             {"id":"source-eco","kind":"model","model":"climate@1",
              "inputs":{"entityId":"switch.demo_lamp","rangeCommitEntityIds":[]}}]
            """.utf8))
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources", to: .array(sources))
        var nodes = try XCTUnwrap(json["document"]?["pages"]?.array?[0]["components"]?.array)
        nodes += try JSONDecoder().decode([JSONValue].self, from: Data("""
            [{"id":"dial-authored","title":"Test Zone","type":"climate-control","layout":{"span":1},
              "props":{"kind":"dial","sourceId":"source-zone","icon":"thermometer","hint":"Set this zone",
               "loadingText":"Reading zone","unavailableText":"No zone","errorText":"Try the zone again",
               "dial":{"minimum":5,"maximum":35,"step":0.5,"unit":"°C","size":"compact"}}},
             {"id":"eco-authored","title":"Zone Economy","type":"climate-control","layout":{"span":1},
              "props":{"kind":"toggle","sourceId":"source-eco","icon":"leaf","hint":"Save energy",
               "loadingText":"Reading economy","unavailableText":"Economy unavailable","errorText":"Try economy again"}}]
            """.utf8))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(nodes))
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities",
                                                   to: .array((ServerUICompositionPublication.firstSliceCapabilities
                                                    + ["sh.climate-source@1", "sh.climate-dial@1", "sh.climate-toggle@1"]).sorted().map(JSONValue.string)))
        return try ServerUIRendererFixture.publication(json)
    }

    func testConfiguredDialAndToggleRetainNativeInstancesAndAccessibleLabelsAcrossFamilyWidths() async throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678),
                     CGSize(width: 951, height: 669), CGSize(width: 1024, height: 1366)] {
            let (host, window, caller) = try ServerUIRendererFixture.host(publication: publication(), size: size)
            defer { window.isHidden = true }
            host.pageContext.store.apply([
                EntityState(entityId: "climate.demo_zone", state: "heat_cool", attributes: [
                    "current_temperature": .number(21), "target_temp_low": .number(19), "target_temp_high": .number(24),
                    "temperature_unit": .string("°C")
                ])
            ])
            await HostedPage.pump(passes: 5)
            let page = try ServerUIRendererFixture.root(host)
            let control = try XCTUnwrap(page.nodes["dial-authored"]?.view)
            let dial = try XCTUnwrap(HostedPage.descendants(of: control).compactMap { $0 as? UKThermostatDial }.first)
            let toggleControl = try XCTUnwrap(page.nodes["eco-authored"]?.view)
            HostedPage.layoutTracked()
            XCTAssertGreaterThan(dial.bounds.height, HassTokens.minTarget)
            XCTAssertGreaterThanOrEqual(control.bounds.height, dial.bounds.height)
            XCTAssertGreaterThanOrEqual(toggleControl.bounds.height, HassTokens.minTarget)
            XCTAssertGreaterThanOrEqual(toggleControl.frame.minY, control.frame.maxY)
            XCTAssertEqual(dial.configuration.title, "Test Zone")
            XCTAssertEqual(dial.configuration.unit, "°C")
            XCTAssertEqual(dial.configuration.step, 0.5)
            let toggle = try XCTUnwrap(HostedDriver.controls(UISwitch.self, in: page.view).first { $0.accessibilityIdentifier == "eco-authored" })
            XCTAssertEqual(toggle.accessibilityLabel, "Zone Economy")
            XCTAssertEqual(toggle.accessibilityHint, "Save energy")
            HostedDriver.use(toggle)
            let sent = await FeatureHost.settleAsync(until: { caller.calls.contains("homeassistant.toggle") })
            XCTAssertTrue(sent)
            XCTAssertTrue(page.nodes["dial-authored"]?.view === control)
            host.pageContext.store.apply([EntityState(entityId: "switch.demo_lamp", state: "on")])
            await HostedPage.pump(passes: 5)
            XCTAssertTrue(page.nodes["dial-authored"]?.view === control, "Live values never reconstruct the dial")
        }
    }

    func testAX5UnavailableDialRemainsReadableAndCannotSendCommands() throws {
        let (host, window, caller) = try ServerUIRendererFixture.host(publication: publication())
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        host.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: host.tabController)
        page.view.setNeedsLayout()
        page.view.layoutIfNeeded()
        let control = try XCTUnwrap(page.nodes["dial-authored"]?.view)
        let dial = try XCTUnwrap(HostedPage.descendants(of: control).compactMap { $0 as? UKThermostatDial }.first)
        HostedPage.layoutTracked()
        XCTAssertGreaterThan(dial.bounds.height, HassTokens.minTarget)
        XCTAssertGreaterThanOrEqual(control.bounds.height, dial.bounds.height)
        XCTAssertFalse(dial.configuration.acceptsInput)
        XCTAssertTrue(control.accessibilityIdentifier == "dial-authored")
        XCTAssertTrue(caller.calls.isEmpty)
    }

    func testPublicationCannotRemoveCommandControlDuringRealCommandLifetime() throws {
        let (host, window, _) = try ServerUIRendererFixture.host(publication: publication())
        defer { window.isHidden = true }
        let adapter = try XCTUnwrap(host.bindings.climates["source-zone"])
        adapter.setEditing(true, controlID: "dial-authored")
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication())) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .interactionBlocked)
        }
        adapter.setEditing(false, controlID: "dial-authored")
    }
}
