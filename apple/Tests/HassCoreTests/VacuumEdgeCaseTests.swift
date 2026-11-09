import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTestSupport
import Testing

/// `get_services` over the mock connection: names flatten to `domain.service`; other shapes and errors throw.
@MainActor
struct HassServiceCatalogTests {
    private func makeConnection() -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "services-\(UUID()).json"))
        return (HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock), mock)
    }

    private func pendingRequest(_ mock: HAMockConnection) async throws -> HAMockConnection.PendingRequest {
        for _ in 0..<1_000 where mock.pendingRequests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return try #require(mock.pendingRequests.first)
    }

    @Test func flattensTheServiceTree() async throws {
        let (connection, mock) = makeConnection()
        async let names = connection.serviceNames()
        let request = try await pendingRequest(mock)
        #expect(request.request.type == .webSocket("get_services"))
        request.completion(.success(HAData(value: [
            "vacuum": ["start": [String: Any](), "locate": [String: Any]()],
            "script": ["demo_main_floor_2": [String: Any]()],
            "broken": "not a dictionary",
        ])))
        #expect(try await names == ["vacuum.start", "vacuum.locate", "script.demo_main_floor_2"])
    }

    @Test func rejectsANonDictionaryResult() async throws {
        let (connection, mock) = makeConnection()
        let names = Task { try await connection.serviceNames() }
        let request = try await pendingRequest(mock)
        request.completion(.success(HAData(value: [1, 2])))
        await #expect(throws: HassConnection.UnexpectedResponse(command: "get_services")) { try await names.value }
    }

    @Test func passesTheServerErrorThrough() async throws {
        let (connection, mock) = makeConnection()
        let names = Task { try await connection.serviceNames() }
        let request = try await pendingRequest(mock)
        request.completion(.failure(.internal(debugDescription: "offline")))
        await #expect(throws: HAError.self) { try await names.value }
    }
}

/// Live polling and the production fetch (served by a stub `URLProtocol`, never the network).
@MainActor
@Suite(.serialized, .demoHouse)
struct ValetudoMapLoaderPollingTests {
    @Test func livePollingReloadsUntilCancelled() async throws {
        let png = try valetudoPNG(sampleMapJSON)
        let counter = FailSwitch()
        let loader = ValetudoMapLoader { _ in await counter.count(); return png }
        let task = Task { await loader.run(url: URL(string: "https://example.invalid/map")!, live: true) }
        for _ in 0..<200 where await counter.calls < 2 { try await Task.sleep(for: .milliseconds(50)) }
        task.cancel()
        await task.value
        #expect(await counter.calls >= 2, "a second load follows the \(ValetudoMapLoader.pollInterval) poll")
        #expect(loader.provenance == .live)
    }

    @Test func urlSessionFetchAcceptsOnlyHTTP200() async throws {
        URLProtocol.registerClass(StubMapProtocol.self)
        defer { URLProtocol.unregisterClass(StubMapProtocol.self) }
        let data = try await ValetudoMapLoader.urlSessionFetch(URL(string: "fentonstub://ok/map.png")!)
        #expect(data == Data("map".utf8))
        await #expect(throws: URLError.self) {
            _ = try await ValetudoMapLoader.urlSessionFetch(URL(string: "fentonstub://missing/map.png")!)
        }
    }
}

