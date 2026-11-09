import HassCore
import HassDesign
import HassTelemetry
import SwiftUI
#if os(iOS)
import ObjectiveC
import UIKit
#endif

/// Scrolls the front scroll view by itself for a fixed time and reports what that cost (pattern:
/// `.agents/patterns/telemetry.md`, "Scroll cost"; tests: `ScrollSurfacesPerformanceTests`).
///
/// With `FENTON_SCROLLCOST=1` the root view carries an invisible element, `diagnostics.scrollcost`, and listens for two
/// Darwin notifications a test posts once the surface under test is on screen:
/// - `com.sfenton.home.scrollcost.scroll`: drags the page up and down at a steady speed;
/// - `com.sfenton.home.scrollcost.idle`: waits the same time without moving.
///
/// When the time is up the element's label becomes ``MainThreadCostMeter/Report/summary``. The scroll is driven by a
/// display link setting the content offset each frame, so none of the cost is an XCUITest swipe or the accessibility
/// snapshot it asks for, and the same code runs in a Release build on a phone. The idle run is the floor to subtract.
struct ScrollCostProbe {
    /// Whether this launch carries the probe.
    static let isEnabled = ProcessInfo.processInfo.environment["FENTON_SCROLLCOST"] == "1"

    /// The dashboard path a scroll cost launch opens first (`FENTON_SCROLLCOST_OPEN=climate`, `living-room`, `settings`),
    /// so a run needs no taps; nil outside a scroll cost launch.
    static let launchPath: String? = isEnabled ? ProcessInfo.processInfo.environment["FENTON_SCROLLCOST_OPEN"] : nil

    static let scrollNotification = "com.sfenton.home.scrollcost.scroll"
    static let idleNotification = "com.sfenton.home.scrollcost.idle"

    #if os(iOS)
    /// Prints the line (a phone launched with `devicectl --console` returns it) and appends it to `path` when there is one.
    static func append(_ text: String, to path: String?) {
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

    /// The two Darwin notifications as an async stream of their names.
    static func notifications() -> AsyncStream<String> {
        AsyncStream { continuation in
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let observer = Unmanaged.passRetained(NotificationSink { continuation.yield($0) })
            for name in [scrollNotification, idleNotification] {
                CFNotificationCenterAddObserver(center, observer.toOpaque(), { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    Unmanaged<NotificationSink>.fromOpaque(observer).takeUnretainedValue().handler(name.rawValue as String)
                }, name as CFString, nil, .deliverImmediately)
            }
            continuation.onTermination = { _ in
                CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer.toOpaque())
                observer.release()
            }
        }
    }

    private final class NotificationSink: @unchecked Sendable {
        let handler: @Sendable (String) -> Void
        init(_ handler: @escaping @Sendable (String) -> Void) { self.handler = handler }
    }
    #endif
}

#if os(iOS)
/// Finds the front scroll view and moves it.
@MainActor
final class ScrollCostDriver {
    /// The largest top inset any run saw, carried to the next run (which may start with the large title already collapsed).
    private var restingTop: CGFloat = 0
    private var link: CADisplayLink?
    private var target: DisplayLinkTarget?

    /// Seconds a run lasts and the scroll speed in points per second (`FENTON_SCROLLCOST_SECONDS`, `_SPEED`).
    private var seconds: Double { Double(ProcessInfo.processInfo.environment["FENTON_SCROLLCOST_SECONDS"] ?? "") ?? 10 }
    /// `FENTON_SCROLLCOST_AXIS=horizontal` drives the widest sideways scroll view (a carousel or rail) instead of the page.
    private var horizontal: Bool { ProcessInfo.processInfo.environment["FENTON_SCROLLCOST_AXIS"] == "horizontal" }
    private var speed: Double { Double(ProcessInfo.processInfo.environment["FENTON_SCROLLCOST_SPEED"] ?? "") ?? 900 }

