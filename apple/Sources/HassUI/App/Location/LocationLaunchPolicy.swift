import Foundation

/// Whether this launch reports location (`.agents/platforms/apple/location.md`).
public enum LocationLaunchPolicy {
    /// Every iOS device reports location (owner, 2026-10-27; an iPad reports but is never linked to a person, see
    /// ``LocationReporter/linksPresence``). Debug UI journeys (a test token, a reset launch, or the component gallery) keep it off unless
    /// `FENTON_LOCATION=1`, so a journey never meets the permission alert unasked.
    /// - Parameter environment: The launch environment.
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        #if DEBUG
        if environment["FENTON_LOCATION"] == "1" { return true }
        let journey = ["FENTON_HASS_TOKEN", "FENTON_UITEST_RESET", "FENTON_GALLERY"].contains { !(environment[$0] ?? "").isEmpty }
        return !journey
        #else
        return true
        #endif
    }
}
