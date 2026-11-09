import HassDesign
import SwiftUI

/// The Setup flow's one sheet: Notifications, Time Sensitive and Location swap in place as each completes
/// (``SetupCoordinator``; owner, 2026-10-27). Always dark, like the Location sheet it grew from, so the secondary text
/// keeps its contrast. It shows no dots, counter or swipe between steps: the only way forward is the step's button
/// (HIG [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy), pre-alert screens).
struct SetupSheet {
    var setup: SetupCoordinator

    /// Full height, always (owner, 2026-10-27): a content-fitted iPhone sheet is inset and iOS draws its content at 0.96x, so
    /// the 50 pt buttons read 48 pt. It also keeps the sheet one size as the three steps swap. This sheet departs from the
    /// fitted-height rule (`.agents/design/setup-flow.md`). A full sheet has one detent, so no remembered fitted height
    /// (``SheetFitMemory``) reaches it.
    static let height: HassSheetHeight = .full


}
