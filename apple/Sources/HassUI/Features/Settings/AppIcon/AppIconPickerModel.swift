import FentonActivityModel
import HassCore
import Observation

/// The state behind Settings → App Icon: which icon is installed and the change in flight.
///
/// The row and the sheet share one model, so the row's preview follows a choice made in the sheet. The system calls
/// are injected (``AppIconPlatform``), so tests drive it without `UIApplication`. Every installed choice is also written to
/// the app group (``ActivityAppIconStore``) so a Live Activity's corner mark follows it.
@MainActor @Observable
final class AppIconPickerModel {
    private let platform: AppIconPlatform
    private let iconStore: ActivityAppIconStore

    /// The icon that is installed, read back from the system after every change.
    private(set) var selected: AppIconChoice
    /// Whether a change is waiting on the system; taps are ignored meanwhile.
    private(set) var isChanging = false
    /// The text of the error alert after a change the system refused, nil when there is none.
    var failureMessage: String?

    /// Creates the model over the installed icon.
    init(platform: AppIconPlatform, iconStore: ActivityAppIconStore = .shared) {
        self.platform = platform
        self.iconStore = iconStore
        isSupported = platform.supportsAlternateIcons()
        selected = AppIconChoice(alternateIconName: platform.currentName())
    }

    /// Whether the app can switch icons on this device, read once with the installed icon.
    let isSupported: Bool

    /// Whether `choice` is the installed icon.
    func isSelected(_ choice: AppIconChoice) -> Bool { choice == selected }

    /// Installs `choice`. iOS shows its own notice when the icon changes; a refusal raises ``failureMessage`` and leaves
    /// the selection where it was.
    func select(_ choice: AppIconChoice) async {
        guard !isChanging, choice != selected else { return }
        isChanging = true
        defer { isChanging = false }
        do {
            try await platform.setName(choice.alternateIconName)
            selected = AppIconChoice(alternateIconName: platform.currentName())
            iconStore.write(selected.rawValue)
        } catch {
            failureMessage = Self.failureText(for: choice, error: error)
        }
    }

    /// The alert's message: the choice that failed and the system's reason.
    static func failureText(for choice: AppIconChoice, error: any Error) -> String {
        "The icon wasn't changed to \(choice.displayName). \(error.localizedDescription)"
    }
}

/// Keeps the app group's icon choice (``ActivityAppIconStore``) in step with the installed icon, so the Live Activity's
/// corner mark has it even before the person opens Settings.
public enum AppIconAppGroupSync {
    /// Writes the installed icon's choice; the app calls it at launch.
    @MainActor
    public static func writeInstalledChoice() {
        write(platform: .system, store: .shared)
    }

    @MainActor
    static func write(platform: AppIconPlatform, store: ActivityAppIconStore) {
        store.write(AppIconChoice(alternateIconName: platform.currentName()).rawValue)
    }
}
