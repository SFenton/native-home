import Foundation
@testable import HassCore
import Observation
import HassTestSupport
import Testing

/// The flipped facades (`HomeConfig`, `SecurityConfig`, weather, cameras) read the loaded house document and answer
/// empty values without one. Every test scopes its own ``HouseConfigSource`` so parallel suites never see its document.
@MainActor
struct HouseConfigSourceTests {
    /// The demo house with every flipped value changed.
    private static func changedHouse() -> HouseConfig {
        var config = DemoHouse.config
        config.home.statusChips = [HomeConfig.StatusChip(title: "Demo", icon: "mdi:home", entityId: "sensor.demo_demo", tone: .light, sheet: .lights)]
        config.home.weatherEntityId = "weather.demo_demo"
        config.home.guestToggles = [HomeConfig.GuestToggle(title: "Demo Room", entityId: "input_boolean.demo_demo", icon: "mdi:bed")]
        config.home.cameras = [HomeConfig.Camera(title: "Demo Cam", entityId: "camera.demo_demo", rtcStreamId: "demo", aspectRatio: 2)]
        config.security.alarmEntityId = "alarm_control_panel.demo_demo"
        config.security.entryLockEntityId = "lock.demo_entry"
        config.security.garageDoors = ["left": "cover.demo_a", "right": "cover.demo_b"]
        config.security.vehicleLockEntityId = "lock.demo_car"
        config.security.contactSensorsEntityId = "binary_sensor.demo_contacts"
        config.security.showsVehicleSection = true
        config.security.controlTiles = [SecurityConfig.Tile(title: "Demo Lock", entityId: "lock.demo_entry", icon: "mdi:lock", kind: .lock)]
        config.security.vehicleTiles = [SecurityConfig.Tile(title: "Demo Car", entityId: "lock.demo_car", icon: "mdi:car", kind: .vehicle)]
        return config
    }

    // MARK: - Facades

    @Test func withoutADocumentEveryFlippedValueIsEmpty() {
        HouseConfigSource.$scoped.withValue(HouseConfigSource()) {
            #expect(HomeConfig.statusChips.isEmpty)
            #expect(HomeConfig.weatherEntityId.isEmpty)
            #expect(HomeConfig.guestToggles.isEmpty)
            #expect(HomeConfig.cameras.isEmpty)
            #expect(SecurityConfig.alarmEntityId.isEmpty)
            #expect(SecurityConfig.frontDoorLockEntityId.isEmpty)
            #expect(SecurityConfig.leftGarageDoorEntityId.isEmpty)
            #expect(SecurityConfig.rightGarageDoorEntityId.isEmpty)
            #expect(SecurityConfig.vehicleLockEntityId.isEmpty)
            #expect(SecurityConfig.contactSensorsEntityId.isEmpty)
            #expect(SecurityConfig.showsVehicleSection == false)
            #expect(SecurityConfig.controlTiles.isEmpty)
            #expect(SecurityConfig.vehicleTiles.isEmpty)
            #expect(WeatherEntities.weather.isEmpty)
        }
    }

