#if os(iOS)
import UIKit

/// Whether a view is actually on screen: in a window whose scene is foreground-active, not hidden or transparent anywhere up the
/// chain, inside the visible bounds of every clipping ancestor (a scroll view's viewport above all), and not in the middle of a
/// window size change (rotation, fold).
///
/// Shared by both apps. A view "in a window" is not on screen: a tile below the fold of a scroll view is in the window, and a
/// Metal video view there still decodes, draws and waits on `CAMetalLayer.nextDrawable` on the main thread (measured on the iPhone
/// Duo simulator 2026-10-31: 45 to 70% of main-thread samples at idle on Home). The owner of a video surface asks this monitor and
/// detaches the video while it says no. See `.agents/patterns/camera-streams.md`, "Video draws only while on screen".
///
/// The owner forwards `didMoveToWindow` and `layoutSubviews`; the monitor re-evaluates on those, on every enclosing scroll view's
/// `contentOffset`, and on the scene's activation changes, and calls ``onChange`` only when the answer changes.
@MainActor
final class OnScreenMonitor {
    /// How long after the last window size change the view still counts as in a transition (rotation animations run about 0.35 s).
    static let transitionSettle: Duration = .milliseconds(450)

    private weak var view: UIView?
    private let onChange: @MainActor (Bool) -> Void
    private(set) var isOnScreen = false
    private var observers: [NSObjectProtocol] = []
    private var offsetObservations: [NSKeyValueObservation] = []
    private var lastWindowSize: CGSize?
    private var inTransition = false
    private var settleTask: Task<Void, Never>?

    init(view: UIView, onChange: @escaping @MainActor (Bool) -> Void) {
        self.view = view
        self.onChange = onChange
    }

    isolated deinit {
        settleTask?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Call from `didMoveToWindow`.
    func windowDidChange() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        offsetObservations = []
        settleTask?.cancel()
        inTransition = false
        lastWindowSize = view?.window?.bounds.size
        if let window = view?.window {
            let center = NotificationCenter.default
            for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification] {
                observers.append(center.addObserver(forName: name, object: window.windowScene, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.evaluate() }
                })
            }
            var ancestor = view?.superview
            while let current = ancestor {
                if let scroll = current as? UIScrollView {
                    offsetObservations.append(scroll.observe(\.contentOffset, options: []) { [weak self] _, _ in
                        MainActor.assumeIsolated { self?.evaluate() }
                    })
                }
                ancestor = current.superview
            }
        }
        evaluate()
    }

    /// Call from `layoutSubviews` (a window size change shows up here first).
    func layoutDidRun() {
        if let size = view?.window?.bounds.size {
            if let last = lastWindowSize, last != size { beginTransition() }
            lastWindowSize = size
        }
        evaluate()
    }

    private func beginTransition() {
        inTransition = true
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.transitionSettle)
            guard !Task.isCancelled, let self else { return }
            inTransition = false
            evaluate()
        }
    }

    /// Re-evaluates and reports a change.
    func evaluate() {
        let now = computeOnScreen()
        guard now != isOnScreen else { return }
        isOnScreen = now
        onChange(now)
    }

    private func computeOnScreen() -> Bool {
        guard let view, let window = view.window, !inTransition,
              window.windowScene?.activationState == .foregroundActive,
              view.bounds.width > 0, view.bounds.height > 0 else { return false }
        var rect = view.bounds
        var current: UIView? = view
        while let node = current {
            if node.isHidden || node.alpha < 0.01 { return false }
            guard let parent = node.superview else { break }
            rect = node.convert(rect, to: parent)
            if parent is UIScrollView || parent.clipsToBounds || parent === window {
                rect = rect.intersection(parent.bounds)
                if rect.isNull || rect.isEmpty { return false }
            }
            current = parent
        }
        return true
    }
}
#endif
