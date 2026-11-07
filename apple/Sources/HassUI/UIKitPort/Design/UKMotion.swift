#if os(iOS)
import HassDesign
import UIKit

/// ``MotionTokens`` as UIKit animations (`.agents/design/motion.md` §7; the UIKit counterpart of `MotionSafeAnimation`).
///
/// Call sites never write a duration: they pick a token. Springs run through `UIView.animate(springDuration:bounce:…)`,
/// curves through `UIViewPropertyAnimator`, and layer properties through ``fade(_:keyPath:to:token:)``. Reduce Motion is read
/// at the moment of the animation, as `@Environment(\.accessibilityReduceMotion)` is at render time: pass `reduced:` for the
/// cross-fade that Reduce Motion allows, or leave it out and the change applies at once.
///
/// ```swift
/// UKMotion.animate(.standard) { stack.arrangedSubviews[1].isHidden = true; stack.layoutIfNeeded() }
/// UKMotion.animate(.state, reduced: .stateReduced) { background.backgroundColor = fill }
/// ```
@MainActor
public enum UKMotion {
    /// A ``MotionTokens`` animation.
    public enum Token: Sendable {
        /// Numbers, small fades and button state: ease out, 0.2 s.
        case quick
        /// Every state colour: ease in out, 0.6 s.
        case state
        /// ``state`` under Reduce Motion: 0.2 s.
        case stateReduced
        /// Layout a person caused: smooth spring of 0.3 s, no bounce.
        case standard
        /// A selected-segment capsule gliding: snappy spring, 0.2 s.
        case segment
        /// One panel's content cross-fading: ease in out, 0.15 s.
        case contentFade
        /// The intro mark only: spring of 0.5 s, bounce 0.2.
        case emphasized
        /// An arrival item fading and rising: smooth spring of 0.3 s.
        case arrival
        /// A moment under Reduce Motion: cross-fade of 0.35 s.
        case reducedMoment
        /// A button shrinking under a finger: ease out, 0.12 s.
        case press

        /// Seconds the token runs (a spring's settling duration).
        public var duration: TimeInterval {
            switch self {
            case .quick: MotionTokens.quickDuration
            case .state: MotionTokens.stateDuration
            case .stateReduced: MotionTokens.stateReducedDuration
            case .standard, .arrival: MotionTokens.standardDuration
            case .segment: MotionTokens.segmentDuration
            case .contentFade: MotionTokens.contentFadeDuration
            case .emphasized: MotionTokens.emphasizedDuration
            case .reducedMoment: MotionTokens.crossFadeDuration
            case .press: MotionTokens.pressDuration
            }
        }

        /// The spring's bounce, or nil for a timing curve.
        var bounce: Double? {
            switch self {
            case .standard, .arrival: 0
            case .segment: 0.15 // SwiftUI `.snappy`
            case .emphasized: MotionTokens.emphasizedBounce
            default: nil
            }
        }

        /// The timing curve of a non-spring token.
        var curve: UIView.AnimationCurve {
            switch self {
            case .state, .stateReduced, .contentFade, .reducedMoment: .easeInOut
            default: .easeOut
            }
        }

        /// The token as the timing of a `UIViewPropertyAnimator` that something else drives (an interactive transition): the spring of a
        /// spring token, else the curve. A scrubbed animator moves linearly with the finger whatever this is.
        var timingParameters: any UITimingCurveProvider {
            if let bounce { return UISpringTimingParameters(duration: duration, bounce: CGFloat(bounce)) }
            return UICubicTimingParameters(animationCurve: curve)
        }

        /// The same curve as a Core Animation timing function.
        var timingFunction: CAMediaTimingFunction {
            CAMediaTimingFunction(name: curve == .easeInOut ? .easeInEaseOut : .easeOut)
        }
    }

    #if DEBUG
    /// Tests only: forces ``reduceMotion`` on or off without touching the simulator's accessibility settings.
    public static var reduceMotionOverride: Bool?
    #endif

    /// Whether Reduce Motion is on.
    public static var reduceMotion: Bool {
        #if DEBUG
        if let reduceMotionOverride { return reduceMotionOverride }
        #endif
        return UIAccessibility.isReduceMotionEnabled
    }

    /// Runs `animations` with `token`, or with `reduced` (default: at once) when Reduce Motion is on.
    ///
    /// Never let a slide, scale, spring or layout move through ``reduced``; pass a short fade token only for an opacity or
    /// colour change.
    /// - Returns: The animator of a curve token, so a caller can stop it; nil for springs and immediate changes.
    @discardableResult
    public static func animate(_ token: Token, reduced: Token? = nil, delay: TimeInterval = 0,
                               animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) -> UIViewPropertyAnimator? {
        let effective: Token? = reduceMotion ? reduced : token
        guard let effective else {
            animations()
            completion?(true)
            return nil
        }
        if let bounce = effective.bounce {
            UIView.animate(springDuration: effective.duration, bounce: CGFloat(bounce), initialSpringVelocity: 0, delay: delay,
                           options: [.allowUserInteraction, .beginFromCurrentState], animations: animations, completion: completion)
            return nil
        }
        let animator = UIViewPropertyAnimator(duration: effective.duration, curve: effective.curve, animations: animations)
        animator.isInterruptible = true
        if let completion { animator.addCompletion { completion($0 == .end) } }
        animator.startAnimation(afterDelay: delay)
        return animator
    }

    /// A state colour change (`stateColorTransition`): 0.6 s, or 0.2 s under Reduce Motion (a colour change is not motion).
    @discardableResult
    public static func stateColor(_ animations: @escaping () -> Void) -> UIViewPropertyAnimator? {
        animate(.state, reduced: .stateReduced, animations: animations)
    }

    /// Cross-fades a layer property (a `CAShapeLayer`'s `fillColor`, `strokeColor`, `opacity`) to `value`: the layer's model
    /// value moves at once and a Core Animation interpolates from where it was shown.
    public static func fade(_ layer: CALayer, keyPath: String, to value: Any?, token: Token = .state, reduced: Token? = .stateReduced) {
        let effective: Token? = reduceMotion ? reduced : token
        let from = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        guard let effective else {
            layer.removeAnimation(forKey: "uk.fade.\(keyPath)")
            return
        }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = value
        animation.duration = effective.duration
        animation.timingFunction = effective.timingFunction
        layer.add(animation, forKey: "uk.fade.\(keyPath)")
    }

    /// A cross-dissolve of `view`'s contents (a foreground colour or glyph that follows state) with the state timing.
    public static func dissolve(_ view: UIView, token: Token = .state, reduced: Token? = .stateReduced, changes: @escaping () -> Void) {
        let effective: Token? = reduceMotion ? reduced : token
        guard let effective else {
            changes()
            return
        }
        UIView.transition(with: view, duration: effective.duration, options: [.transitionCrossDissolve, .allowUserInteraction],
                          animations: changes)
    }
}
#endif
