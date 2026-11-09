import Foundation
@testable import FentonActivityModel
import Testing

struct ActivityDeepLinkTests {
    @Test func aStateLinksToItsDashboardPathAndBack() throws {
        let state = HomeActivityState(url: "/sfenton-react-dash/home?path=kitchen")
        let url = try #require(ActivityDeepLink.url(for: state))
        #expect(url.scheme == "fentonhome" && url.host == "liveactivity")
        #expect(ActivityDeepLink.link(from: url) == "/sfenton-react-dash/home?path=kitchen")
    }

    @Test func noPathMeansNoLink() {
        #expect(ActivityDeepLink.url(for: HomeActivityState()) == nil)
        #expect(ActivityDeepLink.url(for: HomeActivityState(url: "")) == nil)
    }

    @Test func onlyLiveActivityLinksAreRead() {
        #expect(ActivityDeepLink.link(from: URL(string: "https://example.com/?url=x")!) == nil)
        #expect(ActivityDeepLink.link(from: URL(string: "fentonhome://other?url=x")!) == nil)
        #expect(ActivityDeepLink.link(from: URL(string: "fentonhome://liveactivity")!) == nil)
        #expect(ActivityDeepLink.link(from: URL(string: "fentonhome://liveactivity?url=")!) == nil)
    }
}

struct HomeActivityFixturesTests {
    private let now = ActivityFixtures.now

    @Test func everyNameResolvesAndNamesAreUnique() {
        let names = HomeActivityFixtures.allNames
        #expect(Set(names).count == names.count)
        for name in names {
            let fixture = HomeActivityFixtures.fixture(name, now: now)
            #expect(fixture?.name == name && fixture?.id == name, Comment(rawValue: name))
        }
        #expect(HomeActivityFixtures.fixture("nothing", now: now) == nil)
        #expect(HomeActivityFixtures.fixture("problem-nothing", now: now) == nil)
    }

    @Test func everyGroupMemberResolves() {
        for (group, members) in HomeActivityFixtures.groups {
            #expect(!members.isEmpty)
            #expect(members.allSatisfy { HomeActivityFixtures.fixture($0, now: now) != nil }, Comment(rawValue: group))
        }
        #expect(HomeActivityFixtures.stackNames.count == 4, "four job cards is the cap")
    }

    @Test func activeTimesPointIntoTheFuture() {
        for name in HomeActivityFixtures.allNames {
            guard let fixture = HomeActivityFixtures.fixture(name, now: now), fixture.state.phase != .done,
                  let end = fixture.state.value?.endDate else { continue }
            #expect(end > now, Comment(rawValue: name))
        }
    }

    @Test func everyProblemRowOfTheSpecIsThere() {
        let codes = HomeActivityFixtures.problemRows.map(\.code)
        for code in ["navigation.stuck", "navigation.target_unreachable", "navigation.dock_unreachable", "navigation.ramp_hazard",
                     "maintenance.main_brush_jammed", "maintenance.side_brush_jammed", "power.critical_battery", "power.low_battery",
                     "mop.clean_water_empty", "mop.dirty_water_unavailable", "mop.attachment_missing", "dock.cover_open",
                     "dock.dustbag_blocked", "vendor.unknown_error_88", "dishwasher.actionrequired", "dishwasher.error"] {
            #expect(codes.contains(code), Comment(rawValue: code))
        }
        #expect(HomeActivityFixtures.problemNames.count == HomeActivityFixtures.problemFlippedNames.count)
        #expect(codes.contains { $0.hasPrefix("unmapped.") } && codes.contains("mop.vacuum_only_fallback"))
    }

    @Test func doneIsLastAndOnlyWhereATaskIsBehindTheProblem() throws {
        for row in HomeActivityFixtures.problemRows {
            let table = try #require(HomeActivityFixtures.fixture("problem-" + row.slug, now: now))
            let flipped = try #require(HomeActivityFixtures.fixture("problem-" + row.slug + (row.hasTask ? "-nodone" : "-done"), now: now))
            #expect(table.state.controls.last?.id == "done" || !row.hasTask, Comment(rawValue: row.code))
            #expect(table.state.problem?.hasTask == row.hasTask && flipped.state.problem?.hasTask == !row.hasTask)
            #expect((table.state.controls.last?.id == "done") == row.hasTask)
            #expect((flipped.state.controls.last?.id == "done") == !row.hasTask)
            #expect(table.state.controls.count <= HomeActivityState.maxProblemControls)
            // Done never appears before another button.
            #expect(!table.state.controls.dropLast().contains { $0.id == "done" })
            #expect(table.attributes.title == row.device && table.attributes.tag == row.tag)
        }
    }

    @Test func theUnknownNumberedErrorKeepsOnlyItsChipAndTheUnmappedOneHasNone() throws {
        let numbered = try #require(HomeActivityFixtures.fixture("problem-vendor-unknown_error_88", now: now))
        #expect(numbered.state.problem?.chips == ["Error 88"] && numbered.state.problem?.severity == .critical)
        let unmapped = try #require(HomeActivityFixtures.fixture("problem-unmapped-wheel_suspended", now: now))
        #expect(unmapped.state.problem?.chips.isEmpty == true && unmapped.state.problem?.message.contains("Wheel suspended") == true)
    }

    @Test func launchValuesAreNamesGroupsOrBase64Content() throws {
        #expect(HomeActivityFixtures.fixtures(fromLaunchValue: "fan", now: now).map(\.name) == ["fan"])
        #expect(HomeActivityFixtures.fixtures(fromLaunchValue: "stack", now: now).map(\.name) == HomeActivityFixtures.stackNames)
        let custom = try #require(HomeActivityFixtures.fixture("fan", now: now)).state
        let encoded = try custom.encoded().base64EncodedString()
        let decoded = HomeActivityFixtures.fixtures(fromLaunchValue: encoded, now: now)
        #expect(decoded.count == 1 && decoded[0].state == custom && decoded[0].attributes.tag == "job.custom")
        #expect(HomeActivityFixtures.fixtures(fromLaunchValue: "!!not base64!!", now: now).isEmpty)
        #expect(HomeActivityFixtures.fixtures(fromLaunchValue: Data("nope".utf8).base64EncodedString(), now: now).isEmpty)
    }

    @Test func aFixtureMakesACard() throws {
        let fixture = try #require(HomeActivityFixtures.fixture("fan-pending-stale", now: now))
        #expect(fixture.isStale && fixture.card(now: now).isUnconfirmed)
    }
}
