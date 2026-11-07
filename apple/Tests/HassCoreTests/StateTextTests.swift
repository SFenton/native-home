import Testing
@testable import HassCore

/// The one title-case and availability rule every feature shares (web `entityState.ts`).
struct StateTextTests {
    @Test func titleCasesSnakeCaseLikeTheWeb() {
        #expect(StateText.titleCase("armed_away") == "Armed Away")
        #expect(StateText.titleCase("on") == "On")
        #expect(StateText.titleCase("heat_cool") == "Heat Cool")
        // Only the first letter of each word changes; spaces are not separators.
        #expect(StateText.titleCase("mop only") == "Mop only")
        #expect(StateText.titleCase("auto_HIGH") == "Auto HIGH")
        // `split('_')` on the web keeps empty parts.
        #expect(StateText.titleCase("a__b") == "A  B")
    }

    @Test func missingStateReadsUnknownOrTheGivenFallback() {
        #expect(StateText.titleCase(nil) == "Unknown")
        #expect(StateText.titleCase("") == "Unknown")
        #expect(StateText.titleCase("", empty: "") == "")
        #expect(StateText.titleCase(nil, empty: "Off") == "Off")
    }

    @Test func unavailableMeansMissingUnavailableOrUnknown() {
        #expect(EntityState.isUnavailable(nil))
        #expect(EntityState.isUnavailable("unavailable"))
        #expect(EntityState.isUnavailable("unknown"))
        #expect(!EntityState.isUnavailable("off"))
        #expect(!EntityState.isUnavailable(""))
        #expect(EntityState(entityId: "light.demo_a", state: "unknown").isUnavailable)
    }
}
