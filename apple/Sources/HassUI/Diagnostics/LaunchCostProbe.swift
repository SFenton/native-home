import HassTelemetry
import SwiftUI

/// Measures what the launch intro, a signed-in relaunch and the sign-in arrival cost the main thread (pattern:
/// `.agents/testing/apple/performance.md`, "Launch and sign-in"; tool: `tools/ios_launchperf.sh`).
///
/// A simulator's hitch ratio means nothing, so this uses ``MainThreadCostMeter``: per run-loop turn, how long the main thread
/// computed. A turn longer than the frame budget is a hitch whatever the display says. With `FENTON_LAUNCHCOST=1`:
/// - **intro**: from the first frame of a signed-out launch for two seconds (the intro runs 1.2 s);
/// - **snapshot**: the same for a signed-in relaunch (the launch ground fading onto the disk snapshot);
/// - **arrival**: from the moment tokens arrive until Home has finished arriving.
///
/// Each run appends `LAUNCHCOST<TAB>phase<TAB>summary` (the meter's `key=value` pairs, then the signpost intervals the run
/// recorded: `Launch`, `SnapshotShown`, `SignIn`, `Intro`, `Arrival`, in ms) to `FENTON_LAUNCHCOST_FILE`, prints it, and shows
/// it as the label of the invisible `diagnostics.launchcost` element so a UI test can read it. No test drives the app while it
/// measures.
@MainActor
enum LaunchCostProbe {
    /// Whether this launch measures.
    static var isEnabled = ProcessInfo.processInfo.environment["FENTON_LAUNCHCOST"] == "1"

    /// How long the intro and snapshot phases measure, in seconds.
    static let windowSeconds = 2.0

    /// The last finished line (the `diagnostics.launchcost` label).
    static private(set) var latest = "ready"

    private static var meter: MainThreadCostMeter?
    private static var phase = ""

    /// Starts measuring `phase`. Does nothing when probing is off or a phase is running.
    static func begin(_ phase: String) {
        guard isEnabled, meter == nil else { return }
        self.phase = phase
        let meter = MainThreadCostMeter()
        meter.begin()
        self.meter = meter
    }

    /// Stops the running phase, appends its line and returns it.
    @discardableResult
    static func finish(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let meter else { return nil }
        self.meter = nil
        let line = line(for: meter.finish(), records: Telemetry.log.records)
        latest = line
        append("LAUNCHCOST\t\(phase)\t\(line)\nLAUNCHCOST_DONE\t\(phase)\n", to: environment["FENTON_LAUNCHCOST_FILE"])
        return line
    }

    /// Measures `phase` for ``windowSeconds`` (the intro and the snapshot).
    static func measureWindow(_ phase: String) async {
        guard isEnabled else { return }
        begin(phase)
        try? await Task.sleep(for: .seconds(windowSeconds))
        finish()
    }

    /// The meter's summary followed by the latest length of each launch interval, as `Name_ms=value`.
    static func line(for report: MainThreadCostMeter.Report, records: [TelemetryRecord]) -> String {
        var line = report.summary
        for kind in ["Launch", "SnapshotShown", "SignIn", "Intro", "Arrival"] {
            if let ms = records.last(where: { $0.kind == kind })?.durationMs { line += " \(kind)_ms=\(String(format: "%.2f", ms))" }
        }
        return line
    }

    private static func append(_ text: String, to path: String?) {
        print(text, terminator: "")
        fflush(stdout)
        guard let path, let data = text.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
