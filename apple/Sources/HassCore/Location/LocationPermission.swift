import Foundation

/// The app's location permission, free of Core Location (`CLAuthorizationStatus` plus `CLAccuracyAuthorization`).
public struct LocationPermission: Equatable, Sendable {
    /// What the person allowed.
    public enum Authorization: Equatable, Sendable {
        /// Not asked yet.
        case notDetermined
        /// Parental controls or a profile block it; the person cannot change it.
        case restricted
        /// The person said no, or turned Location Services off.
        case denied
        /// While Using the App.
        case whenInUse
        /// Always.
        case always
    }

    /// What the person allowed.
    public var authorization: Authorization
    /// Whether Precise Location is on. Approximate fixes are kilometers wide and cannot place anyone in a zone.
    public var isPrecise: Bool

    /// Creates a permission value.
    public init(authorization: Authorization, isPrecise: Bool = true) {
        self.authorization = authorization
        self.isPrecise = isPrecise
    }

    /// Not asked yet.
    public static let notDetermined = LocationPermission(authorization: .notDetermined)

    /// Whether the app may read location at all.
    public var isAuthorized: Bool { authorization == .whenInUse || authorization == .always }

    /// Whether zone and significant-change monitoring can wake the app in the background.
    public var allowsBackgroundReporting: Bool { authorization == .always && isPrecise }

    /// The step the permission screen shows.
    public var stage: Stage {
        switch authorization {
        case .notDetermined: .notDetermined
        case .restricted, .denied: .denied
        case .whenInUse: isPrecise ? .whenInUse : .reducedAccuracy
        case .always: isPrecise ? .always : .reducedAccuracy
        }
    }

    /// The permission screen's states (`.agents/pages/settings/location.md`).
    public enum Stage: String, CaseIterable, Sendable {
        /// Ask for While Using the App.
        case notDetermined = "not-determined"
        /// Offer the upgrade to Always.
        case whenInUse = "when-in-use"
        /// Everything Home and Away needs.
        case always
        /// Off: the only way back is Settings.
        case denied
        /// Allowed, but Precise Location is off: fix it in Settings.
        case reducedAccuracy = "reduced-accuracy"
    }

    /// The official app's "Location permission" sensor state for this authorization.
    public var sensorState: String {
        switch authorization {
        case .notDetermined: "Not determined"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .whenInUse: "Authorized when in use"
        case .always: "Authorized Always"
        }
    }
}
