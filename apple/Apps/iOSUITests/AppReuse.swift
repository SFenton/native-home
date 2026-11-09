import XCTest

/// One running app per journey class, reset between tests instead of relaunched (`.agents/testing/apple/app-reuse.md`).
///
/// A cold launch of the gallery costs about 6.5 s (process start to first frame 4.5 s, UI-automation idle wait 1 s, terminate 1 s).
/// With reuse on (`TEST_RUNNER_FENTON_UITEST_REUSE=1`, which `ios_uitest.sh` sets for every run), ``JourneyTestCase/startApp(_:)``
/// launches once per launch configuration, then asks the running app to rebuild the gallery for the next test through a request file
/// (`GalleryReset` in the app, Debug only). It relaunches instead when:
/// - reuse is off (`TEST_RUNNER_FENTON_UITEST_REUSE=0`, or a run outside `ios_uitest.sh` that does not set it);
/// - the launch arguments or any non-`FENTON_GALLERY*` launch variable differ from the resident app's (appearance, Reduce
///   Motion and other system settings, a custom environment);
/// - the launch has launch arguments (AX5): those always launch fresh;
/// - the resident app was switched to AX5 in place by an audit (``enlargeInPlace(_:)``);
/// - the resident app is no longer running (a test terminated or crashed it), or another launch of the bundle replaced it: the
///   simulator runs one process per bundle id, so there is only ever one live resident, and every launch (a different signature's
///   resident, an AX5 launch) drops all the others at once (`dropResidents()`) instead of leaving a dead one to time out;
/// - the reset does not show its new generation within 10 s.
@MainActor
enum AppReuse {
    /// Whether this run reuses apps.
    static var isOn: Bool { ProcessInfo.processInfo.environment["FENTON_UITEST_REUSE"] == "1" }

    /// The app one class keeps, with the launch configuration it was started with.
    struct Resident {
        var app: XCUIApplication
        var signature: String
        var generation: Int
        var directory: String
        var sequence = 0
    }

    /// Keyed by class and launch signature. At most one entry is live: a later launch of the bundle ends the earlier process, so the
    /// launch drops the others (`dropResidents()`).
    nonisolated(unsafe) private static var resident: [String: Resident] = [:]

    /// Resets and cold launches, for the run's log (`REUSE reused=… launched=…`).
    nonisolated(unsafe) static var reused = 0
    nonisolated(unsafe) static var launched = 0

    /// What must match for a running app to serve the next test: launch arguments and every launch variable that is not a gallery
    /// setting (those are what a reset changes).
    static func signature(of app: XCUIApplication) -> String {
        let environment = app.launchEnvironment.filter { !$0.key.hasPrefix("FENTON_GALLERY") }
            .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return (app.launchArguments + environment).joined(separator: "\u{1F}")
    }

    /// Returns the app for `owner` on the gallery `app` is configured for: the resident one, reset, or a fresh launch.
    /// - Parameters:
    ///   - owner: The test class (one resident app each).
    ///   - app: A configured, not yet launched handle (`FentonHomeApp.makeApp()` plus the test's launch environment).
    static func start(_ app: XCUIApplication, owner: String) -> XCUIApplication {
        // Launch arguments (AX5) always launch fresh: a gallery reset inside an app launched at AX5 left the Food hub and recipe
        // grid cards failing the Dynamic Type audit that a fresh AX5 launch passes (2026-10-31, iPhone and Duo).
        guard isOn, app.launchArguments.isEmpty else {
            // Launching ends whatever process of the bundle is running, so every resident is gone (see ``dropResidents()``).
            if isOn { dropResidents() }
            app.launch()
            return app
        }
        let signature = signature(of: app)
        let gallery = app.launchEnvironment.filter { $0.key.hasPrefix("FENTON_GALLERY") }
        let key = "\(owner)|\(signature)"
        // An app switched to AX5 in place is not reset: a system alert it showed outlived the reset and took the next test's taps
        // (Security disarm alert, 2026-10-31). It is relaunched instead.
        if let current = resident[key], enlarged.remove(current.directory) != nil {
            print("REUSE \(owner): relaunching after an in-place AX5 audit")
            current.app.terminate()
            resident[key] = nil
        }
        if var current = resident[key], current.app.state == .runningForeground || current.app.state == .runningBackground {
            if current.app.state != .runningForeground { current.app.activate() }
            current.sequence += 1
            if reset(current.app, to: gallery, from: current.generation, directory: current.directory, sequence: current.sequence) {
                current.generation += 1
                resident[key] = current
                reused += 1
                return current.app
            }
            print("REUSE reset failed for \(owner); relaunching")
            current.app.terminate()
        }
        // The launch below ends any other resident of the bundle (one process per bundle id on a simulator), so forget them now: the
        // next test of their signature then launches at once instead of writing a reset request to a dead process and waiting 10 s.
        dropResidents()
        let directory = "/tmp/fenton-uitest-reuse/\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        app.launchEnvironment["FENTON_UITEST_REUSE"] = directory
        app.launch()
        if !arrivedWithEnvironment(app) {
            print("REUSE \(owner): the launch arrived without its environment; relaunching once")
            launchesWithoutEnvironment += 1
            app.launch()
        }
        resident[key] = Resident(app: app, signature: signature, generation: 0, directory: directory)
        launched += 1
        return app
    }

    /// Fresh launches that came up without their launch environment and were launched again (``arrivedWithEnvironment(_:)``).
    nonisolated(unsafe) static var launchesWithoutEnvironment = 0

