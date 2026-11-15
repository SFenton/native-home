import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Configured camera fixtures

@MainActor
enum ServerUICameraHostedFixture {
    static func json() throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let camera = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent("Tests/HassCoreTests/ServerUICameraFixture.json")))
        var root = try ServerUIRendererFixture.json()
        let sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources", to: .array(sources + [try XCTUnwrap(camera["source"])]))
        let nodes = try XCTUnwrap(root["document"]?["pages"]?.array?[0]["components"]?.array)
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(nodes + [try XCTUnwrap(camera["tile"])]))
        root = try ServerUIRendererFixture.changing(root, path: "/document/modals/0/components", to: .array([try XCTUnwrap(camera["viewer"])]))
        root = try ServerUIRendererFixture.changing(root, path: "/document/modals/0/presentation/width", to: .string("page"))
        root = try ServerUIRendererFixture.changing(root, path: "/document/modals/0/presentation/appearance", to: .string("dark"))
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array((ServerUICompositionPublication.firstSliceCapabilities
            + ["sh.camera-stream@1", "sh.camera-tile@1", "sh.camera-video@1", "sh.camera-controls@1", "sh.camera-viewer@1"]).sorted().map(JSONValue.string)))
        return root
    }

    static func publication(_ json: JSONValue? = nil) throws -> ServerUICompositionPublication {
        try ServerUIRendererFixture.publication(json ?? self.json())
    }

    static func descriptor() throws -> ServerUICameraDescriptor {
        guard case .camera(_, let configuration) = try publication().document.dataSources.last else {
            throw NSError(domain: "SyntheticCameraFixture", code: 1)
        }
        return configuration
    }

    static func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll([
            EntityState(entityId: "camera.demo_entry", state: "idle"),
            EntityState(entityId: "input_boolean.demo_recording", state: "off")
        ])
        return store
    }

    static func reader() throws -> UKCameraReadProvider {
        UKCameraReadProvider(descriptors: [try descriptor()], appear: { _ in }, disappear: { _ in },
                             retry: { _ in }, snapshotURL: { _ in nil }, offline: { false })
    }
}

// MARK: - Command lifetime, privacy and permission

