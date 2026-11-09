import HassDesign

/// The words of a failed load: what failed, why, and how to go on (HIG Loading: explain the problem and what people
/// can do; owner decision 2026-10-24, `proposals/loading-states` section 2). A failed load always offers
/// ``AlertCopy/tryAgain``; offline it says so instead of repeating a server message that only describes the symptom.
struct LoadFailure: Equatable {
    var symbol: String
    var title: String
    var message: String

    /// The state for a failed load of `subject` ("Task").
    /// - Parameters:
    ///   - subject: What was being loaded, in Title Case ("Task", "Recipes").
    ///   - reason: What the loader reported ("Couldn't reach Donetick."); shown when the phone is online.
    ///   - isOffline: The phone has no network path (``HassConnection/isOffline``).
    static func of(_ subject: String, reason: String, isOffline: Bool) -> LoadFailure {
        isOffline
            ? LoadFailure(symbol: "wifi.slash", title: "You're Offline", message: "Connect to the internet to load this \(subject.lowercased()).")
            : LoadFailure(symbol: "exclamationmark.triangle", title: "Unable to Load \(subject)", message: reason)
    }
}
