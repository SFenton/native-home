import HassCore

/// Hands a page from an App Shortcut to the running app. A shortcut can run before the app finishes launching, so a
/// request made with no handler waits for one.
@MainActor
public enum AppShortcutRouter {
    private static var handler: (@MainActor (PushDestination) -> Void)?
    private static var pending: PushDestination?

    /// Opens `destination` now, or as soon as the app installs its handler.
    public static func route(to destination: PushDestination) {
        if let handler {
            handler(destination)
        } else {
            pending = destination
        }
    }

    /// The app's handler, installed once at launch; runs a request that arrived first.
    public static func install(_ newHandler: @escaping @MainActor (PushDestination) -> Void) {
        handler = newHandler
        if let waiting = pending {
            pending = nil
            newHandler(waiting)
        }
    }

    /// Forgets the handler and any waiting request (tests).
    static func reset() {
        handler = nil
        pending = nil
    }
}
