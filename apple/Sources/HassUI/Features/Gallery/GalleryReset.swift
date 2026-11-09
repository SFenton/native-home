#if DEBUG
import Foundation
import HassDesign
import Observation
#if os(iOS)
import UIKit
#endif

/// Debug-only in-place reset of the component gallery, so a UI-test class can keep one running app and move it between launch
/// states instead of paying a cold launch per test (about 6.5 s each; `.agents/testing/apple/app-reuse.md`).
///
/// A journey writes `FENTON_GALLERY=bedroom&FENTON_GALLERY_SCENARIO=ringing` to the request file, which the app watches
/// (``watchRequests()``; a file, not a URL route, because `XCUIApplication.open(_:)` costs about 5 s a test). The app replaces every `FENTON_GALLERY*` variable in its own process environment with the request's, empties the tree for ``blankInterval`` (so sheets and alerts are gone), then bumps
/// ``generation``; ``RootView`` gives the gallery that identity, so SwiftUI discards the whole gallery (its fixtures, sheets,
/// alerts, navigation stack and scroll position) and builds it again from the new variables exactly as a launch would.
/// Variables outside the `FENTON_GALLERY` prefix are never touched, so a test that needs a different launch environment,
/// launch arguments (AX5), appearance or system settings relaunches instead.
///
/// A second request file switches the running page's text size in place (``setTextSize(_:)``): the accessibility audit's AX5 check
/// enlarges the page it just audited instead of relaunching at AX5 and reopening it. The next reset puts the launch's size back.
///
/// The whole type is compiled into Debug builds only and is inert unless the app was launched with `FENTON_UITEST_REUSE=<request directory>`.
@MainActor
@Observable
public final class GalleryReset {
    /// The one instance the root view observes.
    public static let shared = GalleryReset()

    /// How many resets have been applied. The root view publishes it as the `uitest.generation` element's label, which a test
    /// waits on to know the new gallery is built.
    public private(set) var generation = 0

    /// How many reset requests have been applied, counted the moment one is accepted. Unlike ``generation`` it is not observed, so
    /// a gallery's fixtures can key on it (``UKGalleryChrome``) without becoming a dependency of the view that builds them.
    @ObservationIgnored public private(set) var appliedRequests = 0

    /// Whether the gallery is removed from the tree while a reset waits for the old one's sheets to finish dismissing. Presenting
    /// the next gallery's sheet over a sheet that is still leaving would drop it.
    public private(set) var isBlank = false

    /// How long the tree stays empty between the two halves of a reset, in seconds.
    nonisolated public static let blankInterval = 0.4

    /// The URL host that marks a reset request.
    nonisolated public static let host = "uitest-reset"

    /// The variables a reset may change.
    nonisolated public static let prefix = "FENTON_GALLERY"

