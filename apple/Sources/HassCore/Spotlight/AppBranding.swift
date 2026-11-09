import Foundation

/// The app's public name and the other names people may search or say for it (owner, 2026-10-17: "S+H" is the
/// public-facing name; the bundle id stays `com.sfenton.home`).
///
/// The home-screen label, Spotlight's app result and Siri read `CFBundleDisplayName` (`apple/project.yml`). Nothing else
/// in a development-signed build lets the icon itself match other words, so ``searchTerms`` ride on the Core Spotlight
/// items (``SpotlightCatalog``) and the App Shortcuts instead (`.agents/platforms/apple/app-name.md`).
public enum AppBranding {
    /// The name people see: home screen, Settings, notification settings, Spotlight.
    public static let displayName = "S+H"
    /// How VoiceOver and text-to-speech say it (`CFBundleSpokenName`); "S+H" would read as "S plus H".
    public static let spokenName = "S and H"
    /// The names Siri accepts in place of the app's own in an App Shortcut phrase (`INAlternativeAppNames`).
    /// Apple allows at most three per localization.
    public static let alternativeNames = ["Home Assistant", "HASS", "Fenton Home"]
    /// Words every Spotlight item carries so a search for the old name or the platform finds the app's pages.
    public static let searchTerms = [
        "S+H", "S and H", "Home", "Home Assistant", "HASS", "Fenton", "Fenton Home", "Smart Home",
    ]
}
