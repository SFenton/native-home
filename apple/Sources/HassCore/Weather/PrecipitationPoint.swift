import Foundation

/// One hour of the precipitation charts.
public struct PrecipitationPoint: Equatable, Sendable {
    /// Hourly accumulation; `nil` when the provider gave none.
    public var amount: Double?
    /// Running total; `nil` from the first missing hour on (a gap makes the total unknowable).
    public var cumulative: Double?
    public var endTime: Date?
    public var index: Int
    /// 0...100.
    public var probability: Double?
    public var startTime: Date?
}
