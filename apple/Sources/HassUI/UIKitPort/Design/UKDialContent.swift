#if os(iOS)
import HassCore
import UIKit

// MARK: - What a dial draws

/// What one line in the middle of a dial shows: its words, the words it keeps while it has none, or the pending bar while it loads.
enum UKDialLineValue: Equatable {
    case text(String)
    case unavailable
    case loading
}

/// The numbers and words a ``UKDialView`` places, read from the document's operands: the pointer's reading in the dial's own scale and one value for
/// each line in the middle. A `nil` value is "not known": the pointer is hidden and the letters that need a value are dropped.
struct UKDialReading: Equatable {
    var value: Double?
    var lines: [UKDialLineValue] = []
}
#endif
