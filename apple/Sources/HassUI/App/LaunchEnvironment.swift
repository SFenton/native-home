import Foundation

/// The process environment as the app should read its `FENTON_*` launch variables.
///
/// A journey passes `FENTON_HASS_*` to the app on purpose (`--env shell`), but `swift test` inherits the developer's
/// whole shell, so a host test must not see them unless it opts in with `FENTON_TEST_HONOURS_TOKEN=1`. Every reader of
/// `FENTON_HASS_*` goes through ``current`` so the rule lives in one place.
enum LaunchEnvironment {
    /// The variables dropped from a host test process.
    static let shellCredentialKeys = ["FENTON_HASS_TOKEN", "FENTON_HASS_USERNAME", "FENTON_HASS_PASSWORD", "FENTON_HASS_SERVER"]

    /// Whether this is the host test runner (`swift test` runs XCTest and Swift Testing in `xctest` or
    /// `swiftpm-testing-helper`), not the app.
    static func isHostTestProcess(name: String, environment: [String: String]) -> Bool {
        name == "xctest" || name.hasPrefix("swiftpm-testing-helper") || environment["XCTestConfigurationFilePath"] != nil
    }

    /// `environment` with `FENTON_HASS_*` removed when the process is a host test that did not opt in.
    static func filtered(_ environment: [String: String], processName: String) -> [String: String] {
        guard isHostTestProcess(name: processName, environment: environment),
              environment["FENTON_TEST_HONOURS_TOKEN"] != "1" else { return environment }
        return environment.filter { !shellCredentialKeys.contains($0.key) }
    }

    /// The live process environment, filtered.
    static var current: [String: String] {
        filtered(ProcessInfo.processInfo.environment, processName: ProcessInfo.processInfo.processName)
    }
}
