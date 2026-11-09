#if DEBUG
import HassTelemetry
import SwiftUI

/// Debug builds only. With `FENTON_RESOURCE_CENSUS=1` the root view carries an invisible element,
/// `diagnostics.resources`, whose label is ``ResourceCensus/summary()`` (one `name=count` pair per gauge, plus
/// `Process.threads`). A journey reads it after the first launch and after every resume and requires the live set to
/// be the same: whatever a resume registers, a background must have taken away
/// (`.agents/patterns/resume-lifecycle.md`).
struct ResourceCensusProbe {
    /// Whether this launch shows the probe.
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["FENTON_RESOURCE_CENSUS"] == "1" }



    /// The census plus the process' thread count.
    @MainActor
    static func currentSummary() -> String {
        var counts = ResourceCensus.shared.counts()
        if let threads = ResourceCensus.threadCount() { counts["Process.threads"] = threads }
        return ResourceCensus.summary(of: counts)
    }
}
#endif
