import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// The system's alternate-icon calls, behind closures so tests do not touch `UIApplication`
/// (``AppIconPickerModel``). The view environment carries one (``SwiftUICore/EnvironmentValues/appIconPlatform``),
/// the real thing by default.
struct AppIconPlatform: Sendable {
    /// Whether the app can switch icons at all (`UIApplication.supportsAlternateIcons`); the Settings row hides when not.
    var supportsAlternateIcons: @MainActor @Sendable () -> Bool
    /// The installed icon's name (`UIApplication.alternateIconName`): nil for the default.
    var currentName: @MainActor @Sendable () -> String?
    /// Switches the icon (`setAlternateIconName(_:)`): nil restores the default. iOS shows its own notice after it.
    var setName: @MainActor @Sendable (String?) async throws -> Void

    /// The device's real calls. Off iOS (the macOS test host) the app has no alternate icons.
    static let system: AppIconPlatform = {
        #if canImport(UIKit) && !os(watchOS)
        AppIconPlatform(
            supportsAlternateIcons: { UIApplication.shared.supportsAlternateIcons },
            currentName: { UIApplication.shared.alternateIconName },
            setName: { try await UIApplication.shared.setAlternateIconName($0) }
        )
        #else
        AppIconPlatform(supportsAlternateIcons: { false }, currentName: { nil }, setName: { _ in })
        #endif
    }()
}
