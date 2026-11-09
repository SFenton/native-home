import Foundation

/// Launch rules of the app's root (`UKRootViewController`): what VoiceOver hears on arrival, and whether the sign-in intro plays.
enum AppRoot {
    /// What VoiceOver hears when sign-in finishes and Home takes over.
    static let arrivalAnnouncement = "Signed in. Home"

    /// Whether the sign-in intro plays: while the session has not played it (a cold launch, or the first screen after a sign-out). Debug launches can switch it off (`FENTON_SKIP_INTRO=1`) so a
    /// journey that is not about the intro does not wait for it.
    static func playsIntro(played: Bool, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        #if DEBUG
        if environment["FENTON_SKIP_INTRO"] == "1" { return false }
        #endif
        return !played
    }
}
