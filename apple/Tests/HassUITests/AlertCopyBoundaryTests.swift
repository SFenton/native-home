import Testing
@testable import HassUI

/// The sign-out alerts the layout recovery boundary shares with the Account sheet and Home Assistant settings
/// (`.agents/design/server-ui-boundary.md`, rule 6).
struct AlertCopyBoundaryTests {
    @Test func signOutAsksAboutHomeAssistantWithADestructiveConfirm() {
        let spec = AlertCopy.signOut
        #expect(spec.title == "Sign Out of Home Assistant?")
        #expect(spec.message == "You'll need your username and password to sign in again.")
        #expect(spec.confirm == AlertCopy.Action(title: "Sign Out", role: .destructive))
        #expect(spec.cancel == .cancel)
    }

    @Test func theFailureNamesThisIPhoneOrThisIPadNeverThisPhone() {
        let phone = AlertCopy.signOutFailed(device: .iPhone)
        let pad = AlertCopy.signOutFailed(device: .iPad)
        #expect(phone.title == "Couldn't Sign Out")
        #expect(phone.message == "Signing out needs a connection so this iPhone stops reporting its location. Connect and try again.")
        #expect(pad.message == "Signing out needs a connection so this iPad stops reporting its location. Connect and try again.")
        #expect(phone.confirm == AlertCopy.Action(title: "Try Again", role: .plain))
        #expect(pad.cancel == .cancel)
        #expect(!(phone.message ?? "").contains("phone"))
    }
}
