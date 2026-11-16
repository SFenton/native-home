import CryptoKit
import HassCore
import HassDemoHouse
import UIKit
import XCTest
@testable import HassUI

// MARK: - Isolated live preview

@MainActor
final class ServerUIPreviewTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appendingPathComponent("ServerUIPreviewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testPreviewDoesNotReadOrReplaceTheNormalSavedAccount() {
        let tokens = PreviewTokenStore()
        let session = AppSession(tokenStore: tokens, launchArguments: ["app", "--server-ui-preview"])
        XCTAssertFalse(session.isSignedIn)
        XCTAssertNil(session.tokens)
        XCTAssertNil(session.houseConfig)
        XCTAssertEqual(tokens.accesses, 0)
    }

    func testGalleryFixtureDoesNotReadOrReplaceTheNormalSavedAccount() {
        let tokens = PreviewTokenStore()
        let session = AppSession(tokenStore: tokens, launchArguments: ["app", "--gallery-fixture"])
        XCTAssertFalse(session.isSignedIn)
        XCTAssertNil(session.tokens)
        XCTAssertNil(session.houseConfig)
        XCTAssertEqual(tokens.accesses, 0)
    }

    func testGalleryFixturePinsGeneratedWeatherData() throws {
        let saved = ProcessInfo.processInfo.environment.filter {
            $0.key.hasPrefix("FENTON_GALLERY") || $0.key == "FENTON_BACKDROP_FIXTURE"
        }
        let wasPaused = UKDesign.animationsPaused
        defer {
            for key in ProcessInfo.processInfo.environment.keys
                where key.hasPrefix("FENTON_GALLERY") || key == "FENTON_BACKDROP_FIXTURE" {
                XCTAssertEqual(unsetenv(key), 0)
            }
            for (key, value) in saved { XCTAssertEqual(setenv(key, value, 1), 0) }
            GalleryFixtureClock.shared.setReferenceDate(nil)
            UKDesign.animationsPaused = wasPaused
        }
        let date = Date(timeIntervalSince1970: 1_794_615_600)
        let configuration = GalleryFixtureLaunch.Configuration(id: "weather-pinned",
            variables: ["FENTON_GALLERY": "weather"], referenceTime: date.timeIntervalSince1970)
        try JSONEncoder().encode(configuration).write(to: directory.appendingPathComponent("bootstrap.json"))
        try GalleryFixtureLaunch.prepare(at: directory)
        XCTAssertEqual(WeatherFixtures.states(condition: "rainy", night: false, airQuality: true).map(\.attributes),
                       WeatherFixtures.states(condition: "rainy", night: false, airQuality: true, now: date).map(\.attributes))
        XCTAssertEqual(WeatherFixtures.hourly(), WeatherFixtures.hourly(now: date))
        XCTAssertEqual(WeatherFixtures.daily(), WeatherFixtures.daily(now: date))
    }

    func testBootstrapRejectsMixedStateAndUntrustedLiveOrigins() throws {
        let base: [String: Any] = [:]
        func decode(_ additions: [String: Any]) throws -> UKServerUIPreview.Configuration {
            try JSONDecoder().decode(UKServerUIPreview.Configuration.self,
                from: JSONSerialization.data(withJSONObject: base.merging(additions) { $1 }))
        }
        try decode(["entities": [:]]).validate()
        let gallery: [String: Any] = ["viewerUserID": "demo", "administrator": false]
        try decode(["entities": [:], "gallery": gallery]).validate()
        try decode(["live": ["server": "https://home.example.com", "accountID": "demo"]]).validate()
        XCTAssertThrowsError(try decode(["live": ["server": "https://home.example.com", "accountID": "demo"], "gallery": gallery]).validate())
        XCTAssertThrowsError(try decode([:]).validate())
        XCTAssertThrowsError(try decode(["entities": [:], "live": ["server": "https://home.example.com", "accountID": "demo"]]).validate())
        for server in ["http://home.example.com", "https://person:secret@home.example.com",
                       "https://home.example.com/api", "https://home.example.com?token=demo", "https://home.example.com#section"] {
            XCTAssertThrowsError(try decode(["live": ["server": server, "accountID": "demo"]]).validate())
        }
    }

    func testGalleryPreviewMountsCanonicalProvidersAndSavesOnlyItsFixtureAcrossFamilies() async throws {
        let source = HouseConfigSource.active
        let original = source.current
        GalleryHouse.install(into: source)
        defer { source.set(original); HostedPage.hideTracked(); HostedPage.resetGlobals() }
        let publication = try galleryPublication()
        let partition = try ServerUIPublicationPartition(server: HassServer(baseURL: URL(string: "https://preview.invalid")!))
        let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: partition.storageDirectory(in: directory),
            transport: ServerUIAssetTransport(server: HassServer(baseURL: URL(string: "https://preview.invalid")!),
                                              tokenProvider: { throw URLError(.notConnectedToInternet) }))
        let assets = try await stager.stage(publication, documentDigest: publication.documentSha256)
        let viewer = try XCTUnwrap(DemoHouse.config.chores.people.first)
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            let store = EntityStore()
            store.replaceAll([
                EntityState(entityId: "person.demo_alex", state: "home", attributes: ["friendly_name": .string("Alex Demo")]),
                EntityState(entityId: "person.demo_sam", state: "not_home", attributes: ["friendly_name": .string("Sam Demo")]),
                EntityState(entityId: "person.demo_guest", state: "home", attributes: ["friendly_name": .string("Guest")]),
            ])
            let fixtures = try UKServerUIPreviewFixtures(configuration: .init(viewerUserID: viewer.haUserId, administrator: true), store: store)
            let prepared = try UKServerUIPreview.Prepared(publication: publication, context: fixtures.context, assets: assets,
                backdrop: ServerUIRendererFixture.backdrop(), renderDirectory: directory, fixtures: fixtures)
            let renderer = prepared.renderer
            let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            XCTAssertEqual(Set(fixtures.settings.keys),
                           Set(["household", "away", "profile", "preferences", "performance", "feedback-bug", "feedback-feature"]))
            XCTAssertNil(fixtures.context.connection)
            XCTAssertNil(fixtures.context.session)
            let page = try ServerUIRendererFixture.root(renderer)
            let collection = try XCTUnwrap(renderer.recordCollection("records-groceries"))
            try await collection.load()
            XCTAssertFalse(collection.records.isEmpty, collection.error ?? "The fixture returned no grocery records.")
            let collectionView = try XCTUnwrap(page.nodes["fixture-groceries"]?.view as? UKServerUICollectionView)
            await Task.yield()
            let rendered = await HostedPage.settle { !collectionView.rows.isEmpty }
            XCTAssertTrue(rendered, "Loaded \(collection.records.count) records; rendered \(collectionView.rows.count); error: \(collection.error ?? "none")")
            XCTAssertTrue(HostedPage.descendants(of: page.view).contains {
                $0.accessibilityIdentifier == "fixture-groceries"
            })
            let form = try await XCTUnwrap(fixtures.records.forms["records-groceries-add"]).open()
            let group = try XCTUnwrap(form.groups.first { $0.fields.contains { $0.key == "name" } })
            try form.set(.string("Fixture-only addition"), group: group.id, field: "name")
            let person = try XCTUnwrap(store.value(viewer.personEntityId))
            store.apply([.init(entityId: person.entityId, state: "away", attributes: person.attributes)])
            try await form.save()
            try await collection.load()
            XCTAssertTrue(collection.records.contains {
                if case .todo(let item, _) = $0 { item.summary == "Fixture-only addition" } else { false }
            })
            XCTAssertEqual(store.value(person.entityId)?.state, "away", "A todo echo must preserve newer unrelated entity values.")
            XCTAssertTrue(fixtures.feedback.submittedReports.isEmpty)
            fixtures.recordService.isCurrent = false
            do {
                try await fixtures.caller.callService("input_boolean", "turn_on", data: ["entity_id": "input_boolean.demo_unit"])
                XCTFail("An ended fixture retained device command authority")
            } catch { XCTAssertTrue(error is CancellationError) }
            do {
                _ = try await fixtures.records.forms["records-groceries-add"]?.open()
                XCTFail("An ended fixture opened another draft")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
    }

    func testGalleryRejectsUnknownIdentityAndUnsupportedRecordServices() async throws {
        let source = HouseConfigSource.active
        let original = source.current
        GalleryHouse.install(into: source)
        defer { source.set(original) }
        XCTAssertThrowsError(try UKServerUIPreviewFixtures(configuration: .init(viewerUserID: "not-a-demo-user", administrator: true),
                                                         store: EntityStore()))
        let records = UKServerUIPreviewFixtureRecords(store: EntityStore())
        do {
            _ = try await records.callServiceForResponse("script", "demo_unknown", data: [:])
            XCTFail("An unsupported service was reported as successful")
        } catch { XCTAssertEqual(error as? UKServerUIPreviewFixtureRecords.Failure, .unsupportedService) }
        do {
            try await records.callService("todo", "add_item", data: ["entity_id": "todo.demo_unknown", "item": "Not added"])
            XCTFail("An unauthored list was created")
        } catch { XCTAssertEqual(error as? UKServerUIPreviewFixtureRecords.Failure, .unsupportedService) }
    }

    func testGallerySeedsOnlyAnExplicitCanonicalBedroomScenario() throws {
        let source = HouseConfigSource.active, original = source.current
        GalleryHouse.install(into: source)
        GalleryFixtureClock.shared.setReferenceDate(Date(timeIntervalSince1970: 1_794_615_600))
        defer { source.set(original); GalleryFixtureClock.shared.setReferenceDate(nil) }
        let viewer = try XCTUnwrap(DemoHouse.config.chores.people.first)
        for scenario in [BedroomFixtures.Scenario.default, .ringing] {
            let store = EntityStore()
            store.apply([.init(entityId: "sensor.demo_unrelated", state: "retained")])
            _ = try UKServerUIPreviewFixtures(configuration: .init(viewerUserID: viewer.haUserId,
                administrator: true, bedroomScenario: scenario.rawValue), store: store)
            for state in BedroomFixtures.states(scenario) {
                XCTAssertEqual(store.value(state.entityId)?.state, state.state)
                XCTAssertEqual(store.value(state.entityId)?.attributes, state.attributes)
            }
            XCTAssertEqual(store.value("sensor.demo_unrelated")?.state, "retained")
        }
        let store = EntityStore()
        XCTAssertThrowsError(try UKServerUIPreviewFixtures(configuration: .init(viewerUserID: viewer.haUserId,
            administrator: true, bedroomScenario: "misspelled"), store: store))
        XCTAssertTrue(store.allValues.isEmpty, "Rejected scenarios must not replace the caller's entity inputs.")
        _ = try UKServerUIPreviewFixtures(configuration: .init(viewerUserID: viewer.haUserId, administrator: true), store: store)
        XCTAssertNil(store.value(MasterBedroom.scheduleEntityId), "Omission must not silently select a bedroom scenario.")
    }

    private func galleryPublication() throws -> ServerUICompositionPublication {
        var json = try ServerUIRendererFixture.json()
        json = try ServerUIRendererFixture.changing(json, path: "/document/assets", to: .array([]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/theme/background",
            to: .object(["type": "solid", "token": "shell-base@1"]))
        json = try ServerUIRendererFixture.changing(json, path: "/assetManifestSha256",
            to: .string(SHA256.hash(data: Data("[]".utf8)).map { String(format: "%02x", $0) }.joined()))
        let ids = ["household", "away", "profile", "preferences", "performance", "feedback-bug", "feedback-feature"]
        let sources: [JSONValue] = ids.map { id in
            .object(["id": .string("fixture-" + id), "kind": "model", "model": "settings-provider@1",
                     "inputs": .object(["providerId": .string(id), "domain": .string(id.hasPrefix("feedback") ? "feedback" : id)])])
        }
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources",
            to: .array(try XCTUnwrap(json["document"]?["dataSources"]?.array) + sources))
        let collection: JSONValue = .object(["id": "fixture-groceries", "type": "collection", "title": "Groceries",
            "layout": .object(["span": .number(1)]), "props": .object(["providerId": "records-groceries", "template": "todo",
                "loadingText": "Loading", "emptyText": "No groceries"])])
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components",
            to: .array(try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array) + [collection]))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.assets.publisher@1" }
            + ["sh.collection@1", "sh.settings-controls@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        json = try ServerUITodoPublicationFixture.adding(DemoHouse.config.chores.pages.filter { $0.id == "groceries" }, to: json)
        return try ServerUIRendererFixture.publication(json)
    }

    // MARK: Environment credential

    private static let secret = "env-only-secret-token-9f3a"

    func testEnvironmentTokenIsUsedAndRemovedFromTheProcessEnvironment() throws {
        let name = "FENTON_TEST_\(UUID().uuidString.prefix(8))"
        setenv(name, Self.secret, 1)
        defer { unsetenv(name) }
        let token = try UKServerUIPreview.liveCredential(environmentName: name)
        XCTAssertEqual(token, Self.secret)
        XCTAssertNil(getenv(name), "The bearer must not stay visible to child processes or later reads")
        XCTAssertNil(try UKServerUIPreview.consumeEnvironmentCredential(named: name), "A second read finds nothing")
        XCTAssertEqual(UKServerUIPreview.environmentCredentialName, "FENTON_PREVIEW_HA_TOKEN")
    }

    func testAStrayCredentialFileInThePreviewFolderIsIgnoredAndNeverRead() throws {
        let name = "FENTON_TEST_\(UUID().uuidString.prefix(8))"
        let file = directory.appendingPathComponent("ha-credential")
        try Data("file-token".utf8).write(to: file)
        XCTAssertThrowsError(try UKServerUIPreview.liveCredential(environmentName: name)) { error in
            XCTAssertEqual(error as? UKServerUIPreviewLiveData.Failure, .credential)
        }
        XCTAssertEqual(try Data(contentsOf: file), Data("file-token".utf8), "The file is neither read nor deleted")
        setenv(name, Self.secret, 1)
        defer { unsetenv(name) }
        XCTAssertEqual(try UKServerUIPreview.liveCredential(environmentName: name), Self.secret)
    }

    func testMalformedEnvironmentTokenIsRemovedAndFailsWithTheCredentialErrorWithoutEchoingIt() {
        for bad in ["", "two tokens"] {
            let name = "FENTON_TEST_\(UUID().uuidString.prefix(8))"
            setenv(name, bad, 1)
            defer { unsetenv(name) }
            XCTAssertThrowsError(try UKServerUIPreview.consumeEnvironmentCredential(named: name)) { error in
                XCTAssertEqual(error as? UKServerUIPreviewLiveData.Failure, .credential)
                XCTAssertFalse("\(error)".contains("tokens"))
            }
            XCTAssertNil(getenv(name))
        }
    }

    func testMissingTokenFailsWithTheBootstrapCredentialErrorNotACrash() {
        let name = "FENTON_TEST_\(UUID().uuidString.prefix(8))"
        XCTAssertNil(getenv(name))
        XCTAssertThrowsError(try UKServerUIPreview.liveCredential(
            environmentName: name)) { error in
            XCTAssertEqual(error as? UKServerUIPreviewLiveData.Failure, .credential)
            XCTAssertEqual((error as? UKServerUIPreviewLiveData.Failure)?.errorDescription?.contains("FENTON_PREVIEW_HA_TOKEN"), true)
        }
    }

    func testTheTokenNeverAppearsInAnyStringTheLiveTypeProduces() async throws {
        let live = try UKServerUIPreviewLiveData(configuration: .init(server: "https://home.example.com", accountID: "demo"),
                                               credential: Self.secret, directory: directory, store: EntityStore())
        var strings = ["\(live)", String(reflecting: live), "\(live.receipt)", "\(live.caller)", String(reflecting: live.caller),
                       "\(live.connection)", "\(live.lifecycle)", "\(live.context)"]
        for failure in [UKServerUIPreviewLiveData.Failure.configuration, .credential, .commandsDisabled] {
            strings += ["\(failure)", failure.localizedDescription, failure.errorDescription ?? ""]
        }
        do { try await live.caller.callService("light", "turn_on", data: [:]) }
        catch { strings += ["\(error)", error.localizedDescription] }
        do { _ = try await live.caller.callServiceWithResponse("script", "run", data: [:]) }
        catch { strings += ["\(error)", error.localizedDescription] }
        strings += ["\(live.receipt)"]
        for value in strings { XCTAssertFalse(value.contains(Self.secret), "Token leaked into: \(value.prefix(80))") }
    }

    func testLiveModeStillRejectsEveryServiceCallWhenBuiltFromTheEnvironmentToken() async throws {
        let name = "FENTON_TEST_\(UUID().uuidString.prefix(8))"
        setenv(name, Self.secret, 1)
        defer { unsetenv(name) }
        let token = try UKServerUIPreview.liveCredential(environmentName: name)
        let live = try UKServerUIPreviewLiveData(configuration: .init(server: "https://home.example.com", accountID: "demo"),
                                               credential: token, directory: directory, store: EntityStore())
        for index in 1...3 {
            do {
                if index == 2 { _ = try await live.caller.callServiceWithResponse("script", "run", data: [:]) }
                else { try await live.caller.callService("light", "turn_on", data: ["entity_id": "light.x"]) }
                XCTFail("A live service call was accepted")
            } catch { XCTAssertEqual(error as? UKServerUIPreviewLiveData.Failure, .commandsDisabled) }
            XCTAssertEqual(live.caller.blockedCommands, index)
        }
        XCTAssertEqual(live.connection.status, .disconnected)
    }

    func testLiveContextUsesConnectionBoxesAndKeepsValuesDuringDisconnect() throws {
        let store = EntityStore()
        let live = try UKServerUIPreviewLiveData(configuration: .init(server: "https://home.example.com", accountID: "demo"),
                                               credential: "test-only-token", directory: directory, store: store)
        let context = live.context
        XCTAssertTrue(context.store === live.connection.store)
        XCTAssertNil(context.connection, "Configured actions cannot reach the raw connection")
        XCTAssertNil(context.session)
        XCTAssertTrue(context.valuesPending)
        let sources = try ServerUIRendererFixture.publication(ServerUIRendererFixture.liveJSON()).document.dataSources
        let bindings = UKServerUIBindings(sources: sources, context: context)
        let box = store.entity("alarm_control_panel.demo_panel")
        store.replaceAll([EntityState(entityId: box.id, state: "armed_home")])
        XCTAssertFalse(context.valuesPending)
        XCTAssertEqual(bindings.alarms["source-panel"]?.projection.state, "armed_home")
        live.lifecycle.stop()
        XCTAssertTrue(store.entity(box.id) === box)
        XCTAssertEqual(bindings.alarms["source-panel"]?.projection.state, "armed_home")
        store.apply([EntityState(entityId: box.id, state: "disarmed")])
        XCTAssertEqual(bindings.alarms["source-panel"]?.projection.state, "disarmed")
    }

    func testReadOnlyCallerFailsWithoutChangingLiveStateOrReportingSuccess() async throws {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "alarm_control_panel.demo_panel", state: "disarmed")])
        let live = try UKServerUIPreviewLiveData(configuration: .init(server: "https://home.example.com", accountID: "demo"),
                                               credential: "test-only-token", directory: directory, store: store)
        let publication = try ServerUIRendererFixture.publication(ServerUIRendererFixture.liveJSON())
        let bindings = UKServerUIBindings(sources: publication.document.dataSources, context: live.context)
        let alarm = try XCTUnwrap(bindings.alarms["source-panel"])
        XCTAssertEqual(alarm.projection.spec.phase, .ready, "Read-only design keeps production control geometry")
        let ticket = try alarm.reserve()
        try alarm.execute(ticket)
        await alarm.completion?.value
        XCTAssertEqual(live.caller.blockedCommands, 1)
        XCTAssertTrue(alarm.projection.failed)
        XCTAssertEqual(store.value("alarm_control_panel.demo_panel")?.state, "disarmed")
        do {
            _ = try await live.caller.callServiceWithResponse("script", "demo_run", data: [:])
            XCTFail("The response-bearing command path accepted a live mutation")
        } catch { XCTAssertTrue(error is UKServerUIPreviewLiveData.Failure) }
        XCTAssertEqual(live.caller.blockedCommands, 2)
        XCTAssertEqual(live.connection.status, .disconnected, "The command path cannot open a socket")
    }

    func testScopedLiveReadersDoNotExposeConnectionOrAcceptAnUnauthoredForecast() async throws {
        let live = try UKServerUIPreviewLiveData(configuration: .init(server: "https://home.example.com", accountID: "demo"),
                                               credential: "test-only-token", directory: directory, store: EntityStore())
        let publication = try ServerUIRendererFixture.publication()
        let weather = live.weatherReader(for: publication.document)
        XCTAssertFalse(weather.isConnected)
        do {
            _ = try await weather.forecast(entityId: "weather.demo_not_in_publication", kind: .hourly)
            XCTFail("An unauthored forecast reached the connection")
        } catch { XCTAssertEqual(error as? ServerUIWeatherReader.Failure, .unapprovedEntity) }
        let cameras = live.cameraReader(for: publication.document, pool: CameraStreamPool(modes: [], observesApp: false))
        XCTAssertNil(cameras.snapshotURL("camera.demo_not_in_publication"))
        XCTAssertNil(live.context.connection)
        XCTAssertNil(live.context.session)
        XCTAssertEqual(live.caller.blockedCommands, 0)
        XCTAssertEqual(live.connection.status, .disconnected)
    }

    func testMissingScopedReaderCannotReplaceThePreparedRendererOrDurableLastGood() async throws {
        var firstJSON = try ServerUIRendererFixture.json()
        firstJSON = try ServerUIRendererFixture.changing(firstJSON, path: "/document/assets", to: .array([]))
        firstJSON = try ServerUIRendererFixture.changing(firstJSON, path: "/document/theme/background",
            to: .object(["type": "solid", "token": "shell-base@1"]))
        firstJSON = try ServerUIRendererFixture.changing(firstJSON, path: "/assetManifestSha256",
            to: .string(SHA256.hash(data: Data("[]".utf8)).map { String(format: "%02x", $0) }.joined()))
        firstJSON = try ServerUIRendererFixture.changing(firstJSON, path: "/capabilities", to: .array(
            ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.assets.publisher@1" }.map(JSONValue.string)))
        let first = try ServerUIRendererFixture.publication(firstJSON)
        var json = firstJSON
        var sources = try XCTUnwrap(json["document"]?["dataSources"]?.array)
        sources.append(.object([
            "id": "unprovided-weather", "kind": "model", "model": "home-weather@1",
            "inputs": .object([
                "weatherEntityId": .object(["type": "literal", "value": "weather.demo_unit"]),
                "sunEntityId": .object(["type": "literal", "value": "sun.sun"]),
                "airQualityEntityId": .object(["type": "literal", "value": "sensor.demo_aqi"]),
                "units": "source@1",
            ]),
        ]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources", to: .array(sources))
        json = try ServerUIRendererFixture.changing(json, path: "/revision", to: .number(Double(first.revision + 1)))
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(
            (first.capabilities + ["sh.home-weather@1"]).sorted().map(JSONValue.string)))
        let second = try ServerUIRendererFixture.publication(json)
        XCTAssertNoThrow(try UKServerUIRenderer.preflight(second), "Static support is not scoped-provider readiness.")
        let events = [try UKServerUIPreview.publishedEvent(envelope: JSONEncoder().encode(firstJSON)),
                      try UKServerUIPreview.publishedEvent(envelope: JSONEncoder().encode(json))]
        let server = HassServer(baseURL: URL(string: "https://preview.invalid")!)
        let partition = try ServerUIPublicationPartition(server: server)
        let root = partition.storageDirectory(in: directory)
        let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: root,
            transport: ServerUIAssetTransport(server: server, tokenProvider: { throw URLError(.notConnectedToInternet) }))
        let backdrop = try ServerUIRendererFixture.backdrop()
        let entities = EntityStore()
        let store = ServerUIPublicationStore<UKServerUIPreview.Prepared>(
            partition: partition, cacheDirectory: root,
            prepare: { publication, context in
                let assets = try await stager.stage(publication, documentDigest: publication.documentSha256,
                                                    reservingBytes: context.cacheWriteBytes)
                do {
                    return try await MainActor.run {
                        try UKServerUIPreview.Prepared(publication: publication, context: UKContext(store: entities),
                            assets: assets, backdrop: backdrop, renderDirectory: root)
                    }
                } catch {
                    let protected = await MainActor.run { context.protected.map(\.assets) }
                    try await stager.discard(assets, retaining: protected)
                    throw error
                }
            }, discard: { candidate, protected in
                let assets = await MainActor.run { (candidate.assets, protected.map(\.assets)) }
                try await stager.discard(assets.0, retaining: assets.1)
            })
        await store.bind(userID: "preview")
        await store.apply(events[0])
        XCTAssertEqual(store.status, .ready)
        let renderer = try XCTUnwrap(store.prepared?.renderer)
        let cache = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("ServerUIPublications"), includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "json" })
        let saved = try Data(contentsOf: cache)
        await store.apply(events[1])
        XCTAssertEqual(store.status, .failure(.acceptanceRejected))
        XCTAssertEqual(store.current, first)
        XCTAssertTrue(store.prepared?.renderer === renderer)
        XCTAssertEqual(try Data(contentsOf: cache), saved)
        await store.reset()
    }
}

// MARK: - Saved-account access sentinel

private final class PreviewTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var accesses: Int { lock.withLock { count } }

    func load() -> StoredCredentials? {
        lock.withLock { count += 1 }
        return StoredCredentials(server: HassServer(baseURL: URL(string: "http://127.0.0.1:1")!), refreshToken: "test-only")
    }
    func save(_ credentials: StoredCredentials) throws { lock.withLock { count += 1 } }
    func clear() { lock.withLock { count += 1 } }
}
