import HassCore
import HassDesign
import Observation
import UIKit
import XCTest
@testable import HassUI

/// What a room's light tile sends and how it follows its light (`UKRoomsBind.lightTile`).
@MainActor
final class UKHostedRoomsBindingTests: DemoHouseTestCase {
    /// A light the test can change; the tile reads it through the observation the real store gives.
    @MainActor @Observable
    final class Light {
        var state: EntityState?
        init(_ state: EntityState?) { self.state = state }
    }

    func bind(_ light: Light, sent: @escaping (LightControl.Command) -> Void, bag: UKObservationBag) -> UIView {
        UKRoomsBind.lightTile(title: "Lamp", entityId: "light.demo_lamp", identifier: "tile.lamp", bag: bag, environment: UKTileEnvironment(),
                              read: { light.state }, send: sent)
    }

    func testADimmableLightSendsPowerAndBrightnessAndFollowsTheLight() throws {
        let light = Light(EntityState(entityId: "light.demo_lamp", state: "on", attributes: ["brightness": .number(128)]))
        var sent: [LightControl.Command] = []
        let bag = UKObservationBag()
        let tile = try XCTUnwrap(bind(light, sent: { sent.append($0) }, bag: bag) as? UKBrightnessTileView)
        tile.onPower?(false)
        tile.onBrightness?(40)
        XCTAssertEqual(sent, [LightControl.power("light.demo_lamp", on: false), LightControl.brightness("light.demo_lamp", percent: 40)])

        XCTAssertFalse(tile.isUnavailable)
        light.state = EntityState(entityId: "light.demo_lamp", state: "unavailable", attributes: ["brightness": .number(128)])
        hostedSettle(0.3)
        XCTAssertTrue(tile.isUnavailable, "the tile follows the light in place")
        withExtendedLifetime(bag) {}
    }

    func testAPlainLightIsAPowerTileThatSendsExplicitTurnOnAndTurnOff() throws {
        let light = Light(EntityState(entityId: "light.demo_lamp", state: "off"))
        var sent: [LightControl.Command] = []
        let bag = UKObservationBag()
        let tile = try XCTUnwrap(bind(light, sent: { sent.append($0) }, bag: bag) as? UKGlassTileView)
        XCTAssertEqual(tile.model.subtitle, "Off")
        XCTAssertFalse(tile.model.isActive)
        tile.onPerform?(PowerToggleActions.actionId)
        XCTAssertEqual(sent, [LightControl.flip("light.demo_lamp", shownOn: false)], "an off light is sent turn_on, never toggle")

        light.state = EntityState(entityId: "light.demo_lamp", state: "on")
        hostedSettle(0.3)
        XCTAssertEqual(tile.model.subtitle, "On", "the tile follows the light in place")
        XCTAssertTrue(tile.model.isActive)
        tile.onPerform?(PowerToggleActions.actionId)
        XCTAssertEqual(sent.last, LightControl.flip("light.demo_lamp", shownOn: true))

        light.state = EntityState(entityId: "light.demo_lamp", state: "unavailable")
        hostedSettle(0.3)
        XCTAssertEqual(tile.model.subtitle, "Unavailable")
        light.state = nil
        hostedSettle(0.3)
        XCTAssertNil(tile.model.subtitle, "a light the house does not have says nothing")
        XCTAssertTrue(tile.model.isUnavailable)
        withExtendedLifetime(bag) {}
    }
}
