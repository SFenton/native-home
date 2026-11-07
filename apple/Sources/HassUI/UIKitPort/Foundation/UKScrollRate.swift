#if os(iOS)
import HassDesign
import HassTelemetry
import ObjectiveC
import UIKit

/// Asks for the display's top refresh rate while a scroll view of the port scrolls: the UIKit counterpart of
/// the removed scrollFrameRate() request (PR #211, removed by owner 2026-10-31, `.agents/patterns/scroll-frame-rate.md`).
///
/// One observer per scroll view reports `begin` when the content offset first moves and `end` once it has rested for
/// ``restDelay``. The offset observer is one closure call a frame that only stamps a time; a timer runs only while the scroll is
/// in motion. It also tells ``ScrollActivity`` so a deferred websocket switch never lands mid-scroll. iOS 18 and later, as in SwiftUI.
@MainActor
final class UKScrollRate {
    private static var key = 0
    private static let restDelay: TimeInterval = 0.12

    private weak var scroll: UIScrollView?
    private let token = UUID()
    private var observation: NSKeyValueObservation?
    private var lastMove: TimeInterval = 0
    private var timer: Timer?
    private var isActive = false

    /// Starts following `scroll` (once; a second call does nothing).
    static func attach(to scroll: UIScrollView) {
        guard #available(iOS 18.0, *), !UKPerfSwitches.isOff(.ukScrollRate), objc_getAssociatedObject(scroll, &key) == nil else { return }
        let rate = UKScrollRate(scroll)
        objc_setAssociatedObject(scroll, &key, rate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Follows every scroll view under `root` (lists, grids and rails a page or sheet holds), stopping at cells.
    static func attachAll(in root: UIView) {
        if let scroll = root as? UIScrollView { attach(to: scroll) }
        for sub in root.subviews where !(sub is UICollectionViewCell) && !(sub is UITableViewCell) { attachAll(in: sub) }
    }

    private init(_ scroll: UIScrollView) {
        self.scroll = scroll
        observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
            MainActor.assumeIsolated { self?.moved(scroll) }
        }
    }

    deinit {
        MainActor.assumeIsolated { finish() }
    }

    private func moved(_ scroll: UIScrollView) {
        // Only a scroll the user or momentum produces: layout changing the offset of a hidden or detached view does not count.
        guard scroll.window != nil, scroll.isTracking || scroll.isDecelerating || scroll.isDragging else { return }
        lastMove = ProcessInfo.processInfo.systemUptime
        guard !isActive else { return }
        isActive = true
        ScrollActivity.shared.begin(page: token.uuidString)
        let timer = Timer(timeInterval: Self.restDelay, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func check() {
        let resting = ProcessInfo.processInfo.systemUptime - lastMove >= Self.restDelay
        if resting, scroll?.isTracking != true, scroll?.isDecelerating != true { finish() }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        guard isActive else { return }
        isActive = false
        ScrollActivity.shared.end(page: token.uuidString)
    }
}
#endif