    /// Runs one measurement.
    /// - Parameter scrolling: Drag the front scroll view, or wait without touching anything.
    /// - Returns: The cost, or nil when scrolling was asked for and no scroll view is on screen.
    /// - Parameter during: Work started a second into the run (a forced reconnect), so what it causes is in the numbers.
    func run(scrolling: Bool, during: (@Sendable () async -> Void)? = nil) async -> MainThreadCostMeter.Report? {
        var scrollView: UIScrollView?
        if scrolling {
            scrollView = Self.frontScrollView(horizontal: horizontal)
            guard scrollView != nil else { return nil }
        }
        let meter = MainThreadCostMeter()
        // Counts how often UIKit changes the page's adjusted content inset (the large title collapsing and expanding does it
        // several times per top crossing): a counter only, no SwiftUI state.
        let insets = scrollView.map { InsetChangeCounter(scrollView: $0) }
        let counters = Telemetry.log.counters
        let startedAt = Date.now
        let end = ContinuousClock.now + .seconds(seconds)
        // Let the notification's own turn settle before counting.
        try? await Task.sleep(for: .milliseconds(300))
        meter.begin()
        let pacer = FramePacer()
        pacer.begin()
        let wallStart = Date().timeIntervalSince1970
        let interruption = during.map { work in Task { try? await Task.sleep(for: .seconds(1)); await work() } }
        defer { interruption?.cancel() }
        var distance = 0.0
        if let scrollView {
            let mover = Mover(scrollView: scrollView, speed: speed, horizontal: horizontal)
            mover.restingTop = restingTop
            start(mover)
            try? await Task.sleep(until: end, clock: .continuous)
            stop()
            restingTop = mover.restingTop
            distance = mover.travelled
        } else {
            try? await Task.sleep(until: end, clock: .continuous)
        }
        pacer.finish()
        let wallEnd = Date().timeIntervalSince1970
        var report = meter.finish()
        report.travelledPoints = distance
        // Live updates the connection applied meanwhile, and what applying them cost on the main thread.
        let after = Telemetry.log.counters
        let updates = Telemetry.log.records.filter { $0.kind == "\(Telemetry.Name.entityUpdate)" && $0.date >= startedAt }
        report.note = Self.deliveryNote(from: counters, to: after)
            + " update_ms=\(String(format: "%.1f", updates.compactMap(\.durationMs).reduce(0, +)))"
            + (insets.map { " inset_changes=\($0.hookChanges) inset_kvo=\($0.kvoChanges)" } ?? "")
            // Frame pacing and memory (``FramePacer``), and the wall-clock window so the host's GPU and render-server
            // samples (`tools/uikit_perf.sh`) can be matched to this run.
            + " " + pacer.summary
            + " t0=\(String(format: "%.3f", wallStart)) t1=\(String(format: "%.3f", wallEnd))"
        return report
    }

    /// `key=value` pairs for what the connection delivered between two counter readings (`HassConnection.apply`): the deliveries
    /// and the entities they carried, how many of those the main thread compared against how many boxes really changed,
    /// deliveries carrying most of the house, socket transitions, subscriptions started, full sets received, network path updates
    /// against the ones that counted as a new network, route moves to the home and public addresses, and the main thread's
    /// CPU time inside the deliveries (including releasing what they replaced).
    static func deliveryNote(from before: [String: Int], to after: [String: Int]) -> String {
        func delta(_ key: String) -> Int { (after[key] ?? 0) - (before[key] ?? 0) }
        return "deliveries=\(delta("entity.deliveries")) changed=\(delta("entity.changed")) received=\(delta("entity.received"))"
            + " full=\(delta("entity.full")) compared=\(delta("entity.compared")) boxes=\(delta("entity.boxChanges"))"
            + " transitions=\(delta("connection.transitions")) subscribes=\(delta("entity.subscribes")) fullsets=\(delta("entity.fullSets"))"
            + " path_updates=\(delta("connection.pathUpdates")) net_changes=\(delta("connection.networkChanges"))"
            + " route_local=\(delta("connection.route.local")) route_public=\(delta("connection.route.public"))"
            + " delivery_ms=\(String(format: "%.1f", Double(delta("entity.mainUs")) / 1000))"
    }

    /// The cold launch as one line: the counters since process start, and when the first live set was applied.
    static func launchSummary() -> String {
        let counters = Telemetry.log.counters
        // The process' CPU and instructions from start to the page settled: the cost of opening the page (a plain `VStack` builds
        // every row here, a `List` builds them as they scroll in), with the rest of the launch the same in both variants.
        let process = ProcessCPU.snapshot()
        return "launch=1 up_s=\(String(format: "%.1f", ProcessCPU.secondsSinceProcessStart())) firstlive_ms=\(counters["entity.firstLiveMs"] ?? 0) "
            + "cpu_ms=\(Int(process.cpuSeconds * 1000)) instr_m=\(process.instructions / 1_000_000) "
            + deliveryNote(from: [:], to: counters) + " ping_reconnects=\(counters["connection.pingReconnects"] ?? 0)"
    }

    private func start(_ mover: Mover) {
        let target = DisplayLinkTarget(mover: mover)
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.target = target
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
        target = nil
    }

