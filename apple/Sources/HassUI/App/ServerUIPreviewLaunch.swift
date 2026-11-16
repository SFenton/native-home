import Foundation

/// Isolates downloaded-configuration previews from the normal account and house side effects.
public enum ServerUIPreviewLaunch {
    /// Only a debug process explicitly launched in preview mode may use ephemeral design credentials.
    public static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        arguments.contains("--server-ui-preview")
        #else
        false
        #endif
    }
}
