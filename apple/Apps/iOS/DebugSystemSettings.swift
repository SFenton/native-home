#if DEBUG
import Foundation

/// Debug builds only: lets UI journeys turn the system accessibility settings on and off.
///
/// UIKit launch arguments (`-UIAccessibilityReduceMotionEnabled YES`) do not reach SwiftUI's environment or the
/// system materials, so the journeys pass `FENTON_SYSTEM_SETTINGS` (a comma list of `reduceMotion`,
/// `reduceTransparency`, `increaseContrast`, `boldText`, or `none`) and the app sets the simulator's own
/// accessibility settings through `libAccessibility` before its first window, as accessibility snapshot tools do
/// (`.agents/testing/apple/accessibility.md`, System accessibility settings).
///
/// The settings belong to the whole simulator, not the app: every journey launch passes the list (`none` by
/// default) so the next launch always starts clean.
enum DebugSystemSettings {
    /// Applies the settings named by `FENTON_SYSTEM_SETTINGS`, when it is set.
    static func applyIfRequested() {
        guard let list = ProcessInfo.processInfo.environment["FENTON_SYSTEM_SETTINGS"] else { return }
        let wanted = Set(list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW) else { return }
        typealias SetEnabled = @convention(c) (Int32) -> Void
        func set(_ names: [String], _ on: Bool) {
            for name in names {
                if let symbol = dlsym(library, name) {
                    unsafeBitCast(symbol, to: SetEnabled.self)(on ? 1 : 0)
                    return
                }
            }
            NSLog("DebugSystemSettings: none of %@ found", names.joined(separator: ", "))
        }
        set(["_AXSSetReduceMotionEnabled"], wanted.contains("reduceMotion"))
        set(["_AXSSetEnhanceBackgroundContrastEnabled"], wanted.contains("reduceTransparency"))
        set(["_AXSSetDarkenSystemColors", "_AXSSetDarkenSystemColorsEnabled"], wanted.contains("increaseContrast"))
        set(["_AXSSetEnhanceTextLegibilityEnabled"], wanted.contains("boldText"))
    }
}
#endif
