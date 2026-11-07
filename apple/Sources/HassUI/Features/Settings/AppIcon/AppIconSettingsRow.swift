import HassCore
import HassDesign
import SwiftUI

/// The Settings row for the app icon: a small preview of the installed icon, "App Icon" and its name, opening
/// ``AppIconPickerSheet``. It sits like the other Settings rows (``SettingsLinkRow``), in ``AppearanceSettingsSection``.
struct AppIconSettingsRow {
    let model: AppIconPickerModel


    /// The row's title.
    static let title = "App Icon"
}
