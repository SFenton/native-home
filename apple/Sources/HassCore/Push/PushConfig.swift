import Foundation

/// What the S+H Home Integration (`SFenton/ha-fenton-push`) tells the app about push delivery:
/// `GET /api/fenton_home/config` (contract v1, rule 1).
public struct PushConfig: Equatable, Sendable {
    /// The integration can deliver alert pushes. When false the app registers without a push URL or token and
    /// receives only websocket pushes, and tries again on the next launch.
    public var available: Bool
    /// Where Home Assistant's `mobile_app` posts each notification: the integration's own APNs relay.
    public var pushURL: URL?
    /// The bundle the relay signs for; the app registers only when it matches its own.
    public var bundleID: String?
    /// Whether the integration sends true critical alerts (`aps.sound.critical`) rather than time-sensitive ones.
    public var criticalAlerts: Bool

    /// Creates a config.
    public init(available: Bool, pushURL: URL? = nil, bundleID: String? = nil, criticalAlerts: Bool = false) {
        self.available = available
        self.pushURL = pushURL
        self.bundleID = bundleID
        self.criticalAlerts = criticalAlerts
    }

    /// Parses the endpoint's JSON body; an unreadable body is unavailable.
    /// - Parameter data: The response body.
    public init(json data: Data) {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let url = (object["push_url"] as? String).flatMap(URL.init(string:))
        self.init(available: (object["available"] as? Bool ?? false) && url != nil,
                  pushURL: url,
                  bundleID: object["bundle_id"] as? String,
                  criticalAlerts: object["critical_alerts"] as? Bool ?? false)
    }
}