    /// Whether the app just launched received its launch environment: the `uitest.generation` marker is in the tree only when
    /// `FENTON_UITEST_REUSE` reached the app. The first launch of a coverage batch's second `xcodebuild` invocation (right after
    /// Xcode's lazy reinstall of the app) came up with no `FENTON_*` variable at all, signed out instead of on its gallery, in 5 of
    /// 5 runs, while every other launch of the run got them (the app's `UKLaunch variables:` log, 2026-11-04). That is Xcode's
    /// launch, not the test, so the launch is repeated once; a second miss is left for the test's own assertions to report.
    private static func arrivedWithEnvironment(_ app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)["uitest.generation"].firstMatch.waitForExistence(timeout: 3)
    }

    /// Forgets every resident app. A simulator runs one process per bundle id, so any launch of the app (another signature's resident,
    /// an AX5 launch, a test's own `launch()`) terminates the previous process, yet the old `XCUIApplication` handle still reports
    /// `.runningForeground`, and a reset sent to it would wait out the full 10 s before relaunching.
    private static func dropResidents() {
        for (key, gone) in resident {
            resident[key] = nil
            enlarged.remove(gone.directory)
            try? FileManager.default.removeItem(atPath: gone.directory)
        }
    }

    /// Call before a test's own `app.launch()` (a test about the app lifecycle): that launch ends the resident process, so the
    /// resident is forgotten and the next test launches at once instead of waiting out a 10 s reset on the dead handle.
    static func willLaunchOutside() {
        if isOn { dropResidents() }
    }

    /// Ends the class's resident app.
    static func finish(owner: String) {
        let keys = resident.keys.filter { $0.hasPrefix("\(owner)|") }
        guard !keys.isEmpty else { return }
        print("REUSE \(owner) reused=\(reused) launched=\(launched) withoutEnvironment=\(launchesWithoutEnvironment)")
        for key in keys {
            guard let current = resident.removeValue(forKey: key) else { continue }
            current.app.terminate()
            try? FileManager.default.removeItem(atPath: current.directory)
        }
    }

    /// Text-size requests sent per request directory (the app ignores a sequence it has seen).
    nonisolated(unsafe) private static var textSizeSequence: [String: Int] = [:]

    /// Request directories of apps switched to AX5 in place: the next test relaunches rather than resets them.
    nonisolated(unsafe) private static var enlarged: Set<String> = []

    /// Switches the running `app` to AX5 in place and returns it, or nil when it cannot: the app was not launched with a reuse
    /// request directory, is not running, `FENTON_UITEST_AX5_RELAUNCH=1` asks for the relaunch, or the app does not acknowledge
    /// within 5 s. The audit then relaunches at AX5 instead (`FentonHomeApp.audit`). The next reset puts the launch's size back.
    static func enlargeInPlace(_ app: XCUIApplication) -> XCUIApplication? {
        guard ProcessInfo.processInfo.environment["FENTON_UITEST_AX5_RELAUNCH"] != "1",
              let directory = app.launchEnvironment["FENTON_UITEST_REUSE"], directory.hasPrefix("/"),
              app.state == .runningForeground else { return nil }
        guard setTextSize(app, FentonHomeApp.ax5[1]) else {
            print("AX5 in place not acknowledged; relaunching at AX5")
            return nil
        }
        enlarged.insert(directory)
        print("AX5 in place")
        return app
    }

    /// Puts the running reuse `app` at the content size category `size` (a raw `UIContentSizeCategory`) and waits for the app to
    /// acknowledge, up to 5 s. False when the app was not launched with a reuse request directory or does not acknowledge. The
    /// next reset puts the launch's size back, so unlike ``enlargeInPlace(_:)`` this does not make the next test relaunch.
    static func setTextSize(_ app: XCUIApplication, _ size: String) -> Bool {
        guard let directory = app.launchEnvironment["FENTON_UITEST_REUSE"], directory.hasPrefix("/") else { return false }
        let sequence = (textSizeSequence[directory] ?? 0) + 1
        textSizeSequence[directory] = sequence
        do { try "\(sequence)\n\(size)".write(toFile: directory + "/textSize", atomically: true, encoding: .utf8) } catch { return false }
        let done = directory + "/textSize.done"
        let end = Date().addingTimeInterval(5)
        while Date() < end {
            if (try? String(contentsOfFile: done, encoding: .utf8)) == "\(sequence)" { return true }
            usleep(50_000)
        }
        return false
    }

    private static func reset(_ app: XCUIApplication, to gallery: [String: String], from generation: Int, directory: String,
                              sequence: Int) -> Bool {
        var components = URLComponents()
        components.queryItems = gallery.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let query = components.percentEncodedQuery ?? ""
        do { try "\(sequence)\n\(query)".write(toFile: directory + "/request", atomically: true, encoding: .utf8) } catch { return false }
        let marker = app.descendants(matching: .any)["uitest.generation"].firstMatch
        let expected = "\(generation + 1)"
        let end = Date().addingTimeInterval(10)
        // The app's tree is empty for `GalleryReset.blankInterval` (0.4 s) by design, so the wait cannot beat that; each check is itself a
        // 20-40 ms accessibility request, so the pause between checks is short (it was 50 ms, which delayed the answer by ~35 ms on average).
        while Date() < end {
            if marker.exists, marker.label == expected { return true }
            usleep(10_000)
        }
        return false
    }
}

extension JourneyTestCase {
    /// Launches (or, with reuse on, resets) the gallery for this test and returns the app.
    /// - Parameter app: The configured, not yet launched handle.
    func startApp(_ app: XCUIApplication) -> XCUIApplication {
        AppReuse.start(app, owner: String(describing: type(of: self)))
    }
}
