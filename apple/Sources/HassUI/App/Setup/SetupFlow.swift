import Foundation

/// Which Setup step comes next: a pure function of what the system says and which steps were already shown.
///
/// The flow keeps a persisted set of steps already shown (``seenKey``). Each launch, after sign-in and connection, it
/// shows the first step whose condition holds and that is not in the set; the sheet swaps to the next pending step in
/// place when a step completes.
///
/// | Step | Condition |
/// |---|---|
/// | Notifications | the person was never asked (``PushAuthorization/notDetermined``) |
/// | Time Sensitive | notifications are allowed and the device supports Time Sensitive; shown even when the switch is already on |
/// | Location | nothing is set, or While Using can still be upgraded to Always (``Inputs/locationNeedsAsk``) |
public struct SetupFlow: Equatable, Sendable {
    /// `UserDefaults` key: the raw values of the steps already shown, a string array.
    public static let seenKey = "setup.stepsSeen"

    /// What the system says right now.
    public struct Inputs: Equatable, Sendable {
        /// The notification permission.
        public var push: PushAuthorization
        /// The Time Sensitive switch.
        public var timeSensitive: TimeSensitiveSetting
        /// Whether this launch reports location and there is something left to ask (``LocationCoordinator/needsPermissionStep``).
        public var locationNeedsAsk: Bool

        /// Creates the inputs.
        public init(push: PushAuthorization, timeSensitive: TimeSensitiveSetting, locationNeedsAsk: Bool) {
            self.push = push
            self.timeSensitive = timeSensitive
            self.locationNeedsAsk = locationNeedsAsk
        }
    }

    /// Whether `step` applies to these inputs, ignoring whether it was shown.
    public static func applies(_ step: SetupStep, to inputs: Inputs) -> Bool {
        switch step {
        case .notifications: inputs.push == .notDetermined
        case .timeSensitive: inputs.push == .granted && inputs.timeSensitive != .notSupported
        case .location: inputs.locationNeedsAsk
        }
    }

    /// The first step that applies and was not shown yet; nil when the flow has nothing to show.
    /// - Parameters:
    ///   - inputs: What the system says.
    ///   - seen: The steps already shown.
    public static func nextStep(for inputs: Inputs, seen: Set<SetupStep>) -> SetupStep? {
        SetupStep.allCases.first { !seen.contains($0) && applies($0, to: inputs) }
    }

    // MARK: - Persistence

    /// The steps already shown. An install that offered location before the flow existed
    /// (`location.permissionOffered`, ``LocationCoordinator``) counts as having seen the location step, so nobody sees
    /// it twice; that person gets only the steps they have not seen.
    /// - Parameter defaults: Where the set lives.
    public static func seen(in defaults: UserDefaults = .standard) -> Set<SetupStep> {
        var steps = Set((defaults.stringArray(forKey: seenKey) ?? []).compactMap(SetupStep.init(rawValue:)))
        if defaults.bool(forKey: LocationCoordinator.offeredKey) { steps.insert(.location) }
        return steps
    }

    /// Records `step` as shown, keeping the migrated location step too.
    /// - Parameters:
    ///   - step: The step.
    ///   - defaults: Where the set lives.
    public static func markSeen(_ step: SetupStep, in defaults: UserDefaults = .standard) {
        var steps = seen(in: defaults)
        steps.insert(step)
        defaults.set(steps.sorted().map(\.rawValue), forKey: seenKey)
    }
}
