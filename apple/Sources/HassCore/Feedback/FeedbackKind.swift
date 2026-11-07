import Foundation

/// Which in-app feedback form is open (Settings → Feedback), ported from FestivalNativeApps' feedback form.
public enum FeedbackKind: String, Sendable, Codable, CaseIterable, Identifiable {
    /// "Report an Issue": title, description, steps to reproduce and expected behavior.
    case bug
    /// "Request a Feature": title and description.
    case feature

    public var id: String { rawValue }

    /// Title prefix the form pre-fills and keeps, including its trailing space.
    public var titlePrefix: String {
        switch self {
        case .bug: "[Bug] "
        case .feature: "[Feature] "
        }
    }

    /// The Settings row and sheet title.
    public var formTitle: String {
        switch self {
        case .bug: "Report an Issue"
        case .feature: "Request a Feature"
        }
    }

    /// The Settings row's subtitle.
    public var rowSubtitle: String {
        switch self {
        case .bug: "Something broken? Send a report with screenshots or a recording."
        case .feature: "Suggest something new or a change to the app."
        }
    }

    /// The Settings row's SF Symbol.
    public var symbol: String {
        switch self {
        case .bug: "ladybug"
        case .feature: "lightbulb"
        }
    }

    /// Whether the form shows the Steps to Reproduce and Expected Behavior boxes.
    public var includesReproduction: Bool { self == .bug }

    /// The GitHub label for the kind (`Bug` or `Feature`).
    public var label: String {
        switch self {
        case .bug: "Bug"
        case .feature: "Feature"
        }
    }

    /// "report" or "request", for sentences like "Discard this report?".
    public var noun: String {
        switch self {
        case .bug: "report"
        case .feature: "request"
        }
    }
}
