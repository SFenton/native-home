import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// What a stretch of time cost the process and its main thread (pattern: `.agents/patterns/telemetry.md`, "Scroll cost").
///
/// **Why it exists.** Frame hitch ratios from a simulator mean nothing, and an XCUITest swipe drags the app's own
/// accessibility snapshots into the number, so a fixed scroll on any page read the same floor. This measures the app's
/// CPU instructions (which do not move with other work on the Mac) and, per run-loop turn, how long the main thread
/// computed: a turn longer than a frame's budget is a hitch whatever the display link says.
///
/// Usage: ``begin()`` then ``finish()``. Main thread only.
@MainActor
public final class MainThreadCostMeter {
    /// One turn of the main run loop, from waking to going back to sleep.
    struct Turn: Sendable, Equatable {
        /// CPU time the main thread spent in the turn, in milliseconds.
        var cpuMs: Double
    }

    /// The result of a measured stretch.
    public struct Report: Sendable, Equatable {
        /// Wall seconds measured.
        public var seconds: Double
        /// CPU instructions the whole process retired, in millions (0 where the system does not report them).
        public var megaInstructions: Double
        /// CPU seconds the whole process used.
        public var processCPUSeconds: Double
        /// CPU seconds the main thread used.
        public var mainCPUSeconds: Double
        /// Run-loop turns the main thread ran.
        public var turns: Int
        /// Turns that computed for more than 4, 8 and 16 ms (half a frame at 120 Hz, a frame at 120 Hz, a frame at 60 Hz).
        public var turnsOver4: Int
        public var turnsOver8: Int
        public var turnsOver16: Int
        /// The longest turn's CPU time and the 95th percentile, in milliseconds.
        public var worstTurnMs: Double
        public var p95TurnMs: Double
        /// How far a driver scrolled during the run, in points (set by the caller; 0 for an idle run).
        public var travelledPoints = 0.0
        /// Extra `key=value` pairs a caller appends (live entity deliveries during the run).
        public var note = ""

        /// `key=value` pairs on one line, for an accessibility label or a log.
        public var summary: String {
            [
                "seconds=\(Self.format(seconds))", "minstr=\(Self.format(megaInstructions))",
                "cpu_ms=\(Self.format(processCPUSeconds * 1000))", "main_ms=\(Self.format(mainCPUSeconds * 1000))",
                "turns=\(turns)", "over4=\(turnsOver4)", "over8=\(turnsOver8)", "over16=\(turnsOver16)",
                "worst_ms=\(Self.format(worstTurnMs))", "p95_ms=\(Self.format(p95TurnMs))", "travelled=\(Int(travelledPoints))",
            ].joined(separator: " ") + (note.isEmpty ? "" : " " + note)
        }

        static func format(_ value: Double) -> String { String(format: "%.2f", value) }
    }

    private var startWall: ContinuousClock.Instant?
    private var startProcess = ProcessCPU.Snapshot.zero
    private var startMain = 0.0
    private var turns: [Turn] = []
    private var observer: CFRunLoopObserver?
    private var turnStart: Double?

    /// Creates a meter.
    public init() {}

    /// Starts measuring: the process' counters now, and every main run-loop turn from here.
    public func begin() {
        guard startWall == nil else { return }
        turns.removeAll(keepingCapacity: true)
        startWall = .now
        startProcess = ProcessCPU.snapshot()
        startMain = ProcessCPU.currentThreadSeconds()
        // After waking: a turn starts. Before sleeping: it ends. Both in the common modes, so scrolling's tracking mode
        // counts.
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities, true, Int.max) { [weak self] _, activity in
            MainActor.assumeIsolated { self?.record(activity) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    /// Stops measuring and reports.
    public func finish() -> Report {
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = nil
        }
        let wall = startWall.map { (ContinuousClock.now - $0).seconds } ?? 0
        let process = ProcessCPU.snapshot()
        let main = ProcessCPU.currentThreadSeconds() - startMain
        startWall = nil
        return Self.report(seconds: wall, process: process - startProcess, mainSeconds: main, turns: turns)
    }

    private func record(_ activity: CFRunLoopActivity) {
        if activity.contains(.afterWaiting) {
            turnStart = ProcessCPU.currentThreadSeconds()
        } else if activity.contains(.beforeWaiting), let start = turnStart {
            turns.append(Turn(cpuMs: (ProcessCPU.currentThreadSeconds() - start) * 1000))
            turnStart = nil
        }
    }

    /// The report for measured numbers (separate from the clocks so it can be tested).
    static func report(seconds: Double, process: ProcessCPU.Snapshot, mainSeconds: Double, turns: [Turn]) -> Report {
        let sorted = turns.map(\.cpuMs).sorted()
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        return Report(
            seconds: seconds,
            megaInstructions: Double(process.instructions) / 1_000_000,
            processCPUSeconds: process.cpuSeconds,
            mainCPUSeconds: mainSeconds,
            turns: turns.count,
            turnsOver4: turns.filter { $0.cpuMs > 4 }.count,
            turnsOver8: turns.filter { $0.cpuMs > 8 }.count,
            turnsOver16: turns.filter { $0.cpuMs > 16 }.count,
            worstTurnMs: sorted.last ?? 0,
            p95TurnMs: p95
        )
    }
}

// libproc's `proc_pid_rusage` is in every iOS system, but its header is not part of the Swift Darwin module.
@_silgen_name("proc_pid_rusage")
private func fenton_proc_pid_rusage(_ pid: Int32, _ flavor: Int32, _ buffer: UnsafeMutableRawPointer) -> Int32

/// The process' and the current thread's CPU counters.
public enum ProcessCPU {
    /// A reading of the process' counters.
    public struct Snapshot: Sendable, Equatable {
        /// Instructions retired by the process (0 where the system does not report them).
        public var instructions: UInt64
        /// User plus system CPU seconds.
        public var cpuSeconds: Double

        static let zero = Snapshot(instructions: 0, cpuSeconds: 0)

        static func - (lhs: Snapshot, rhs: Snapshot) -> Snapshot {
            Snapshot(instructions: lhs.instructions &- rhs.instructions, cpuSeconds: lhs.cpuSeconds - rhs.cpuSeconds)
        }
    }

    /// The process' counters now (`proc_pid_rusage`).
    public static func snapshot() -> Snapshot {
        #if canImport(Darwin)
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { fenton_proc_pid_rusage(getpid(), RUSAGE_INFO_V4, UnsafeMutableRawPointer($0)) }
        guard status == 0 else { return .zero }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanoseconds = Double(info.ri_user_time &+ info.ri_system_time) * Double(timebase.numer) / Double(timebase.denom)
        return Snapshot(instructions: info.ri_instructions, cpuSeconds: nanoseconds / 1_000_000_000)
        #else
        return .zero
        #endif
    }

    /// Seconds since this process started (`sysctl` `kern.proc.pid`), 0 where the system does not say.
    public static func secondsSinceProcessStart() -> Double {
        #if canImport(Darwin)
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return 0 }
        let start = info.kp_proc.p_un.__p_starttime
        return max(0, Date().timeIntervalSince1970 - (Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000))
        #else
        return 0
        #endif
    }

    /// CPU seconds (user plus system) the calling thread has used.
    public static func currentThreadSeconds() -> Double {
        #if canImport(Darwin)
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        func seconds(_ value: time_value_t) -> Double { Double(value.seconds) + Double(value.microseconds) / 1_000_000 }
        return seconds(info.user_time) + seconds(info.system_time)
        #else
        return 0
        #endif
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
