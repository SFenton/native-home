import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Synthetic provider and publication

@MainActor
private enum RemoteRendererFixture {
    static func json() throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUIRemoteFixture.json")))
    }

    static func config() -> MediaRemoteConfig {
        let key = MediaRemoteButton("Demo", icon: "", action: .service("remote", "send_command", target: "remote.demo_unit", data: ["command": "UP"]))
        let hue = HueSyncConfig(powerEntityId: "switch.demo_power", lightSyncEntityId: "switch.demo_sync", syncModeEntityId: "select.demo_mode",
                                intensityEntityId: "select.demo_intensity", brightnessEntityId: "number.demo_brightness",
                                hdmiInputEntityId: "select.demo_input", hdmiStatusEntityIds: ["sensor.demo_input"])
        return .init(id: "demo-provider", title: "Demo", roomTitle: "Demo", remoteTitle: "Demo",
                     mediaEntityId: "media_player.demo_unit", controlEntityId: "media_player.demo_unit",
                     power: key, up: key, left: key, select: key, right: key, down: key, back: key, home: key,
                     keyboard: .init("Text", icon: "", action: .command(.textPrompt(targetEntityId: "media_player.demo_unit"))),
                     pause: key, play: key, volumeTitle: "Speaker", volumeEntityId: "media_player.demo_speaker",
                     volumeDown: key, volumeMute: key, volumeUp: key,
                     apps: [.init("Demo app", action: .service("script", "demo_app"))],
                     devices: [.init("Demo player", entityId: "media_player.demo_unit", icon: "", semantics: .state)], lightSync: hue)
    }

    static func host(size: CGSize, caller: any HassServiceCalling, value: JSONValue? = nil) throws -> (UKServerUIRenderer, UKServerUIPage, ServerUIRemoteSession, UIWindow) {
        let store = EntityStore()
        store.replaceAll([.init(entityId: "media_player.demo_unit", state: "playing"),
                          .init(entityId: "media_player.demo_speaker", state: "on", attributes: ["volume_level": .number(0.2)])])
        let session = ServerUIRemoteSession(controller: .init(config: config(), store: store, caller: caller))
        let publication = try ServerUIRendererFixture.publication(value ?? json())
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: caller),
                                          backdrop: ServerUIRendererFixture.backdrop(), remoteProviders: ["demo-provider": session],
                                          roomResidentId: { "demo-resident" })
        let window = HostedPage.show(host, size: HostedPage.inScene(size))
        HostedPage.wait(0.1)
        let page = try XCTUnwrap(host.stacks[.initial]?.viewControllers.first as? UKServerUIPage)
        page.loadViewIfNeeded()
        return (host, page, session, window)
    }
}

@MainActor
private final class RemoteRendererDelayedCaller: HassServiceCalling {
    private var completion: CheckedContinuation<Void, Error>?
    private var started: CheckedContinuation<Void, Never>?
    struct Failure: Error {}
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        try await withCheckedThrowingContinuation {
            completion = $0
            started?.resume()
            started = nil
        }
    }
    func waitForStart() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func reject() { completion?.resume(throwing: Failure()); completion = nil }
}

// MARK: - Native regression evidence authored for parent execution

