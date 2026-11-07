@testable import HassCore
import Testing

/// `FENTON_BACKGROUND_GRACE_SECONDS` shortens the background grace for journeys, in debug builds only.
@MainActor
struct BackgroundGraceTests {
    private let key = "FENTON_BACKGROUND_GRACE_SECONDS"

    @Test func absentOverrideKeepsThirtySeconds() {
        #expect(ConnectionLifecycle.resolveGrace(environment: [:], debugBuild: true) == .seconds(30))
        #expect(ConnectionLifecycle.resolveGrace(environment: [:], debugBuild: false) == .seconds(30))
    }

    @Test func debugBuildHonoursTheOverride() {
        #expect(ConnectionLifecycle.resolveGrace(environment: [key: "3"], debugBuild: true) == .seconds(3))
    }

    @Test func nonDebugBuildIgnoresTheOverride() {
        #expect(ConnectionLifecycle.resolveGrace(environment: [key: "3"], debugBuild: false) == .seconds(30))
    }

    @Test func unusableValuesAreIgnored() {
        for bad in ["", "abc", "0", "-5"] {
            #expect(ConnectionLifecycle.resolveGrace(environment: [key: bad], debugBuild: true) == .seconds(30))
        }
    }

    @Test func defaultPropertyIsThirtySecondsWithoutTheVariable() {
        // The test process does not set the variable.
        #expect(ConnectionLifecycle.backgroundGrace == .seconds(30))
    }
}
