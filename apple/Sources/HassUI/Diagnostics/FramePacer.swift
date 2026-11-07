#if os(iOS)
import Darwin
import QuartzCore
import UIKit

/// Frame pacing and memory for a scroll cost run (`ScrollCostDriver`), measured the same way in the SwiftUI app and its
/// UIKit port: a display link counts the frames the main thread delivered and the ones it missed, and the process's
/// physical footprint is read at the end (`phys_footprint`, the number Xcode's memory gauge and jetsam use).
@MainActor
final class FramePacer {
    private var link: CADisplayLink?
    private var target: Target?
    private var last: CFTimeInterval?
    private(set) var frames = 0
    private(set) var dropped = 0
    private(set) var hitchSeconds = 0.0
    private(set) var expected = 0.0
    private var started: CFTimeInterval = 0
    private var ended: CFTimeInterval = 0

    /// Starts counting frames.
    func begin() {
        let target = Target(pacer: self)
        let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        self.target = target
        started = CACurrentMediaTime()
    }

    /// Stops counting.
    func finish() {
        link?.invalidate()
        link = nil
        target = nil
        ended = CACurrentMediaTime()
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let duration = link.targetTimestamp - link.timestamp
        if duration > 0 { expected = duration }
        defer { last = link.timestamp }
        frames += 1
        guard let last, expected > 0 else { return }
        let interval = link.timestamp - last
        // A frame that arrives one or more refresh intervals late: the missed refreshes are dropped frames, and the
        // time past the expected interval is hitch time.
        let missed = Int((interval / expected).rounded()) - 1
        if missed > 0 {
            dropped += missed
            hitchSeconds += interval - expected
        }
    }

    /// `key=value` pairs: delivered frames per second, the display's rate, dropped frames, hitch time ratio (ms of hitch
    /// per second, Apple's hitch metric), memory now and at its peak.
    var summary: String {
        let seconds = max(ended - started, 0.001)
        let memory = Self.memory()
        return [
            "fps=\(String(format: "%.1f", Double(frames) / seconds))",
            "hz=\(expected > 0 ? String(format: "%.0f", 1 / expected) : "0")",
            "dropped=\(dropped)",
            "hitch_ms_per_s=\(String(format: "%.2f", hitchSeconds * 1000 / seconds))",
            "mem_mb=\(String(format: "%.1f", memory.now))",
            "peak_mb=\(String(format: "%.1f", memory.peak))",
        ].joined(separator: " ")
    }

    /// The process's physical footprint now and at its peak, in MB.
    static func memory() -> (now: Double, peak: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return (0, 0) }
        return (Double(info.phys_footprint) / 1_048_576, Double(info.ledger_phys_footprint_peak) / 1_048_576)
    }

    private final class Target: NSObject {
        weak var pacer: FramePacer?
        init(pacer: FramePacer) { self.pacer = pacer }
        @MainActor @objc func tick(_ link: CADisplayLink) { pacer?.tick(link) }
    }
}
#endif
