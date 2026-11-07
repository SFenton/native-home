import HassCore
import HassDesign
import SwiftUI

/// A detail page in a controller's sheet (web `DETAIL_WATER` / `DETAIL_SCHEDULE`).
public enum SprinklerDetail: Hashable, Sendable {
    /// Water a zone now.
    case water(zone: Int)
    /// Edit a zone's program.
    case schedule(zone: Int)
}

/// A controller's sheet (web `SprinklerController.tsx` modal): status, zones, Stop watering, rain delay and smart
/// watering, and each program. A zone pushes Water now; a program pushes its schedule editor (HIG: Sheets, a
/// navigation stack inside the sheet in place of the web's in-modal detail pages).
struct SprinklerControllerSheet {
    var controller: SprinklerController
    private let format = SprinklerFormat()




    static func tone(_ snapshot: SprinklerSnapshot) -> StatusPill.Tone {
        switch snapshot.status {
        case .unavailable: .unavailable
        case .fault: .danger
        case .watering: .active
        case .ready: snapshot.mode == "off" ? .warning : .ok
        }
    }
}

// MARK: - Water now

/// Water a zone for a chosen time (web `waterDetail`).
struct SprinklerWaterPage {
    var controller: SprinklerController
    var zone: Int
    var done: () -> Void


    /// The preset that matches `minutes`, or `nil` when the stepper has moved off every preset.
    static func presetSelection(_ minutes: Int) -> Int? {
        SprinklersConfig.manualRunPresets.contains(minutes) ? minutes : nil
    }

}

// MARK: - Schedule

/// Edit a zone's program (web `scheduleDetail`): enabled, run now, days, start times and budget; Apply saves.
///
/// Two commit models, said aloud (HIG Entering data; owner, 2026-10-24): "Right now" (Program Enabled, Start Program Now)
/// applies immediately, since turning a program off is expected to take effect; "Schedule" (days, start times, budget)
/// waits for Apply, and leaving with edits asks first (``DiscardGuard``).
struct SprinklerSchedulePage {
    var controller: SprinklerController
    var zone: Int
    var done: () -> Void
    /// Closes the whole sheet.
    var close: () -> Void
    private let initial: Draft
    private let format = SprinklerFormat()


    /// What the page edits, to tell whether anything changed (``DiscardGuard``).
    struct Draft: Equatable {
        var days: Set<Int>
        var clocks: [String]
        var budget: Int
    }


    /// Why Apply is off for this draft, nil when it can save: no day chosen, else no start time.
    static func applyBlocker(days: Set<Int>, startTimes: Int) -> String? {
        if days.isEmpty { return "Choose at least one day." }
        if startTimes == 0 { return "Add a start time." }
        return nil
    }



    // MARK: - Start times

    /// One editable start time. Its id is allocated once, so a row keeps its identity when another is removed.
    struct StartTime: Identifiable, Equatable {
        let id = UUID()
        var date: Date

        init(_ date: Date) { self.date = date }
    }



}
