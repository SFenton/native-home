#if os(iOS)
import HassCore
import UIKit

// MARK: - What a linear gauge draws

/// The numbers a ``UKLinearGaugeView`` places, read from the document's operands: the marker's reading and the span's start and size, in the
/// gauge's own scale. A `nil` is "not known": the marker is hidden and a missing span number is 0.
struct UKGaugeReading: Equatable {
    var value: Double?
    var spanStart: Double?
    var spanSize: Double?
}

/// What a gauge tells an assistive technology: nothing, or a name and a value.
enum UKGaugeSpeech: Equatable {
    /// The rail is decoration.
    case hidden
    /// One element named `label`. Its value is `value`, or the marker's percent when the document gives none.
    case value(label: String, value: String?)
}
#endif