@MainActor
final class ServerUICameraIntentTests: XCTestCase {
    func testScopedReaderRejectsUnknownStreamsSnapshotsAndPublicationRetargeting() throws {
        let descriptor = try ServerUICameraHostedFixture.descriptor()
        var leases: [Bool] = [], retries = 0, snapshots: [String] = []
        var offline = false
        let reader = UKCameraReadProvider(descriptors: [descriptor], appear: { _ in leases.append(true) },
            disappear: { _ in leases.append(false) }, retry: { _ in retries += 1 },
            snapshotURL: { id in snapshots.append(id); return URL(string: "https://example.invalid/snapshot") },
            offline: { offline })
        let camera = descriptor.camera(title: "Demo")
        reader.setVisible(camera, true)
        reader.setVisible(camera, false)
        reader.retry(camera)
        XCTAssertNotNil(reader.snapshotURL(descriptor.snapshotEntityId))
        let unapproved = HomeConfig.Camera(title: "Other", entityId: camera.entityId, rtcStreamId: "unapproved", aspectRatio: 1)
        reader.setVisible(unapproved, true)
        reader.retry(unapproved)
        XCTAssertNil(reader.snapshotURL("camera.demo_not_approved"))
        XCTAssertEqual(leases, [true, false])
        XCTAssertEqual(retries, 1)
        XCTAssertEqual(snapshots, [descriptor.snapshotEntityId])
        offline = true
        XCTAssertTrue(reader.isOffline)

        let publication = try ServerUICameraHostedFixture.publication()
        let context = UKContext(store: ServerUICameraHostedFixture.store())
        XCTAssertThrowsError(try UKServerUIRenderer(publication: publication, context: context,
            backdrop: ServerUIRendererFixture.backdrop())) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .unavailableSource)
        }
        let host = try UKServerUIRenderer(publication: publication, context: context,
            backdrop: ServerUIRendererFixture.backdrop(), cameraPool: CameraStreamPool(modes: [], observesApp: false), cameraReader: reader)
        let index = publication.document.dataSources.count - 1
        let changed = try ServerUIRendererFixture.changing(ServerUICameraHostedFixture.json(),
            path: "/document/dataSources/\(index)/inputs/rtcStreamId", to: .string("unapproved"))
        XCTAssertThrowsError(try host.validateUpdate(ServerUICameraHostedFixture.publication(changed)))
        XCTAssertEqual(host.publication, publication)
        XCTAssertNil(host.pageContext.connection)
    }

    private final class DelayedCaller: HassServiceCalling {
        var targets: [String?] = []
        var commands: [String] = []
        private var continuation: CheckedContinuation<Void, Error>?
        private var waiting: CheckedContinuation<Void, Never>?
        func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
            commands.append("\(domain).\(service)")
            targets.append(data["entity_id"] as? String)
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                waiting?.resume()
                waiting = nil
            }
        }
        func waitForStart() async {
            if continuation != nil { return }
            await withCheckedContinuation { waiting = $0 }
        }
        func complete() { continuation?.resume(); continuation = nil }
    }

    func testRecordingPinsActualCallEvenAfterEarlyStateConfirmationAndBlocksSourceReplacement() async throws {
        let publication = try ServerUICameraHostedFixture.publication()
        let caller = DelayedCaller(), store = ServerUICameraHostedFixture.store()
        defer { caller.complete() }
        let pool = CameraStreamPool(modes: [], observesApp: false)
        let bindings = UKServerUIBindings(sources: publication.document.dataSources, context: UKContext(store: store, caller: caller), cameraPool: pool)
        let source = try XCTUnwrap(bindings.cameras["demo-camera-source"])
        try source.perform(.record)
        await caller.waitForStart()
        store.apply([EntityState(entityId: "input_boolean.demo_recording", state: "on")])
        XCTAssertTrue(source.hasPendingIntent, "A confirmation must not unpin the still-running call.")
        XCTAssertThrowsError(try bindings.validateReplacement([]))
        XCTAssertEqual(caller.commands, ["script.turn_on"])
        XCTAssertEqual(caller.targets, ["script.demo_recording"])
        caller.complete()
        await source.actions?.waitForCalls()
    }

    func testPrivacyAndUnavailableStatesRevalidateBeforeAnyIntent() throws {
        for hidden in [true, false] {
            let store = ServerUICameraHostedFixture.store(), caller = HostedCaller()
            if !hidden { store.apply([EntityState(entityId: "camera.demo_entry", state: "unavailable")]) }
            let source = UKServerUICameraSource(configuration: try ServerUICameraHostedFixture.descriptor(),
                                                context: UKContext(store: store, caller: caller),
                                                pool: CameraStreamPool(modes: [], observesApp: false), privacy: { hidden },
                                                saveSnapshot: { _, _ in XCTFail("Unavailable/private cameras must prevent the saver"); return .failed })
            XCTAssertEqual(source.status, hidden ? "Private camera" : "Camera unavailable")
            for intent in [ServerUICompositionDocument.CameraIntent.record, .snapshot, .sound] {
                XCTAssertThrowsError(try source.perform(intent))
            }
            XCTAssertTrue(caller.calls.isEmpty)
        }
    }

    func testDeniedSnapshotStaysExplicitAndPinnedUntilAcknowledgedWithoutCallingPhotos() async throws {
        let source = UKServerUICameraSource(configuration: try ServerUICameraHostedFixture.descriptor(),
                                            context: UKContext(store: ServerUICameraHostedFixture.store()),
                                            pool: CameraStreamPool(modes: [], observesApp: false),
                                            saveSnapshot: { _, _ in .denied })
        try source.perform(.snapshot)
        XCTAssertTrue(source.hasPendingIntent)
        await source.waitForSnapshot()
        XCTAssertTrue(source.photosDenied)
        XCTAssertTrue(source.hasPendingIntent)
        source.acknowledgePhotosDenied()
        XCTAssertFalse(source.hasPendingIntent)
    }

    func testSnapshotResultsAndSoundUseInjectedNativePathsWithoutStartingAStream() async throws {
        for result in [CameraSnapshotSaver.Result.saved, .failed] {
            let pool = CameraStreamPool(modes: [], observesApp: false)
            let source = UKServerUICameraSource(configuration: try ServerUICameraHostedFixture.descriptor(),
                                                context: UKContext(store: ServerUICameraHostedFixture.store()), pool: pool,
                                                saveSnapshot: { _, _ in result })
            try source.perform(.sound)
            XCTAssertFalse(source.model.isMuted)
            try source.perform(.sound)
            XCTAssertTrue(source.model.isMuted)
            try source.perform(.snapshot)
            XCTAssertEqual(source.snapshot, .saving)
            XCTAssertFalse(source.canPerform(.snapshot))
            await source.waitForSnapshot()
            XCTAssertEqual(source.snapshot, result == .saved ? .saved : .failed)
            XCTAssertFalse(source.hasPendingIntent)
            XCTAssertFalse(pool.shouldRun(source.camera))
        }
    }

    func testPendingRecordingPinsControlRemovalOrderAndParentAttachmentWithoutLoadingUI() async throws {
        let json = try ServerUICameraHostedFixture.json()
        let publication = try ServerUICameraHostedFixture.publication(json)
        let caller = DelayedCaller()
        defer { caller.complete() }
        let host = try UKServerUIRenderer(publication: publication,
                                          context: UKContext(store: ServerUICameraHostedFixture.store(), caller: caller),
                                          backdrop: ServerUIRendererFixture.backdrop(),
                                          cameraPool: CameraStreamPool(modes: [], observesApp: false),
                                          cameraReader: ServerUICameraHostedFixture.reader())
        let source = try XCTUnwrap(host.bindings.cameras["demo-camera-source"])
        try source.perform(.record)
        await caller.waitForStart()
        let controls = try XCTUnwrap(json["document"]?["modals"]?.array?[0]["components"]?.array?[0]["props"]?["controls"]?.array)
        let viewer = try XCTUnwrap(json["document"]?["modals"]?.array?[0]["components"]?.array?[0])
        var grid = try XCTUnwrap(json["document"]?["pages"]?.array?[0]["components"]?.array?[0])
        grid = try ServerUIRendererFixture.changing(grid, path: "/id", to: .string("demo-viewer-grid"))
        grid = try ServerUIRendererFixture.changing(grid, path: "/children", to: .array([viewer]))
        for (path, replacement) in [
            ("/document/modals/0/components/0/props/controls", JSONValue.array(Array(controls.reversed()))),
            ("/document/modals/0/components/0/props/controls", .array(Array(controls.dropFirst()))),
            ("/document/modals/0/components", .array([grid]))
        ] {
            let changed = try ServerUIRendererFixture.changing(json, path: path, to: replacement)
            let candidate = try ServerUICameraHostedFixture.publication(changed)
            XCTAssertThrowsError(try host.validateUpdate(candidate)) {
                XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .interactionBlocked)
            }
        }
        XCTAssertFalse(host.isViewLoaded)
        XCTAssertEqual(host.publication, publication)
        caller.complete()
        await source.actions?.waitForCalls()
    }

    func testPoolRejectsStreamRetargetingWithoutCreatingAnotherModel() throws {
        let pool = CameraStreamPool(modes: [], observesApp: false)
        let source = UKServerUICameraSource(configuration: try ServerUICameraHostedFixture.descriptor(),
                                            context: UKContext(store: ServerUICameraHostedFixture.store()), pool: pool)
        let conflicting = HomeConfig.Camera(title: "Entry", entityId: source.camera.entityId, rtcStreamId: "demo_other",
                                            aspectRatio: source.camera.aspectRatio)
        XCTAssertFalse(pool.accepts(conflicting))
        XCTAssertTrue(pool.accepts(source.camera))
        XCTAssertEqual(pool.liveResources["CameraPool.models"], 1)
        XCTAssertFalse(pool.shouldRun(source.camera))
    }

    func testAllFamilyLayoutsKeepControlsAccessibleAtAX5AndShareThePoolWithoutStartingStreams() throws {
        let publication = try ServerUICameraHostedFixture.publication()
        guard case .cameraViewer(let controls) = publication.document.modals[0].surface.components[0] else { return XCTFail("Viewer") }
        let pool = CameraStreamPool(modes: [], observesApp: false)
        let source = UKServerUICameraSource(configuration: try ServerUICameraHostedFixture.descriptor(),
                                            context: UKContext(store: ServerUICameraHostedFixture.store()), pool: pool,
                                            saveSnapshot: { _, _ in .failed })
        for width: CGFloat in [320, 390, 540, 768, 1024] {
            let view = UKServerUICameraControls(controls: controls, source: source, presenter: { nil }, error: { _ in XCTFail("No gesture") })
            let controller = UIViewController()
            controller.view = view
            let window = HostedPage.show(controller, size: HostedPage.inScene(CGSize(width: width, height: 900)))
            defer { window.isHidden = true }
            view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            view.updateTraitsIfNeeded()
            view.frame = CGRect(x: 0, y: 0, width: width, height: view.gridHeight(forWidth: width))
            view.layoutIfNeeded()
            let buttons = view.subviews.flatMap(\.subviews).compactMap { $0 as? UKCameraControlButton }
            XCTAssertEqual(buttons.count, 3)
            XCTAssertEqual(buttons.map(\.accessibilityLabel), ["Snapshot", "Muted", "Record"])
            XCTAssertTrue(buttons.allSatisfy { $0.bounds.height >= 44 && $0.bounds.width > 0 })
            XCTAssertTrue(zip(buttons, buttons.dropFirst()).allSatisfy { $0.frame.maxY <= $1.frame.minY })
        }
        XCTAssertTrue(source.model === pool.model(for: source.camera))
        XCTAssertFalse(pool.shouldRun(source.camera))
    }
}

