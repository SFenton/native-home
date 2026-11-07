@testable import HassCore
import HassDemoHouse
@testable import HassUI
import Testing

/// The DEBUG gallery draws the synthetic demo house: its fixtures key their states by the ids the facades answer with, so the
/// pages are populated whichever house is installed. Every test scopes its own source, so none touches `HouseConfigSource.shared`.
@MainActor
struct GalleryHouseTests {
    @Test func installingFillsAndUninstallingClearsTheGivenSource() {
        let source = HouseConfigSource()
        GalleryHouse.install(into: source)
        #expect(source.current == DemoHouse.config)
        GalleryHouse.install(into: source)
        #expect(source.current == DemoHouse.config, "installing twice leaves the same document")
        GalleryHouse.uninstall(from: source)
        #expect(source.current == nil)
    }

    @Test func choresFixturesFillTheDemoResidentsFirstListAndPadItOnRequest() throws {
        try HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            let page = try #require(ChoresConfig.page(ChoresFixtures.firstResidentPageId), "the demo house has the first resident's page")
            let first = try #require(page.lists.first).entityId
            let plain = ChoresFixtures.lists()
            #expect(plain[first]?.isEmpty == false, "the page's first list has chores to show")
            let padded = ChoresFixtures.lists(extra: 5)
            #expect((padded[first]?.count ?? 0) == (plain[first]?.count ?? 0) + 5, "extra chores pad the resident's lists")
            #expect(padded[ChoresConfig.groceryEntityId]?.count == plain[ChoresConfig.groceryEntityId]?.count, "other lists are not padded")
        }
    }

    @Test func statusChipReadingsFollowTheChipsOfTheInstalledHouse() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            let chips = HomeConfig.statusChips
            let states = HomeFixtures.statusChipStates
            #expect(!states.isEmpty)
            #expect(states.allSatisfy { state in chips.contains { $0.entityId == state.entityId || $0.detailEntityId == state.entityId } }, "each reading belongs to a chip")
        }
    }

    @Test func galleryFixturesNeverIndexAShortHouseList() {
        // A document with no purifiers, fans or rooms must not trap a gallery fixture.
        var bare = DemoHouse.config
        bare.roomDevices.airPurifiers = []
        bare.roomDevices.bathroomFans = []
        bare.rooms.pages = []
        let source = HouseConfigSource()
        source.set(bare)
        HouseConfigSource.$scoped.withValue(source) {
            let fixtures = RoomDeviceFixture.all()
            #expect(!fixtures.contains { fixture in
                if case .purifier = fixture.kind { return true }
                return false
            }, "no purifier in the document, no purifier fixture")
            #expect(RoomsConfig.pages.isEmpty)
        }
    }
}
