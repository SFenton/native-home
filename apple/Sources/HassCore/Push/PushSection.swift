import Foundation

/// A root section a notification can open; mirrors the app's sections.
public enum PushSection: String, Equatable, Sendable {
    case home, security, climate, chores, settings
}
