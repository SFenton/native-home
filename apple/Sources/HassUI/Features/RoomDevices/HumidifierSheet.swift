import HassCore
import HassDesign
import SwiftUI

/// The humidifier sheet's tabs (web `HUMIDIFIER_MODAL_TABS`).
public enum HumidifierTab: String, CaseIterable, Identifiable, Sendable {
    case controls, schedules, info
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .controls: "Controls"
        case .schedules: "Schedules"
        case .info: "Info"
        }
    }
}

/// When the humidifier sheet splits: the hero dial in a leading column, the tab in a trailing one.
enum HumidifierLayout {
    /// The narrowest sheet that fits the dial beside a tab.
    static let minimumTwoColumnWidth: CGFloat = 640

    /// Only where the window may split (landscape, regular width; `SplitPolicy`) and the sheet is wide enough.
    static func usesTwoColumns(window: CGSize, isRegularWidth: Bool, container: CGSize) -> Bool {
        SplitPolicy.allowsSplit(size: window, isRegularWidth: isRegularWidth) && container.width >= minimumTwoColumnWidth
    }
}
