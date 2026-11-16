#if os(iOS)
import HassCore

// MARK: - What the recovery ground says

extension UKServerUIProductionHost {
    /// The words of the boundary's actions and the Clear alert, compiled beside ``Boundary`` (never in the copy table and never
    /// a literal in the host; `.agents/design/server-ui-boundary.md`, rule 9). Sign Out's alerts are ``AlertCopy/signOut`` and
    /// ``AlertCopy/signOutFailed(device:)``.
    enum BoundaryCopy {
        /// The one prominent action, where a retry can help.
        static let tryAgain = AlertCopy.tryAgain
        /// The action's label while a retry runs.
        static let tryingAgain = AlertCopy.tryingAgain
        /// The Clear button on the failed state.
        static let clear = "Clear Rejected Layout"
        /// The Sign Out button on every state.
        static let signOut = "Sign Out"
        /// The Clear confirmation: destructive, because the downloaded layout is discarded.
        static let clearAlert = AlertCopy.Spec(
            title: "Clear Rejected Layout?",
            message: "Only this account's downloaded layout will be cleared. Your Home Assistant sign-in is kept.",
            confirm: AlertCopy.Action(title: "Clear Layout", role: .destructive))
    }

    /// The compiled recovery shown while no layout is on screen. Pure values, so every case is testable without a view.
    ///
    /// The ground is the existing recovery boundary (``UKStateMessageView``, the component ``UKServerUIBootstrapMessage`` uses
    /// for authored copy): a layout has not arrived yet, nothing is published, this build is too old for what is published, or
    /// the layout failed.
    struct Boundary: Equatable {
        let title: String
        let message: String
        let symbol: String
        let canRetry: Bool
        let offersClear: Bool
        /// Whether waiting longer would change nothing, so a held arrival can proceed.
        let isFinal: Bool

        init(remote: ServerUIPublicationRemoteState, status: ServerUIPublicationStatus, storeMissing: Bool,
             expired: Bool, adoptionFailed: Bool) {
            if storeMissing {
                self = .unavailable(offersClear: false, canRetry: false)
            } else if case .incompatible = remote {
                self = Boundary(title: "Update Required",
                                message: "The layout published for your home needs a newer version of S+H. Update the app to see it.",
                                symbol: "arrow.down.app", canRetry: false, offersClear: false, isFinal: true)
            } else if remote == .unpublished {
                self = Boundary(title: "No Layout Published",
                                message: "Your Home Assistant has no layout yet. Publish one from the Configurator, then try again.",
                                symbol: "exclamationmark.triangle", canRetry: true, offersClear: false, isFinal: true)
            } else if case .failure = status {
                self = .unavailable(offersClear: true, canRetry: true)
            } else if expired || adoptionFailed {
                self = .unavailable(offersClear: !adoptionFailed, canRetry: !adoptionFailed)
            } else {
                self = Boundary(title: "Getting Your Layout…", message: "Waiting for your Home Assistant to send the layout.",
                                symbol: "arrow.down.circle", canRetry: false, offersClear: false, isFinal: false)
            }
        }

        private init(title: String, message: String, symbol: String, canRetry: Bool, offersClear: Bool, isFinal: Bool) {
            self.title = title
            self.message = message
            self.symbol = symbol
            self.canRetry = canRetry
            self.offersClear = offersClear
            self.isFinal = isFinal
        }

        private static func unavailable(offersClear: Bool, canRetry: Bool) -> Boundary {
            Boundary(title: "Layout Unavailable",
                     message: "No usable layout is available. Try again, or clear a rejected saved layout and download it again.",
                     symbol: "exclamationmark.triangle", canRetry: canRetry, offersClear: offersClear, isFinal: true)
        }
    }
}
#endif
