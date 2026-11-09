import SwiftUI

private struct StaticTimerRingKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Draw a time-range ring as the fraction elapsed when the view was drawn, instead of `ProgressView(timerInterval:)`.
    ///
    /// Inside a Live Activity the system draws that ring and fills it as time passes. Inside an ordinary app view it draws an
    /// indeterminate spinner, so the debug gallery turns this on to show the ring the Lock Screen would.
    var activityStaticTimerRing: Bool {
        get { self[StaticTimerRingKey.self] }
        set { self[StaticTimerRingKey.self] = newValue }
    }
}
