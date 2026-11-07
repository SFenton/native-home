import Foundation

/// Solo Trip copy, verbatim from the web (`src/i18n/locales/en/pages/soloTrip.json`).
public enum SoloTripCopy {
    // MARK: - Chooser

    public static let title = "Solo Trip"
    public static let chooserSubtitle = "One traveler, one home resident"
    public static let setupRequiredSubtitle = "Needs setup in Home Assistant"

    // MARK: - Page

    public static let description = "Enable or disable Solo Trip mode for the house."
    public static let awayFromHomeTitle = "Away From Home"
    public static let awayFromHomeDescription = "Select the user that will be away from home"
    public static let toggleOn = "On"
    public static let toggleOff = "Off"
    public static let toggleDisabled = "Select the user that will be away from home first."
    public static let travelerAway = "Away"
    public static let travelerHome = "Home"
    public static let travelerSelected = "Selected"
    /// The viewer's own tile (web `HOUSEHOLD_COPY_KEYS.you`).
    public static let you = "You"

    // MARK: - Editor

    public static let editorTitle = "Schedule Solo Trip"
    public static let editorDescription = "Choose when Solo Trip starts and ends for the selected traveler."
    public static let editorConfirm = "Schedule Solo Trip"
    /// The confirm button while Home Assistant has not yet echoed the schedule.
    public static let editorConfirmBusy = "Scheduling"
    /// The combined departure picker (the web's Departure Date and Departure Time fields in one row).
    public static let departs = "Departs"
    /// The combined return picker.
    public static let returns = "Returns"
    public static let endAfterStart = "Return must be after departure."
    public static let endInFuture = "Return date/time must be in the future."

    // MARK: - Errors

    public static let commandFailed = "Home Assistant could not apply the Solo Trip change. Try again."
    public static let setupRequired = "Solo Trip scheduling is unavailable. Complete Household Away setup, then try again."
    public static let travelerRequired = "Select the user that will be away from home to continue."
    public static let unknownOutcome = "Home Assistant did not confirm the Solo Trip change. Wait for the dashboard to refresh before sending another request."
    public static let vacationConflict = "Vacation Mode is already engaged. Turn it off before scheduling Solo Trip."

    // MARK: - Status

    public static func activeTitle(traveler: String) -> String { "\(traveler) Away" }
    public static func activeDescription(traveler: String) -> String {
        "While \(traveler) is away from home and the Solo Trip setting is enabled in settings, your controls and alarms will control the entire bed."
    }
    public static func activeDescriptionTraveler(homeResident: String) -> String {
        "While you are away from home and the Solo Trip setting is enabled in settings, \(homeResident)'s controls and alarms will control the entire bed."
    }
    public static let activeUnconfirmedDescription = "Solo Trip is active, but some requested effects are still waiting for Home Assistant confirmation."
    public static let activatingTitle = "Starting Solo Trip"
    public static let activatingDescription = "Solo Trip is starting. Wait for Home Assistant to confirm the current schedule, or end it now if needed."
    public static let degradedTitle = "Solo Trip Degraded"
    public static let degradedDescription = "Some requested effects are unconfirmed. Retries continue automatically, or end away mode."
    public static let endingTitle = "Ending Solo Trip"
    public static let endingDescription = "Solo Trip is ending and restoring normal settings."
    public static let endNow = "End Solo Trip Now"
    public static let restoreRequiredTitle = "Solo Trip Needs Attention"
    public static let restoreRequiredDescription = "The away-side schedule changed unexpectedly during Solo Trip. Choose how to resolve it before Solo Trip can finish."
    public static let restoreKeepCurrent = "Keep Current Schedule"
    public static let restoreSaved = "Restore Saved Schedule"

    /// The household message for a command error; backend codes stay diagnostics (web `householdAwayCommandError`).
    public static func commandError(_ errorCode: String?) -> String? {
        guard let errorCode else { return nil }
        return errorCode == HouseholdAwayController.ErrorCode.unknownOutcome ? unknownOutcome : commandFailed
    }
}
