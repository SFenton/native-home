import HassCore
import HassDesign
import SwiftUI

/// The room's wake-light alarms sheet (pattern: `.agents/patterns/bedroom-devices.md`; web `WakeLightModal`).
///
/// Two tabs in the bottom section bar (direction G, Sheets): the alarm schedule (with stop controls while a wake
/// runs) and room defaults. Adding or editing an alarm pushes an editor inside the sheet. Mirrored bed alarms open their bed's sheet through `onOpenBed`.
public struct WakeLightSheet {
    /// A sheet tab.
    public enum Tab: String, CaseIterable, Identifiable, Sendable {
        case alarms, defaults
        public var id: String { rawValue }
        var title: String { self == .alarms ? "Wake Alarms" : "Defaults" }
    }

    /// An editor page.
    enum Route: Hashable {
        case add
        case edit(String)
    }

    let devices: BedroomDevices
    var onOpenBed: (BedSide) -> Void








}
