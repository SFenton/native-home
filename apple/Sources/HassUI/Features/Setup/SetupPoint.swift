import HassDesign
import SwiftUI

/// One "how it works" point on a Setup step: a title, and optionally a symbol and a line of detail.
struct SetupPoint: Equatable, Identifiable {
    /// The symbol of a plain bullet, for points that are only a line of text.
    static let bullet = "circle.fill"

    var symbol: String
    var title: String
    var detail: String?
    /// The accessibility identifier's last part; the symbol when nil.
    var key: String?
    var id: String { title }
}
