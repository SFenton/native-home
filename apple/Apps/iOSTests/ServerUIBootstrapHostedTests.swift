import CryptoKit
import HassCore
import FentonActivityModel
import HassDemoHouse
import os
import UIKit
import XCTest
@testable import HassUI

// MARK: - All-family native bootstrap boundaries

@MainActor
final class ServerUIBootstrapHostedTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    func testAnUnpublishedHouseShowsTheRecoveryBoundaryNeverACompiledDashboardOrChangesTheOAuthAccount() throws {
        setenv("FENTON_UI_PUBLICATION", "unpublished", 1)
        defer { unsetenv("FENTON_UI_PUBLICATION") }
        for size in [CGSize(width: 390, height: 844), CGSize(width: 1130, height: 880), CGSize(width: 1024, height: 1366)] {
            let directory = URL.temporaryDirectory.appendingPathComponent("bootstrap-hosted-\(UUID().uuidString)")
            let tokenStore = InMemoryTokenStore()
            let session = AppSession(tokenStore: tokenStore,
                snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities.json")),
                houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house.json")),
                buildDefault: nil, launchArguments: [])
            let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
            try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic-access", expiresAt: .distantFuture,
                                                              refreshToken: "synthetic-refresh"))
            let root = UKRootViewController(session: session)
            root.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            let window = HostedPage.show(root, size: HostedPage.inScene(size))
            window.overrideUserInterfaceStyle = .light
            defer {
                window.isHidden = true
                session.signOut()
                try? FileManager.default.removeItem(at: directory)
            }
            HostedPage.wait(0.3)
            let identifiers = HostedDriver.identifiers(in: root.view)
            XCTAssertTrue(identifiers.contains("server-ui.production.recovery"))
            XCTAssertTrue(identifiers.contains("server-ui.production.signOut"))
            XCTAssertTrue(identifiers.contains("server-ui.production.retry"), "An unpublished layout can be asked for again.")
            XCTAssertFalse(identifiers.contains("server-ui.production.provision"), "There is no publisher to set up.")
            let production = try XCTUnwrap(root.children.first { $0 is UKServerUIProductionHost })
            XCTAssertEqual(production.traitCollection.userInterfaceStyle, .dark,
                           "Recovery uses the same fixed dark canvas as the published renderer.")
            XCTAssertFalse(identifiers.contains("login.password"))
            XCTAssertTrue(session.isSignedIn)
            XCTAssertEqual(tokenStore.load()?.server, server)
            XCTAssertEqual(tokenStore.load()?.refreshToken, "synthetic-refresh")
        }
    }

    func testBoundaryCopyAndActionsFollowTheServersStateAndNeverOfferAnAppUpdateRetry() {
        typealias Boundary = UKServerUIProductionHost.Boundary
        func boundary(_ remote: ServerUIPublicationRemoteState = .waiting, status: ServerUIPublicationStatus = .idle,
                      storeMissing: Bool = false, expired: Bool = false, adoptionFailed: Bool = false) -> Boundary {
            Boundary(remote: remote, status: status, storeMissing: storeMissing, expired: expired, adoptionFailed: adoptionFailed)
        }
        let waiting = boundary()
        XCTAssertEqual(waiting.title, "Getting Your Layout\u{2026}")
        XCTAssertFalse(waiting.isFinal)
        XCTAssertFalse(waiting.canRetry)
        let unpublished = boundary(.unpublished)
        XCTAssertEqual(unpublished.title, "No Layout Published")
        XCTAssertTrue(unpublished.canRetry && unpublished.isFinal && !unpublished.offersClear)
        let incompatible = boundary(.incompatible(missing: ["sh.future@1"]))
        XCTAssertEqual(incompatible.title, "Update Required")
        XCTAssertTrue(incompatible.message.contains("Update the app"))
        XCTAssertFalse(incompatible.canRetry)
        XCTAssertTrue(incompatible.isFinal)
        let failed = boundary(.waiting, status: .failure(.subscription))
        XCTAssertEqual(failed.title, "Layout Unavailable")
        XCTAssertTrue(failed.canRetry && failed.offersClear)
        XCTAssertEqual(boundary(expired: true).title, "Layout Unavailable")
        let stuck = boundary(adoptionFailed: true)
        XCTAssertFalse(stuck.canRetry)
        XCTAssertFalse(stuck.offersClear)
        let missing = boundary(storeMissing: true)
        XCTAssertFalse(missing.canRetry || missing.offersClear)
        XCTAssertTrue(UKServerUIRendererError(code: .interactionBlocked, pointer: "/document").isDeferred)
        XCTAssertFalse(UKServerUIRendererError(code: .symbolUnavailable, pointer: "/document").isDeferred)
        XCTAssertTrue(SetupCoordinator.ConfigurationError.interactionPending.isDeferred)
    }

    func testASavedPublicationIsOnScreenInTheHostsFirstLayoutPassBeforeAnyNetworkAnswer() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("cold-launch-\(UUID())")
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
            buildDefault: nil, launchArguments: [])
        defer {
            session.signOut()
            try? FileManager.default.removeItem(at: directory)
        }
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
        try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
        guard case .signedIn(let connection, _) = session.phase else { return XCTFail("Missing synthetic session") }

        // An earlier run saved this layout; the writer below is the same store the app uses.
        let publication = try solidPublication()
        let partition = try ServerUIPublicationPartition(server: server)
        let root = partition.storageDirectory(in: directory)
        let seed = ServerUIPublicationStore<Int>(partition: partition, cacheDirectory: root, prepare: { _, _ in 1 }, discard: { _, _ in })
        await seed.bind(userID: "ha-user-1")
        await seed.apply(try Self.published(publication))
        XCTAssertEqual(seed.status, .ready)

        let transport = SilentPublicationTransport()
        let runtime = UKServerUIProductionRuntime(session: session, connection: connection, privateRoot: directory,
                                                  transport: transport)
        defer { runtime.endSession() }
        XCTAssertNotNil(runtime.store?.current, "The saved layout is restored before any window exists.")
        XCTAssertEqual(session.cachedPublicationUserID(for: connection), "ha-user-1")
        for size in [HostedPage.phoneSize, CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            let host = UKServerUIProductionHost(runtime: runtime, session: session, connection: connection,
                                                environment: UKShellEnvironment())
            let window = HostedPage.show(host, size: HostedPage.inScene(size))
            defer { window.isHidden = true; host.didMove(toParent: nil) }
            // No waiting and no network: the first layout pass already attached the renderer.
            XCTAssertNotNil(host.renderer, "A signed-in cold launch with a saved layout never shows the loading ground.")
            let identifiers = HostedDriver.identifiers(in: host.view)
            XCTAssertFalse(identifiers.contains("server-ui.production.recovery"))
            XCTAssertEqual(try XCTUnwrap(host.renderer).publication, runtime.store?.current)
        }
        XCTAssertEqual(transport.subscriptions, 1, "The restored identity starts following the server at once.")
    }

    func testAnUpdateRequiredServerKeepsTheSavedLayoutAndWithoutOneShowsTheUpdateBoundary() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("incompatible-\(UUID())")
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
            buildDefault: nil, launchArguments: [])
        defer {
            session.signOut()
            try? FileManager.default.removeItem(at: directory)
        }
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
        try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
        guard case .signedIn(let connection, _) = session.phase else { return XCTFail("Missing synthetic session") }
        let transport = SilentPublicationTransport()
        let runtime = UKServerUIProductionRuntime(session: session, connection: connection, privateRoot: directory, transport: transport)
        defer { runtime.endSession() }
        let host = UKServerUIProductionHost(runtime: runtime, session: session, connection: connection, environment: UKShellEnvironment())
        let window = HostedPage.show(host, size: HostedPage.phoneSize)
        defer { window.isHidden = true }
        XCTAssertNil(host.renderer)
        await runtime.store?.apply(.incompatible(epoch: "e", revision: 3, missing: ["sh.future@1"]))
        await HostedPage.pump(passes: 10)
        let identifiers = HostedDriver.identifiers(in: host.view)
        XCTAssertTrue(identifiers.contains("server-ui.production.recovery"))
        XCTAssertFalse(identifiers.contains("server-ui.production.retry"))
        XCTAssertTrue(identifiers.contains("server-ui.production.signOut"))
    }

    /// The solid-background fixture publication: nothing to stage, so a cache entry needs no asset files.
    private func solidPublication() throws -> (json: JSONValue, publication: ServerUICompositionPublication) {
        var json = try ServerUIRendererFixture.json()
        json = try ServerUIRendererFixture.changing(json, path: "/document/assets", to: .array([]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/theme/background",
            to: .object(["type": "solid", "token": "shell-base@1"]))
        if case .object(let root) = json, case .array(let capabilities)? = root["capabilities"] {
            json = try ServerUIRendererFixture.changing(json, path: "/capabilities",
                to: .array(capabilities.filter { $0 != .string("sh.assets.publisher@1") }))
        }
        json = try ServerUIRendererFixture.changing(json, path: "/assetManifestSha256",
            to: .string(SHA256.hash(data: Data("[]".utf8)).map { String(format: "%02x", $0) }.joined()))
        return (json, try ServerUIRendererFixture.publication(json))
    }

    private static func published(_ solid: (json: JSONValue, publication: ServerUICompositionPublication),
                                  revision: Int = 1) throws -> ServerUIPublicationEvent {
        let envelope = try JSONSerialization.jsonObject(with: JSONEncoder().encode(solid.json))
        let reply = try JSONSerialization.data(withJSONObject: [
            "state": "published", "epoch": "epoch-1", "revision": revision,
            "envelopeSha256": String(repeating: "c", count: 64), "envelope": envelope,
        ] as [String: Any])
        return ServerUIPublicationEvent.judge(.success(reply))
    }

    func testBootstrapMessageUsesAuthoredCopyAndCanonicalStateViewWithoutFeatureDispatch() throws {
        var json = try ServerUIRendererFixture.json()
        let message: JSONValue = .object([
            "id": .string("synthetic-no-account"), "title": .string("Sample Account Needed"),
            "type": .string("bootstrap-message"), "layout": .object(["span": .number(1)]),
            "icon": .object(["type": .string("sf-symbol"), "name": .string("person.crop.circle.badge.exclamationmark"),
                             "rendering": .string("canonical"), "unavailable": .string("reject")]),
            "props": .object(["message": .string("Sign in to see sample content.")]),
        ])
        var nodes = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
        nodes.append(message)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(nodes))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string) + ["sh.bootstrap-message@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        for size in [CGSize(width: 390, height: 844), CGSize(width: 1130, height: 880), CGSize(width: 1024, height: 1366)] {
            let (renderer, window, _) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(json), size: size)
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(renderer)
            let state = try XCTUnwrap(page.nodes["synthetic-no-account"]?.view)
            XCTAssertTrue(state is UKServerUIBootstrapMessage)
            XCTAssertTrue(HostedPage.labels(in: state).contains("Sample Account Needed"))
            XCTAssertTrue(HostedPage.labels(in: state).contains("Sign in to see sample content."))
        }
    }

    func testNotificationPromptTakesValuesAndClosuresAndDisablesBothActionsDuringRequest() {
        var enabled = 0, dismissed = 0
        let prompt = UKNotificationPermissionPromptView(
            copy: .init(title: "Sample Alerts", message: "Choose sample alerts.", enable: "Continue", dismiss: "Later"),
            onEnable: { enabled += 1 }, onDismiss: { dismissed += 1 })
        let controller = UIViewController()
        controller.view = prompt
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let buttons = HostedPage.descendants(of: prompt).compactMap { $0 as? UIButton }
        let enable = buttons.first { $0.accessibilityIdentifier == "push.banner.turnOn" }
        let dismiss = buttons.first { $0.accessibilityIdentifier == "push.banner.notNow" }
        enable?.sendActions(for: .touchUpInside)
        dismiss?.sendActions(for: .touchUpInside)
        XCTAssertEqual(enabled, 1)
        XCTAssertEqual(dismissed, 1)
        prompt.apply(copy: .init(title: "Updated Alerts", message: "Updated explanation.", enable: "Enable", dismiss: "Not Now"), busy: true)
        XCTAssertEqual(enable?.isEnabled, false)
        XCTAssertEqual(dismiss?.isEnabled, false)
        XCTAssertTrue(HostedPage.labels(in: prompt).contains("Updated explanation."))
    }

    /// A push link, Live Activity tap, Spotlight result and shortcut all hand the renderer a `RouteRequest`; the publication's
    /// routes decide what it means. Written for the three families (phone, Duo's unfolded width and iPad).
    func testSystemRoutesUseAuthoredTabAndAnchorWithoutCompiledDispatch() throws {
        var json = try ServerUIRendererFixture.json()
        let document = try XCTUnwrap(json["document"])
        let pageID = try XCTUnwrap(document["pages"]?.array?.first?["id"]?.string)
        let tabID = try XCTUnwrap(document["navigation"]?["tabs"]?.array?.first?["id"]?.string)
        let modalID = try XCTUnwrap(document["modals"]?.array?.first?["id"]?.string)
        let targets: JSONValue = .object([
            "type": .string("native-extensions@1"), "watch": .string("stub@1"), "cameras": .array([]),
            "routes": .array([.object([
                "id": .string("home-link"), "path": .string("home"), "pageId": .string(pageID), "tabId": .string(tabID),
                "title": .string("Home"), "summary": .string("Your house"), "icon": .string("house.fill"),
                "aliases": .array([.string("overview")]),
                "anchors": .array([.object(["fragment": .string("details"), "modalId": .string(modalID)])]),
            ])]),
        ])
        json = try ServerUIRendererFixture.changing(json, path: "/document/extensions", to: targets)
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string) + ["sh.native-extensions@1", "sh.route-links@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        for size in [CGSize(width: 390, height: 844), CGSize(width: 1130, height: 880), CGSize(width: 1024, height: 1366)] {
            let (renderer, window, _) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(json), size: size)
            defer { window.isHidden = true }
            let initial = renderer.navigation.snapshot
            // An unknown path opens the app and navigates nowhere: no error, no placeholder, nothing changes.
            XCTAssertFalse(try renderer.openSystemRoute(RouteRequest(path: "unknown")))
            XCTAssertFalse(try renderer.openSystemRoute(RouteRequest(path: "unknown", anchor: "details")))
            XCTAssertEqual(renderer.navigation.snapshot, initial)
            // No path opens the publication's initial page.
            XCTAssertTrue(try renderer.openSystemRoute(RouteRequest()))
            XCTAssertTrue(renderer.navigation.snapshot.presentations.isEmpty)
            // An unknown anchor opens the page and drops the anchor; an alias is the route.
            XCTAssertTrue(try renderer.openSystemRoute(RouteRequest(path: "overview", anchor: "missing")))
            XCTAssertEqual(renderer.navigation.snapshot.selection, .tab(tabID))
            XCTAssertTrue(renderer.navigation.snapshot.presentations.isEmpty, "the missing anchor opened no sheet")
            // An authored anchor opens its sheet.
            XCTAssertTrue(try renderer.openSystemRoute(RouteRequest(path: "home", anchor: "details")))
            XCTAssertEqual(renderer.navigation.snapshot.selection, .tab(tabID))
            XCTAssertEqual(renderer.navigation.snapshot.presentations.last?.modalID, modalID)
            // Behind a presented sheet a known route waits (the host retries it); an unknown path still opens nothing.
            XCTAssertThrowsError(try renderer.openSystemRoute(RouteRequest(path: "home")))
            XCTAssertFalse(try renderer.openSystemRoute(RouteRequest(path: "unknown")))
        }
    }

    /// The solid fixture publication with one route that has an alias and an anchor, and a second that has neither.
    private func routedPublication() throws -> (json: JSONValue, publication: ServerUICompositionPublication, tab: String, modal: String) {
        var solid = try solidPublication()
        let document = try XCTUnwrap(solid.json["document"])
        let pageID = try XCTUnwrap(document["pages"]?.array?.first?["id"]?.string)
        let tabID = try XCTUnwrap(document["navigation"]?["tabs"]?.array?.first?["id"]?.string)
        let modalID = try XCTUnwrap(document["modals"]?.array?.first?["id"]?.string)
        var json = try ServerUIRendererFixture.changing(solid.json, path: "/document/extensions", to: .object([
            "type": "native-extensions@1", "watch": "stub@1", "cameras": .array([]),
            "linkPrefixes": .array(["my-dash"]),
            "routes": .array([.object([
                "id": "home-link", "path": "home", "pageId": .string(pageID), "tabId": .string(tabID),
                "title": "Home", "summary": "Your house", "icon": "house.fill", "aliases": .array(["overview"]),
                "keywords": .array(["rooms"]), "siri": true,
                "anchors": .array([.object(["fragment": "details", "modalId": .string(modalID)])]),
            ])]),
        ]))
        if case .object(let root) = json, case .array(let capabilities)? = root["capabilities"] {
            json = try ServerUIRendererFixture.changing(json, path: "/capabilities",
                to: .array((capabilities + [.string("sh.native-extensions@1"), .string("sh.route-links@1")])
                    .compactMap(\.string).sorted().map(JSONValue.string)))
        }
        solid = (json, try ServerUIRendererFixture.publication(json))
        return (solid.json, solid.publication, tabID, modalID)
    }

    /// A link or shortcut asked for a route before the publication was accepted: it stays pending, then the restored publication
    /// resolves it through the authored route and its alias, drops an unknown anchor, and opens nothing for an unknown path.
    /// Written for the three families.
    func testARouteRequestedBeforeTheLayoutIsAcceptedOpensWhenItArrives() async throws {
        let cases: [(request: () -> Void, modal: Bool, moves: Bool)] = [
            ({ [unowned self] in _ = self }, false, false), // placeholder replaced below
        ]
        _ = cases
        let sizes = [HostedPage.phoneSize, CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)]
        let requests: [(RouteRequest, expectModal: Bool, navigates: Bool)] = [
            (RouteRequest(path: "overview", anchor: "details"), true, true),   // alias plus an authored anchor
            (RouteRequest(path: "home", anchor: "missing"), false, true),      // an unknown anchor is dropped
            (RouteRequest(path: "no-such-route", anchor: "details"), false, false), // an unknown path opens the app only
            (RouteRequest(), false, true),                                     // no path: the initial page
        ]
        for size in sizes {
            for (request, expectModal, navigates) in requests {
                let directory = URL.temporaryDirectory.appendingPathComponent("route-open-\(UUID())")
                let store = ExtensionPresentationStore(directory: directory.appendingPathComponent("targets"))
                let session = AppSession(tokenStore: InMemoryTokenStore(),
                    snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
                    houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
                    buildDefault: nil, launchArguments: [], extensionStore: store)
                defer {
                    session.signOut()
                    try? FileManager.default.removeItem(at: directory)
                }
                let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
                try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
                guard case .signedIn(let connection, _) = session.phase else { return XCTFail("Missing synthetic session") }
                // Nothing is accepted yet: the request waits, as a raw link when it came from one.
                session.push.open(request)
                let pending = try XCTUnwrap(session.push.pendingRequest)
                XCTAssertNil(session.routeCatalog)

                let routed = try routedPublication()
                let partition = try ServerUIPublicationPartition(server: server)
                let seed = ServerUIPublicationStore<Int>(partition: partition, cacheDirectory: partition.storageDirectory(in: directory),
                                                         prepare: { _, _ in 1 }, discard: { _, _ in })
                await seed.bind(userID: "ha-user-1")
                await seed.apply(try Self.published((routed.json, routed.publication)))
                let runtime = UKServerUIProductionRuntime(session: session, connection: connection, privateRoot: directory,
                                                          transport: SilentPublicationTransport())
                defer { runtime.endSession() }
                // The restored publication is accepted: the routes are offered and the link prefixes known.
                XCTAssertEqual(session.routeCatalog?.routes.map(\.path), ["home"])
                XCTAssertEqual(session.routeCatalog?.suggested.map(\.path), ["home"])
                XCTAssertEqual(session.push.linkPrefixes, ["my-dash"])
                XCTAssertEqual(session.push.pendingRequest, pending, "accepting a publication does not drop or restamp a pending route")

                let host = UKServerUIProductionHost(runtime: runtime, session: session, connection: connection,
                                                    environment: UKShellEnvironment())
                let window = HostedPage.show(host, size: HostedPage.inScene(size))
                defer { window.isHidden = true; host.didMove(toParent: nil) }
                await HostedPage.pump(passes: 15)
                let renderer = try XCTUnwrap(host.renderer, "\(size) \(request)")
                XCTAssertNil(session.push.pendingRequest, "the host opened (or settled) the request: \(size) \(request)")
                let snapshot = renderer.navigation.snapshot
                XCTAssertEqual(snapshot.presentations.last?.modalID, expectModal ? routed.modal : nil, "\(size) \(request)")
                if navigates { XCTAssertEqual(snapshot.selection, .tab(routed.tab), "\(size) \(request)") }
                let identifiers = HostedDriver.identifiers(in: host.view)
                XCTAssertFalse(identifiers.contains("server-ui.production.recovery"), "an unknown path shows no error ground")
            }
        }
    }

    /// The accepted publication's `linkPrefixes` decide which links are the dashboard's, and a later publication without them
    /// returns to the migration default; the saved route catalog is account-scoped and removed at sign-out.
    func testAcceptingAPublicationSavesTheCatalogAndTheLinkPrefixesAndSignOutClearsThem() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("route-catalog-hosted-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionPresentationStore(directory: directory.appendingPathComponent("targets"))
        let routesStore = RouteCatalogStore(base: store)
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
            buildDefault: nil, launchArguments: [], extensionStore: store)
        var refreshes = 0
        session.routeCatalogDidChange = { refreshes += 1 }
        try session.didSignIn(server: HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1"))),
            tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
        defer { session.signOut() }
        XCTAssertNil(routesStore.read())
        let routed = try routedPublication()
        // A link made before the publication is read by the migration slugs; the publication then names its own.
        session.push.open(link: "/sfenton-react-dash/home?path=overview")
        XCTAssertNotNil(session.push.pendingRequest?.link)
        try session.deliverExtensions(routed.publication)
        XCTAssertEqual(session.push.linkPrefixes, ["my-dash"])
        XCTAssertNil(session.push.pendingRequest, "the pending link is read again: its slug is now an ordinary Home Assistant page")
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(routesStore.read()?.routes.map(\.path), ["home"])
        XCTAssertEqual(routesStore.read()?.routes.first?.aliases, ["overview"])
        // The same routes again change nothing visible: no second write or shortcut refresh.
        try session.deliverExtensions(routed.publication)
        XCTAssertEqual(refreshes, 1)
        session.signOut()
        XCTAssertNil(routesStore.read())
        XCTAssertNil(session.routeCatalog)
        XCTAssertNil(session.push.linkPrefixes)
    }

    func testAcceptedExtensionCopyRollsBackOnFailedNativeCommitAndLogoutFencesLateDelivery() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("extension-hosted-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionPresentationStore(directory: directory.appendingPathComponent("targets"))
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
            buildDefault: nil, launchArguments: [], extensionStore: store)
        try session.didSignIn(server: HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1"))),
            tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
        defer { session.signOut() }
        let publication = try ServerUIRendererFixture.publication(ServerUIRendererFixture.json())
        try session.deliverExtensions(publication)
        let accepted = try store.read()
        enum Rejected: Error { case commit }
        XCTAssertThrowsError(try session.deliverExtensions(publication) { throw Rejected.commit })
        XCTAssertEqual(try store.read(), accepted)
        session.signOut()
        XCTAssertNil(try store.read())
        XCTAssertThrowsError(try session.deliverExtensions(publication))
        if let accepted { XCTAssertThrowsError(try store.write(accepted)) }
    }

    func testALaunchWithoutAnExtensionStoreStillCommitsThePublication() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("no-extension-store-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
            buildDefault: nil, launchArguments: [])
        try session.didSignIn(server: HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1"))),
            tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
        defer { session.signOut() }
        var applied = false
        let publication = try ServerUIRendererFixture.publication(ServerUIRendererFixture.json())
        XCTAssertNoThrow(try session.deliverExtensions(publication) { applied = true },
                         "Without a store there is nothing to feed; the layout must not be rejected for it")
        XCTAssertTrue(applied)
    }

    func testNormalProvidersRetainControllersAndRejectAStaleSessionCaller() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("providers-hosted-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
        let cache = HouseConfigCache(fileURL: directory.appendingPathComponent("house"))
        try cache.save(DemoHouse.config, hash: "synthetic", server: server)
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: cache, buildDefault: nil, launchArguments: [])
        try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
        guard case .signedIn(let connection, _) = session.phase else { return XCTFail("Missing synthetic session") }
        let providers = UKServerUIProductionProviders(session: session, connection: connection)
        let publication = try ServerUIRendererFixture.publication()
        try providers.prepare(publication)
        let id = try XCTUnwrap(DemoHouse.config.media.remotes.first?.id)
        let remote = try XCTUnwrap(providers.remotes[id])
        try providers.prepare(publication)
        XCTAssertTrue(providers.remotes[id] === remote)
        XCTAssertEqual(providers.bedrooms[DemoHouse.config.bedroom.wakeLight.id]?.kind, .wake)
        var context = UKContext(store: connection.store, caller: providers.caller)
        context.connection = connection
        context.session = session
        let renderer = try UKServerUIRenderer(publication: publication, context: context,
            backdrop: ServerUIRendererFixture.backdrop(), bedroomProviders: providers.bedrooms, remoteProviders: providers.remotes)
        var replacements = providers.remotes
        replacements[id] = ServerUIRemoteSession(controller: MediaRemoteController(config: remote.controller.config,
            store: connection.store, caller: providers.caller))
        remote.setEditing(true, controlID: "synthetic-gesture")
        XCTAssertThrowsError(try renderer.validateUpdate(publication, remoteProviders: replacements))
        remote.setEditing(false, controlID: "synthetic-gesture")
        XCTAssertNoThrow(try renderer.validateUpdate(publication, remoteProviders: replacements))
        let wakeID = DemoHouse.config.bedroom.wakeLight.id
        let replacementWake = UKServerUIBedroomProvider.wake(WakeLightController(
            config: DemoHouse.config.bedroom.wakeLight, store: connection.store, caller: providers.caller, canEdit: false))
        var bedrooms = providers.bedrooms
        bedrooms[wakeID] = replacementWake
        try renderer.apply(publication: publication, backdrop: ServerUIRendererFixture.backdrop(),
                           bedroomProviders: bedrooms, remoteProviders: replacements)
        XCTAssertEqual(renderer.bindings.bedroomProviders[wakeID]?.identity, replacementWake.identity)
        try renderer.apply(publication: publication, backdrop: ServerUIRendererFixture.backdrop())
        XCTAssertEqual(renderer.bindings.bedroomProviders[wakeID]?.identity, replacementWake.identity,
                       "A later publication must not restore the superseded house-config provider.")
        for (providerID, remote) in providers.remotes {
            for app in remote.controller.config.apps {
                if let path = app.imagePath {
                    XCTAssertEqual(renderer.artworkURL(providerID: providerID, appID: app.id), server.url(path))
                }
            }
        }
        for useHouseIDs in [false, true] {
            let json = try ServerUIRendererFixture.authoredBedroom(useHouseIDs: useHouseIDs)
            let authored = try ServerUIRendererFixture.publication(json)
            try providers.prepare(authored)
            let supplied = providers.supplementalProviders(for: authored)
            let host = try UKServerUIRenderer(publication: authored, context: context,
                backdrop: ServerUIRendererFixture.backdrop(), bedroomProviders: supplied.bedrooms,
                remoteProviders: supplied.remotes, deviceResponder: providers.caller)
            let room = try XCTUnwrap(host.deviceProviders.bedrooms["authored-bedroom"])
            let key = room.descriptor.wakeProviderId
            XCTAssertNil(supplied.bedrooms[key])
            XCTAssertEqual(host.bindings.bedroomProviders[key]?.identity, ObjectIdentifier(room.devices.wakeLight))
            XCTAssertNotEqual(host.bindings.bedroomProviders[key]?.identity, providers.bedrooms[key]?.identity)
            let index = try XCTUnwrap(json["document"]?["dataSources"]?.array?.count) - 1
            let missing = try ServerUIRendererFixture.changing(json,
                path: "/document/dataSources/\(index)/inputs/providerId", to: "unregistered-wake")
            XCTAssertThrowsError(try providers.prepare(ServerUIRendererFixture.publication(missing)))
        }
        session.signOut()
        XCTAssertNil(renderer.artworkURL(providerID: id, appID: remote.controller.config.apps.first?.id ?? "missing"))
        let scopedOperations: [@MainActor () async throws -> Void] = [
            { _ = try await providers.caller.accessToken() },
            { _ = try await providers.caller.listSchedules() },
            { _ = try await providers.caller.updateSchedule([:]) },
            { _ = try await providers.caller.userIsAdmin() },
            { _ = try await providers.caller.callServiceForResponse("evershelf", "inventory_list", data: [:]) },
            { _ = try await providers.caller.todoItems(entityId: "todo.demo_unit") },
            { try await providers.caller.uploadAdminTodo(.init(entityId: "todo.demo_unit", item: "Synthetic item", images: []),
                                                        accessToken: "synthetic") },
        ]
        for operation in scopedOperations {
            do {
                try await operation()
                XCTFail("Ended session accepted a scoped operation")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        do {
            try await providers.caller.callService("switch", "turn_on", data: ["entity_id": "switch.demo_unit"])
            XCTFail("Ended session accepted a command")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertThrowsError(try providers.prepare(publication))
    }

    func testAllWindowPlansArePreparedBeforeAdoptionAndRejectChangesDuringPersistence() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("production-plans-\(UUID())")
        let suite = "production-plans-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(45, forKey: BackdropBlur.defaultsKey)
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
            buildDefault: nil, launchArguments: [])
        defer {
            session.signOut()
            defaults.removePersistentDomain(forName: suite)
            do {
                if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            } catch { XCTFail("Fixture cleanup failed: \(error)") }
        }
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
        try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
        guard case .signedIn(let connection, _) = session.phase else { return XCTFail("Missing synthetic session") }
        let runtime = UKServerUIProductionRuntime(session: session, connection: connection,
                                                 privateRoot: directory, preferencesDefaults: defaults,
                                                 transport: SilentPublicationTransport())
        var json = try ServerUIRendererFixture.json()
        json = try ServerUIRendererFixture.changing(json, path: "/document/assets", to: .array([]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/theme/background",
            to: .object(["type": "solid", "token": "shell-base@1"]))
        json = try ServerUIRendererFixture.changing(json, path: "/assetManifestSha256",
            to: .string(SHA256.hash(data: Data("[]".utf8)).map { String(format: "%02x", $0) }.joined()))
        let sources = try XCTUnwrap(json["document"]?["dataSources"]?.array) + [
            JSONValue.object(["id": "preferences", "kind": "model", "model": "settings-provider@1",
                              "inputs": .object(["providerId": "preferences", "domain": "preferences"])]),
            JSONValue.object(["id": "performance", "kind": "model", "model": "settings-provider@1",
                              "inputs": .object(["providerId": "performance", "domain": "performance"])]),
        ]
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources", to: .array(sources))
        let components = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
        let icon = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["icon"])
        let blur: JSONValue = .object([
            "id": "blur", "title": "Background Blur", "type": "settings-control", "layout": .object(["span": .number(1)]),
            "icon": icon, "props": .object(["sourceId": "preferences", "kind": "background-blur", "item": "", "subtitle": ""]),
        ])
        let diagnostics: JSONValue = .object([
            "id": "diagnostics", "title": "Performance", "type": "settings-control", "layout": .object(["span": .number(1)]),
            "icon": icon, "props": .object(["sourceId": "performance", "kind": "performance-action", "item": "refresh", "subtitle": ""]),
        ])
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components",
                                                   to: .array(components + [blur, diagnostics]))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.assets.publisher@1" }
            + ["sh.settings-controls@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        let publication = try ServerUIRendererFixture.publication(json)
        let partition = try ServerUIPublicationPartition(server: server)
        let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: partition.storageDirectory(in: directory),
            transport: ServerUIAssetTransport(server: server, tokenProvider: { throw URLError(.notConnectedToInternet) }))
        let assets = try await stager.stage(publication, documentDigest: publication.documentSha256)
        let prepared = UKServerUIProductionRuntime.Prepared(assets: assets, photo: nil, blurPercent: 0,
                                                            directory: directory.appendingPathComponent("renders"))
        let hosts = (0..<2).map { _ in
            UKServerUIProductionHost(runtime: runtime, session: session, connection: connection, environment: UKShellEnvironment())
        }
        let windows = hosts.map { HostedPage.show($0, size: HostedPage.phoneSize) }
        defer { windows.forEach { $0.isHidden = true } }
        for host in hosts { try await prepared.prepare(host: host) }
        try prepared.prepareRenderers(publication, hosts: hosts, generation: runtime.providers.generation)
        XCTAssertTrue(hosts.allSatisfy { $0.renderer == nil }, "Preparation must not expose any new window.")
        XCTAssertThrowsError(try prepared.validatedPlans(hosts: hosts, generation: runtime.providers.generation + 1))
        defaults.set(60, forKey: BackdropBlur.defaultsKey)
        XCTAssertThrowsError(try prepared.validatedPlans(hosts: hosts, generation: runtime.providers.generation),
                             "A changed local preference invalidates the staged backdrop before adoption.")
        defaults.set(45, forKey: BackdropBlur.defaultsKey)

        let arriving = UKServerUIProductionHost(runtime: runtime, session: session, connection: connection, environment: UKShellEnvironment())
        XCTAssertThrowsError(try prepared.validatedPlans(hosts: hosts + [arriving], generation: runtime.providers.generation),
                             "A window arriving during the durable write needs its own complete plan.")
        let original = hosts[1].view.bounds
        hosts[1].view.bounds.size.width -= 20
        XCTAssertThrowsError(try prepared.validatedPlans(hosts: hosts, generation: runtime.providers.generation))
        XCTAssertTrue(hosts.allSatisfy { $0.renderer == nil }, "Failure in the second window must not expose the first.")
        hosts[1].view.bounds = original
        let plans = try prepared.validatedPlans(hosts: hosts, generation: runtime.providers.generation)
        XCTAssertEqual(plans.count, 2)
        for plan in plans { try plan.apply() }
        for host in hosts {
            let renderer = try XCTUnwrap(host.renderer)
            XCTAssertTrue(renderer.isViewLoaded)
            XCTAssertFalse(try ServerUIRendererFixture.root(renderer).nodes.isEmpty)
            XCTAssertEqual(renderer.publication, publication)
            let preferences = try XCTUnwrap(renderer.settingsProviders["preferences"] as? UKServerUIPreferencesProvider)
            let visibleBackdrop = try prepared.readyBackdrop(for: host)
            XCTAssertTrue(preferences.blur === visibleBackdrop.blur)
            XCTAssertEqual(preferences.blur.percent, 45)
            XCTAssertNotNil(renderer.collections["performance-loading"])
        }
        let firstPreferences = try XCTUnwrap(hosts[0].renderer?.settingsProviders["preferences"] as? UKServerUIPreferencesProvider)
        try firstPreferences.setBlur(60)
        XCTAssertEqual(defaults.integer(forKey: BackdropBlur.defaultsKey), 60)
        for host in hosts {
            XCTAssertEqual((host.renderer?.settingsProviders["preferences"] as? UKServerUIPreferencesProvider)?.blur.percent, 60,
                           "One device preference updates each visible window's independent backdrop.")
        }
        XCTAssertThrowsError(try plans[0].validate(), "A plan cannot replace a renderer mounted after preparation.")
        prepared.releasePlans()
        XCTAssertThrowsError(try prepared.validatedPlans(hosts: hosts, generation: runtime.providers.generation))

        try prepared.prepareRenderers(publication, hosts: hosts, generation: runtime.providers.generation)
        session.signOut()
        XCTAssertThrowsError(try prepared.validatedPlans(hosts: hosts, generation: runtime.providers.generation))
        XCTAssertThrowsError(try firstPreferences.setBlur(80))
        XCTAssertEqual(defaults.integer(forKey: BackdropBlur.defaultsKey), 60)
        prepared.releasePlans()
    }

    func testRecordRegistrationsUseVerifiedScopeAndKeepWindowSelectionsSeparate() async throws {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        try await HouseConfigSource.$scoped.withValue(source) {
            let config = DemoHouse.config.chores
            let person = try XCTUnwrap(config.people.first)
            let entities = EntityStore()
            let service = ChoresFixtureService(store: entities, lists: ChoresFixtures.lists())
            let todos = TodoStore(service: service)
            let recipes = FixtureRecipeService(delay: .zero)
            var current = true
            let chores = try ServerUIRendererFixture.publication(
                ServerUITodoPublicationFixture.adding(config.pages, to: ServerUIRendererFixture.json()))
            let definition = UKServerUIRecordProviders.Definition(people: config.people, document: chores.document)
            @MainActor func make(_ id: String, retaining previous: UKServerUIRecordProviders? = nil) throws -> UKServerUIRecordProviders {
                try .init(definition: definition, authenticatedUserID: id, service: service, recipes: recipes,
                    todos: todos, store: entities, accessToken: { "synthetic" }, isCurrentSession: { current }, retaining: previous)
            }
            let first = try make(person.haUserId)
            let second = try make(person.haUserId)
            let firstSummary = try XCTUnwrap(first.records.collections["summary-overdue"] as? UKServerUIChoresCollection)
            let secondSummary = try XCTUnwrap(second.records.collections["summary-overdue"] as? UKServerUIChoresCollection)
            XCTAssertEqual(firstSummary.configuration.lists.map(\.entityId), [person.summaryLists.overdue])
            XCTAssertTrue(firstSummary.model.todos === secondSummary.model.todos)
            XCTAssertFalse(firstSummary === secondSummary)
            let firstRecipes = try XCTUnwrap(first.records.recipes["recipes"])
            let secondRecipes = try XCTUnwrap(second.records.recipes["recipes"])
            let selected = try firstRecipes.select(XCTUnwrap(FoodFixtures.catalog.first))
            XCTAssertNil(secondRecipes.selected)
            let replacement = try make(person.haUserId, retaining: first)
            XCTAssertTrue(replacement.records.recipes["recipes"]?.selected === selected)
            XCTAssertTrue(replacement.records.collections["records-inventory-pantry"] === first.records.collections["records-inventory-pantry"])

            let guest = try make("synthetic-guest")
            XCTAssertEqual(guest.records.tabScopes["summary"]?.allowedTabIDs, ["profile", "expired-food"])
            XCTAssertNil(guest.records.collections["summary-overdue"])
            XCTAssertNotNil(guest.records.collections["summary-expired-food"], "Shared food is not a personal chore list.")
            for id in ["summary-overdue-edit", "summary-upcoming-edit"] {
                let factory = try XCTUnwrap(guest.records.forms[id])
                do { _ = try await factory.open(); XCTFail("Guest opened a private Summary editor") }
                catch { XCTAssertEqual(error as? ServerUITodoProvider.Failure, .forbidden) }
            }
            let admin = try XCTUnwrap(config.pages.first(where: \.editsAdminTodo))
            let adminSource = try XCTUnwrap(guest.records.collections["records-" + admin.id])
            do { try await adminSource.load(); XCTFail("Guest read the restricted admin collection") }
            catch { XCTAssertEqual(error as? ServerUITodoProvider.Failure, .forbidden) }
            XCTAssertNotNil(adminSource.error)
            let adminFactory = try XCTUnwrap(guest.records.forms["records-" + admin.id + "-add"])
            do { _ = try await adminFactory.open(); XCTFail("Guest opened the admin attachment editor") }
            catch { XCTAssertEqual(error as? ServerUITodoProvider.Failure, .forbidden) }

            let scanFactory = try XCTUnwrap(first.records.forms["records-inventory-pantry-scan"])
            let scan = try await scanFactory.open()
            XCTAssertTrue(scan is UKServerUIScanForm)
            try scan.discard()
            current = false
            do { _ = try await scanFactory.open(); XCTFail("Ended session opened a new scanner") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(service.lastCall, "none", "Registration and rejected factories must not issue service calls.")
            XCTAssertTrue(recipes.calls.isEmpty)
        }
    }

    func testNormalRecordsRestoreOnlyTheirAccountCacheAndForgetItAtSignOut() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("record-accounts-\(UUID())")
        defer {
            do { if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) } }
            catch { XCTFail("Fixture cleanup failed: \(error)") }
        }
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
        let users = Array(DemoHouse.config.chores.people.prefix(2))
        XCTAssertEqual(users.count, 2)
        let root = directory.appendingPathComponent("records")
        var files: [URL] = []
        for (index, user) in users.enumerated() {
            let bytes = try JSONEncoder().encode([server.baseURL.absoluteString, user.haUserId])
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let file = root.appendingPathComponent(digest).appendingPathComponent("todo.json")
            files.append(file)
            try TodoItemsCache(server: server, fileURL: file).save([
                DemoHouse.config.chores.groceryEntityId: [.init(uid: "private-item", summary: "Account \(index)")],
            ])
        }
        var json = try ServerUITodoPublicationFixture.adding(DemoHouse.config.chores.pages, to: ServerUIRendererFixture.json())
        let component: JSONValue = .object([
            "id": "account-records", "title": "Groceries", "type": "collection", "layout": .object(["span": .number(1)]),
            "props": .object(["providerId": "records-groceries", "template": "todo", "loadingText": "Loading", "emptyText": "Empty"]),
        ])
        let components = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components + [component]))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string) + ["sh.collection@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        let publication = try ServerUIRendererFixture.publication(json)
        let settingsDomains = ["household", "away", "profile", "preferences", "performance", "feedback-bug", "feedback-feature"]
        let settingsSources: [JSONValue] = settingsDomains.map { id in
            .object(["id": .string("settings-" + id), "kind": "model", "model": "settings-provider@1",
                     "inputs": .object(["providerId": .string(id),
                                        "domain": .string(id.hasPrefix("feedback-") ? "feedback" : id)])])
        }
        var settingsJSON = try ServerUIRendererFixture.changing(json, path: "/document/dataSources",
            to: .array(try XCTUnwrap(json["document"]?["dataSources"]?.array) + settingsSources))
        settingsJSON = try ServerUIRendererFixture.changing(settingsJSON, path: "/capabilities",
            to: .array((capabilities + ["sh.settings-controls@1"]).sorted().map(JSONValue.string)))
        let withSettings = try ServerUIRendererFixture.publication(settingsJSON)
        for (index, user) in users.enumerated() {
            let cache = HouseConfigCache(fileURL: directory.appendingPathComponent("house-\(index)"))
            try cache.save(DemoHouse.config, hash: "synthetic", server: server)
            let credentials = StoredCredentials(server: server, refreshToken: "synthetic-\(index)")
            let session = AppSession(tokenStore: InMemoryTokenStore(),
                snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities-\(index)")),
                houseConfigCache: cache, buildDefault: nil, launchArguments: [])
            try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture,
                                                               refreshToken: credentials.refreshToken))
            defer { session.signOut() }
            guard case .signedIn(let connection, _) = session.phase else { return XCTFail("Missing synthetic session") }
            let providers = UKServerUIProductionProviders(session: session, connection: connection, recordCacheRoot: root)
            session.setPublicationUser(user.haUserId, connection: connection)
            XCTAssertEqual(session.cachedPublicationUserID(for: connection), user.haUserId)
            let sceneID = UUID()
            let records = try providers.records(for: publication, sceneID: sceneID)
            let groceries = try XCTUnwrap(records.collections["records-groceries"] as? UKServerUIChoresCollection)
            let list = groceries.model.todos.controller(for: DemoHouse.config.chores.groceryEntityId)
            XCTAssertEqual(list.items?.map(\.summary), ["Account \(index)"])
            let again = try providers.records(for: publication, sceneID: sceneID)
            XCTAssertTrue(again.collections["records-groceries"] === groceries)
            let settings = try providers.settings(for: withSettings, sceneID: sceneID)
            XCTAssertEqual(Set(settings.keys), Set(settingsDomains))
            let complete = try providers.records(for: withSettings, sceneID: sceneID)
            XCTAssertNotEqual(complete.identity, records.identity)
            XCTAssertEqual(try providers.records(for: withSettings, sceneID: sceneID).identity, complete.identity,
                           "Unchanged preflight must not replace a registry while a form is open.")
            let away = try XCTUnwrap(settings["away"] as? UKServerUIAwayProvider)
            XCTAssertEqual(away.solo.viewer?.key, user.key)
            XCTAssertTrue(away.vacation.household === away.solo.household)
            XCTAssertEqual(providers.roomResidentID, user.key)
            let feedback = try XCTUnwrap(settings["feedback-bug"] as? UKServerUIFeedbackProvider)
            feedback.model.descriptionText = "Keep this window's draft"
            let otherSettings = try providers.settings(for: withSettings, sceneID: UUID())
            let otherFeedback = try XCTUnwrap(otherSettings["feedback-bug"] as? UKServerUIFeedbackProvider)
            XCTAssertFalse(otherFeedback.model.hasUnsavedInput)
            XCTAssertTrue(try providers.settings(for: withSettings, sceneID: sceneID)["feedback-bug"] === feedback)
            XCTAssertTrue(feedback.protectsPublication)
            providers.detachRecordWindow(sceneID)
            let reopened = try providers.records(for: publication, sceneID: sceneID)
            XCTAssertFalse(reopened.collections["records-groceries"] === groceries)
            let fenced = UKServerUISessionCaller(session: session, connection: connection, configuration: DemoHouse.config)
            session.houseConfig?.clear()
            XCTAssertFalse(away.isCurrentSession)
            XCTAssertThrowsError(try providers.settings(for: withSettings, sceneID: sceneID))
            do { _ = try await fenced.accessToken(); XCTFail("A stale descriptor retained command authority") }
            catch { XCTAssertTrue(error is CancellationError) }
            providers.endSession()
            XCTAssertFalse(FileManager.default.fileExists(atPath: files[index].path))
            if index == 0 { XCTAssertTrue(FileManager.default.fileExists(atPath: files[1].path)) }
            session.signOut()
            XCTAssertNil(session.cachedPublicationUserID(for: connection))
            XCTAssertThrowsError(try providers.records(for: publication))
        }
    }

    /// A first sign-in has no house configuration when the publication arrives. The household and away providers are pending (a
    /// deferrable timing failure the store holds), never an `unavailable_source` rejection. Written for iPhone, Duo and iPad widths.
    func testAProfileLocationControlHidesInsteadOfRejectingTheLayoutWhenTheLaunchHasNoLocationCoordinator() throws {
        let sources: [JSONValue] = [.object(["id": "settings-profile", "kind": "model", "model": "settings-provider@1",
                                             "inputs": .object(["providerId": "profile", "domain": "profile"])])]
        var json = try ServerUIRendererFixture.json()
        let icon = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["icon"])
        let components = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
        let control: JSONValue = .object([
            "id": "synthetic-location-status", "title": "Location", "type": "settings-control", "layout": .object(["span": .number(1)]),
            "icon": icon, "props": .object(["sourceId": "settings-profile", "kind": "location-status", "item": "", "subtitle": ""]),
        ])
        // Every control whose availability is a fact of the launch (no location coordinator, no alternate icons) is hidden or
        // disabled, never a reason to reject the layout.
        let launchDependent: [(id: String, source: String, kind: String, item: String)] = [
            ("synthetic-location-action", "settings-profile", "location-action", ""),
            ("synthetic-icon-choice", "settings-preferences", "app-icon-choice", AppIconChoice.midnightGold.rawValue),
        ]
        let extras: [JSONValue] = launchDependent.map { row in
            .object(["id": .string(row.id), "title": "Synthetic", "type": "settings-control", "layout": .object(["span": .number(1)]),
                     "icon": icon, "props": .object(["sourceId": .string(row.source), "kind": .string(row.kind),
                                                     "item": .string(row.item), "subtitle": ""])])
        }
        let allSources = sources + [.object(["id": "settings-preferences", "kind": "model", "model": "settings-provider@1",
                                          "inputs": .object(["providerId": "preferences", "domain": "preferences"])])]
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources",
            to: .array(try XCTUnwrap(json["document"]?["dataSources"]?.array) + allSources))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components + [control] + extras))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string) + ["sh.settings-controls@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        let publication = try ServerUIRendererFixture.publication(json)
        let directory = URL.temporaryDirectory.appendingPathComponent("no-location-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
            buildDefault: nil, launchArguments: [])
        try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic-refresh"))
        defer { session.signOut() }
        guard case .signedIn(let connection, _) = session.phase else { return XCTFail("Missing synthetic session") }
        XCTAssertNil(session.location, "The fixture session has no location coordinator, as a debug journey launch does not")
        let providers = UKServerUIProductionProviders(session: session, connection: connection)
        XCTAssertNoThrow(try providers.settings(for: publication),
                         "A profile control for a location the launch cannot report must hide, not reject the layout")
    }

    func testHouseholdAndAwayProvidersArePendingNotRejectedUntilTheHouseConfigurationArrives() throws {
        let settingsDomains = ["household", "away"]
        let settingsSources: [JSONValue] = settingsDomains.map { id in
            .object(["id": .string("settings-" + id), "kind": "model", "model": "settings-provider@1",
                     "inputs": .object(["providerId": .string(id), "domain": .string(id)])])
        }
        var json = try ServerUIRendererFixture.json()
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string) + ["sh.settings-controls@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources",
            to: .array(try XCTUnwrap(json["document"]?["dataSources"]?.array) + settingsSources))
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        let publication = try ServerUIRendererFixture.publication(json)
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            let directory = URL.temporaryDirectory.appendingPathComponent("pending-inputs-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
            let session = AppSession(tokenStore: InMemoryTokenStore(),
                snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
                houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
                buildDefault: nil, launchArguments: [])
            try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture,
                                                               refreshToken: "synthetic-refresh"))
            defer { session.signOut() }
            guard case .signedIn(let connection, _) = session.phase else { return XCTFail("Missing synthetic session at \(size)") }
            XCTAssertNil(session.houseConfig?.current, "The fixture must start without a house configuration at \(size)")
            let providers = UKServerUIProductionProviders(session: session, connection: connection)
            session.setPublicationUser(try XCTUnwrap(DemoHouse.config.chores.people.first).haUserId, connection: connection)
            for attempt in [{ _ = try providers.settings(for: publication) }, { _ = try providers.records(for: publication) },
                            { try providers.prepare(publication) }] {
                do { try attempt(); XCTFail("The providers were built without a house configuration at \(size)") }
                catch let error as UKServerUIRendererError {
                    XCTAssertEqual(error.code, .inputsPending, "A missing input is pending, not rejected, at \(size): \(error)")
                    XCTAssertTrue(error.isDeferred)
                } catch { XCTFail("Unexpected failure at \(size): \(error)") }
            }
            XCTAssertFalse(providers.hasPendingConfiguration)
        }
    }

    func testAwayProjectionsReadExplicitTargetsRatherThanTheGlobalHouse() throws {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        try HouseConfigSource.$scoped.withValue(source) {
            var configuration = DemoHouse.config
            configuration.vacation.modeEntityId = "input_boolean.demo_published_vacation"
            let store = EntityStore()
            store.replaceAll([.init(entityId: DemoHouse.config.vacation.modeEntityId, state: "on"),
                              .init(entityId: configuration.vacation.modeEntityId, state: "off")])
            let caller = LoggingResponder()
            var current = true
            let away = try UKServerUIHouseholdProviders.away(id: "away", configuration: configuration,
                authenticatedUserID: XCTUnwrap(configuration.chores.people.first).haUserId, store: store,
                caller: caller, current: { current })
            var records = UKServerUIRecords()
            try away.addPresentations(to: &records)
            let scope = try XCTUnwrap(records.tabScopes["away-route"])
            XCTAssertEqual(scope.automaticSelection?(), "chooser")
            XCTAssertEqual(records.sections["away-checklist"]?().visible, true)
            store.apply([.init(entityId: configuration.vacation.modeEntityId, state: "on")])
            XCTAssertEqual(scope.automaticSelection?(), "vacation")
            XCTAssertEqual(records.sections["away-checklist"]?().visible, false)
            XCTAssertEqual(records.sections["away-dates"]?().visible, true)
            current = false
            XCTAssertEqual(records.actionStates["modal-vacation-confirm-cancel"]?().enabled, false)
            XCTAssertTrue(caller.calls.isEmpty)
            XCTAssertThrowsError(try away.addPresentations(to: &records), "Duplicate presentation ownership must be rejected.")
        }
    }

    func testFeedbackRejectsAnOldAccountsLateResponseAndFurtherRequests() async throws {
        let started = expectation(description: "Feedback availability started")
        let inner = SuspendedFeedbackFiler(started: { started.fulfill() })
        var current = true
        let filer = UKServerUISessionFeedbackFiler(filer: inner, isCurrentSession: { current })
        let pending = Task { try await filer.isAvailable() }
        await fulfillment(of: [started], timeout: 2)
        current = false
        inner.complete()
        do { _ = try await pending.value; XCTFail("Old feedback response crossed sign-out") }
        catch { XCTAssertEqual(error as? FeedbackFilingError, .signedOut) }
        do { _ = try await filer.isAvailable(); XCTFail("Ended account issued a new request") }
        catch { XCTAssertEqual(error as? FeedbackFilingError, .signedOut) }
        XCTAssertEqual(inner.calls, 1)
    }

    /// A private catalog can be supplied locally without embedding house bindings in the test bundle.
    func testNormalProvidersAdmitTheSuppliedCatalog() async throws {
        let inputPath = ProcessInfo.processInfo.environment["FENTON_SERVERUI_CATALOG_INPUT"]
        let publication: ServerUICompositionPublication
        let configuration: HouseConfig
        if let inputPath {
            let input = try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: URL(fileURLWithPath: inputPath)))
            publication = try ServerUIRendererFixture.publication(XCTUnwrap(input["publication"]))
            configuration = try HouseConfig.decode(JSONEncoder().encode(XCTUnwrap(input["configuration"])))
        } else {
            publication = try ServerUIRendererFixture.publication(ServerUIRendererFixture.json())
            configuration = DemoHouse.config
        }
        let directory = URL.temporaryDirectory.appendingPathComponent("catalog-providers-\(UUID())")
        defer {
            do { if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) } }
            catch { XCTFail("Catalog fixture cleanup failed: \(error)") }
        }
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
        let user = try XCTUnwrap(configuration.chores.people.first)
        let cache = HouseConfigCache(fileURL: directory.appendingPathComponent("house.json"))
        try cache.save(configuration, hash: "synthetic", server: server)
        let defaultsName = "catalog-location-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let push = PushCoordinator.inert()
        let location = LocationCoordinator(platform: GalleryLocationPlatform(.notDetermined), mobileApp: push.mobileApp,
                                           defaults: defaults)
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities.json")),
            houseConfigCache: cache, push: push, location: location,
            buildDefault: nil, launchArguments: [])
        defer { session.signOut() }
        try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
        _ = user
        guard case .signedIn(let connection, _) = session.phase else { return XCTFail("Missing catalog session") }
        let runtime = UKServerUIProductionRuntime(session: session, connection: connection,
                                                  privateRoot: directory, preferencesDefaults: defaults,
                                                  transport: SilentPublicationTransport())
        let providers = runtime.providers
        defer { runtime.endSession() }
        do { try providers.prepare(publication) }
        catch {
            XCTFail("Normal provider preflight rejected the catalog: \(error)")
            return
        }
        do {
            try await prepareCatalogWindows(publication, runtime: runtime, session: session, connection: connection,
                                            directory: directory, privateInput: inputPath != nil)
        } catch {
            XCTFail("Detached catalog preparation failed: \(error)")
            return
        }
        if let inputPath {
            let evidence: [String: Any] = ["result": "passed", "documentSHA256": publication.documentSha256,
                "pages": publication.document.pages.count, "modals": publication.document.modals.count,
                "sources": publication.document.dataSources.count, "network": "isolated-loopback",
                "scope": "normal-provider-preflight-and-three-window-plans", "verifiedAssets": publication.document.assets.count]
            try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
                .write(to: URL(fileURLWithPath: inputPath + ".result.json"), options: .atomic)
        }
    }

    private func prepareCatalogWindows(_ publication: ServerUICompositionPublication, runtime: UKServerUIProductionRuntime,
                                       session: AppSession, connection: HassConnection, directory: URL,
                                       privateInput: Bool) async throws {
        let assetDirectory = ProcessInfo.processInfo.environment["FENTON_SERVERUI_CATALOG_ASSETS"]
        let bytes = try Dictionary(uniqueKeysWithValues: publication.document.assets.map { asset in
            let data: Data
            if privateInput {
                let root = URL(fileURLWithPath: try XCTUnwrap(assetDirectory, "Private catalog needs its local asset directory."))
                data = try Data(contentsOf: root.appendingPathComponent((asset.source.path as NSString).lastPathComponent))
            } else {
                data = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGOQsIhIWLCBYUOBxYMDDQAiXgXRUMwx1wAAAABJRU5ErkJggg=="))
            }
            return (ServerUIAssetTransport.path(for: asset.sha256), data)
        })
        CatalogAssetProtocol.responses.withLock { $0 = bytes }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogAssetProtocol.self]
        let http = URLSession(configuration: configuration)
        defer { http.invalidateAndCancel(); CatalogAssetProtocol.responses.withLock { $0.removeAll() } }
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "https://publisher.invalid")))
        let partition = try ServerUIPublicationPartition(server: server)
        let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: partition.storageDirectory(in: directory),
            transport: ServerUIAssetTransport(server: server, tokenProvider: { "catalog-fixture" }, session: http))
        let assets = try await stager.stage(publication, documentDigest: publication.documentSha256)
        let photo: CGImage?
        let percent: Int
        switch publication.document.theme.background {
        case .solid: photo = nil; percent = 0
        case let .downloaded(id, _, blur, _, _, _):
            let file = try XCTUnwrap(assets.assets.first { $0.id == id }?.fileURL)
            photo = try XCTUnwrap(UIImage(contentsOfFile: file.path)?.cgImage)
            switch blur {
            case .fixed(let value): percent = value
            case .preference(_, let value): percent = value
            }
        }
        let prepared = UKServerUIProductionRuntime.Prepared(assets: assets, photo: photo, blurPercent: percent,
                                                            directory: directory.appendingPathComponent("renders"))
        defer { prepared.releasePlans() }
        let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)]
        let hosts = sizes.map { _ in
            UKServerUIProductionHost(runtime: runtime, session: session, connection: connection, environment: UKShellEnvironment())
        }
        let windows = zip(hosts, sizes).map { HostedPage.show($0.0, size: HostedPage.inScene($0.1)) }
        defer { windows.forEach { $0.isHidden = true } }
        for host in hosts { try await prepared.prepare(host: host) }
        try prepared.prepareRenderers(publication, hosts: hosts, generation: runtime.providers.generation)
        XCTAssertTrue(hosts.allSatisfy { $0.renderer == nil })
        let plans = try prepared.validatedPlans(hosts: hosts, generation: runtime.providers.generation)
        XCTAssertEqual(plans.count, sizes.count)
        for plan in plans { try plan.apply() }
        for host in hosts {
            let renderer = try XCTUnwrap(host.renderer)
            XCTAssertEqual(renderer.publication.documentSha256, publication.documentSha256)
            let root = try XCTUnwrap(renderer.stacks[renderer.navigation.snapshot.selection]?.viewControllers.first as? UKServerUIPage)
            XCTAssertFalse(root.nodes.isEmpty)
            try renderer.validateUpdate(publication)
        }
    }

    func testOldAccountCleanupDoesNotConsumeTheNextSessionsQueuedSystemRoute() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("account-route-hosted-\(UUID())")
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
            buildDefault: nil, launchArguments: [])
        defer {
            session.signOut()
            do {
                if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            } catch { XCTFail("Fixture cleanup failed: \(error)") }
        }
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
        try session.didSignIn(server: server,
            tokens: .init(accessToken: "first", expiresAt: .distantFuture, refreshToken: "first"))
        session.push.open(RouteRequest(path: "old"))
        session.signOut()
        XCTAssertNil(session.push.pendingRequest)
        try session.didSignIn(server: server,
            tokens: .init(accessToken: "second", expiresAt: .distantFuture, refreshToken: "second"))
        session.push.open(RouteRequest(path: "new"))
        let request = try XCTUnwrap(session.push.pendingRequest)
        await session.waitForSystemServices()
        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(session.push.pendingRequest, request)
    }
}

