import SwiftUI

/// Helper the tinted glass finish uses to tell a filled or lit face from a neutral one.
extension TileFaceStyle {
    public var isFilledOrLit: Bool {
        switch self {
        case .filled, .lit, .colored: true
        default: false
        }
    }
}
