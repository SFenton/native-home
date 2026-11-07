import HassCore
import HassDesign
import SwiftUI

/// One bed side's sheet (pattern: `.agents/patterns/bedroom-devices.md`; web `EightSleepBedModal` in SleepyPod
/// climate mode).
///
/// The hero (level dial, power, hint and any ringing alarm) sits above the tab's content, or beside it where a split
/// is allowed (iPad and unfolded iPhone Duo in landscape). The tabs are the bottom section bar (direction G, Sheets). Alarm day pages and the alarm editor push inside the sheet.
public struct BedSideSheet {
    /// A sheet tab (web `SLEEPYPOD_MODAL_TABS`).
    public enum Tab: String, CaseIterable, Identifiable, Sendable {
        case temperature, specialModes = "special-modes", alarms, status
        public var id: String { rawValue }
        var title: String {
            switch self {
            case .temperature: "Temperature"
            case .specialModes: "Special Modes"
            case .alarms: "Alarms"
            case .status: "Status"
            }
        }
    }

    /// A pushed page.
    enum Route: Hashable {
        case day(Weekday)
        case add(Weekday?)
        case edit(String)
    }

    let devices: BedroomDevices
    let side: BedSide







}
