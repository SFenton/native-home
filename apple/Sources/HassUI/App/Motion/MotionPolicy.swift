import HassDesign
import HassTelemetry
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Which one-time moments have played this session, and whether Reduce Motion is on (design: `.agents/design/motion.md` §3, §8;
/// pattern: `.agents/patterns/motion.md`).
///
/// One instance per session: ``AppSession`` owns it and `RootView` puts it in the environment (`@Environment(MotionPolicy.self)`). A moment plays once, then never
/// again until the session ends: ``reset()`` runs at sign-out, so a second sign-in plays the arrival again. A cold launch that
/// resumes a saved sign-in marks the arrival as played, because nothing introduces the app to someone already in it.
@MainActor
@Observable
public final class MotionPolicy {
    /// The moments that have played this session.
    public private(set) var played: Set<Moment> = []

    /// Whether Reduce Motion is on right now (`UIAccessibility`, kept current by the system notification). Views read the
    /// environment's `accessibilityReduceMotion` instead; this is for code outside a view.
    public private(set) var reduceMotion: Bool

    @ObservationIgnored private let reduceMotionSource: @MainActor () -> Bool

    /// Creates the policy.
    /// - Parameter reduceMotion: Reads the system setting; tests inject a fake.
    public init(reduceMotion source: @escaping @MainActor () -> Bool = MotionPolicy.systemReduceMotion) {
        reduceMotionSource = source
        reduceMotion = source()
        Self.observeSystemChanges { [weak self] in self?.refreshReduceMotion() }
    }

    // MARK: Moments

    /// Whether `moment` has already played this session.
    public func hasPlayed(_ moment: Moment) -> Bool { played.contains(moment) }

    /// Records that `moment` played. The moment's owner calls it once its last item has been shown: the items of a staggered
    /// moment all read ``hasPlayed(_:)``, so marking earlier would cut the stagger short.
    public func markPlayed(_ moment: Moment) { played.insert(moment) }

    /// Forgets every moment, at sign-out, so the next sign-in plays its arrival (and the signed-out screen its intro) again.
    public func reset() { played.removeAll() }

    // MARK: Reduce Motion

    /// Reads the setting again (the system notification calls this).
    public func refreshReduceMotion() {
        let current = reduceMotionSource()
        if current != reduceMotion { reduceMotion = current }
    }

    /// The system's Reduce Motion setting.
    public static func systemReduceMotion() -> Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        false
        #endif
    }

    private static func observeSystemChanges(_ change: @escaping @MainActor () -> Void) {
        #if canImport(UIKit)
        let name = UIAccessibility.reduceMotionStatusDidChangeNotification
        let center = NotificationCenter.default
        #elseif canImport(AppKit)
        let name = NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        let center = NSWorkspace.shared.notificationCenter
        #endif
        // The policy lives as long as the session, which is the process; the observer holds it weakly.
        _ = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { change() }
        }
    }

    // MARK: Measurement

    /// Starts timing a navigation transition (``NavigationTransition``). Call it at the intent; the destination reports its
    /// first frame and settling through the returned measurement, or through ``SwiftUICore/View/measuresNavigation(_:page:)``.
    public func measure(_ transition: NavigationTransition) -> NavigationMeasurement {
        .begin(transition.surface, page: transition.page)
    }

    /// Times a transition that is a cut (a tab switch): its first frame and its settling are the next display tick.
    /// - Parameter onSettled: Called once the tick has passed and the measurement is recorded (tests).
    public func measureCut(_ transition: NavigationTransition, onSettled: (@MainActor () -> Void)? = nil) {
        let measurement = measure(transition)
        NextFrame.perform {
            measurement.settled()
            onSettled?()
        }
    }
}
