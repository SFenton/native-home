#if os(iOS)
import HassDesign
import UIKit

/// Content fades out before it reaches the header, and the header draws no band of its own: the UIKit counterpart of
/// ``SwiftUICore/View/headerEdgeFade()`` (`.agents/patterns/header-edge-fade.md`).
///
/// A gradient mask on the page's content view: clear over the header, then a ``HeaderEdgeFade/rampHeight`` ramp whose top stop
/// follows the scroll offset (opaque at rest, so a page at rest looks untouched; transparent once scrolled a ramp's length).
/// The geometry is the shared ``HeaderEdgeFade``; this class only reads the page's scroll view (KVO on `contentOffset`, whole
/// points clamped to the ramp, so only a change that moves the mask reaches it) and its safe area, and writes the mask.
@MainActor
final class UKHeaderEdgeFade {
    private weak var masked: UIView?
    private weak var scrollView: UIScrollView?
    private let gradient = CAGradientLayer()
    private var offsetObservation: NSKeyValueObservation?
    private var scrollOffset: CGFloat = 0
    private var smallestInset: CGFloat?
    private var lastSize: CGSize = .zero
    private var lastApplied: String?
    /// Where the inline bar ends (``HeaderEdgeFade/edgeCap(statusTop:barHeight:barIsRail:)``); nil for a sheet.
    var cap: CGFloat? { didSet { if cap != oldValue { apply() } } }
    /// Reduce Transparency and Increase Contrast turn the ramp into a hard cut (``HeaderEdgeFade/ramp(reduceTransparency:increaseContrast:tracksScroll:)``).
    var reduceTransparency = false { didSet { apply() } }
    var increaseContrast = false { didSet { apply() } }

    /// iOS 26 and later draw the header edge with the system's soft scroll edge effect. `FENTON_PERF_DISABLE=ukSoftEdge` forces the
    /// mask back for A/B runs (Debug builds).
    static var usesSoftEdge: Bool {
        if UKPerfSwitches.isOff(.ukSoftEdge) { return false }
        return UKGlassEra.hasGlass
    }

    /// Gives `scroll` the soft top edge effect (`headerSoftEdge()`, header-edge-fade R10) on iOS 26+; hides the effect when the
    /// mask draws the edge instead.
    static func applySoftEdge(to scroll: UIScrollView) {
        guard #available(iOS 26.0, *) else { return }
        scroll.topEdgeEffect.isHidden = !usesSoftEdge
        if usesSoftEdge { scroll.topEdgeEffect.style = .soft }
    }

    /// The mask is installed on `view`'s layer.
    init(masking view: UIView) {
        masked = view
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        // iOS 26 and later: the system's soft scroll-edge effect (``UKPageViewController``), no mask (header-edge-fade R10).
        if Self.usesSoftEdge { return }
        guard !PerfSwitches.isOff(.headerFade), !PerfSwitches.isOff(.fadeMask) else { return }
        view.layer.mask = gradient
    }

    /// Follows `scroll`'s offset; nil stops following (a page with no scroll view keeps the ramp's resting state).
    func follow(_ scroll: UIScrollView?) {
        offsetObservation = nil
        scrollView = scroll
        scrollOffset = 0
        guard !Self.usesSoftEdge else { return }
        guard let scroll, !PerfSwitches.isOff(.headerFade), !PerfSwitches.isOff(.fadeReaders), !PerfSwitches.isOff(.fadeScroll) else {
            apply()
            return
        }
        offsetObservation = scroll.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scroll, _ in
            MainActor.assumeIsolated { self?.report(scroll) }
        }
    }

    private func report(_ scroll: UIScrollView) {
        let value = HeaderEdgeFade.trackedOffset(contentOffset: scroll.contentOffset.y, topInset: scroll.adjustedContentInset.top)
        guard value != scrollOffset else { return }
        scrollOffset = value
        apply()
    }

    /// Call from the page's `viewDidLayoutSubviews` / `viewSafeAreaInsetsDidChange`: reads the safe area and rewrites the mask.
    func layoutChanged() {
        guard let view = masked else { return }
        let size = CGSize(width: view.bounds.width.rounded(), height: view.bounds.height.rounded())
        // A new size (rotation, fold, resize) starts over: the bar's height may have changed.
        if size != lastSize {
            lastSize = size
            smallestInset = nil
        }
        let inset = view.safeAreaInsets.top.rounded()
        if inset > 0, inset < (smallestInset ?? .infinity) { smallestInset = inset }
        apply()
    }

    private var tracksScroll: Bool {
        UKGlassEra.hasIOS18
    }

    private func apply() {
        guard let view = masked, view.layer.mask === gradient, view.bounds.height > 0 else { return }
        let height = view.bounds.height
        let ramp = HeaderEdgeFade.ramp(reduceTransparency: reduceTransparency, increaseContrast: increaseContrast, tracksScroll: tracksScroll)
        let readsGeometry = !PerfSwitches.isOff(.fadeReaders) && !PerfSwitches.isOff(.fadeGeometry)
        let header = readsGeometry
            ? HeaderEdgeFade.clearHeight(header: HeaderEdgeFade.headerHeight(safeAreaInset: view.safeAreaInsets.top.rounded(), containerOffset: 0),
                                        smallestInset: smallestInset, cap: cap)
            : 0
        let progress = HeaderEdgeFade.progress(scrollOffset: scrollOffset, rampHeight: ramp)
        let edge = HeaderEdgeFade.edgeOpacity(progress: progress)
        let key = "\(height)|\(header)|\(ramp)|\(edge)"
        guard key != lastApplied else { return }
        lastApplied = key
        let start = min(max(header / height, 0), 1)
        let end = min(max((header + ramp) / height, start), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = view.bounds
        gradient.colors = [
            UIColor.clear.cgColor, UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(edge).cgColor, UIColor.black.cgColor, UIColor.black.cgColor,
        ]
        gradient.locations = [0, NSNumber(value: start), NSNumber(value: start), NSNumber(value: end), 1]
        CATransaction.commit()
    }
}
#endif
