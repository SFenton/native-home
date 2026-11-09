import HassCore
import HassDesign
import SwiftUI

/// A room-by-room overview sheet that pushes a room's detail page (web `LightsSheet`, `ClimateSheet`,
/// `OccupancySheet`, `ContactSheet` and `AirQualitySheet` in `ha-sfenton-react-dash@f5a7bf9:src/pages/AtAGlancePage.tsx`;
/// pattern: `.agents/patterns/room-overview-sheet.md`).
///
/// Home opens it from five status chips and the Security page from its Contact Sensors chip. A room tap pushes the
/// room inside the sheet's own `NavigationStack` with Back, as the web's in-sheet back button does (HIG: Sheets,
/// "a sheet can contain a navigation hierarchy").
struct RoomOverviewSheet {
    var kind: RoomOverviewKind



    /// The sheet's title: its name where the subtitle carries the state, else the web's title with its count.
    static func title(_ kind: RoomOverviewKind, read: RoomOverview.Read) -> String {
        SheetSubtitle.isShown ? RoomOverview.sheetName(kind) : RoomOverview.sheetTitle(kind, read: read)
    }
}