    /// Whether this launch accepts resets: `FENTON_UITEST_REUSE` names the request directory the test writes to.
    nonisolated public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        !(environment["FENTON_UITEST_REUSE"] ?? "").isEmpty
    }

    /// The request file inside the launch's request directory.
    nonisolated public static func requestFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        environment["FENTON_UITEST_REUSE"].flatMap { $0.isEmpty ? nil : $0 + "/request" }
    }

    /// The text-size request file inside the launch's request directory: `<sequence>\n<UIContentSizeCategory raw value>`, an empty
    /// value for the system's own size. The app writes the sequence it applied to ``textSizeDoneFile(environment:)``.
    nonisolated public static func textSizeFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        environment["FENTON_UITEST_REUSE"].flatMap { $0.isEmpty ? nil : $0 + "/textSize" }
    }

    /// Where the app acknowledges a text-size request.
    nonisolated public static func textSizeDoneFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        textSizeFile(environment: environment).map { $0 + ".done" }
    }

    /// The text size a text-size request file asks for, or nil when `text` is malformed. `size` is nil for the system's own size.
    nonisolated public static func textSizeRequest(from text: String) -> (sequence: Int, size: String?)? {
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = lines.first, let sequence = Int(first) else { return nil }
        let size = lines.count == 2 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return (sequence, size.isEmpty ? nil : size)
    }

    /// The reset a request file asks for: `<sequence>\n<query>`, or nil when `text` is malformed. The test bumps the sequence on
    /// every request, so a repeat of the same query still counts.
    nonisolated public static func request(from text: String) -> (sequence: Int, url: URL)? {
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard lines.count == 2, let sequence = Int(lines[0]),
              let url = URL(string: "fentonhome://\(host)?\(lines[1])") else { return nil }
        return (sequence, url)
    }

    /// Watches the request file (every 50 ms, on the main actor: one small file read) and applies each new request.
    ///
    /// A file instead of `XCUIApplication.open(_:)`: that route makes UI automation re-launch and wait for the app to idle,
    /// about 5 s a test, which is as slow as the launch it replaces (measured 2026-10-30).
    public func watchRequests() async {
        guard let path = Self.requestFile(), let textSizePath = Self.textSizeFile(), let donePath = Self.textSizeDoneFile() else { return }
        var handled = 0
        var handledTextSize = 0
        while !Task.isCancelled {
            if let text = try? String(contentsOfFile: path, encoding: .utf8), let request = Self.request(from: text),
               request.sequence > handled {
                handled = request.sequence
                apply(request.url)
            }
            if let text = try? String(contentsOfFile: textSizePath, encoding: .utf8), let request = Self.textSizeRequest(from: text),
               request.sequence > handledTextSize {
                handledTextSize = request.sequence
                Self.setTextSize(request.size)
                // After a layout pass at the new size, so the test reads the enlarged page.
                try? await Task.sleep(for: .milliseconds(100))
                try? "\(request.sequence)".write(toFile: donePath, atomically: true, encoding: .utf8)
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// What a reset changes in the environment.
    public struct Plan: Equatable, Sendable {
        /// Variables to remove.
        public var unset: [String]
        /// Variables to set.
        public var set: [String: String]
    }

    /// The change a reset URL asks for, or nil when `url` is not a reset request.
    /// - Parameters:
    ///   - url: `fentonhome://uitest-reset?KEY=value&...`.
    ///   - environment: The current environment: its `FENTON_GALLERY*` variables the URL does not repeat are unset.
    ///     Query keys outside the prefix are ignored.
    nonisolated public static func plan(for url: URL, environment: [String: String]) -> Plan? {
        guard url.scheme == "fentonhome", url.host == host else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var set: [String: String] = [:]
        for item in items where item.name.hasPrefix(prefix) { set[item.name] = item.value ?? "" }
        let unset = environment.keys.filter { $0.hasPrefix(prefix) && set[$0] == nil }.sorted()
        return Plan(unset: unset, set: set)
    }

    /// Applies a reset request read from the request file. Returns whether `url` was one (and this launch accepts it).
    @discardableResult
    func apply(_ url: URL) -> Bool {
        guard Self.isEnabled(), let plan = Self.plan(for: url, environment: ProcessInfo.processInfo.environment) else { return false }
        appliedRequests += 1
        for key in plan.unset { unsetenv(key) }
        for (key, value) in plan.set { setenv(key, value, 1) }
        // `FENTON_SHEETFIT_RESET=1` means a launch that has never opened a sheet: a reset gives the next test the same, so the
        // remembered sheet heights and chromes do not warm across tests of a reused app.
        if ProcessInfo.processInfo.environment["FENTON_SHEETFIT_RESET"] == "1" { SheetMemory.clearAll() }
        // A reset starts the next test at the launch's own text size.
        Self.setTextSize(nil)
        isBlank = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.blankInterval))
            isBlank = false
            generation += 1
        }
        return true
    }

    /// Shows `size` (a raw `UIContentSizeCategory`) in every window of the app, or the launch's own size for nil: a trait override on
    /// each window scene, which UIKit and SwiftUI follow live, as they do when someone changes the text size in Control Center. It
    /// lives in this process only, so it cannot outlast the app or reach another one on the simulator.
    static func setTextSize(_ size: String?) {
        #if os(iOS)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            if let size {
                scene.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(rawValue: size)
            } else if scene.traitOverrides.contains(UITraitPreferredContentSizeCategory.self) {
                scene.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
            }
        }
        #endif
    }
}
#endif
