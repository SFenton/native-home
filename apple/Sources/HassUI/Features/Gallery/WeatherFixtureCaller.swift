#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// A `weather.get_forecasts` double that answers from ``WeatherFixtures``.
@MainActor
final class WeatherFixtureCaller: WeatherForecastCalling {
    enum Mode: String {
        case normal, loading, error, empty
    }

    struct Failure: LocalizedError {
        var errorDescription: String? { "Home Assistant could not reach Pirate Weather." }
    }

    private(set) var lastCall = "None"
    let mode: Mode

    init(mode: Mode) { self.mode = mode }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        let kind = WeatherForecastKind(rawValue: data["type"] as? String ?? "") ?? .daily
        lastCall = "\(domain).\(service) \(kind.rawValue)"
        switch mode {
        case .loading:
            try await Task.sleep(for: .seconds(3600))
            return .null
        case .error: throw Failure()
        case .empty: return WeatherFixtures.response([])
        case .normal: return WeatherFixtures.response(kind == .daily ? WeatherFixtures.daily() : WeatherFixtures.hourly())
        }
    }
}
#endif
