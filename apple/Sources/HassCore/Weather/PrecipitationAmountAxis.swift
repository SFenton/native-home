import Foundation

/// An axis for the accumulation chart.
public struct PrecipitationAmountAxis: Equatable, Sendable {
    public var domain: Double
    public var maximumFractionDigits: Int
    public var step: Double
}
