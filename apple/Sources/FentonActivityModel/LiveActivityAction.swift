import Foundation

/// A button press on a job card, as the App Intent in `apple/Apps/Shared/LiveActivityIntents.swift` hands it to the app
/// (`.agents/platforms/apple/live-activities-per-job.md` §7).
public enum LiveActivityAction: Hashable, Sendable {
    /// A card's button: the activity (by tag) and the control id.
    case control(tag: String, control: String)

    /// The activity the press belongs to.
    public var tag: String {
        switch self {
        case let .control(tag, _): tag
        }
    }
}

/// The app side of the Live Activity intents.
///
/// The intents are compiled into both the app and the widget extension, but a `LiveActivityIntent` runs in the app's
/// process (the system launches it in the background), so `perform()` only forwards here. The extension never
/// installs a handler, which keeps the Keychain, the webhook and the networking out of it.
public enum LiveActivityIntentRuntime {
    /// Handles presses; installed once at launch by the app.
    public protocol Handler: Sendable {
        /// Runs a press.
        /// - Returns: Whether Home Assistant took it (a failed control restores its button and shows
        ///   "Couldn't reach Home").
        func handle(_ action: LiveActivityAction) async -> Bool
    }

    private nonisolated(unsafe) static var installed: (any Handler)?
    private static let lock = NSLock()

    /// Installs the handler (the app, at launch, before any scene).
    public static func install(_ handler: (any Handler)?) {
        lock.withLock { installed = handler }
    }

    /// Hands a press to the installed handler.
    /// - Returns: Whether it was handled; false in a process with no handler.
    public static func perform(_ action: LiveActivityAction) async -> Bool {
        let handler = lock.withLock { installed }
        guard let handler else { return false }
        return await handler.handle(action)
    }
}
