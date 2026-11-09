#if os(iOS)
import HassDesign
import UIKit

/// Push and pop on the single-page layouts (iPhone, folded Duo, Duo and iPad portrait) move like the columns do (owner, 2026-11-02,
/// `.agents/design/single-page-motion.md`): both pages travel a full width over the one wallpaper behind the window, the new page in
/// from the trailing edge and the old one out by the leading edge, on ``UKMotion/Token/standard``, with no dim, no shadow and no
/// fade. Back reverses it. The pages are transparent, so nothing else is needed to keep the wallpaper still.
///
/// Three parts, installed on a `UINavigationController` by ``UKStackMotion``:
/// - ``UKStackTransition``: the `UIViewControllerAnimatedTransitioning` for one push or pop, built on a `UIViewPropertyAnimator` so the
///   interactive pop can scrub it;
/// - ``UKStackInteraction``: the `UIPercentDrivenInteractiveTransition` the edge swipe drives (completes past half or on a flick,
///   otherwise the animator reverses);
/// - the edge pan itself, which replaces the system's `interactivePopGestureRecognizer` (and on iOS 26 its content swipe, which stays
///   off for now so the swipe is the same on every OS).
///
/// **Reduce Motion** turns the slide into a 0.2 s cross-fade (``UKMotion/Token/quick``); the swipe still pops, and it scrubs the fade.
@MainActor
final class UKStackMotion: NSObject, UIGestureRecognizerDelegate, UINavigationControllerDelegate {
    private weak var navigation: UINavigationController?
    private let isEnabled: () -> Bool
    /// Reduce Motion, read when a transition starts; tests replace it.
    var reduceMotion: () -> Bool = { UKMotion.reduceMotion }
    /// Tells VoiceOver the screen changed after an animated push or pop; tests replace it.
    var announceScreenChange: () -> Void = { Announcer.screenChanged() }
    private let pan = UIScreenEdgePanGestureRecognizer()
    /// The swipe in progress; the delegate hands it to UIKit when the pop it started asks for an interaction controller.
    private(set) var interaction: UKStackInteraction?
    /// How far the finger has to go, as a fraction of the width, for a let-go to complete; and the speed that completes it regardless.
    static let completionFraction: CGFloat = 0.5
    static let completionVelocity: CGFloat = 600

    /// - Parameters:
    ///   - navigation: The stack to move.
    ///   - isEnabled: False while something else shows the stack's routes (the columns of a wide Settings): no animation controller
    ///     is returned and the swipe does not begin.
    init(navigation: UINavigationController, isEnabled: @escaping () -> Bool = { true }) {
        self.navigation = navigation
        self.isEnabled = isEnabled
        super.init()
        pan.edges = navigation.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        pan.delegate = self
        pan.addTarget(self, action: #selector(panned(_:)))
        pan.name = "UKStackMotion.edgePan"
        navigation.view.addGestureRecognizer(pan)
        silenceSystemGestures()
    }

    /// The system's edge pop and the iOS 26 content pop stay off: the edge pan above pops through the animator. UIKit re-enables the
    /// first when the stack changes, so this runs after every transition too.
    func silenceSystemGestures() {
        navigation?.interactivePopGestureRecognizer?.isEnabled = false
        if #available(iOS 26.0, *) { navigation?.interactiveContentPopGestureRecognizer?.isEnabled = false }
    }

    /// The edge pan that drives the swipe back (tests).
    var edgePanRecognizer: UIScreenEdgePanGestureRecognizer { pan }

    // MARK: Navigation controller delegate

    // The pieces of `UINavigationControllerDelegate` this type owns. A stack whose controller is its own delegate (the section's)
    // forwards these; a plain one (the gallery host) sets this object as its delegate.

    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        guard isEnabled(), operation != .none else { return nil }
        return UKStackTransition(isPush: operation == .push, isInteractive: interaction != nil,
                                 rightToLeft: navigationController.view.effectiveUserInterfaceLayoutDirection == .rightToLeft,
                                 reduceMotion: reduceMotion())
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        animationController is UKStackTransition ? interaction : nil
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        silenceSystemGestures()
        // The custom transition replaces the system's, so tell VoiceOver the screen changed once the page has landed: focus moves to the
        // page's first element, and the page that left is not reachable (HIG, Accessibility: VoiceOver).
        if animated, isEnabled() { announceScreenChange() }
    }

