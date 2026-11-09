import HassCore
import HassDesign
import SwiftUI

/// Adds or edits a bed alarm (web `EightSleepAlarmEditor`).
struct BedAlarmEditor {
    let devices: BedroomDevices
    let side: BedSide
    var onDone: () -> Void






    /// "Delete Alarm?" over "Set for 7:00 AM on Monday."; without a day the sentence ends after the time.
    static func deletePrompt(time: String, day: String?) -> AlertCopy.Spec {
        AlertCopy.delete("Alarm", detail: "Set for \(time)" + (day.map { " on \($0)." } ?? "."))
    }


}
