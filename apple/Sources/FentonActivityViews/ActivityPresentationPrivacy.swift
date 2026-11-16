import FentonActivityModel
import SwiftUI

extension View {
    /// Marks all authored activity content sensitive without changing existing activity rendering.
    func activityPresentationPrivacy(_ card: ActivityCard) -> some View {
        privacySensitive(card.presentation != nil)
    }
}