/// A publication transport that never answers: the socket is not there, and nothing may arrive during a first layout pass.
@MainActor
private final class SilentPublicationTransport: ServerUIPublicationTransport {
    private(set) var subscriptions = 0
    func subscribe(capabilities: [String], handler: @escaping @Sendable (Result<Data, any Error>) -> Void) -> @Sendable () -> Void {
        subscriptions += 1
        return {}
    }
}

/// Only this test URLSession sees the protocol; no request can reach the house or publisher.
private final class CatalogAssetProtocol: URLProtocol {
    static let responses = OSAllocatedUnfairLock(initialState: [String: Data]())
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "publisher.invalid", request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "Authorization") == "Bearer catalog-fixture",
              let data = Self.responses.withLock({ $0[url.path] }),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                  headerFields: ["Content-Type": data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg",
                                 "Content-Length": String(data.count)]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class SuspendedFeedbackFiler: FeedbackFiling {
    private let started: () -> Void
    private var response: CheckedContinuation<Bool, Never>?
    private(set) var calls = 0
    init(started: @escaping () -> Void) { self.started = started }
    func isAvailable() async throws -> Bool {
        calls += 1
        return await withCheckedContinuation {
            response = $0
            started()
        }
    }
    func complete() {
        response?.resume(returning: true)
        response = nil
    }
    func upload(_ attachment: FeedbackAttachment) async throws -> URL {
        XCTFail("Unexpected upload")
        throw CancellationError()
    }
    func submit(_ report: FeedbackReport) async throws -> FiledIssue {
        XCTFail("Unexpected submit")
        throw CancellationError()
    }
}
