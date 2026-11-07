import Foundation

/// A one-time event in the app's motion (`.agents/design/motion.md` §1): it plays once per session and then never again.
public enum Moment: String, CaseIterable, Sendable {
    /// The first-launch intro on the sign-in screen.
    case intro
    /// Home arriving after a sign-in.
    case signInArrival
}