    // MARK: The swipe

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, isEnabled(), let navigation else { return false }
        guard navigation.viewControllers.count > 1, navigation.transitionCoordinator == nil else { return false }
        // A column host on top (the Food hub, a wide to-do page) whose columns have a page to close: their edge pan takes this swipe.
        // At its root column the stack pops the host.
        if (navigation.topViewController as? UKColumnsHosting)?.columns.takesEdgePan == true { return false }
        return navigation.topViewController?.navigationItem.hidesBackButton != true
    }

    /// Only an edge pan from outside the stack (the flyout's, on the shell's view, which sits at a section root and never begins
    /// deeper) runs alongside; the columns' pan inside it never does (see ``gestureRecognizerShouldBegin(_:)``). The page's scroll
    /// views do not: they wait for the swipe to fail (``gestureRecognizer(_:shouldBeRequiredToFailBy:)``) and are cancelled once it
    /// begins, so a pop never scrolls the page (HIG, Gestures: respond as people expect; the system pop is exclusive too).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        guard other is UIScreenEdgePanGestureRecognizer, let root = navigation?.view else { return false }
        return !(other.view?.isDescendant(of: root) ?? false)
    }

    /// The pan of any scroll view inside the stack (the page's, a horizontal rail's) waits for the edge pan to fail. The edge pan fails
    /// at once for a touch that does not start at the edge, so scrolling elsewhere is not delayed.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, let scroll = other.view as? UIScrollView, other === scroll.panGestureRecognizer,
              let root = navigation?.view else { return false }
        return scroll.isDescendant(of: root)
    }

    @objc private func panned(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let sign: CGFloat = recognizer.edges == .right ? -1 : 1
        let progress = min(max(sign * recognizer.translation(in: view).x / max(view.bounds.width, 1), 0), 1)
        switch recognizer.state {
        case .began: beginSwipe()
        case .changed: updateSwipe(progress: progress)
        case .ended: endSwipe(progress: progress, velocity: sign * recognizer.velocity(in: view).x)
        case .cancelled, .failed: endSwipe(progress: 0, velocity: 0, cancelled: true)
        default: break
        }
    }

    /// Whether letting go at `progress` (0 to 1 of the width) with `velocity` (points per second toward the trailing edge) completes
    /// the pop.
    static func completes(progress: CGFloat, velocity: CGFloat) -> Bool {
        progress > completionFraction || velocity > completionVelocity
    }

    /// Starts the pop the swipe drives; the pages then follow ``updateSwipe(progress:)``.
    func beginSwipe() {
        guard let navigation, interaction == nil else { return }
        interaction = UKStackInteraction()
        navigation.popViewController(animated: true)
    }

    func updateSwipe(progress: CGFloat) {
        interaction?.update(min(max(progress, 0), 1))
    }

    /// Lets go of the swipe: completes the pop past halfway or on a flick, otherwise reverses it.
    func endSwipe(progress: CGFloat, velocity: CGFloat, cancelled: Bool = false) {
        guard let interaction else { return }
        self.interaction = nil
        if !cancelled, Self.completes(progress: progress, velocity: velocity) { interaction.finish() } else { interaction.cancel() }
    }
}

/// What the edge swipe drives. A plain `UIPercentDrivenInteractiveTransition`: the animator is a paused `UIViewPropertyAnimator`, so
/// the pages follow the finger 1:1 (``UKStackTransition`` scrubs linearly) and let-go continues or reverses it.
@MainActor
final class UKStackInteraction: UIPercentDrivenInteractiveTransition {}

/// One push or pop.
@MainActor
final class UKStackTransition: NSObject, UIViewControllerAnimatedTransitioning {
    let isPush: Bool
    let isInteractive: Bool
    /// Slides run opposite ways in a right-to-left layout.
    private let direction: CGFloat
    /// Read once per transition: Reduce Motion changes the next one, not this one.
    let reduceMotion: Bool
    private var animator: UIViewPropertyAnimator?

    init(isPush: Bool, isInteractive: Bool = false, rightToLeft: Bool = false, reduceMotion: Bool = UKMotion.reduceMotion) {
        self.isPush = isPush
        self.isInteractive = isInteractive
        self.reduceMotion = reduceMotion
        direction = rightToLeft ? -1 : 1
    }

    /// The token this transition runs on: the column motion, or the cross-fade under Reduce Motion.
    var token: UKMotion.Token { reduceMotion ? .quick : .standard }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval { token.duration }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        makeAnimator(transitionContext).startAnimation()
    }

    func interruptibleAnimator(using transitionContext: any UIViewControllerContextTransitioning) -> any UIViewImplicitlyAnimating {
        makeAnimator(transitionContext)
    }

    private func makeAnimator(_ context: any UIViewControllerContextTransitioning) -> UIViewPropertyAnimator {
        if let animator { return animator }
        let container = context.containerView
        let from = context.view(forKey: .from)
        let to = context.view(forKey: .to)
        let width = container.bounds.width
        let slide = (isPush ? 1 : -1) * direction * width
        if let to {
            to.frame = container.bounds
            if to.superview !== container { container.addSubview(to) }
            // Lay the destination out now, before the first frame: its build is not part of the slide, and a layout the commit does
            // later lands in the animation's first turn (`.agents/design/motion.md` §4.2).
            to.layoutIfNeeded()
            if reduceMotion { to.alpha = 0 } else { to.transform = CGAffineTransform(translationX: slide, y: 0) }
        }
        let animator = UIViewPropertyAnimator(duration: token.duration, timingParameters: token.timingParameters)
        animator.scrubsLinearly = true
        animator.addAnimations {
            if self.reduceMotion {
                to?.alpha = 1
                from?.alpha = 0
            } else {
                to?.transform = .identity
                from?.transform = CGAffineTransform(translationX: -slide, y: 0)
            }
        }
        animator.addCompletion { _ in
            let finished = !context.transitionWasCancelled
            for view in [from, to] {
                view?.transform = .identity
                view?.alpha = 1
            }
            context.completeTransition(finished)
        }
        self.animator = animator
        return animator
    }
}
#endif
