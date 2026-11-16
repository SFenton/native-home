import HassCore

/// Hands a route from an App Shortcut or a Siri phrase to the running app. A shortcut can run before the app finishes
/// launching, so a request made with no handler waits for one.
@MainActor
public enum AppShortcutRouter {
    private static var handler: (@MainActor (RouteRequest) -> Void)?
    private static var pending: RouteRequest?

    /// Opens `request` now, or as soon as the app installs its handler.
    public static func route(_ request: RouteRequest) {
        if let handler {
            handler(request)
        } else {
            pending = request
        }
    }

    /// The app's handler, installed once at launch; runs a request that arrived first.
    public static func install(_ newHandler: @escaping @MainActor (RouteRequest) -> Void) {
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
