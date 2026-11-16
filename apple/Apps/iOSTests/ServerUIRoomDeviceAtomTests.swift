import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Family-compatible hosted regressions (no device certification claim)

@MainActor
final class ServerUIRoomDeviceAtomTests: XCTestCase {
    private func publication(roomTile: Bool = false, initialMinutes: Int = 10) throws -> ServerUICompositionPublication {
        func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
        var root = try ServerUIRendererFixture.json()
        var sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        sources.append(try json("""
            {"id":"source-device","kind":"model","model":"bathroom-fan@1","inputs":{
              "id":"synthetic-fan","roomTitle":"Synthetic Room","autoUnlockEntityId":"input_boolean.demo_auto",
              "deadlineEntityId":"input_datetime.demo_deadline","lockEntityId":"input_boolean.demo_lock",
              "pendingEntityId":"input_boolean.demo_pending","powerEntityId":"switch.demo_fan",
              "scriptService":"demo_fan_command","timerEntityId":"timer.demo_fan"}}
            """))
        var components = try XCTUnwrap(root["document"]?["pages"]?.array?.first?["components"]?.array)
        components.append(try json("""
            {"id":"authored-countdown","title":"My Fan Timer","type":"room-device-control","layout":{"span":1},
              "icon":{"type":"sf-symbol","name":"timer","rendering":"canonical","unavailable":"reject"},
              "binding":{"sourceId":"source-device"},"props":{"control":"fan-timer","family":"air","initialMinutes":\(initialMinutes),
              "options":[{"value":"10","label":"Ten minutes","actionLabel":"Stop after ten minutes"},
                         {"value":"30","label":"Half an hour","actionLabel":"Stop after half an hour"}],
              "labels":{"loading":"Reading fan","unavailable":"Fan offline","failed":"No fan response",
                        "on":"Enabled","off":"Disabled","action":"Start timer","cancel":"Clear timer","footnote":"My timer help",
                        "sleep":"Sleeping","tankFault":"Replace tank","waterFault":"Refill","invalidTarget":"Choose target","highTarget":"High target"}}}
            """))
        if roomTile {
            guard case .object(var component) = components.removeLast(),
                  case .object(var props) = component["props"],
                  let modalId = root["document"]?["modals"]?.array?.first?["id"] else { throw DeviceFixtureError() }
            props["control"] = .string("fan-room")
            props["initialMinutes"] = nil
            props["options"] = .array([])
            props["modalId"] = modalId
            props["fanRail"] = try json("""
                {"order":["lock","power"],"powerIcon":{"type":"sf-symbol","name":"power","rendering":"canonical","unavailable":"reject"},
                 "lockedIcon":{"type":"sf-symbol","name":"lock.fill","rendering":"canonical","unavailable":"reject"},
                 "unlockedIcon":{"type":"sf-symbol","name":"lock.open","rendering":"canonical","unavailable":"reject"},
                 "powerOn":"Start fan","powerOff":"Stop fan","lock":"Hold fan","unlock":"Release fan","locked":"Held"}
                """)
            component["props"] = .object(props)
            components.append(.object(component))
        }
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources", to: .array(sources))
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(components))
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities",
            to: .array((ServerUICompositionPublication.firstSliceCapabilities + ["sh.bathroom-fan@1"]).sorted().map(JSONValue.string)))
        return try ServerUIRendererFixture.publication(root)
    }
    private struct DeviceFixtureError: Error {}

    func testTimerAuthoringIdentityAXAndReachableControlsAcrossFamilyWidths() throws {
        let publication = try publication()
        guard case .roomDeviceControl(let control)? = publication.document.pages[0].surface.components.last,
              case .roomDevice(_, let descriptor)? = publication.document.dataSources.last else { return XCTFail("Expected domain contract") }
        for (family, size) in [("iPhone", CGSize(width: 390, height: 844)), ("Duo", CGSize(width: 540, height: 720)),
                               ("iPad", CGSize(width: 834, height: 1194))] {
            let store = EntityStore()
            store.replaceAll([
                EntityState(entityId: "switch.demo_fan", state: "off"),
                EntityState(entityId: "input_boolean.demo_lock", state: "off"),
                EntityState(entityId: "input_boolean.demo_pending", state: "off"),
                EntityState(entityId: "input_boolean.demo_auto", state: "off")
            ])
            let caller = HostedCaller(), context = UKContext(store: store, caller: caller)
            let source = ServerUIRoomDeviceSource(descriptor: descriptor, store: store, caller: caller)
            let atom = UKServerUIRoomDeviceAtom()
            atom.update(control, source: source, context: context)
            let controller = UIViewController()
            controller.view.addSubview(atom)
            let window = HostedPage.show(controller, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            let height = atom.gridHeight(forWidth: size.width - 32)
            atom.frame = CGRect(x: 16, y: 30, width: size.width - 32, height: height)
            atom.layoutIfNeeded()
            let ten = try XCTUnwrap(FeatureHost.view("authored-countdown.timerOption.10", in: atom) as? UIControl, family)
            XCTAssertEqual(ten.accessibilityLabel, "Ten minutes", family)
            XCTAssertTrue(ten.accessibilityTraits.contains(.selected), family)
            XCTAssertGreaterThanOrEqual(ten.bounds.height, 44, family)
            let start = try XCTUnwrap(FeatureHost.view("authored-countdown.setTimer", in: atom) as? UIControl, family)
            XCTAssertTrue(start.isEnabled, family)
            XCTAssertNotNil(FeatureHost.view("authored-countdown.timerOption.30", in: atom), family)
            atom.update(control, source: source, context: context)
            XCTAssertTrue(ten === FeatureHost.view("authored-countdown.timerOption.10", in: atom), "Compatible updates retain native focus identity: \(family)")
            guard case .roomDeviceControl(let replacement)? = try self.publication(initialMinutes: 30).document.pages[0].surface.components.last else {
                return XCTFail("Expected updated timer")
            }
            atom.update(replacement, source: source, context: context)
            let thirty = try XCTUnwrap(FeatureHost.view("authored-countdown.timerOption.30", in: atom))
            XCTAssertTrue(thirty.accessibilityTraits.contains(.selected), "An unedited default follows accepted authoring changes: \(family)")
            XCTAssertFalse(atom.hasLocalEdits, family)
        }
    }

    func testPendingSourceAndEditedTimerCannotBeRetargetedByPublication() throws {
        let publication = try publication()
        let (host, window, _) = try ServerUIRendererFixture.host(publication: publication)
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        let atom = try XCTUnwrap(page.nodes["authored-countdown"]?.view as? UKServerUIRoomDeviceAtom)
        let option = try XCTUnwrap(FeatureHost.view("authored-countdown.timerOption.30", in: atom) as? UIControl)
        option.sendActions(for: .touchUpInside)
        XCTAssertTrue(atom.hasLocalEdits)
        // The canonical first-slice publication would remove the edited timer and its descriptor.
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication())) { error in
            XCTAssertEqual((error as? UKServerUIRendererError)?.code, .interactionBlocked)
        }
    }

    func testRoomBodyAndBothNativeRailsAreIndependentAcrossFamilyWidths() async throws {
        let publication = try publication(roomTile: true)
        guard case .roomDeviceControl(let control)? = publication.document.pages[0].surface.components.last,
              case .roomDevice(_, let descriptor)? = publication.document.dataSources.last else { return XCTFail("Expected fan room atom") }
        for width in [390.0, 540.0, 834.0] {
            let store = EntityStore(), caller = HostedCaller()
            store.replaceAll([
                EntityState(entityId: "switch.demo_fan", state: "off"),
                EntityState(entityId: "input_boolean.demo_lock", state: "off"),
                EntityState(entityId: "input_boolean.demo_pending", state: "off")
            ])
            let source = ServerUIRoomDeviceSource(descriptor: descriptor, store: store, caller: caller)
            let atom = UKServerUIRoomDeviceAtom()
            atom.update(control, source: source, context: UKContext(store: store, caller: caller))
            atom.frame = CGRect(x: 0, y: 0, width: width, height: atom.gridHeight(forWidth: width))
            atom.layoutIfNeeded()
            let lock = try XCTUnwrap(FeatureHost.view("authored-countdown.action.lock", in: atom) as? UIControl)
            let power = try XCTUnwrap(FeatureHost.view("authored-countdown.action.power", in: atom) as? UIControl)
            XCTAssertTrue(lock.accessibilityLabel?.contains("Hold fan") == true)
            XCTAssertTrue(power.accessibilityLabel?.contains("Start fan") == true)
            var navigation: ServerUICompositionDocument.Action?
            atom.onNavigate = { action, _ in navigation = action }
            let body = try XCTUnwrap(FeatureHost.view("authored-countdown", in: atom) as? UIControl)
            body.sendActions(for: .touchUpInside)
            XCTAssertEqual(navigation, control.navigationAction)
            XCTAssertTrue(caller.calls.isEmpty, "Opening the sheet cannot toggle power")
            lock.sendActions(for: .touchUpInside)
            await source.commands.waitForCalls()
            XCTAssertEqual(caller.calls, ["script.demo_fan_command"])
            XCTAssertEqual(caller.data.last?["command"] as? String, "lock")
            XCTAssertEqual(caller.data.last?["locked"] as? Bool, true)
        }
    }
}
