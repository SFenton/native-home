import SwiftUI

/// The one haptic vocabulary of the app (pattern: `.agents/patterns/tap-feedback.md`; owner decision 2026-10-24,
/// HIG: [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)).
///
/// Every control that changes the house plays ``tap`` when it is tapped, ``step`` for each detent of a slider,
/// ``failure`` when its call fails, and ``confirmation`` when a scan or an answer lands. Doors and the alarm
/// get no heavier impact: the weight of a haptic never carries meaning, only the family does. There is no late
/// success haptic for a slow device: Home Assistant may take seconds, and a buzz that late reads as a second tap.
public enum TapFeedback {
    /// A tap on a switch, key or command: a light impact, the media pad's feel.
    public static let tap = SensoryFeedback.impact(weight: .light)
    /// One detent of a slider or dial.
    public static let step = SensoryFeedback.selection
    /// A call that failed or an answer that was refused.
    public static let failure = SensoryFeedback.error
    /// A scan or other input that was read.
    public static let confirmation = SensoryFeedback.success
}

/// A tap counter a control bumps from its action, so ``View/tapFeedback(_:trigger:)`` fires once per tap.
public struct TapCounter: Equatable, Sendable {
    /// Taps so far.
    public private(set) var count = 0

    /// Creates a counter at zero.
    public init() {}

    /// Records a tap.
    public mutating func tap() { count &+= 1 }
}
