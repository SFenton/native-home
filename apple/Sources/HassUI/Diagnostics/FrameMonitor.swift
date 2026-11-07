import HassDesign
import HassTelemetry
import SwiftUI
#if os(iOS)
import QuartzCore
import UIKit
#endif

/// Measures frame pacing while a page scrolls (pattern: `.agents/patterns/telemetry.md`).
///
/// A link runs only while some page is scrolling and telemetry records, so it costs nothing otherwise. Each
/// frame's duration is compared with the display's budget (8.3 ms at 120 Hz); frames past half a budget late count
/// as hitches and add to that page's ``ScrollStats`` in ``Telemetry/log``. Every scroll is also a `Scroll`
/// signpost interval and every hitch a `Hitch` event, for Instruments.
///
/// **The link must not hold the panel up.** A `CADisplayLink` asks for a frame every vsync and so keeps the display at its
/// top rate by existing, which would make every number here the rate we caused. On iOS 18 and later the monitor uses a
/// passive `UIUpdateLink` (`requiresContinuousUpdates` false): it requests no frame, only observes the ones the scroll and
/// the system produce, and the frame time is the gap between their `UIUpdateInfo.estimatedPresentationTime`s. Below iOS 18
/// (or with no active window scene) it falls back to a `CADisplayLink`, which does hold the rate. The app requests no
/// refresh rate while scrolling (`.agents/patterns/scroll-frame-rate.md`), so the numbers are the system's own.
@MainActor
public final class FrameMonitor {
    /// The app's monitor.
    public static let shared = FrameMonitor()

    /// Posted when a page's scroll ends, with `userInfo` `page` (String) and `frameMs` ([Double]); the fling frame-rate probe
    /// (`FENTON_FLINGFPS=1`) listens. Nothing else observes it.
    static let didEndScroll = Notification.Name("com.sfenton.home.framemonitor.didEndScroll")

    #if os(iOS)
    private var link: CADisplayLink?
    /// A passive `UIUpdateLink` (iOS 18+), held as `AnyObject` so the property needs no availability.
    private var updateLink: AnyObject?
    #endif
    private var active: [String: Telemetry.Interval] = [:]
    private var frames: [String: [Double]] = [:]
    private var lastTimestamp: CFTimeInterval?
    private var budgetMs = 1000.0 / 60
    private var census: ResourceCensus.Registration?

    init() {
        census = ResourceCensus.shared.register { [weak self] in ["FrameMonitor.displayLinks": self?.displayLinkCount ?? 0] }
    }

    /// Display links running now: one while a page scrolls with telemetry on, else none.
    var displayLinkCount: Int {
        #if os(iOS)
        (link == nil && updateLink == nil) ? 0 : 1
        #else
        0
        #endif
    }

    /// Whether any page is scrolling.
    public var isMonitoring: Bool { !active.isEmpty }

    /// Starts counting frames for `page`.
    public func beginScroll(page: String) {
        guard active[page] == nil else { return }
        active[page] = Telemetry.begin(Telemetry.Name.scroll, page: page, page)
        guard Telemetry.isEnabled else { return }
        startLink()
    }

    /// Stops counting frames for `page` and records its stats.
    public func endScroll(page: String) {
        guard let interval = active.removeValue(forKey: page) else { return }
        let pageFrames = frames.removeValue(forKey: page) ?? []
        Telemetry.log.addScroll(page: page, frameMs: pageFrames, budgetMs: budgetMs)
        if !pageFrames.isEmpty { NotificationCenter.default.post(name: Self.didEndScroll, object: nil, userInfo: ["page": page, "frameMs": pageFrames]) }
        let hitchMs = pageFrames.reduce(0) { $0 + max(0, $1 - budgetMs * 1.5 > 0 ? $1 - budgetMs : 0) }
        Telemetry.end(interval, value: hitchMs, detail: "\(pageFrames.count) frames")
        if active.isEmpty { stopLink() }
    }

    /// Adds one frame to every scrolling page (the display link calls it; tests call it directly).
    func record(frameMs: Double, budgetMs: Double) {
        self.budgetMs = budgetMs
        for page in active.keys {
            frames[page, default: []].append(frameMs)
            if frameMs - budgetMs > budgetMs / 2 {
                Telemetry.event(Telemetry.Name.hitch, page: page, value: frameMs - budgetMs)
            }
        }
    }

    // MARK: Display link

    #if os(iOS)
    private func startLink() {
        guard link == nil, updateLink == nil else { return }
        lastTimestamp = nil
        if #available(iOS 18, *), let scene = ActiveWindowScene.current() {
            let maxFPS = max(scene.screen.maximumFramesPerSecond, 60)
            let update = UIUpdateLink(windowScene: scene, actionHandler: { [weak self] _, info in
                self?.updateTick(presentation: info.estimatedPresentationTime, maxFramesPerSecond: maxFPS)
            })
            // Passive: asks for no frames and states no rate, so it observes the system's own cadence.
            update.requiresContinuousUpdates = false
            update.isEnabled = true
            updateLink = update
            return
        }
        let link = CADisplayLink(target: DisplayLinkTarget(monitor: self), selector: #selector(DisplayLinkTarget.tick(_:)))
        // Measures only; no rate preference. Below iOS 18 the link itself still forces a frame per vsync.
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
        if #available(iOS 18, *), let update = updateLink as? UIUpdateLink { update.isEnabled = false }
        updateLink = nil
        lastTimestamp = nil
    }

    /// One frame seen by the passive link: the gap since the previous presentation, against the panel's best budget.
    private func updateTick(presentation: CFTimeInterval, maxFramesPerSecond: Int) {
        defer { lastTimestamp = presentation }
        guard let lastTimestamp else { return }
        record(frameMs: (presentation - lastTimestamp) * 1000, budgetMs: 1000.0 / Double(maxFramesPerSecond))
    }

    fileprivate func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let lastTimestamp else { return }
        let budget = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
        record(frameMs: (link.timestamp - lastTimestamp) * 1000, budgetMs: budget * 1000)
    }
    #else
    private func startLink() {}
    private func stopLink() {}
    #endif
}

#if os(iOS)
/// Keeps the display link from retaining the monitor.
private final class DisplayLinkTarget: NSObject {
    weak var monitor: FrameMonitor?
    init(monitor: FrameMonitor) { self.monitor = monitor }

    @MainActor @objc func tick(_ link: CADisplayLink) { monitor?.tick(link) }
}
#endif
