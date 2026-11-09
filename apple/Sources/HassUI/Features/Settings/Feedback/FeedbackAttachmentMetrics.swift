import SwiftUI

/// Measurements of the feedback form's attachment thumbnails.
enum FeedbackAttachmentMetrics {
    /// The square thumbnail's side.
    static let side: CGFloat = 76
    /// The thumbnail's corner radius.
    static let cornerRadius: CGFloat = 12
    /// The thumbnail's inset from the tile's top and trailing edges, leaving room for the remove button's corner.
    static let thumbnailInset: CGFloat = 10
    /// How far the remove button sits beyond the thumbnail's top trailing corner; the tile reserves it on the trailing edge.
    static let removeReach: CGFloat = 12
}
