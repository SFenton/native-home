import SwiftUI

/// The only animation values in the app (design: `.agents/design/motion.md` §7; pattern: `.agents/patterns/motion.md`).
///
/// Call sites never write a duration: they pick a token and pass it to ``SwiftUICore/View/motionSafeAnimation(_:reduced:value:)``
/// or `withAnimation`. Navigation (push, sheet, zoom, tab) uses the system's own motion and has no token.
/// ``ContentGateModel`` keeps its own profile constants (`.agents/patterns/content-gate.md`).
public enum MotionTokens {
    /// Numbers, small fades and button state: `easeOut`, 0.2 s.
    public static let quick: Animation = .easeOut(duration: 0.2)
    /// Every background, fill, tint and rim colour that changes with state: `easeInOut`, 0.6 s, the status chip's timing the
    /// owner approved. Nothing moves in a colour fade, so its length never delays a tap. Use ``stateReduced`` under Reduce
    /// Motion (``SwiftUICore/View/stateColorTransition(_:value:)`` does).
    public static let state: Animation = .easeInOut(duration: 0.6)
    /// ``state`` under Reduce Motion: still a cross-fade (a colour change is not motion), shorter: 0.2 s.
    public static let stateReduced: Animation = .easeInOut(duration: stateReducedDuration)
    /// Layout a person caused (rows in or out, an expanding section, a pane): a smooth spring of 0.3 s with no bounce.
    public static let standard: Animation = .smooth(duration: 0.3)
    /// A selected-segment capsule gliding to its neighbour (`BadgedTabSegment`): `snappy`, 0.2 s.
    public static let segment: Animation = .snappy(duration: segmentDuration)
    /// One panel's content cross-fading when its own tab changes (`SummaryPanel`): `easeInOut`, 0.15 s. The longer swap with a layout
    /// change is `UKSmoothContentSwapView`, which chains its fades by completion and keeps its own timing like ``ContentGateModel``.
    public static let contentFade: Animation = .easeInOut(duration: contentFadeDuration)
    /// The house-and-heart mark in the intro, and nothing else: a spring of 0.5 s with a 0.2 bounce.
    public static let emphasized: Animation = .spring(duration: emphasizedDuration, bounce: emphasizedBounce)

    /// Seconds between one arrival item and the next (the sign-in arrival's stagger, first ``Arrival/staggerLimit`` items only).
    public static let arrivalStagger: Double = 0.06
    /// What an arrival item uses to fade and rise (no bounce), before its stagger delay.
    public static let arrival: Animation = .smooth(duration: 0.3)
    /// A moment under Reduce Motion: a cross-fade of about 0.35 s, with no rise, scale, spring or stagger.
    public static let reducedMoment: Animation = .easeInOut(duration: 0.35)

    // MARK: The sign-in lane's names

    // The sign-in lane (`claude/signin-and-launch-motion`) wrote its tokens first; its call sites use these names, so they stay.
    // `state` is the one value that differs from its draft: the owner set it to the status chip's 0.6 s on 2026-10-18.

    /// ``quick``'s duration, in seconds.
    public static let quickDuration: TimeInterval = 0.2
    /// ``stateReduced``'s duration, in seconds.
    public static let stateReducedDuration: TimeInterval = 0.2
    /// ``state``'s duration, in seconds.
    public static let stateDuration: TimeInterval = 0.6
    /// ``standard``'s duration, in seconds.
    public static let standardDuration: TimeInterval = 0.3
    /// What Reduce Motion allows instead of movement in a moment: a cross-fade of about a third of a second (``reducedMoment``).
    public static let crossFadeDuration: TimeInterval = 0.35
    public static var crossFade: Animation { reducedMoment }
    /// A button shrinking under a finger.
    public static var press: Animation { .easeOut(duration: pressDuration) }

    // MARK: Durations the UIKit port reads (`UKMotion`); the animations above are built from them.

    /// ``stateReduced``'s duration, in seconds.

    /// ``segment``'s duration, in seconds (a snappy spring, bounce 0.15).
    public static let segmentDuration: TimeInterval = 0.2
    /// ``contentFade``'s duration, in seconds.
    public static let contentFadeDuration: TimeInterval = 0.15
    /// ``emphasized``'s duration, in seconds, and its bounce.
    public static let emphasizedDuration: TimeInterval = 0.5
    public static let emphasizedBounce: Double = 0.2
    /// ``press``'s duration, in seconds.
    public static let pressDuration: TimeInterval = 0.12

    /// The launch sequence on the sign-in screen, about 1.2 s in all (a moment: the one place motion may run past 0.4 s).
    public enum Intro {
        /// The glow fading up from the plain launch ground.
        public static var glow: Animation { .easeOut(duration: 0.5) }
        /// Seconds before the mark starts, then the mark's rise to its peak (0.86 to 1.03).
        public static let markDelay: TimeInterval = 0.15
        public static let markRiseDuration: TimeInterval = 0.28
        public static var markRise: Animation { .easeOut(duration: markRiseDuration) }
        public static let markStart: CGFloat = 0.86
        public static let markPeak: CGFloat = 1.03
        /// The title and subtitle fading up by 10 pt, starting 0.46 s in (as the mark's rise ends).
        public static let titleDelay: TimeInterval = 0.46
        public static var title: Animation { .easeOut(duration: 0.4) }
        public static let titleRise: CGFloat = 10
        /// The form rising 28 pt, starting 0.71 s in, so the whole sequence ends at 1.16 s.
        public static let formDelay: TimeInterval = 0.71
        public static var form: Animation { .easeOut(duration: 0.45) }
        public static let formRise: CGFloat = 28
    }

    /// Home arriving after a sign-in, about 0.9 s in all.
    public enum Arrival {
        /// The sign-in layer lifting away.
        public static let liftDistance: CGFloat = -18
        public static let liftScale: CGFloat = 0.97
        public static var lift: Animation { .easeOut(duration: 0.4) }
        /// The house backdrop settling from 1.06 to 1.
        public static let backdropScale: CGFloat = 1.06
        public static var backdrop: Animation { .easeOut(duration: 0.6) }
        /// Cards rising 16 pt and chips sliding 30 pt, staggered ``MotionTokens/arrivalStagger`` apart from 0.2 s.
        public static let riseDistance: CGFloat = 16
        public static let slideDistance: CGFloat = 30
        public static let slideDelay: TimeInterval = 0.12
        public static let firstDelay: TimeInterval = 0.20
        /// Elements past this index come in with the last staggered one: the stagger is for the first screenful.
        public static let staggerLimit = 5
    }

    /// The label ticker (``TickerLabel``): the one constant-speed loop in the app, an exception to `.agents/design/motion.md`
    /// §9.6 and §9.10 because it runs only while its label overflows, and pauses on scroll, off screen and in the background.
    public enum Ticker {
        /// How fast the label travels, in points per second.
        public static let speed: CGFloat = 30
        /// Seconds the label holds at the start and again at the end of each pass.
        public static let hold: TimeInterval = 1.5
        /// Seconds the label takes to return from the end to the start (`standard`'s length, eased out).
        public static let returnDuration: TimeInterval = 0.3
        /// Passes played after the label appears or its text changes, then it rests at the start.
        public static let passes = 3
        /// Width of the soft fade at each edge, in points.
        public static let fadeWidth: CGFloat = 12
        /// A label wider than its column by more than this overflows (absorbs sub-point measuring noise).
        public static let overflowTolerance: CGFloat = 0.5
    }
}
