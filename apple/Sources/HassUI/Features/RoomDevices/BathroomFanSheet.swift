import HassCore
import HassDesign
import SwiftUI

/// The fan's controls, separate from the chrome so hosted tests render them directly.
struct BathroomFanControls {

    /// The idle timer's footnote. True to the fan script: `timer_start` ends with `switch.turn_on`.
    static let timerFootnote = "The fan runs, then turns itself off. Starting a timer turns it on if it's off."



}