    @Test func aLoadedDocumentProvidesEveryFlippedValue() {
        let source = HouseConfigSource()
        let house = Self.changedHouse()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(HomeConfig.statusChips == house.home.statusChips)
            #expect(HomeConfig.weatherEntityId == "weather.demo_demo")
            #expect(WeatherEntities.weather == "weather.demo_demo")
            #expect(HomeConfig.guestToggles == house.home.guestToggles)
            #expect(HomeConfig.cameras == house.home.cameras)
            #expect(SecurityConfig.alarmEntityId == "alarm_control_panel.demo_demo")
            #expect(QuickLinks.securityEntityId == "alarm_control_panel.demo_demo")
            #expect(SecurityConfig.frontDoorLockEntityId == "lock.demo_entry")
            #expect(SecurityConfig.leftGarageDoorEntityId == "cover.demo_a")
            #expect(SecurityConfig.rightGarageDoorEntityId == "cover.demo_b")
            #expect(SecurityConfig.vehicleLockEntityId == "lock.demo_car")
            #expect(SecurityConfig.contactSensorsEntityId == "binary_sensor.demo_contacts")
            #expect(SecurityConfig.showsVehicleSection)
            #expect(SecurityConfig.controlTiles == house.security.controlTiles)
            #expect(SecurityConfig.vehicleTiles == house.security.vehicleTiles)
        }
    }

    @Test func aDocumentWithOneGarageDoorLeavesTheRightDoorEmpty() {
        var house = Self.changedHouse()
        house.security.garageDoors = ["left": "cover.demo_only"]
        let source = HouseConfigSource()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(SecurityConfig.leftGarageDoorEntityId == "cover.demo_only")
            #expect(SecurityConfig.rightGarageDoorEntityId.isEmpty)
        }
    }

    @Test func clearingTheSourceEmptiesTheFacades() {
        let source = HouseConfigSource()
        source.set(Self.changedHouse())
        source.set(nil)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(HomeConfig.cameras.isEmpty)
        }
    }

    // MARK: - Observation

    /// Counts `withObservationTracking` change callbacks, which the compiler treats as concurrent.
    private final class FireCount: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func bump() { lock.withLock { value += 1 } }
    }

    @Test func aRuntimeChangeNotifiesAnObserverThatReadAFacade() {
        let source = HouseConfigSource()
        let fired = FireCount()
        HouseConfigSource.$scoped.withValue(source) {
            withObservationTracking {
                _ = HomeConfig.cameras
            } onChange: {
                fired.bump()
            }
        }
        source.set(Self.changedHouse())
        #expect(fired.count == 1)
        // An equal document is not a change.
        HouseConfigSource.$scoped.withValue(source) {
            withObservationTracking {
                _ = SecurityConfig.alarmEntityId
            } onChange: {
                fired.bump()
            }
        }
        source.set(Self.changedHouse())
        #expect(fired.count == 1)
        source.set(DemoHouse.config)
        #expect(fired.count == 2)
    }

    // MARK: - Seeding

    @Test func seedingReadsTheCacheForTheSignedInServer() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "house-seed-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let server = HassServer(baseURL: URL(string: "https://demo.example.com")!)
        let cache = HouseConfigCache(fileURL: url)
        try cache.save(Self.changedHouse(), hash: "h", server: server)
        let seeded = HouseConfigSource()
        seeded.seed(from: cache, for: server)
        #expect(seeded.current == Self.changedHouse())
        // Another server's file is refused (and removed by the cache).
        let other = HouseConfigSource()
        other.seed(from: cache, for: HassServer(baseURL: URL(string: "https://other.example.com")!))
        #expect(other.current == nil)
    }

    // MARK: - Store wiring

    @Test func theCachedDocumentIsPublishedBeforeAnyDelivery() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "house-cached-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let server = HassServer(baseURL: URL(string: "https://demo.example.com")!)
        let cache = HouseConfigCache(fileURL: url)
        try cache.save(Self.changedHouse(), hash: "cached", server: server)
        let source = HouseConfigSource()
        // The transport never answers, so only the cache can have filled the source.
        let store = HouseConfigStore(server: server, transport: FakeHouseConfigTransport(), cache: cache, source: source)
        store.start()
        #expect(await eventually { source.current != nil })
        #expect(source.current == Self.changedHouse())
        #expect(store.status == .loading)
    }

    @Test func readProjectsWithoutAnObserverAndIsNilWithoutADocument() {
        let source = HouseConfigSource()
        #expect(source.read { $0.home.weatherEntityId } == nil)
        source.set(Self.changedHouse())
        #expect(source.read { $0.home.weatherEntityId } == "weather.demo_demo")
    }

    @Test func theStorePublishesAcceptedDocumentsAndClearsOnSignOut() async throws {
        let transport = FakeHouseConfigTransport()
        transport.initial = .success(try HouseReply.document(Self.changedHouse(), hash: "h1"))
        let source = HouseConfigSource()
        let url = FileManager.default.temporaryDirectory.appending(path: "house-pub-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HouseConfigStore(
            server: HassServer(baseURL: URL(string: "https://demo.example.com")!), transport: transport,
            cache: HouseConfigCache(fileURL: url), source: source
        )
        store.start()
        #expect(await eventually { source.current != nil })
        #expect(source.current == Self.changedHouse())
        store.clear()
        #expect(source.current == nil)
    }
}