/// Answers `fentonstub://ok` with 200 and anything else with 404.
final class StubMapProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "fentonstub" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let status = url.host == "ok" ? 200 : 404
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("map".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Focus edge cases the main suite leaves out.
struct ValetudoMapFocusEdgeTests {
    @Test func missingPolicyValuesUseTheWebDefaults() {
        var defaults = focusPolicy
        defaults.paddingCm = nil
        defaults.wallAssociationCm = nil
        let explicit = ValetudoMapFocus.resolve(focusedFixture(), policy: focusPolicy)
        let defaulted = ValetudoMapFocus.resolve(focusedFixture(), policy: defaults)
        #expect(defaulted.mode == .focused)
        #expect(defaulted.viewBounds == explicit.viewBounds, "15 cm padding and 20 cm walls are the defaults")
        #expect(defaulted.renderWallCells == explicit.renderWallCells)

        var thresholds = focusPolicy
        thresholds.minimumExcludedAreaM2 = nil
        thresholds.minimumExcludedFraction = nil
        #expect(ValetudoMapFocus.resolve(focusedFixture(), policy: thresholds).reason == .insufficientBenefit,
                "the phantom segment is under the 4 m² default")
    }

    @Test func anActiveZoneEnclosingAnExcludedRoomFallsBack() {
        // Edges stay clear of every segment cell; only the enclosed phantom segment (pixels 0–10 × 15–35) is inside.
        var zone = focusedFixture()
        zone.entities.append(.init(type: "active_zone", points: [-50, 20, 90, 20, 90, 250, -50, 250]))
        #expect(ValetudoMapFocus.resolve(zone, policy: focusPolicy).reason == .activeRouteExcluded)

        var clear = focusedFixture()
        clear.entities.append(.init(type: "active_zone", points: [400, 400, 450, 400, 450, 450, 400, 450]))
        #expect(ValetudoMapFocus.resolve(clear, policy: focusPolicy).mode == .focused, "a zone away from excluded rooms is fine")

        var line = focusedFixture()
        line.entities.append(.init(type: "active_zone", points: [-50, 20, 90, 20]))
        #expect(ValetudoMapFocus.resolve(line, policy: focusPolicy).mode == .focused, "fewer than three corners is no area")
    }

    @Test func multiSegmentRoutesAreCheckedEdgeByEdge() {
        var route = focusedFixture()
        route.entities.append(.init(type: "path", points: [125, 125, 130, 125, 130, 130, 25, 130]))
        #expect(ValetudoMapFocus.resolve(route, policy: focusPolicy).reason == .activeRouteExcluded)
    }
}

/// Small lookups and equality the views rely on.
@Suite(.demoHouse)
struct VacuumLookupTests {
    @Test func findsAVacuumByEntityId() {
        #expect(Vacuums.config(entityId: Vacuums.mainFloor.entityId)?.title == "Main Floor")
        #expect(Vacuums.config(entityId: "vacuum.demo_nope") == nil)
        #expect(Vacuums.all.map(\.title) == ["Main Floor", "Studio", "Media room"], "Auto-Clean order")
    }

    @Test func selectableRoomsCompareEveryField() throws {
        let rooms = ValetudoMapFixtures.map(Vacuums.mainFloor.vacuumMapId).selectableRooms(Vacuums.mainFloor.zones)
        let first = try #require(rooms.first)
        #expect(first == first)
        var moved = first
        moved.centroid = (first.centroid.x + 1, first.centroid.y)
        #expect(moved != first)
        #expect(rooms[0] != rooms[1])
    }
}

/// The legacy "Lost mop pad" alias reads as a missing mop attachment (`LEGACY_REASON_ALIASES`).
struct VacuumOutcomeAliasTests {
    @Test func lostMopPadBecomesAMopAttachmentReason() throws {
        let legacy: [String: Any] = ["code": "unknown", "category": "unknown", "raw": "Lost mop pad", "data": [String: Any]()]
        let report = sampleReport { report in
            var events = report["events"] as! [[String: Any]]
            events[2]["reason"] = legacy
            report["events"] = events
            var rooms = report["rooms"] as! [[String: Any]]
            rooms[2]["latest_attempt"] = ["event_id": "e3", "mode": "vacuum_mop", "result": "interrupted", "reason": legacy]
            rooms[2]["outstanding"] = ["operation": "vacuum_mop", "reason": legacy]
            report["rooms"] = rooms
        }
        guard case let .valid(contract) = VacuumOutcomeParser.parse(report) else { Issue.record("parse"); return }
        let living = try #require(contract.rooms.first { $0.roomId == "living_room" })
        #expect(living.latestAttempt?.reason?.code == "mop.attachment_missing")
        #expect(living.latestAttempt?.reason?.category == "mop")
        #expect(living.outstanding?.reason?.code == "mop.attachment_missing")
        #expect(living.latestAttempt?.reason?.raw == "Lost mop pad", "the raw text is kept")
    }
}
