import XCTest

/// What the house-layout reveal costs (`.agents/design/motion.md` section 10, `.agents/patterns/content-gate.md`; runner:
/// `tools/ios_motionperf.sh`, deferred by tier: written now, run in the end-of-migration pass).
///
/// The gate records a `LayoutChange` signpost interval (page `HouseLayout`) around each transition: the layers fading out (`layersOut`),
/// the message fading in (`messageIn`) and the content reveal (`reveal`, the shared content-gate fade-in and 4 pt rise). The Security
/// gallery forces the skeleton (`FENTON_GALLERY_HOUSECONFIG=loading`) and releases it after `FENTON_GALLERY_HOUSECONFIG_SWAP` seconds, so
/// each launch measures one skeleton-to-content swap. Simulator numbers are CPU and signpost lengths only; hitches need a device.
@MainActor
final class HouseLayoutRevealPerformanceTests: JourneyTestCase {
    override class var measuresAnimation: Bool { true }

    private func requireOptIn() throws {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["FENTON_PERF_ON_SIMULATOR"] != "1" {
            throw XCTSkip("Set TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1 to measure the house-layout reveal on a simulator.")
        }
        #endif
    }

    private func measureSwap(state: String, reduceMotion: Bool) {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "security"
        app.launchEnvironment["FENTON_GALLERY_HOUSECONFIG"] = state
        app.launchEnvironment["FENTON_GALLERY_HOUSECONFIG_SWAP"] = "2"
        if reduceMotion { app.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment([.reduceMotion])) { _, new in new } }
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        let signpost = XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "LayoutChange")
        measure(metrics: [signpost], options: options) {
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["security.system.state"].firstMatch.appears(timeout: 30), "the page shows after the swap")
            app.terminate()
        }
    }

    /// Skeleton fades out, then the page fades in and rises 4 pt.
    func testSkeletonToContentRevealCost() throws {
        try requireOptIn()
        measureSwap(state: "loading", reduceMotion: false)
    }

    /// The same with Reduce Motion on: a fade only.
    func testSkeletonToContentRevealCostReduceMotion() throws {
        try requireOptIn()
        measureSwap(state: "loading", reduceMotion: true)
    }

    /// A message gives way to the page.
    func testMessageToContentRevealCost() throws {
        try requireOptIn()
        measureSwap(state: "missing", reduceMotion: false)
    }
}
