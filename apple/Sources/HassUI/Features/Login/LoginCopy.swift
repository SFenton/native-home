import Foundation
import HassCore
import HassTelemetry
import Observation

/// The words on the sign-in screen, in one place so the view, the model and the tests agree.
enum LoginCopy {
    static let appName = "S+H"
    static let subtitle = "Sign in to your Home Assistant"
    static let signInTitle = "Sign In"
    static let busyTitle = "Signing In…"
    static let retryTitle = AlertCopy.tryAgain
    static let footnote = "Your password goes only to your Home Assistant. S+H keeps a sign-in key in your Keychain, never the password."
    static let wrongCredentials = "That username and password don't match. Check them and try again."
    static let twoStepUnsupported = "Two-step sign-in isn't supported. Turn it off for this account in Home Assistant."
    static let serverLabel = "Server"
    static let serverAccessibilityLabel = "Server address"
    static let serverPlaceholder = "homeassistant.local:8123"
    static let badAddress = "Enter the address you open Home Assistant with, like homeassistant.local:8123."
    static let notHomeAssistant = "Home Assistant didn't answer at that address. Check it and try again."
    static let unreachableTitle = "Can't reach Home Assistant"
    static let unreachableBody = "Check the server address and that this phone is online. If both are right, Home Assistant may be restarting; try again in a minute."
    static let failedTitle = "Sign-in didn't work"
    static let failedBody = "Something went wrong while signing in. Try again; if it keeps happening, the details may say why."
    static let detailsTitle = "Details"
    static let welcomeSubtitle = "Your sign-in ended. Enter your password to pick up where you left off."
    static let differentAccount = "Use a Different Account"

    static func welcomeBack(_ firstName: String) -> String { "Welcome back, \(firstName)" }
}
