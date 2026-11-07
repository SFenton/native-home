import HassCore
import HassDesign
import SwiftUI

// MARK: - Swipe and context menu

extension TodoListSection {


    /// The fill behind a swipe button.
    static func swipeTint(_ action: TodoRowActions.Action) -> Color {
        switch action {
        case .complete, .reopen: ColorFamily.occupancy.fill ?? .green
        default: Color(swipeTintToken(action))
        }
    }

    /// ``swipeTint(_:)`` as raw sRGB.
    static func swipeTintToken(_ action: TodoRowActions.Action) -> HassRGB {
        switch action {
        case .complete, .reopen: ColorFamily.occupancy.fillToken ?? HassRGB(red: 0, green: 0.5, blue: 0)
        case .edit: HassTokens.RGB.Ink.actionFill
        case .delete: HassTokens.RGB.Ink.badge
        }
    }
}
