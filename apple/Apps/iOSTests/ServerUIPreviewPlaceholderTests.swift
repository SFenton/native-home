import CryptoKit
import HassCore
import HassDemoHouse
import UIKit
import XCTest
@testable import HassUI

// MARK: - Preview stand-ins

/// The preview route must accept every document the live route accepts, drawing the surfaces' own unavailable states.
///
/// Placeholder ids only. The same assertions run at the iPhone, Duo and iPad widths.
@MainActor
final class ServerUIPreviewPlaceholderTests: XCTestCase {
    private static let checkItem = "input_boolean.preview_placeholder_check"
    private var directory: URL!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appendingPathComponent("ServerUIPreviewPlaceholderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixture

    /// The Home fixture (weather source and panel) with a camera source and tile, an away provider and one vacation check.
    private func json() throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let tests = apple.appendingPathComponent("Tests/HassCoreTests")
        var root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: tests.appendingPathComponent("ServerUIHomeFixture.json")))
        let camera = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: tests.appendingPathComponent("ServerUICameraFixture.json")))
        root = try ServerUIRendererFixture.changing(root, path: "/document/assets", to: .array([]))
        root = try ServerUIRendererFixture.changing(root, path: "/document/theme/background",
            to: .object(["type": "solid", "token": "shell-base@1"]))
        root = try ServerUIRendererFixture.changing(root, path: "/assetManifestSha256",
            to: .string(SHA256.hash(data: Data("[]".utf8)).map { String(format: "%02x", $0) }.joined()))
        let away: JSONValue = .object(["id": "fixture-away", "kind": "model", "model": "settings-provider@1",
            "inputs": .object(["providerId": "away", "domain": "away"])])
        let sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources",
            to: .array(sources + [try XCTUnwrap(camera["source"]), away]))
        guard case .object(var tileFields)? = camera["tile"] else { throw NSError(domain: "PlaceholderFixture", code: 1) }
        tileFields["action"] = .object(["type": "present", "modalId": "fixture-camera-viewer", "arguments": .object([:]), "ifPresented": "reject"])
        let tile: JSONValue = .object(tileFields)
        let modals = try XCTUnwrap(root["document"]?["modals"]?.array)
        guard case .object(var viewerModal)? = modals.first else { throw NSError(domain: "PlaceholderFixture", code: 2) }
        viewerModal["id"] = "fixture-camera-viewer"
        viewerModal["components"] = .array([try XCTUnwrap(camera["viewer"])])
        root = try ServerUIRendererFixture.changing(root, path: "/document/modals", to: .array(modals + [.object(viewerModal)]))
        let symbol: JSONValue = .object(["type": "sf-symbol", "name": "checkmark.circle", "rendering": "canonical", "unavailable": "reject"])
        let check: JSONValue = .object(["id": "fixture-vacation-check", "title": "Placeholder task", "type": "settings-control",
            "layout": .object(["span": .number(1)]), "icon": symbol,
            "props": .object(["sourceId": "fixture-away", "kind": "vacation-check", "item": .string(Self.checkItem), "subtitle": ""])])
        let components = try XCTUnwrap(root["document"]?["pages"]?.array?.first?["components"]?.array)
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(components + [tile, check]))
        let capabilities = try XCTUnwrap(root["capabilities"]?.array).compactMap(\.string)
            .filter { $0 != "sh.assets.publisher@1" }
            + ["sh.camera-stream@1", "sh.camera-tile@1", "sh.camera-video@1", "sh.camera-controls@1",
               "sh.camera-viewer@1", "sh.settings-controls@1"]
        return try ServerUIRendererFixture.changing(root, path: "/capabilities",
            to: .array(Set(capabilities).sorted().map(JSONValue.string)))
    }

    private func publication() throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(JSONEncoder().encode(json()))
    }

    // MARK: Logic

    func testHouseConfigGainsTheDocumentsChecklistItemsWithoutMutatingTheDemoHouse() throws {
        let document = try publication().document
        let before = DemoHouse.config.vacation.checklist
        let derived = UKServerUIPreviewPlaceholders.houseConfig(for: document, awayProviderId: "away")
        XCTAssertFalse(before.contains { $0.entityId == Self.checkItem })
        XCTAssertEqual(DemoHouse.config.vacation.checklist, before)
        XCTAssertEqual(Array(derived.vacation.checklist.prefix(before.count)), before)
        XCTAssertEqual(derived.vacation.checklist.last, .init(title: "Placeholder task", entityId: Self.checkItem))
        XCTAssertEqual(derived.vacation.checklist.count, before.count + 1)
        var rest = derived
        rest.vacation.checklist = before
        XCTAssertEqual(rest, DemoHouse.config, "Only the checklist differs.")
        XCTAssertEqual(UKServerUIPreviewPlaceholders.houseConfig(for: document, awayProviderId: "unrelated"), DemoHouse.config)
        XCTAssertEqual(UKServerUIPreviewPlaceholders.houseConfig(for: document, awayProviderId: "away", base: derived), derived,
                       "Items already present are not added twice.")
    }

    func testLiveValidatorStillRefusesCameraAndWeatherSourcesWithNoReader() throws {
        let publication = try publication()
        let context = UKContext(store: EntityStore())
        XCTAssertNil(context.connection)
        XCTAssertThrowsError(try UKServerUIRenderer(publication: publication, context: context,
                                                    backdrop: ServerUIRendererFixture.backdrop())) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .unavailableSource)
        }
        let weather = UKServerUIPreviewPlaceholders.weatherReader(for: publication.document)
        XCTAssertThrowsError(try UKServerUIRenderer(publication: publication, context: context,
            backdrop: ServerUIRendererFixture.backdrop(), weatherReader: weather)) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .unavailableSource,
                           "The camera source is still refused with no camera reader.")
        }
    }

    func testPlaceholderReadersApproveOnlyTheDocumentsSourcesAndStayOffline() async throws {
        let document = try publication().document
        let weather = UKServerUIPreviewPlaceholders.weatherReader(for: document)
        XCTAssertEqual(weather.entityIds, ["weather.demo_forecast"])
        XCTAssertFalse(weather.isConnected)
        do {
            _ = try await weather.forecast(entityId: "weather.demo_forecast", kind: .hourly)
            XCTFail("A placeholder never answers a forecast")
        } catch { XCTAssertEqual(error as? ServerUIWeatherReader.Failure, .unapprovedEntity) }
        let cameras = UKServerUIPreviewPlaceholders.cameraReader(for: document)
        XCTAssertTrue(cameras.isOffline)
        XCTAssertNil(cameras.snapshotURL("camera.demo_still"))
        guard case .camera(_, let descriptor) = document.dataSources.first(where: {
            if case .camera = $0 { true } else { false }
        }) else { return XCTFail("Camera source") }
        XCTAssertTrue(cameras.accepts(descriptor))
    }

    // MARK: Hosted UX and accessibility

    func testPlaceholderStatesDrawAtIPhoneDuoAndIPadWidths() async throws {
        let source = HouseConfigSource.active
        let original = source.current
        GalleryHouse.install(into: source)
        defer { source.set(original) }
        let publication = try publication()
        let partition = try ServerUIPublicationPartition(server: HassServer(baseURL: URL(string: "https://preview.invalid")!))
        let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: partition.storageDirectory(in: directory),
            transport: ServerUIAssetTransport(server: HassServer(baseURL: URL(string: "https://preview.invalid")!),
                                              tokenProvider: { throw URLError(.notConnectedToInternet) }))
        let assets = try await stager.stage(publication, documentDigest: publication.documentSha256)
        let viewer = try XCTUnwrap(DemoHouse.config.chores.people.first)
        for (family, size) in [("iPhone", CGSize(width: 390, height: 844)), ("Duo", CGSize(width: 466, height: 678)),
                               ("iPad", CGSize(width: 820, height: 1180))] {
            let store = EntityStore()
            store.replaceAll([
                EntityState(entityId: "weather.demo_forecast", state: "rainy",
                            attributes: ["temperature": .number(18), "temperature_unit": .string("°C")]),
            ])
            let fixtures = try UKServerUIPreviewFixtures(configuration: .init(viewerUserID: viewer.haUserId, administrator: false), store: store)
            let prepared = try UKServerUIPreview.Prepared(publication: publication, context: fixtures.context, assets: assets,
                backdrop: ServerUIRendererFixture.backdrop(), renderDirectory: directory,
                weatherReader: UKServerUIPreviewPlaceholders.weatherReader(for: publication.document),
                cameraReader: UKServerUIPreviewPlaceholders.cameraReader(for: publication.document), fixtures: fixtures)
            let renderer = prepared.renderer
            let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            HostedPage.layoutTracked()
            let page = try XCTUnwrap(renderer.stacks[.initial]?.viewControllers.first as? UKServerUIPage, family)
            XCTAssertNil(fixtures.context.connection, family)

            let camera = try XCTUnwrap(page.nodes["demo-camera-tile"]?.view, family)
            let source = try XCTUnwrap(renderer.bindings.cameras["demo-camera-source"], family)
            XCTAssertEqual(source.status, "Camera unavailable", family)
            XCTAssertFalse(source.isAvailable, family)
            XCTAssertTrue(HostedPage.labels(in: camera).contains("Camera unavailable"), "\(family): \(HostedPage.labels(in: camera))")
            XCTAssertTrue(camera.accessibilityElementsHidden == false && (camera.isAccessibilityElement
                          || !HostedPage.labels(in: camera).isEmpty), family)
            XCTAssertThrowsError(try source.perform(.snapshot), family)

            let weather = try XCTUnwrap(renderer.bindings.weather["fixture-weather"], family)
            XCTAssertTrue(weather.offline, family)
            XCTAssertNotNil(page.nodes["fixture-summary"]?.view, family)

            let row = try XCTUnwrap(page.nodes["fixture-vacation-check"]?.view, family)
            let check = try XCTUnwrap(HostedPage.descendants(of: row).compactMap { $0 as? UKVacationChecklistRow }.first
                                      ?? row as? UKVacationChecklistRow, family)
            let toggle = try XCTUnwrap(check.accessibilityElements?.first as? UIView, family)
            XCTAssertEqual(toggle.accessibilityLabel, "Placeholder task", family)
            XCTAssertEqual(toggle.accessibilityValue, "Unavailable", family)
            XCTAssertTrue(toggle.accessibilityTraits.contains(.notEnabled), family)
            XCTAssertTrue(check.bounds.width > 0 && check.bounds.width <= size.width, family)
        }
    }
}
