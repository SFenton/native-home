import HassCore
import HassDesign
import SwiftUI

// MARK: - List

/// Where the Settings tab pushes besides the household topics. Every push is a value on the tab's path
/// (``SettingsRoute``, ``HouseholdSettingsPage``), so the shell knows when the tab is not at its root.
enum SettingsRoute: Hashable, Codable, Sendable {
    case vacation, adminTodo, performance
}
