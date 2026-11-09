import HassDesign
import SwiftUI

/// A labelled 0...100 slider in steps of 5 that shows and speaks its value (web `RangeField`).
struct PercentSliderRow {
    var title: String
    var identifier: String



    /// The value after a VoiceOver swipe: steps of 5 within 0...100.
    static func adjusted(_ value: Double, _ direction: AccessibilityAdjustmentDirection) -> Double {
        switch direction {
        case .increment: adjusted(value, increment: true)
        case .decrement: adjusted(value, increment: false)
        @unknown default: value
        }
    }

    /// The value after one step up or down (shared with the UIKit row): steps of 5 within 0...100.
    static func adjusted(_ value: Double, increment: Bool) -> Double {
        increment ? min(100, value + 5) : max(0, value - 5)
    }
}
