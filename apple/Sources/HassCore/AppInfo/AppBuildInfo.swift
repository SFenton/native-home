import Foundation

// MARK: - App build identity

/// Formats the app's own build identity, so a bug report names the exact build: `2610.26.01 (57) · 42edc57`.
///
/// Release builds stamp the version tag's commit into Info.plist as `HassGitSHA` (`HASS_GIT_SHA` in
/// `apple/project.yml`, passed by `tools/release/versioning.py build-settings`); local builds keep the `dev`
/// default and show no commit. See `.agents/workflow/versioning.md`.
public enum AppBuildInfo {
    /// Info.plist key holding the release commit SHA.
    public static let gitSHAKey = "HassGitSHA"

    /// Number of SHA characters shown (git's conventional short SHA).
    public static let shortSHALength = 7

    /// Separator between the version/build and the short commit.
    public static let commitSeparator = " · "

    /// The marketing version, build number and, for stamped builds, the short commit.
    ///
    /// - Parameter info: The bundle's Info.plist dictionary (`Bundle.main.infoDictionary`).
    /// - Returns: `"<version> (<build>)"`, plus `" · <sha7>"` when `HassGitSHA` is a commit; `"—"` stands in for a
    ///   missing version, and a missing build drops the parentheses.
    public static func versionText(_ info: [String: Any]?) -> String {
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        let base = build.map { "\(short) (\($0))" } ?? short
        guard let sha = shortCommit(info?[gitSHAKey] as? String) else { return base }
        return base + commitSeparator + sha
    }

    /// The same identity as VoiceOver should read it: each part named instead of the parentheses and `·` the text
    /// shows, e.g. `"2610.26.01, build 57, commit 42edc57"`.
    ///
    /// - Parameter info: The bundle's Info.plist dictionary (`Bundle.main.infoDictionary`).
    /// - Returns: The version (`"Unknown"` when missing), then `", build <n>"` and `", commit <sha7>"` for the
    ///   parts ``versionText(_:)`` shows.
    public static func spokenVersionText(_ info: [String: Any]?) -> String {
        var parts = [info?["CFBundleShortVersionString"] as? String ?? "Unknown"]
        if let build = info?["CFBundleVersion"] as? String { parts.append("build \(build)") }
        if let sha = shortCommit(info?[gitSHAKey] as? String) { parts.append("commit \(sha)") }
        return parts.joined(separator: ", ")
    }

    /// The first seven characters of a stamped commit SHA.
    ///
    /// - Parameter raw: The `HassGitSHA` value, if present.
    /// - Returns: The short SHA, or nil when the value is absent, `dev`, empty or not hexadecimal (e.g. an
    ///   unexpanded build setting).
    public static func shortCommit(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "dev",
              value.allSatisfy(\.isHexDigit)
        else { return nil }
        return String(value.prefix(shortSHALength)).lowercased()
    }
}
