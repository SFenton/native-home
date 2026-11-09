import SwiftUI

/// Whether ``SwiftUICore/View/sheetSubtitle(_:)`` draws anything on this system: callers that would otherwise lose
/// a figure (a count folded into the title) keep it in the title when this is false.
public enum SheetSubtitle {
    /// True on iOS 26 and later, where the system navigation subtitle exists.
    public static var isShown: Bool {
        #if os(iOS)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }
}

public extension View {
    /// The one-line subtitle under a sheet's centred title (`.agents/design/direction-g.md`, Sheets: "Centred title
    /// plus a one-line subtitle"), such as "3 of 12 On" under Lights or "Live" under a camera.
    ///
    /// iOS 26 and later draw it as the system navigation subtitle, which follows the bar's Dynamic Type and Large
    /// Content Viewer rules. Earlier systems show the title alone (Design thread, 2026-10-15): a custom principal title
    /// shrank instead of growing at AX5 and failed the humidifier audit (2026-10-13). Check ``SheetSubtitle/isShown``
    /// where the subtitle carries a figure the sheet shows nowhere else.
    /// - Parameter subtitle: The line, or nil for none.
    @ViewBuilder
    func sheetSubtitle(_ subtitle: String?) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *), let subtitle, !subtitle.isEmpty {
            navigationSubtitle(subtitle)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
