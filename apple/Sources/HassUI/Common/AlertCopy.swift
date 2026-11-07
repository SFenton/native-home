import HassDesign
import SwiftUI

/// Every alert and confirmation dialog the app raises, in one place so the view, the sibling sites that ask the same
/// question and the tests agree (the way ``LoginCopy`` does for sign-in). The convention is
/// `.agents/patterns/alerts.md` (decided 2026-10-24 from `proposals/alert-conventions`).
///
/// - An **alert** asks a yes or no about a state change or a session: Sign Out, Disarm, Turn Off Vacation Mode,
///   Switch to Rooms, End Solo Trip, Reset. A **confirmation dialog**, attached to the control that raised it, asks
///   before deleting a thing (``AlertCopy/delete(_:named:detail:)``).
/// - Titles are Title Case questions naming the object ("Turn Off Vacation Mode?"); a name too long for a title moves
///   to the message.
/// - Every alert and dialog has a Cancel. Only a loss of data is destructive (Delete, Sign Out, Reset Measurements);
///   a plain confirming button is the bold default.
///
/// HIG: Alerts (succinct titles, a Cancel, destructive only for an action people did not deliberately choose) and
/// Action sheets (choices tied to an intentional action).
enum AlertCopy {
    // MARK: - Shapes

    /// One button: its words and role.
    struct Action: Equatable, Sendable {
        /// What pressing the button means, independent of SwiftUI so tests can state it.
        enum Role: Equatable, Sendable {
            /// The confirming button of a reversible choice: no red, the bold default.
            case plain
            /// Loses data or a session: red, never the default.
            case destructive
            /// Dismisses without acting.
            case cancel

        }

        var title: String
        var role: Role

        /// The one Cancel every alert and dialog shares.
        static let cancel = Action(title: "Cancel", role: .cancel)
    }

    /// A whole alert or dialog: a question, an optional explanation, the confirming button and the Cancel.
    struct Spec: Equatable, Sendable {
        var title: String
        var message: String?
        var confirm: Action
        var cancel: Action = .cancel
    }

    // MARK: - Shared labels

    /// The retry label everywhere (Recipes, Inventory, the Home Assistant web page, a failed sign-out).
    static let tryAgain = "Try Again"

    // MARK: - Feedback

    /// The feedback success alert's message: the issue number and nothing promised after it.
    static func feedbackFiled(number: Int) -> String { "Your report is filed as issue #\(number)." }

    static let unavailableMessage = "Can't open this page right now. Check your connection and try again."

    // MARK: - Session

    /// Sign Out, from the Account sheet and Home Assistant settings: an alert in both places, destructive because it
    /// discards the session.
    static let signOut = Spec(
        title: "Sign Out of Home Assistant?",
        message: "You'll need your username and password to sign in again.",
        confirm: Action(title: "Sign Out", role: .destructive)
    )

    /// Sign Out did not complete; one string for both sign-out sites. It states the reason: signing out asks the server
    /// to unlink this phone so it stops reporting its location, and there is deliberately no local-only sign out.
    static let signOutFailed = Spec(
        title: "Couldn't Sign Out",
        message: "Signing out needs a connection so this phone stops reporting its location. Connect and try again.",
        confirm: Action(title: tryAgain, role: .plain)
    )

    // MARK: - Reversible changes (plain confirm)

    /// Turning Vacation Mode off resets only the checklist and helper flags, which the person can redo.
    static let turnOffVacation = Spec(
        title: "Turn Off Vacation Mode?",
        message: "Your checklist and helpers reset.",
        confirm: Action(title: "Turn Off", role: .plain)
    )

    /// Disarming the alarm: chosen just now, so plain and bold.
    static let disarm = Spec(
        title: "Disarm the Security System?",
        message: "Doors and motion stop triggering the alarm.",
        confirm: Action(title: "Disarm", role: .plain)
    )

    /// Leaving the drawn area for room selection, from the Use Rooms tile, a room tile and the map (owner, 2026-10-28:
    /// "Use Rooms", not "Switch to Rooms").
    static let switchToRooms = Spec(
        title: "Use Rooms?",
        message: "You have an area drawn right now. Using Rooms will discard that area.",
        confirm: Action(title: "Use Rooms", role: .plain)
    )

    /// Leaving the chosen rooms for area drawing, from the Use Area tile.
    static let switchToArea = Spec(
        title: "Use Area?",
        message: "Continuing clears your selected rooms and opens area drawing.",
        confirm: Action(title: "Use Area", role: .plain)
    )

    /// Ending or cancelling a Solo Trip returns the household to its normal automations at once.
    static let endSoloTrip = Spec(
        title: "End Solo Trip?",
        message: "The house goes back to its normal automations right away.",
        confirm: Action(title: "End Solo Trip", role: .plain)
    )

    /// High AQI Mode changes every air purifier in the house at once, in either direction: asked first, reversible (plain).
    /// - Parameter turningOn: The mode is about to turn on, not off.
    static func highAqiMode(turningOn: Bool) -> Spec {
        Spec(title: "Turn \(turningOn ? "On" : "Off") High AQI Mode?",
             message: "This changes every air purifier in the house.",
             confirm: Action(title: turningOn ? "Turn On" : "Turn Off", role: .plain))
    }

    /// A bulk reset of the front yard lights.
    static func resetAllLights(count: Int) -> Spec {
        Spec(title: "Reset All Lights?",
             message: "All \(count) lights go back to warm white.",
             confirm: Action(title: "Reset All Lights", role: .plain))
    }

    /// Copying one light's colour onto the whole group.
    static func applyToAllLights(count: Int) -> Spec {
        Spec(title: "Apply to All Lights?",
             message: "All \(count) lights take this color.",
             confirm: Action(title: "Apply to All", role: .plain))
    }

    // MARK: - Data loss (destructive confirm)

    /// Erasing the whole telemetry log. Clear Image Cache stays instant: the cache refills.
    static let resetMeasurements = Spec(
        title: "Reset Measurements?",
        message: "This erases every sample recorded on this phone.",
        confirm: Action(title: "Reset Measurements", role: .destructive)
    )

    /// The longest name a delete title carries; a longer one moves to the message so the title stays on two lines.
    static let titleNameLimit = 28

    /// Deleting a thing: title "Delete <name>?" and a button "Delete <noun>".
    ///
    /// - Parameters:
    ///   - noun: What it is, Title Case ("Alarm", "Activity", "Task", "Item").
    ///   - name: Its own name. Nil, empty or longer than ``titleNameLimit`` titles the dialog with the noun and moves
    ///     the name to the message.
    ///   - detail: A second sentence ("Set for 7:00 AM on Weekdays.").
    static func delete(_ noun: String, named name: String? = nil, detail: String? = nil) -> Spec {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let fits = name.map { $0.count <= titleNameLimit } ?? false
        let title = fits ? "Delete \(name ?? noun)?" : "Delete \(noun)?"
        let message = [fits ? nil : name, detail].compactMap { $0 }.joined(separator: " ")
        return Spec(title: title, message: message.isEmpty ? nil : message,
                    confirm: Action(title: "Delete \(noun)", role: .destructive))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