@MainActor
final class ServerUIRemoteRendererTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    func testAuthoredPageDeviceTileMeasuresAndRetainsIdentityAtAllFamilyWidths() throws {
        var value = try RemoteRendererFixture.json()
        let components = try XCTUnwrap(value["document"]?["pages"]?.array?[0]["components"]?.array)
        let index = try XCTUnwrap(components.firstIndex { $0["props"]?["kind"] == .string("device") })
        let id = try XCTUnwrap(components[index]["id"]?.string)
        value = try ServerUIRendererFixture.changing(value, path: "/document/pages/0/components/\(index)/props/presentation", to: "tile")
        value = try ServerUIRendererFixture.changing(value, path: "/document/pages/0/components/\(index)/props/personalization",
            to: .object(["residentId": "demo-resident", "ownTitle": "Your PC", "otherTitle": "Demo PC"]))
        for width: CGFloat in [355, 390, 768, 1024] {
            let (host, page, _, window) = try RemoteRendererFixture.host(size: CGSize(width: width, height: 900), caller: HostedCaller(), value: value)
            defer { window.isHidden = true }
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            HostedPage.layoutTracked()
            let wrapper = try XCTUnwrap(page.nodes[id]?.view)
            let tile = try XCTUnwrap(HostedPage.descendants(of: wrapper).compactMap { $0 as? UKGlassTileView }.first)
            XCTAssertGreaterThan(tile.sizeThatFits(CGSize(width: width - 32, height: .greatestFiniteMagnitude)).height, 0)
            XCTAssertEqual(tile.model.behavior, .inert)
            XCTAssertEqual(tile.model.title, "Your PC")
            let next = try ServerUIRendererFixture.changing(value, path: "/revision", to: .number(2))
            try host.apply(publication: ServerUIRendererFixture.publication(next), backdrop: ServerUIRendererFixture.backdrop())
            XCTAssertTrue(page.nodes[id]?.view === wrapper)
        }
    }

    func testMissingProviderAndUnknownAppAreRejectedBeforeNativeAcceptance() throws {
        let publication = try ServerUIRendererFixture.publication(RemoteRendererFixture.json())
        XCTAssertThrowsError(try UKServerUIRenderer.preflight(publication)) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .unavailableSource)
        }
        let caller = HostedCaller(), store = EntityStore()
        let session = ServerUIRemoteSession(controller: .init(config: RemoteRendererFixture.config(), store: store, caller: caller))
        let wrong = try ServerUIRendererFixture.changing(RemoteRendererFixture.json(),
                                                       path: "/document/pages/0/components/4/props/key", to: .string("Missing demo app"))
        XCTAssertThrowsError(try UKServerUIRenderer.preflight(ServerUIRendererFixture.publication(wrong),
                                                             remoteProviders: ["demo-provider": session], store: store)) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.pointer, "/document/pages/0/components/4/props")
        }
    }

    func testKeyboardRejectionPreservesFieldFocusDraftAndPublicationGuard() async throws {
        let caller = RemoteRendererDelayedCaller()
        let (host, page, session, window) = try RemoteRendererFixture.host(size: CGSize(width: 390, height: 844), caller: caller)
        defer { window.isHidden = true }
        try session.press(.keyboard)
        await HostedPage.pump(passes: 3)
        let form = try XCTUnwrap(page.nodes["demo-keyboard"]?.view)
        let field = try XCTUnwrap(HostedPage.descendants(of: form).compactMap { $0 as? UITextField }.first)
        field.becomeFirstResponder()
        field.text = "a retained draft"
        field.sendActions(for: .editingChanged)
        let send = try XCTUnwrap(HostedPage.descendants(of: form).first { $0.accessibilityIdentifier == "demo-keyboard.send" } as? UIButton)
        send.sendActions(for: .touchUpInside)
        await caller.waitForStart()
        XCTAssertTrue(field.isFirstResponder, "Pending submission does not dismiss the native keyboard.")
        let changed = try ServerUIRendererFixture.changing(RemoteRendererFixture.json(),
                                                         path: "/document/pages/0/components/3/title", to: .string("Retargeted field"))
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication(changed))) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .interactionBlocked)
        }
        caller.reject()
        let failed = await FeatureHost.settleAsync(until: { session.keyboardFailed })
        XCTAssertTrue(failed)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(field.text, "a retained draft")
        XCTAssertTrue(page.nodes["demo-keyboard"]?.view === form)
    }

    func testActualNonoptimisticCommandAndSliderGesturePinAttachments() async throws {
        let caller = RemoteRendererDelayedCaller()
        let (host, page, session, window) = try RemoteRendererFixture.host(size: CGSize(width: 744, height: 1133), caller: caller)
        defer { window.isHidden = true }
        try session.press(.up)
        await caller.waitForStart()
        let changed = try ServerUIRendererFixture.changing(RemoteRendererFixture.json(),
                                                         path: "/document/pages/0/components/0/title", to: .string("Replaced pad"))
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication(changed)))
        caller.reject()
        await session.controller.waitForCalls()
        let card = try XCTUnwrap(page.nodes["demo-volume"]?.view)
        let slider = try XCTUnwrap(HostedPage.descendants(of: card).compactMap { $0 as? UKRemoteSlider }.first)
        slider.sendActions(for: .touchDown)
        XCTAssertTrue(session.hasInteraction)
        slider.sendActions(for: .touchCancel)
        XCTAssertFalse(session.hasInteraction)
        XCTAssertTrue(session.editingControls.isEmpty)
        XCTAssertEqual(session.controller.pendingCallCount, 0, "Cancellation must not send a volume command")
    }

    /// Run on each family; the width matrix also exercises phone, Duo and tablet geometric constraints.
    func testUXKeepsControlsAndDraftAcrossTraitsAndCompatiblePublicationAtAllFamilyWidths() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 744, height: 1133), CGSize(width: 1024, height: 1366)] {
            let (host, page, session, window) = try RemoteRendererFixture.host(size: size, caller: HostedCaller())
            defer { window.isHidden = true }
            let pad = try XCTUnwrap(page.nodes["demo-pad"]?.view)
            let form = try XCTUnwrap(page.nodes["demo-keyboard"]?.view)
            try session.press(.keyboard)
            session.keyboardText = "width-independent draft"
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            let updated = try ServerUIRendererFixture.changing(RemoteRendererFixture.json(), path: "/revision", to: .number(2))
            let backdrop = try ServerUIRendererFixture.backdrop()
            try host.apply(publication: ServerUIRendererFixture.publication(updated), backdrop: backdrop)
            XCTAssertTrue(page.nodes["demo-pad"]?.view === pad)
            XCTAssertTrue(page.nodes["demo-keyboard"]?.view === form)
            XCTAssertEqual(session.keyboardText, "width-independent draft")
            try session.cancelKeyboard()
        }
    }

    func testAXAuthoredLabelsPowerFirstReadOnlySemanticsAndTargetsAtAllFamilyWidths() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 744, height: 1133), CGSize(width: 1024, height: 1366)] {
            let (_, page, session, window) = try RemoteRendererFixture.host(size: size, caller: HostedCaller())
            defer { window.isHidden = true }
            page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            page.view.layoutIfNeeded()
            let pad = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UKRemoteDPadView }.first)
            let keys = try XCTUnwrap(pad.accessibilityElements as? [UKRemoteRoundButton])
            XCTAssertEqual(keys.first?.accessibilityLabel, "Power")
            for key in keys {
                XCTAssertGreaterThanOrEqual(key.bounds.width, 44)
                XCTAssertGreaterThanOrEqual(key.bounds.height, 44)
                XCTAssertFalse(key.accessibilityLabel?.isEmpty ?? true)
            }
            let device = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UKRemoteDeviceRow }.first)
            XCTAssertFalse(device.accessibilityTraits.contains(.button), "Read-only devices never acquire command semantics.")
            let field = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UITextField }.first)
            XCTAssertEqual(field.accessibilityLabel, "Text for demo TV")
            session.controller.store.replaceAll([
                .init(entityId: "media_player.demo_unit", state: "playing"),
                .init(entityId: "select.demo_mode", state: "unavailable",
                      attributes: ["options": .array([.string("game"), .string("video")])])
            ])
            HostedPage.wait(0.1)
            let mode = try XCTUnwrap(page.nodes["demo-hue-mode"]?.view)
            let unavailable = try XCTUnwrap(HostedPage.descendants(of: mode).compactMap { $0 as? UILabel }
                .first { $0.accessibilityValue == "Modes unavailable" })
            XCTAssertFalse(unavailable.isHidden, "Cached options must not hide authored unavailable feedback.")
        }
    }
}
