import SwiftUI

/// Builds the one ``AppIconPickerModel`` of a Settings list the first time its row draws.
///
/// The model reads the installed icon (`UIApplication.alternateIconName`), a synchronous Launch Services call that
/// blocks while the system is changing the icon (spindump, iPhone 17 Pro simulator, 2026-10-17: the app hung 30 s with
/// the "icon changed" notice up). A `@State` initialised in the row's `init` would run that read on every redraw of the
/// Settings list, including the ones during a change; this runs it once, when the row first draws.
@MainActor
final class AppIconPickerModelStore {
    private var model: AppIconPickerModel?

    /// The model over `platform`, created on first use.
    func model(for platform: AppIconPlatform) -> AppIconPickerModel {
        if let model { return model }
        let made = AppIconPickerModel(platform: platform)
        model = made
        return made
    }
}
