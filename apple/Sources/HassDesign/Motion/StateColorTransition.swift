import Foundation
import os

/// Background, fill, tint and rim colours that change with state always cross-fade with ``MotionTokens/state`` (0.6 s, or 0.2 s
/// under Reduce Motion), whether the house or the person caused the change (design: `.agents/design/motion.md` §6; every
/// component: `.agents/design/motion-components.md`). The UIKit port animates them with `UKMotion.stateColor` and notes each
/// one in ``MotionAudit`` (debug and test builds), so a test fails when a component stops animating.
/// A registry of the components that animate a state colour, read by tests (`MotionAuditTests`). It records in debug and
/// test builds only; in a release build every call is empty.
///
/// Recording is off unless a test (or `FENTON_MOTION_AUDIT=1`) turns it on. ``capture(_:)`` collects the components one render
/// draws, so a component that drops its animation fails its own test.
public enum MotionAudit {
    #if DEBUG
    private struct State {
        var enabled = ProcessInfo.processInfo.environment["FENTON_MOTION_AUDIT"] == "1"
        var names: Set<String> = []
        var captured: Set<String>?
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    #endif

    /// Starts recording every component for the process (``components``).
    public static func enable() {
        #if DEBUG
        state.withLock { $0.enabled = true }
        #endif
    }

    /// Notes that `component` drew a state colour animation.
    public static func noteStateColor(_ component: String) {
        #if DEBUG
        state.withLock { state in
            if state.enabled { state.names.insert(component) }
            state.captured?.insert(component)
        }
        #endif
    }

    /// The components seen since ``enable()``.
    public static var components: Set<String> {
        #if DEBUG
        state.withLock { $0.names }
        #else
        []
        #endif
    }

    /// The components that drew a state colour animation while `body` ran. Main actor only, so parallel tests that render
    /// views cannot overlap.
    @MainActor
    public static func capture(_ body: () -> Void) -> Set<String> {
        #if DEBUG
        state.withLock { $0.captured = [] }
        body()
        return state.withLock { state in
            defer { state.captured = nil }
            return state.captured ?? []
        }
        #else
        body()
        return []
        #endif
    }
}