    /// The visible vertical scroll view that covers the most of the front-most presented screen.
    static func frontScrollView(horizontal: Bool = false) -> UIScrollView? {
        guard let scene = ActiveWindowScene.currentOrFirst(),
              let window = scene.keyWindow ?? scene.windows.first else { return nil }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        let root: UIView = controller?.view ?? window
        var best: (view: UIScrollView, area: CGFloat)?
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            guard let scroll = view as? UIScrollView, !scroll.isHidden, scroll.alpha > 0.01, scroll.window != nil else { continue }
            let visible = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
            if horizontal {
                // A carousel or rail: wider content than the view, and not the page.
                guard visible.width > 200, visible.height > 20,
                      scroll.contentSize.width > scroll.bounds.width + 1, scroll.contentSize.height <= scroll.bounds.height + 1
                else { continue }
            } else {
                guard visible.width > 200, visible.height > 200 else { continue }
                // A vertical scroller: the content is taller than the view, or wider content is not what scrolls it.
                guard scroll.contentSize.height > scroll.bounds.height + 1 else { continue }
            }
            let area = visible.width * visible.height
            if best == nil || area > best!.area { best = (scroll, area) }
        }
        return best?.view
    }

    /// Every scroll view in the key window with the facts ``frontScrollView()`` judges, for a run that finds none.
    static func describeScrollViews() -> String {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.compactMap({ $0.keyWindow ?? $0.windows.first }).first else { return "no window (\(scenes.count) scenes)" }
        var found: [String] = []
        var stack: [UIView] = [window]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            guard let scroll = view as? UIScrollView else { continue }
            let frame = scroll.convert(scroll.bounds, to: window)
            found.append("\(type(of: scroll)) \(Int(frame.width))x\(Int(frame.height)) content=\(Int(scroll.contentSize.height)) alpha=\(scroll.alpha) hidden=\(scroll.isHidden)")
        }
        let presented = window.rootViewController?.presentedViewController.map { "\(type(of: $0))" } ?? "none"
        return "presented=\(presented) " + found.joined(separator: "; ")
    }

    /// Moves a scroll view up and down at a steady speed, one step per frame.
    @MainActor
    final class Mover {
        let scrollView: UIScrollView
        let speed: Double
        private(set) var travelled = 0.0
        private var direction = 1.0
        private var last: CFTimeInterval?

        let horizontal: Bool
        var restingTop: CGFloat = 0

        init(scrollView: UIScrollView, speed: Double, horizontal: Bool = false) {
            self.scrollView = scrollView
            self.speed = speed
            self.horizontal = horizontal
        }

        func step(_ link: CADisplayLink) {
            defer { last = link.timestamp }
            guard let last else { return }
            let delta = min(link.timestamp - last, 0.1) * speed
            let inset = scrollView.adjustedContentInset
            if horizontal {
                let start = -inset.left
                let end = max(start, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
                var x = scrollView.contentOffset.x + direction * delta
                if x >= end { x = end; direction = -1 } else if x <= start { x = start; direction = 1 }
                travelled += delta
                scrollView.setContentOffset(CGPoint(x: x, y: scrollView.contentOffset.y), animated: false)
                return
            }
            // The page's real top is the largest top inset seen (the large title expanded). The scroll goes back to it every
            // pass, so the title collapses and expands each pass like a hand's flick does; the bound used to follow the
            // collapsed inset, and a page that started collapsed never entered the large-title zone again.
            restingTop = max(restingTop, inset.top)
            let top = -restingTop
            let bottom = max(top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
            var y = scrollView.contentOffset.y + direction * delta
            if y >= bottom { y = bottom; direction = -1 } else if y <= top { y = top; direction = 1 }
            travelled += delta
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
        }
    }

    /// Counts changes of one scroll view's `adjustedContentInset`: through KVO, and through the `adjustedContentInsetDidChange`
    /// hook UIKit calls on every change (a method exchange installed once, which only counts for the watched view). Release
    /// builds too, because the phone is measured on one.
    @MainActor
    final class InsetChangeCounter: NSObject {
        private(set) var hookChanges = 0
        private(set) var kvoChanges = 0
        private var observation: NSKeyValueObservation?
        /// Weak on both sides: a finished measurement or a released scroll view drops out by itself, and a reused object
        /// address can never alias a dead entry (an `ObjectIdentifier` key would grow forever and could).
        nonisolated(unsafe) private static let watched = NSMapTable<UIScrollView, InsetChangeCounter>.weakToWeakObjects()
        nonisolated(unsafe) private static var installed = false

        init(scrollView: UIScrollView) {
            super.init()
            Self.install()
            Self.watched.setObject(self, forKey: scrollView)
            observation = scrollView.observe(\.adjustedContentInset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.kvoChanges += 1 }
            }
            self.scrollView = scrollView
        }

        private weak var scrollView: UIScrollView?

        deinit {
            observation?.invalidate()
        }

        fileprivate static func record(_ scrollView: UIScrollView) {
            watched.object(forKey: scrollView)?.hookChanges += 1
        }

        private static func install() {
            guard !installed else { return }
            installed = true
            if let original = class_getInstanceMethod(UIScrollView.self, #selector(UIScrollView.adjustedContentInsetDidChange)),
               let swapped = class_getInstanceMethod(UIScrollView.self, #selector(UIScrollView.fenton_probeAdjustedContentInsetDidChange)) {
                method_exchangeImplementations(original, swapped)
            }
        }
    }

    private final class DisplayLinkTarget: NSObject {
        let mover: Mover
        init(mover: Mover) { self.mover = mover }
        @MainActor @objc func tick(_ link: CADisplayLink) { mover.step(link) }
    }
}

extension UIScrollView {
    @objc fileprivate func fenton_probeAdjustedContentInsetDidChange() {
        fenton_probeAdjustedContentInsetDidChange()  // the original, after the exchange
        MainActor.assumeIsolated { ScrollCostDriver.InsetChangeCounter.record(self) }
    }
}
#else
/// macOS (hosted tests) has no scroll views to drive.
@MainActor
final class ScrollCostDriver {
    func run(scrolling: Bool, during: (@Sendable () async -> Void)? = nil) async -> MainThreadCostMeter.Report? { nil }
    static func launchSummary() -> String { "" }
}
#endif
