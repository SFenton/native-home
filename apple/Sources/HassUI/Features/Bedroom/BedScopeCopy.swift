import HassCore
import HassDesign
import SwiftUI

// MARK: - Scope prompt

/// The words of "Tonight or All Nights?", asked after a target change during a schedule stage (web
/// `BedTemperatureScopePrompt`). Kept in one place so the alerts work can fold them into `AlertCopy`.
enum BedScopeCopy {
    static let title = "Set Bed Temperature"
    static let tonight = "Tonight"
    static let allNights = "All Nights"

    /// "Bed • Asleep • +5" and what each choice does.
    static func message(bed: String, request: BedSideController.ScopeRequest) -> String {
        "\(bed) • \(request.phase.label) • \(request.targetText)\n"
            + "Tonight changes the current Pod target only. All Nights also becomes the \(request.phase.label) setting for future nights. Cancel keeps the new target for tonight only."
    }
}
