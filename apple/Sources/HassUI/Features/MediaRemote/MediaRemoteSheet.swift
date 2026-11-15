import HassCore
import HassDesign
import SwiftUI

/// When the remote uses two columns (owner's split rules, `.agents/design/apple/split-view.md`).
enum MediaRemoteLayout {
    /// The narrowest sheet that holds the d-pad column beside the tab content.
    static let minimumTwoColumnWidth: CGFloat = 640

    /// Two columns only where the window may split (landscape, regular width) and the sheet is wide enough.
    static func usesTwoColumns(window: CGSize, isRegularWidth: Bool, container: CGSize) -> Bool {
        SplitPolicy.allowsSplit(size: window, isRegularWidth: isRegularWidth) && container.width >= minimumTwoColumnWidth
    }
}

/// The window the sheet is in. A sheet's own size class is compact on iPad, so layout decisions read the window.
struct WindowMetrics: Equatable {
    var size: CGSize?
    var isRegularWidth = false
}
