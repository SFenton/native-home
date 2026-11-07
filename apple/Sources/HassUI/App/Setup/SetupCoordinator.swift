import Foundation
import Observation

/// Runs the after-sign-in Setup flow: one sheet whose steps swap in place, Notifications, then Time Sensitive, then
/// Location (owner, 2026-10-27; HIG [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets):
/// one sheet at a time, no stacking). Which step shows is ``SetupFlow``'s decision; this type keeps the one
/// presentation state, remembers the steps shown (`setup.stepsSeen`) and drives the next one when a step completes.
///
/// The Notifications and Location steps are pre-alert screens: one Continue, no Close, not swipe-dismissible. The
/// Time Sensitive step has no system alert behind it, so its Got It, Open Settings and Not Now are its own way out.
@MainActor
@Observable
public final class SetupCoordinator {
    /// The step on screen; nil while the sheet is closed.
    public private(set) var step: SetupStep?
    /// The last step shown, kept so the sheet draws it while it dismisses instead of going blank.
    public private(set) var shownStep: SetupStep = .notifications

    /// Whether the sheet is up. Setting it false closes the sheet (the presenter's binding).
    public var isPresenting: Bool {
        get { step != nil }
        set { if !newValue { step = nil } }
    }

    /// The notification permission and the Time Sensitive switch, which the first two steps ask about and report.
    @ObservationIgnored public let push: PushCoordinator
    /// Location, for the third step; nil when this launch does not report it.
    @ObservationIgnored public let location: LocationCoordinator?
    @ObservationIgnored private let defaults: UserDefaults
    /// The iOS notification alert is up; a second Continue is ignored meanwhile.
    @ObservationIgnored private var isAsking = false

    /// Creates the flow.
    /// - Parameters:
    ///   - push: The notification coordinator.
    ///   - location: The location coordinator, nil in launches that do not report location.
    ///   - defaults: Where the seen steps live.
    public init(push: PushCoordinator, location: LocationCoordinator?, defaults: UserDefaults = .standard) {
        self.push = push
        self.location = location
        self.defaults = defaults
    }

    // MARK: - Offering

    /// What the flow decides from now: the system's answers and this launch's location state.
    var inputs: SetupFlow.Inputs {
        SetupFlow.Inputs(push: push.authorization, timeSensitive: push.timeSensitive,
                         locationNeedsAsk: location?.needsPermissionStep ?? false)
    }

    /// Signed in and connected: shows the first step that applies and was not shown yet, if the sheet is not already
    /// up. Reads the system's answers first, so a person who allowed notifications in Settings is judged by that.
    public func offerIfNeeded() async {
        guard step == nil else { return }
        syncSeen()
        await push.refreshSettings()
        await advance()
    }

    /// The app came to the foreground: read the notification answers again, so the Time Sensitive step and Settings
    /// are right after the person returns from iOS Settings.
    public func didBecomeActive() async {
        await push.refreshSettings()
    }

    /// Shows the next pending step in place, or closes the sheet when none is left.
    private func advance() async {
        guard let next = SetupFlow.nextStep(for: inputs, seen: SetupFlow.seen(in: defaults)) else {
            step = nil
            return
        }
        show(next)
    }

    private func show(_ next: SetupStep) {
        // Location is multi-stage (While Using, then Always) and can be closed on its status stages, so it counts as
        // shown when it first appears, as the single offer did before. The others count when their button is used.
        if next == .location { SetupFlow.markSeen(.location, in: defaults) }
        shownStep = next
        step = next
    }

    /// Puts `step` on screen without evaluating anything (hosted renders of each step).
    func showForTesting(_ step: SetupStep) {
        shownStep = step
        self.step = step
    }

    private func syncSeen() {
        push.setupHasShownNotifications = SetupFlow.seen(in: defaults).contains(.notifications)
    }

    // MARK: - Steps

    /// Continue on the Notifications step: the one place the iOS alert is requested. When it is answered the sheet
    /// swaps to Time Sensitive if the person allowed, otherwise to the next pending step.
    public func continueNotifications() async {
        guard !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        SetupFlow.markSeen(.notifications, in: defaults)
        push.setupHasShownNotifications = true
        await push.enableNotifications()
        await advance()
    }

    /// Got It or Not Now on the Time Sensitive step: it counts as shown, and the next pending step swaps in.
    public func finishTimeSensitive() async {
        SetupFlow.markSeen(.timeSensitive, in: defaults)
        await advance()
    }

    /// Open Settings on the Time Sensitive step: it counts as shown. The sheet stays on the step, which follows the
    /// switch when the person comes back (``didBecomeActive()``), and they leave it with Got It or Not Now.
    public func openedSettingsFromTimeSensitive() {
        SetupFlow.markSeen(.timeSensitive, in: defaults)
    }

    /// Close on a Location status stage.
    public func close() {
        step = nil
    }
}
