import Foundation

/// How alarming a briefing's lead hazard is.
public enum WeatherBriefingSeverity: String, Codable, Sendable {
    case alert, caution, notable, calm

    var rank: Int {
        switch self {
        case .alert: 3
        case .caution: 2
        case .notable: 1
        case .calm: 0
        }
    }
}
