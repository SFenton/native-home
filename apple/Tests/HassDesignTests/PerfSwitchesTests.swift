@testable import HassDesign
import Testing

struct PerfSwitchesTests {
    @Test func parsesTheNamedLayersAndIgnoresTheRest() {
        #expect(PerfSwitches.parse("headerFade,backdrop") == [.headerFade, .backdrop])
        #expect(PerfSwitches.parse(" backdrop , nonsense,") == [.backdrop])
        #expect(PerfSwitches.parse("") == [])
        #expect(PerfSwitches.parse(nil) == [])
        #expect(PerfSwitches.parse("glassBar,scrollEdge") == [.glassBar, .scrollEdge])
    }

    @Test func aNormalLaunchHasEveryLayerOn() {
        for layer in PerfSwitches.Layer.allCases { #expect(!PerfSwitches.isOff(layer)) }
    }
}
