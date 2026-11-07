import Foundation
import HassCore

/// Where the feedback form files reports: through Home Assistant's Fenton Home Feedback integration on the
/// signed-in server, or the fixture under `FENTON_FEEDBACK_FIXTURE` in Debug builds (`1` set up, `unavailable`
/// without the integration).
struct FeedbackServices: Sendable {
    var filer: any FeedbackFiling

    /// Resolves the services for the signed-in session.
    ///
    /// - Parameters:
    ///   - environment: Launch environment (the fixture switch).
    ///   - server: The signed-in Home Assistant.
    ///   - tokens: Its token manager; nil before sign-in (filing then reports `signedOut`).
    static func resolve(_ environment: [String: String], server: HassServer, tokens: TokenManager?) -> FeedbackServices {
        #if DEBUG
        switch environment["FENTON_FEEDBACK_FIXTURE"] {
        case "1": return FeedbackServices(filer: FeedbackFixtureFiler(delay: .milliseconds(400)))
        case "unavailable": return FeedbackServices(filer: FeedbackFixtureFiler(available: false, delay: .milliseconds(400)))
        default: break
        }
        #endif
        return FeedbackServices(filer: HomeAssistantFeedbackClient(server: server) {
            guard let tokens else { throw FeedbackFilingError.signedOut }
            return try await tokens.validAccessToken()
        })
    }
}
