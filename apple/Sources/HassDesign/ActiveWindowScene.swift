#if os(iOS)
import UIKit

/// The one place that picks which window scene the app is "in": several can be connected at once (iPad multi-window, a Duo's
/// two windows), and code that reads `UIApplication.shared.connectedScenes` must not let a background one decide.
///
/// Readers that need a different answer (every scene's windows, as the orientation refresh and the camera viewer's window
/// metrics do, or all scenes for a diagnostics dump) keep their own loop on purpose; this type is for "the scene the user is
/// looking at".
@MainActor
public enum ActiveWindowScene {
    /// The foreground-active window scene whose window is key, else the first foreground-active one, else `nil`.
    public static func current() -> UIWindowScene? {
        let active = windowScenes.filter { $0.activationState == .foregroundActive }
        return active.first { $0.windows.contains { $0.isKeyWindow } } ?? active.first
    }

    /// ``current()``, falling back to the first connected window scene when none is foreground-active (the moment after
    /// launch, a snapshot being taken).
    public static func currentOrFirst() -> UIWindowScene? {
        current() ?? windowScenes.first
    }

    private static var windowScenes: [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }
}
#endif
