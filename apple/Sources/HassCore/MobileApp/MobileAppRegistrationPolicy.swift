import Foundation

/// Where this build may register with Home Assistant (`.agents/platforms/apple/mobile-app.md`).
public enum MobileAppRegistrationPolicy {
    /// The launch environment key that lets a simulator register, for a deliberate live check.
    public static let simulatorOverrideKey = "FENTON_MOBILE_APP_REGISTER"

    /// A device always registers; a simulator only with `FENTON_MOBILE_APP_REGISTER=1`. Every simulator signs in as a
    /// real person, so without this each one (and each erase) added a `mobile_app` device and a `notify` service
    /// to that person in Home Assistant.
    /// - Parameters:
    ///   - environment: The launch environment.
    ///   - isSimulator: Whether this build runs in the simulator.
    public static func allowsRegistration(environment: [String: String] = ProcessInfo.processInfo.environment,
                                          isSimulator: Bool = isSimulator) -> Bool {
        !isSimulator || environment[simulatorOverrideKey] == "1"
    }

    /// Whether this build runs in the simulator.
    public static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
