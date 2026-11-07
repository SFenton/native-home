import Foundation

// MARK: - Shared vocabulary

/// A side of the Master Bedroom Pod (web `SleepypodSide`).
public enum BedSide: String, CaseIterable, Codable, Hashable, Sendable {
    case left, right
}

/// Week order and the bedroom editors' day groups for ``Weekday`` (declared in `HumidifierSchedule.swift`;
/// web `SCHEDULE_WEEKDAYS`, Sunday first).
extension Weekday: Comparable {
    /// Position in the week, Sunday = 0.
    public var index: Int { Self.allCases.firstIndex(of: self)! }

    /// `Monday`.
    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// `Mon`.
    public var shortLabel: String { String(label.prefix(3)) }

    /// Monday through Friday (web `WAKE_LIGHT_WEEKDAY_GROUPS.WEEKDAYS`, also the schedule editors' default days).
    public static let workdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
    /// Saturday and Sunday in week order (Sunday first).
    public static let weekend: [Weekday] = [.sunday, .saturday]

    /// The weekday of `date` in `calendar`.
    public init(date: Date, calendar: Calendar = .current) {
        self = Self.allCases[calendar.component(.weekday, from: date) - 1]
    }

    /// `days` in week order without duplicates.
    public static func ordered(_ days: some Sequence<Weekday>) -> [Weekday] {
        let set = Set(days)
        return allCases.filter(set.contains)
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.index < rhs.index }
}

// MARK: - Wake light

/// One bed alarm source the wake light can follow (web `WakeLightSourceConfig`).
public struct WakeLightSource: Hashable, Sendable, Codable {
    /// `sleepypod:left`.
    public var id: String
    public var side: BedSide
    /// `Alex's Alarm`.
    public var alarmLabel: String
    /// `Alex's Alarms`.
    public var alarmsLabel: String
    /// The bed side whose alarm editor this source opens.
    public var bedId: String
}

/// A room's wake light (web `WakeLightConfig`, `src/constants/wakeLights.ts`).
public struct WakeLightConfig: Hashable, Sendable, Identifiable, Codable {
    public var id: String
    /// `Wake-Light Alarms`.
    public var title: String
    /// `Master Bedroom`.
    public var roomTitle: String
    /// The integration's status sensor, which carries the whole contract in its attributes.
    public var statusEntityId: String
    public var sources: [WakeLightSource]

    /// The source bound to `side`.
    public func source(for side: BedSide) -> WakeLightSource? { sources.first { $0.side == side } }

    /// The source with `id`.
    public func source(id: String) -> WakeLightSource? { sources.first { $0.id == id } }
}

// MARK: - Bed sides

/// One side of the SleepyPod Eight Pod (web `EightSleepSideConfig`, sleepypod adapter fields only).
public struct BedSideConfig: Hashable, Sendable, Identifiable, Codable {
    /// `stephens-bed` (the web hash without `#`).
    public var id: String
    /// `Alex's Bed`.
    public var title: String
    public var side: BedSide
    public var owner: HouseholdResident

    public var climateEntityId: String
    public var targetLevelEntityId: String
    public var schedulePhaseEntityId: String
    /// `input_number` per stage; the recurring Bedtime, Asleep and Dawn levels.
    public var stageLevelEntityIds: [SchedulePhase: String]
    /// Script that sets tonight's target for the active stage (a per-owner script).
    public var tonightScript: String
    /// Script that sets the target outside the schedule.
    public var outsideScheduleScript: String

    public var alarmStateEntityId: String
    public var alarmSnoozeButtonEntityId: String
    public var alarmStopButtonEntityId: String

    public var hotFlashActiveEntityId: String
    public var hotFlashButtonEntityId: String
    public var hotFlashCancelButtonEntityId: String
    public var hotFlashRestoreAtEntityId: String
    public var hotFlashTimerEntityId: String

    public var heartRateEntityId: String
    public var breathingRateEntityId: String
    public var hrvEntityId: String
    public var pumpClogEntityId: String
    public var pumpStallEntityId: String
    public var pumpLoopTemperatureEntityId: String
    public var pumpRpmEntityId: String
}

/// The Master Bedroom's wake light and Pod (web `MASTER_BEDROOM_WAKE_LIGHT`, `EIGHT_SLEEP_SIDE_CONFIGS`,
/// `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:3522`).
public enum MasterBedroom {
    /// Projects a value out of the loaded document's bedroom section.
    private static func read<T>(_ project: (HouseConfig.BedroomSection) -> T) -> T? {
        HouseConfigSource.active.read { project($0.bedroom) }
    }

    // Each value below is the server's document; with none the value is empty ("not configured").

    /// Both sides' schedules, as the SleepyPod adapter reports them.
    public static var scheduleEntityId: String { read { $0.scheduleEntityId } ?? "" }
    /// MQTT topic that replaces one side's schedule.
    public static var scheduleSetTopic: String { read { $0.scheduleSetTopic } ?? "" }
    /// Script that powers a side on or off through the hot-flash broker.
    public static var hotFlashBrokerScript: String { read { $0.hotFlashBrokerScript } ?? "" }
    /// Household Away (Solo Trip) status.
    public static var householdAwayEntityId: String { read { $0.householdAwayEntityId } ?? "" }
    /// Household Away command script (returns a response).
    public static var householdAwayScript: String { read { $0.householdAwayScript } ?? "" }

    /// The room's wake light; without a document, an unconfigured one with no entity and no sources.
    public static var wakeLight: WakeLightConfig { read { $0.wakeLight } ?? .unconfigured }

    /// Both sides, left first: the server's document.
    public static var beds: [BedSideConfig] { read { $0.beds } ?? [] }

    /// The side config for `side`: the server's bed on that side, else an unconfigured one with no entities.
    public static func bed(_ side: BedSide) -> BedSideConfig {
        beds.first { $0.side == side } ?? .unconfigured(side)
    }

    /// The side config with `id`.
    public static func bed(id: String) -> BedSideConfig? { beds.first { $0.id == id } }
}

extension WakeLightConfig {
    /// A wake light with nothing behind it, for a house with no document.
    public static let unconfigured = WakeLightConfig(id: "", title: "", roomTitle: "", statusEntityId: "", sources: [])
}

extension BedSideConfig {
    /// A bed side with no entities behind it, for a house with no document.
    public static func unconfigured(_ side: BedSide) -> BedSideConfig {
        BedSideConfig(
            id: "", title: "", side: side, owner: Resident(key: ""),
            climateEntityId: "", targetLevelEntityId: "", schedulePhaseEntityId: "", stageLevelEntityIds: [:],
            tonightScript: "", outsideScheduleScript: "",
            alarmStateEntityId: "", alarmSnoozeButtonEntityId: "", alarmStopButtonEntityId: "",
            hotFlashActiveEntityId: "", hotFlashButtonEntityId: "", hotFlashCancelButtonEntityId: "",
            hotFlashRestoreAtEntityId: "", hotFlashTimerEntityId: "",
            heartRateEntityId: "", breathingRateEntityId: "", hrvEntityId: "",
            pumpClogEntityId: "", pumpStallEntityId: "", pumpLoopTemperatureEntityId: "", pumpRpmEntityId: ""
        )
    }
}
