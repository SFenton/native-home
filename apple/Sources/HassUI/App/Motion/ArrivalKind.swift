import HassDesign
import Observation
import SwiftUI

/// How an element comes in as Home arrives.
public enum ArrivalKind: Sendable {
    /// Fades in and rises 16 pt, staggered by its index (cards, tiles).
    case rise
    /// Fades in and slides 30 pt from the right (the status chips).
    case slideIn
}
