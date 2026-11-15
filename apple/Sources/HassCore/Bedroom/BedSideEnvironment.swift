import Foundation

// MARK: - Immutable command environment

/// Shared bedroom targets captured when a controller is created, never retargeted mid-command.
public struct BedSideEnvironment: Hashable, Sendable, Codable {
    public let scheduleEntityId: String
    public let scheduleSetTopic: String
    public let hotFlashBrokerScript: String
    public let householdAwayEntityId: String
    public let householdAwayScript: String
    public let wakeLight: WakeLightConfig

    /// Creates a bed side environment.
    public init(scheduleEntityId: String, scheduleSetTopic: String, hotFlashBrokerScript: String,
                householdAwayEntityId: String, householdAwayScript: String, wakeLight: WakeLightConfig) {
        self.scheduleEntityId = scheduleEntityId
        self.scheduleSetTopic = scheduleSetTopic
        self.hotFlashBrokerScript = hotFlashBrokerScript
        self.householdAwayEntityId = householdAwayEntityId
        self.householdAwayScript = householdAwayScript
        self.wakeLight = wakeLight
    }

    /// Existing feature callers keep their configured behavior; SDUI callers inject their own environment.
    public static var configured: Self {
        .init(scheduleEntityId: MasterBedroom.scheduleEntityId, scheduleSetTopic: MasterBedroom.scheduleSetTopic,
              hotFlashBrokerScript: MasterBedroom.hotFlashBrokerScript, householdAwayEntityId: MasterBedroom.householdAwayEntityId,
              householdAwayScript: MasterBedroom.householdAwayScript, wakeLight: MasterBedroom.wakeLight)
    }
}
