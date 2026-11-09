import SwiftUI

/// Posts VoiceOver announcements for changes the screen shows but does not move focus to: a status that
/// appears, a save that starts, an error that arrives (HIG, Accessibility: tell people about visible changes).
///
/// Every announcement goes through ``announce(_:)`` so a unit test can read the spoken string with ``sink``
/// instead of depending on a screen reader (or on the Mac being unlocked).
@MainActor
public enum Announcer {
    /// A test hook: when set, receives each announcement instead of the system. Nil in the app.
    public static var sink: ((String) -> Void)?

    /// Speaks `text` after whatever VoiceOver is saying, without moving focus. Empty text is ignored.
    public static func announce(_ text: String) {
        guard !text.isEmpty else { return }
        if let sink { sink(text); return }
        AccessibilityNotification.Announcement(text).post()
    }

    /// Tells VoiceOver the whole screen changed (a new root appeared); focus moves to the first element.
    /// - Parameter text: Spoken first, when the new screen deserves a word ("Home").
    public static func screenChanged(announcing text: String? = nil) {
        if let sink { sink("screenChanged" + (text.map { ": " + $0 } ?? "")); return }
        #if os(iOS)
        UIAccessibility.post(notification: .screenChanged, argument: text)
        #endif
    }
}


