import HassCore
import HassDesign
import SwiftUI

// MARK: - Undo button

extension TodoItemRow {

    /// What VoiceOver hears after a tick that leaves the row listed with Undo.
    static func completionAnnouncement(_ title: String) -> String { "\(title) completed. Undo available" }
}
