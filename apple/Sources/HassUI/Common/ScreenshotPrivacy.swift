import Foundation

/// Debug-only redaction for screenshots shared outside the household: `FENTON_REDACT_PRIVATE=1` blurs
/// camera snapshots, hides the security and occupancy summaries, and redacts live inventory item names.
/// Always off in release builds, and off in the debug galleries (`FENTON_GALLERY`): their data is synthetic, and
/// journeys assert the states they show ("Armed Home"), which redaction replaced with "Hidden" (Security journeys
/// failed under `TEST_RUNNER_FENTON_REDACT_PRIVATE=1`, 2026-10-16).
enum ScreenshotPrivacy {
    static let isRedacting: Bool = {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return isRedacting(redactFlag: environment["FENTON_REDACT_PRIVATE"], gallery: environment["FENTON_GALLERY"])
        #else
        false
        #endif
    }()

    /// Whether to redact for the given environment values: the flag is `1` and no gallery page is showing.
    static func isRedacting(redactFlag: String?, gallery: String?) -> Bool {
        redactFlag == "1" && (gallery ?? "").isEmpty
    }
}
