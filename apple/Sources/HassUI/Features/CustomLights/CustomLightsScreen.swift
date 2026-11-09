import HassCore
import HassDesign
import SwiftUI

// MARK: - Front yard rows

/// The manual control switch, the first row of the Front Yard list (direction G: switches only in list rows).
struct ManualControlRow {
    static let title = "Manually Control Front Yard Lights"
    var isOn: Bool
    var isUnavailable: Bool
    var set: (Bool) -> Void

}
