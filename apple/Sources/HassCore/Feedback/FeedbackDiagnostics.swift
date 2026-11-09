import Foundation

/// Device, app and Home Assistant details appended to every report, so the triage agent can reproduce
/// it on the same device family, size and settings. It never holds a token, password or server address. The
/// Home Assistant user who sent it is added by the integration, from the request's own sign-in.
public struct FeedbackDiagnostics: Sendable, Equatable {
    /// `CFBundleShortVersionString (CFBundleVersion)`, plus the build date when known.
    public var app: String
    /// For example "iOS 27.1".
    public var system: String
    /// Marketing family and hardware identifier, for example "iPhone Duo (iPhone19,3)".
    public var device: String
    /// Window size, size class and orientation, for example "402 × 874 pt, compact width, portrait".
    public var window: String
    /// Home Assistant version, or "Not connected".
    public var homeAssistant: String
    /// Text size, VoiceOver, Reduce Motion and appearance, for example "Large, VoiceOver off, Dark".
    public var accessibility: String
    /// Locale and time zone, for example "en_US, America/Los_Angeles".
    public var locale: String

    /// Creates diagnostics.
    public init(
        app: String, system: String, device: String, window: String, homeAssistant: String,
        accessibility: String, locale: String
    ) {
        self.app = app
        self.system = system
        self.device = device
        self.window = window
        self.homeAssistant = homeAssistant
        self.accessibility = accessibility
        self.locale = locale
    }

    /// Rows in display order.
    public var rows: [(label: String, value: String)] {
        [
            ("App", app), ("System", system), ("Device", device), ("Window", window),
            ("Home Assistant", homeAssistant), ("Accessibility", accessibility), ("Locale", locale),
        ]
    }

    /// The app version text from an Info.plist dictionary.
    ///
    /// - Parameters:
    ///   - info: `Bundle.main.infoDictionary`.
    ///   - buildDate: When the executable was built, when known.
    /// - Returns: For example "0.1.0 (1), built 2026-10-13".
    public static func appVersion(_ info: [String: Any]?, buildDate: Date? = nil) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var text = "\(version) (\(build))"
        if let buildDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            text += ", built \(formatter.string(from: buildDate))"
        }
        return text
    }

    /// The window line.
    ///
    /// - Parameters:
    ///   - width: Window width in points.
    ///   - height: Window height in points.
    ///   - regularWidth: Whether the horizontal size class is regular.
    /// - Returns: For example "402 × 874 pt, compact width, portrait".
    public static func windowText(width: Double, height: Double, regularWidth: Bool) -> String {
        let orientation = width > height ? "landscape" : "portrait"
        return "\(Int(width.rounded())) × \(Int(height.rounded())) pt, \(regularWidth ? "regular" : "compact") width, \(orientation)"
    }
}
