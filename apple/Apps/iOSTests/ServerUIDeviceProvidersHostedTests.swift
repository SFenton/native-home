import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Authored domain measuring and keyed bindings

/// Network-free fixtures, runnable unchanged on the three iOS device families.
@MainActor
final class ServerUIDeviceProvidersHostedTests: XCTestCase {
    private func publication() throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try .decode(Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIDeviceProvidersFixture.json")))
    }

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    func testCanonicalDeviceAtomsMeasureAtPhoneFoldedAndWideWidthsAndKeepIdentityAcrossLiveUpdates() throws {
        for width: CGFloat in [355, 390, 768, 1024] {
            let store = EntityStore()
            store.replaceAll([
                .init(entityId: "input_boolean.demo_manual", state: "on"),
                .init(entityId: "input_select.demo_mode", state: "Custom", attributes: ["options": ["Default", "Custom"]]),
                .init(entityId: "light.demo_a", state: "on", attributes: ["supported_color_modes": ["rgb"], "brightness": .number(128), "rgb_color": [.number(1), .number(2), .number(3)]]),
                .init(entityId: "light.demo_b", state: "on"), .init(entityId: "light.demo_group", state: "on")
            ])
            let renderer = try UKServerUIRenderer(publication: publication(), context: UKContext(store: store, caller: HostedCaller()),
                                                 backdrop: ServerUIRendererFixture.backdrop())
            let window = HostedPage.show(renderer, size: HostedPage.inScene(CGSize(width: width, height: 900)))
            let page = try XCTUnwrap(renderer.stacks[.initial]?.viewControllers.first as? UKServerUIPage)
            HostedPage.layoutTracked()
            let brightness = try XCTUnwrap(page.nodes["brightness"]?.view as? UKServerUIDeviceAtom)
            let timeRows = try XCTUnwrap(page.nodes["times"]?.view as? UKServerUIDeviceAtom)
            XCTAssertGreaterThan(brightness.gridHeight(forWidth: width - 32), 0)
            XCTAssertGreaterThan(timeRows.gridHeight(forWidth: width - 32), 0)
            window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            store.apply([.init(entityId: "light.demo_a", state: "off", attributes: ["supported_color_modes": ["rgb"]])])
            HostedPage.layoutTracked()
            XCTAssertTrue(page.nodes["brightness"]?.view === brightness)
            XCTAssertGreaterThan(brightness.gridHeight(forWidth: width - 32), 0)
            try renderer.validateUpdate(publication())
            window.isHidden = true
        }
    }
}