// MARK: - Parent-run all-family journey

/// Synthetic journey definitions only; the parent owns device execution and visual/AX evidence.
@MainActor
final class ServerUICameraJourneyTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    func testAllFamilyTileViewerReturnKeepsIdentityFullHeightAndMutedAudio() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 540, height: 720),
                     CGSize(width: 1024, height: 720), CGSize(width: 768, height: 1024)] {
            let publication = try ServerUICameraHostedFixture.publication()
            let pool = CameraStreamPool(modes: [], observesApp: false)
            let host = try UKServerUIRenderer(publication: publication,
                                              context: UKContext(store: ServerUICameraHostedFixture.store()),
                                              backdrop: ServerUIRendererFixture.backdrop(), cameraPool: pool,
                                              cameraReader: ServerUICameraHostedFixture.reader())
            let window = HostedPage.show(host, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            let root = try ServerUIRendererFixture.root(host)
            let tileHost = try XCTUnwrap(root.nodes["demo-camera-tile"]?.view)
            let tile = try XCTUnwrap(tileHost.subviews.compactMap { $0 as? UKCameraTileView }.first)
            let source = try XCTUnwrap(host.bindings.cameras["demo-camera-source"])
            tile.sendActions(for: .touchUpInside)
            HostedPage.until { host.modal?.presentingViewController != nil && host.modal?.transitionCoordinator == nil }
            let modal = try XCTUnwrap(host.modal)
            let viewer = try XCTUnwrap(modal.topViewController as? UKServerUIPage)
            XCTAssertEqual(modal.options.height, .full)
            XCTAssertEqual(modal.options.width, .page)
            if #available(iOS 18.0, *) { XCTAssertNil(modal.preferredTransition) }
            XCTAssertTrue(viewer.nodes["demo-camera-viewer"]?.view is UKServerUICameraView)
            try source.perform(.sound)
            XCTAssertFalse(source.model.isMuted)
            try host.perform(.dismiss(scope: .currentModal), from: viewer)
            HostedPage.until { host.modal == nil }
            XCTAssertTrue(source.model.isMuted)
            XCTAssertTrue(root.nodes["demo-camera-tile"]?.view === tileHost)
            XCTAssertTrue(host.bindings.cameras["demo-camera-source"] === source)
            XCTAssertFalse(pool.shouldRun(source.camera), "A context without a connection must never acquire a stream lease.")
        }
    }
}
