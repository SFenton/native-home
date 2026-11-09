import XCTest
import Vision

/// Launch helpers shared by every journey.
///
/// Credentials come only from the test runner's environment (`TEST_RUNNER_FENTON_HASS_USERNAME`,
/// `TEST_RUNNER_FENTON_HASS_PASSWORD` or `TEST_RUNNER_FENTON_HASS_TOKEN`, optional
/// `TEST_RUNNER_FENTON_HASS_SERVER`), set by the `--env shell` test scripts, which load them in-process
/// from `~/.config/fenton-hass/env` (`tools/hass_creds.sh`). They are never committed or logged.
@MainActor
enum FentonHomeApp {
    /// Which device family the run is on, from the simulator's own name (never hard-coded per test).
    enum Family { case iPhone, iPhoneDuo, iPad }

    static var family: Family {
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        if name.localizedCaseInsensitiveContains("Duo") { return .iPhoneDuo }
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    }

    static var credentials: (username: String, password: String, server: String?)? {
        let environment = ProcessInfo.processInfo.environment
        guard let username = environment["FENTON_HASS_USERNAME"], !username.isEmpty,
              let password = environment["FENTON_HASS_PASSWORD"], !password.isEmpty else { return nil }
        return (username, password, environment["FENTON_HASS_SERVER"])
    }

    /// Whether launches turn the app's animations off (`FENTON_UITEST_NO_ANIMATIONS=1`; `Apps/iOS/UKAppDelegate.swift`). On by
    /// default for speed; the motion and performance tests, which measure animation, set it false in `setUp`
    /// (``MeasuresAnimation``) and every ``JourneyTestCase`` restores it. `TEST_RUNNER_FENTON_UITEST_ANIMATIONS=1` keeps
    /// animations for a whole run.
    nonisolated(unsafe) static var animationsOff = ProcessInfo.processInfo.environment["FENTON_UITEST_ANIMATIONS"] != "1"

    /// The app under test: the app the test target builds, or another bundle when the runner sets `TEST_RUNNER_FENTON_APP_BUNDLE`.
    static func target() -> XCUIApplication {
        if let bundle = ProcessInfo.processInfo.environment["FENTON_APP_BUNDLE"], !bundle.isEmpty {
            return XCUIApplication(bundleIdentifier: bundle)
        }
        return XCUIApplication()
    }

    /// A fresh app handle; forwards `FENTON_REDACT_PRIVATE` so shared screenshots hide private data, and
    /// `FENTON_APPEARANCE` (`light` or `dark`) so a whole run can draw its sheets in light
    /// (`TEST_RUNNER_FENTON_APPEARANCE=light`, or `tools/ios_uitest.sh --appearance light`).
    static func makeApp() -> XCUIApplication {
        let app = target()
        ImpactRecorder.apply(to: app)  // test impact recording; a no-op unless `ios_uitest.sh --impact` set the directory
        // The settings belong to the simulator, so every launch states them: none unless a journey asks.
        app.launchEnvironment["FENTON_SYSTEM_SETTINGS"] = "none"
        // The sign-in intro (1.2 s) is only for the journeys that are about it (`SignInJourneyTests`, `LaunchPerformanceTests`).
        app.launchEnvironment["FENTON_SKIP_INTRO"] = "1"
        if animationsOff {
            app.launchEnvironment["FENTON_UITEST_NO_ANIMATIONS"] = "1"
            // `TEST_RUNNER_FENTON_UITEST_ANIMATION_SPEED=<n>` sets the animation speed multiplier (the app's default is 10).
            if let speed = ProcessInfo.processInfo.environment["FENTON_UITEST_ANIMATION_SPEED"] {
                app.launchEnvironment["FENTON_UITEST_ANIMATION_SPEED"] = speed
            }
        }
        if let redact = ProcessInfo.processInfo.environment["FENTON_REDACT_PRIVATE"] {
            app.launchEnvironment["FENTON_REDACT_PRIVATE"] = redact
        }
        if let appearance = ProcessInfo.processInfo.environment["FENTON_APPEARANCE"] {
            app.launchEnvironment["FENTON_APPEARANCE"] = appearance
        }
        return app
    }

    /// Whether this test process has waited for a launch yet.
    nonisolated(unsafe) private static var hasWaitedForALaunch = false

    /// How long to wait for the first screen after `app.launch()`: `base`, plus 20 s the first time in a test process, because
    /// the first launch after an install on a cold simulator (a fresh boot, the app's first run) can take far longer than
    /// the ones after it. Bounded: a launch that never shows its screen still fails, after 30 s once and 10 s after.
    static func launchWait(_ base: TimeInterval = 10) -> TimeInterval {
        defer { hasWaitedForALaunch = true }
        return hasWaitedForALaunch ? base : base + 20
    }

    /// Launches signed out.
    static func launchSignedOut() -> XCUIApplication {
        let app = makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launch()
        return app
    }

    /// Launches signed out, then signs in with the runner's credentials. Skips when none are provided.
    /// `TEST_RUNNER_FENTON_HASS_TOKEN` (a long-lived access token) takes precedence over the password.
    /// - Parameter passwordOnly: Ignore the token and go through the real login flow.
    ///   - arguments: Extra launch arguments (e.g. ``ax5``).
    ///   - environment: Extra launch environment (e.g. `FENTON_CAMERA_MODE`).
    ///   - readyIdentifier: What shows once signed in, when not Home (e.g. `inventory.pantry` with
    ///     `FENTON_OPEN_INVENTORY`, which pushes the page over Home).
    static func launchSignedIn(passwordOnly: Bool = false, arguments: [String] = [], environment extra: [String: String] = [:],
                               readyIdentifier: String? = nil) throws -> XCUIApplication {
        func ready(_ app: XCUIApplication) -> XCUIElement {
            readyIdentifier.map { app.descendants(matching: .any)[$0] } ?? app.buttons["home.chip.lights"]
        }
        let environment = ProcessInfo.processInfo.environment
        if !passwordOnly, let token = environment["FENTON_HASS_TOKEN"], !token.isEmpty {
            let app = makeApp()
            app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
            app.launchEnvironment["FENTON_HASS_TOKEN"] = token
            app.launchArguments += arguments
            app.launchEnvironment.merge(extra) { _, new in new }
            if let server = environment["FENTON_HASS_SERVER"] { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
            app.launch()
            XCTAssertTrue(ready(app).appears(timeout: 30), "Home did not appear")
            return app
        }
        guard let credentials else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_HASS_USERNAME / _PASSWORD to run signed-in journeys")
        }
        let app = makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_HASS_USERNAME"] = credentials.username
        app.launchEnvironment["FENTON_HASS_PASSWORD"] = credentials.password
        app.launchArguments += arguments
        app.launchEnvironment.merge(extra) { _, new in new }
        if let server = credentials.server { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(app.textFields["login.username"].appears(timeout: launchWait()), "Sign-in did not appear")
        // At AX5 on a short screen (the folded iPhone Duo) Sign In sits below the fold: the form scrolls.
        let form = app.scrollViews.firstMatch
        for _ in 0..<6 where !(submit.exists && submit.isHittable) {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25)))
        }
        XCTAssertTrue(submit.appears(timeout: 10), "Sign In button not reachable")
        submit.tap()
        XCTAssertTrue(ready(app).appears(timeout: 30), "Home did not appear after sign-in")
        return app
    }

    /// Launches the debug component gallery on `page` (e.g. `thermostat-dial`): fixture data, no sign-in.
    /// - Parameter appearance: `light` or `dark` pins the sheets' appearance for this launch (`FENTON_APPEARANCE`); nil
    ///   keeps the runner's, else the simulator's own.
    static func launchGallery(_ page: String, arguments: [String] = [], environment: [String: String] = [:],
                              appearance: String? = nil) -> XCUIApplication {
        let app = makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = page
        app.launchEnvironment.merge(environment) { _, new in new }
        if let appearance { app.launchEnvironment["FENTON_APPEARANCE"] = appearance }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    /// Launch arguments for the largest accessibility text size (AX5).
    static let ax5 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    /// A system accessibility setting a journey can launch the app with (`.agents/testing/apple/accessibility.md`,
    /// System accessibility settings). UIKit's `-UIAccessibility...Enabled` launch arguments do not reach SwiftUI's
    /// environment (probed 2026-10-15), so the debug app sets the simulator's own settings from
    /// `FENTON_SYSTEM_SETTINGS` (`DebugSystemSettings`). Pass ``environment(_:)`` as the launch environment, then
    /// prove it took with the `system-accessibility` gallery (`SystemSettingsJourneyTests`).
    enum SystemSetting: String, CaseIterable {
        case reduceMotion, reduceTransparency, increaseContrast, boldText

        /// The launch environment that turns exactly the given settings on (and the rest off).
        static func environment(_ settings: [SystemSetting]) -> [String: String] {
            ["FENTON_SYSTEM_SETTINGS": settings.isEmpty ? "none" : settings.map(\.rawValue).joined(separator: ",")]
        }
    }

    /// Every setting at once: Reduce Motion, Reduce Transparency, Increase Contrast and Bold Text.
    static let allSystemSettings = SystemSetting.environment(SystemSetting.allCases)

    /// Runs the full audit, accepting only issues on system-drawn elements the app does not style:
    /// the grouped `Form` section header's secondary text, toolbar bar buttons (e.g. a sheet's glass Close), and
    /// the system's dimmed style on disabled controls (exempt from WCAG 1.4.3).
    /// Collects every remaining issue so one run lists them all, then fails once with the list.
    ///
    /// "Dynamic Type font sizes are (partially) unsupported" is a known false positive on iPad (Festival's
    /// `dynamic-type-grows` waiver). With `ax5Page` (relaunches the same page at AX5; a reuse launch is switched to AX5 in place
    /// instead, ``AppReuse/enlargeInPlace(_:)``) such an issue is
    /// accepted only when the same text is at least 1.35x taller there; an issue with no element only
    /// when every sampled text on the page grew that much (the sample: unique on-screen texts and buttons).
    /// A flagged label that is unique on the audited page but absent from the AX5 page (e.g. scrolled out of a
    /// sheet) is inconclusive: logged, not failed.
    /// "Text clipped" on a labelled element is waived only when the element is fully inside the window on both
    /// pages and measured at least 1.35x taller at AX5 (the reason is logged); any other clip stays open.
    ///
    /// `reflowing` lists identifier prefixes of controls left out of the page-growth sample because they reflow into a shorter row.
    ///
    /// `presenter` names a control on the page under a sheet: element-less "potentially inaccessible
    /// text" is the page showing around an iPad form sheet, accepted only while that control can't be hit.
    static func audit(
        _ app: XCUIApplication, ax5Page: (() throws -> XCUIApplication)? = nil, presenter: XCUIElement? = nil,
        reflowing reflowingIdentifiers: [String] = [],
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        var open: [String] = []
        var unconfirmedType: [(label: String, height: CGFloat)] = []
        var unattributedType = 0
        var clipped: [(label: String, frame: CGRect, issue: String)] = []
        let capture = RenderedContrast.Capture.screen()
        // Read once: per-issue queries add up, and many accessibility requests crash the iPad simulator's backboardd.
        let floatingBarTop = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fab.'"))
            .allElementsBoundByIndex.map(\.frame.minY).min()
        // Noted before the audit too: it can dismiss an alert as well.
        let alertUp = app.alerts.firstMatch.exists
        // The audit can dismiss a popover while it runs, so note it before starting.
        let popover = app.otherElements["PopoverDismissRegion"].exists && app.popovers.firstMatch.exists
            ? app.popovers.firstMatch.frame : nil
        // The handler only collects: element queries made inside it count against the audit's own deadline, and on
        // a long scrolled list (iPhone vacuum Auto-Clean tab, 2026-10-12) they made it fail "to complete in time".
        // Contrast runs as its own pass: alongside the Dynamic Type or text-clipping checks its issues can lose their
        // element (probed 2026-10-11: a row half under the floating action bar came back unattributed), and an
        // unattributed issue cannot be measured or placed.
        var issues: [XCUIAccessibilityAuditIssue] = []
        try app.performAccessibilityAudit(for: .contrast) { issue in
            issues.append(issue)
            return true
        }
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast)) { issue in
            issues.append(issue)
            return true
        }
        // Page text under the floating action bar's hard scroll edge is faded out, and its contrast issue can come
        // back without an element (FloatingActions gallery, iPhone 2026-10-12). Like the tab bar rule, accept an
        // element-less contrast issue only while page text really sits under the bar. Read once, after the audit.
        // One snapshot of the page instead of a label and a frame request per static text. A row is a static text, a button or a
        // switch in the UIKit port; the floating action bar's own buttons (`fab.`) do not count.
        let textUnderFloatingBar = floatingBarTop.map { top in
            func hasTextUnder(_ node: XCUIElementSnapshot) -> Bool {
                if [.staticText, .button, .switch].contains(node.elementType), !node.label.isEmpty, !node.identifier.hasPrefix("fab."),
                   node.frame.maxY > top, node.frame.minY < top + 52 { return true }
                return node.children.contains(where: hasTextUnder)
            }
            guard let root = try? app.snapshot() else {
                let live = app.staticTexts.allElementsBoundByIndex + app.buttons.allElementsBoundByIndex + app.switches.allElementsBoundByIndex
                return live.contains { !$0.label.isEmpty && !$0.identifier.hasPrefix("fab.") && $0.frame.maxY > top && $0.frame.minY < top + 52 }
            }
            return hasTextUnder(root)
        } ?? false
        // An element-less contrast issue cannot be placed. It is accepted only when every labelled text and button on
        // the page measures at least 4.5:1 in a capture from this run (read once, only when one comes back).
        var lowText: [String]?
        func everyTextClears() -> Bool {
            if lowText == nil { lowText = capture.map { lowestVisibleText(below: 4.5, in: app, capture: $0) } ?? ["no capture"] }
            return lowText?.isEmpty == true
        }
        // Whether Home's chips can be hit (they can't while a sheet's dimming layer covers them); asked once, by `exists` first: on a
        // page without them, `isHittable` alone retries for about 3 s before it answers no.
        var homeChipHittable: Bool?
        func homeChipCovered() -> Bool {
            if homeChipHittable == nil {
                let chip = app.buttons["home.chip.lights"]
                homeChipHittable = chip.exists && chip.isHittable
            }
            return homeChipHittable == false
        }
        for issue in issues {
            // Read once: an element that no longer resolves (the page behind an iPad form sheet) costs about 2 s of XCTest retries
            // on every read before it comes back nil (iPad Food Filter audit, 2026-10-30: about 55 s of a 96 s test).
            let issueElement = issue.element
            // The system compact date picker's own time label, unstyled by the app: the combined date-and-time
            // picker reports it with no element, or one that no longer resolves (no type, label or frame), although it
            // renders label ink on the system fill (black on light gray in the audited screenshot, iPhone Vacation
            // Dates, 2026-10-13). A resolvable element is still checked like any other. Decided before the element's
            // attributes are read: an element that does not resolve makes every read wait out XCTest's retries.
            if issue.auditType == .contrast, issue.detailedDescription.contains("_UIDatePickerCompact"),
               issueElement.map({ !$0.exists }) ?? true {
                continue
            }
            let facts = issueElement.map(ElementFacts.init)
            if isSystemDrawn(issue, element: issueElement, facts: facts, in: app, popover: popover, homeChipCovered: homeChipCovered) { continue }
            // The page behind a system alert is hidden from assistive technologies by the alert; its text comes back as
            // element-less "potentially inaccessible text" (Security disarm alert, iPad, 2026-10-16: 6 issues).
            if issueElement == nil, issue.auditType == .elementDetection, alertUp { continue }
            if issue.auditType == .contrast, issueElement == nil, textUnderFloatingBar { continue }
            // The bar is Liquid Glass with a soft scroll edge, so a row scrolled under it stays drawn, blurred, behind the
            // buttons (owner, 2026-10-16: content shows through). The audit sees that blurred text as pixels with no
            // element, element-less "potentially inaccessible text" (Chores tab and Floating Actions gallery, folded
            // iPhone Duo, 2026-10-17; the rows are real elements the scroll view still reports).
            if issue.auditType == .elementDetection, issueElement == nil, textUnderFloatingBar { continue }
            if issue.auditType == .contrast, issueElement == nil, everyTextClears() {
                let note = "Element-less contrast issue accepted: every labelled text and button on screen measured at least 4.5:1 rendered"
                print(note)
                XCTContext.runActivity(named: note) { _ in }
                continue
            }
            // The presenting page around an iPad form sheet, hidden from assistive technologies by the modal.
            if issueElement == nil, issue.auditType == .elementDetection, let presenter,
               presenter.exists, !presenter.isHittable {
                continue
            }
            // An action disc's glyph: 3:1 non-text contrast (WCAG 1.4.11, owner's decision; see `lowestVisibleText`).
            if issue.auditType == .contrast, let facts, facts.elementType == .button,
               facts.identifier.contains(".action.") { continue }
            var measured = ""
            if issue.auditType == .contrast, let element = issueElement, let facts, let capture,
               var ratio = RenderedContrast.ratio(of: facts.frame, in: capture) {
                // The audit scrolls long sheets to inspect elements, so the frame it reports can belong to a later
                // scroll position than the opening capture (iPad vacuum sheet, 2026-10-12: visible 19:1 text measured
                // 1.2:1). Measure a low reading again against the screen as it is now.
                if ratio < 4.5, let now = RenderedContrast.Capture.screen(),
                   let fresh = RenderedContrast.ratio(of: facts.frame, in: now) {
                    ratio = max(ratio, fresh)
                }
                // The audit misjudges text on materials (notably on iPad); accept it when it renders >= 4.5:1.
                if ratio >= 4.5 { continue }
                // Nothing drawn at an unreachable element: it is scrolled out of view (e.g. below an iPad
                // form sheet's edge), not low contrast.
                if ratio < 1.5, !element.isHittable { continue }
                // Nothing drawn under the floating action bar: its hard scroll edge covers rows that scroll
                // beneath it (inventory All Food, 2026-10-11), so the text is hidden, not low contrast.
                if ratio < 1.5, let floatingBarTop, facts.frame.maxY > floatingBarTop { continue }
                // Text mostly inside the bar's strip is faded by the same edge, so it measures low but not nothing
                // (Chores "Replace LV600S Water Filter Sponge" under Add Task, folded Duo, 2.7:1, 2026-10-16).
                if let floatingBarTop, facts.frame.midY > floatingBarTop { continue }
                measured = String(format: " (rendered %.1f:1)", ratio)
            }
            // "May be clipped at larger sizes" is disproved the same way as partial support: at AX5 the text is
            // 1.35x taller, so it wraps rather than clips (a FilterSection header wrapped to three lines, 2026-10-12).
            if ax5Page != nil, issue.auditType == .textClipped
                || (issue.auditType == .dynamicType
                    && issue.compactDescription.localizedCaseInsensitiveContains("font sizes are")) {
                if let facts, !facts.label.isEmpty {
                    unconfirmedType.append((facts.label, facts.frame.height))
                } else {
                    unattributedType += 1
                }
                continue
            }
            // "Text clipped" on a labelled element: decided against the AX5 page below.
            if ax5Page != nil, issue.auditType == .textClipped, let facts, !facts.label.isEmpty {
                clipped.append((facts.label, facts.frame,
                                "\(issue.compactDescription): \(facts.elementType.rawValue) '\(facts.label)' \(issue.detailedDescription)"))
                continue
            }
            let element = facts
            if issue.auditType == .contrast, element == nil, let lowText, !lowText.isEmpty {
                open.append("Texts under 4.5:1 rendered on this page (an element-less contrast issue needs none): " + lowText.joined(separator: "; "))
            }
            open.append("\(issue.compactDescription): \(element?.elementType.rawValue ?? 0) '\(element?.label ?? "")' at \(element.map { "\($0.frame)" } ?? "?")\(measured) "
                + issue.detailedDescription + (element == nil ? " [\(issue)]" : "")
                + (element == nil && issue.auditType == .elementDetection
                    ? " UNLABELLED: " + unlabelledTexts(in: app).map { "'\($0.text)' \($0.frame)" }.joined(separator: "; ") : ""))
        }
        // The screen as audited: taken now only when an AX5 check follows (it changes the screen); otherwise a passing audit pays for
        // no screenshot and a failing one takes it below, of the same unchanged screen.
        let needsAX5 = ax5Page != nil && (!unconfirmedType.isEmpty || unattributedType > 0 || !clipped.isEmpty)
        let auditedScreen = needsAX5 ? XCTAttachment(screenshot: app.screenshot()) : nil
        if let ax5Page, needsAX5 {
            // Only labels that name one content text on the page: bar titles are left out (they barely
            // scale and can repeat a section header, like the Home Assistant modal's), and comparing two
            // different texts proves nothing. Read from one snapshot per page: per-label queries ran
            // hundreds of accessibility requests and crashed the iPad simulator's backboardd.
            func uniqueTexts(in app: XCUIApplication) -> [String: CGRect] {
                guard let root = try? app.snapshot() else { return [:] }
                var bars: [CGRect] = []
                var texts: [(String, CGRect)] = []
                func walk(_ node: XCUIElementSnapshot) {
                    if node.elementType == .navigationBar { bars.append(node.frame) }
                    // Buttons too: a Form button (a sheet's Reset row) is a button element, not static text.
                    // A control that reflows at AX5 into a compact row (an image card) can get shorter, so it says nothing about
                    // whether the page's text grew.
                    if [.staticText, .button].contains(node.elementType), !node.label.isEmpty,
                       !reflowingIdentifiers.contains(where: { node.identifier.hasPrefix($0) }) {
                        texts.append((node.label, node.frame))
                    }
                    node.children.forEach(walk)
                }
                walk(root)
                let content = texts.filter { text in !bars.contains { $0.intersects(text.1) } }
                let counts = Dictionary(content.map { ($0.0, 1) }, uniquingKeysWith: +)
                return Dictionary(content.filter { counts[$0.0] == 1 }, uniquingKeysWith: { first, _ in first })
            }
            let before = uniqueTexts(in: app)
            // The page check samples the same texts and buttons uniqueTexts collects, on screen (inside the
            // window) but not necessarily hittable: under an iPad form sheet the page's own texts are rarely
            // hittable, and requiring it left the sample empty.
            let window = app.windows.firstMatch.frame
            let sample = before.filter { window.contains($0.value) }
                .sorted { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }
                .prefix(12)
                .map { ($0.key, $0.value.height) }
            // Decided before the relaunch: `large` is the same app, so `app` then shows the AX5 page.
            let flagged = Set((unconfirmedType.map(\.label) + clipped.map(\.label)).filter { before[$0] != nil })
            let uniqueBefore = Set(sample.map(\.0)).union(flagged)
            // The page sample decides only an issue with no element or on a label that is not unique on the audited page;
            // otherwise it is read where it shows but the measuring stops once every flagged label is measured.
            let needsPage = unattributedType > 0 || unconfirmedType.contains { before[$0.label] == nil }
            let required = needsPage ? uniqueBefore : flagged
            /// The AX5 evidence on `large`: what stays open.
            func judge(_ large: XCUIApplication) -> [String] {
                var result: [String] = []
                // Hosted run 42448367681 (iPhone Duo, 2026-11-08): the audit itself finished in about 30 s, then this relaunched
                // page's first element query (the collection view probe below) timed out three times at 30 s each ("Failed to get
                // matching snapshots") until the 5-minute test allowance ended the run. The relaunch's "Wait for idle" had
                // returned, but the accessibility tree of the cold two-display simulator was not serving snapshots yet. Wait here,
                // for a bounded 90 s, until the page has a window, so a slow first frame is absorbed and a page that never comes
                // up fails in 90 s with a message instead of hanging the whole test. Every family takes this path; it only waits
                // when the page is not up, so the iPhone and iPad audits are unchanged.
                guard large.windows.firstMatch.waitForExistence(timeout: 90) else {
                    return ["the AX5 page showed no window within 90 s of the relaunch"]
                }
                // AX5 pushes rows below the fold (the folded iPhone Duo shows one or two), so scroll the
                // page to measure every text this audit needs, until the page stops moving.
                var largeHeights: [String: CGFloat] = [:]
                var largeFrames: [String: CGRect] = [:]
                var previous: [String: CGRect]?
                for _ in 0..<8 {
                    let texts = uniqueTexts(in: large)
                    for (label, frame) in texts where uniqueBefore.contains(label) && largeHeights[label] == nil {
                        largeHeights[label] = frame.height
                        largeFrames[label] = frame
                    }
                    let scroller = large.collectionViews.firstMatch.exists ? large.collectionViews.firstMatch : large.scrollViews.firstMatch
                    guard !required.isSubset(of: largeHeights.keys), scroller.exists, texts != previous else { break }
                    previous = texts
                    scroller.swipeUp()
                }
                func grew(_ label: String, _ height: CGFloat) -> Bool? {
                    // Text already 60 pt tall at AX5 is bigger than the largest standard text (AX5 body is about 53 pt): a
                    // display numeral drawn to fit its dial (the thermostat's 72, 91 → 71 pt in iPad landscape, 2026-10-16)
                    // needs no further growth.
                    // Only a bare number: a paragraph is that tall just by wrapping.
                    let numeral = Double(label) != nil
                    return largeHeights[label].map { $0 >= height * 1.35 || (numeral && $0 >= 60) }
                }
                // A live value (humidity, temperature) can change between launches; then the page decides:
                // the sampled texts together are 1.35x taller and none shrank. Measured together because a
                // grouped section header's frame carries fixed padding (Server: 40.3 → 52 pt at AX5 while
                // its glyphs triple), so it can miss 1.35x alone.
                let compared = sample.compactMap { label, height in largeHeights[label].map { (height, $0) } }
                // "None shrank" allows half a point: the same fixed-size text measures 52.0 and 51.99 in two launches
                // (folded Duo, FloatingActions page, 2026-10-17: every pair printed 52.0 → 52.0 and the check failed).
                let pageGrew = !compared.isEmpty && compared.allSatisfy { $0.1 >= $0.0 - 0.5 }
                    && compared.map(\.1).reduce(0, +) >= 1.35 * compared.map(\.0).reduce(0, +)
                var missed = false
                var inconclusive: [String] = []
                for (label, height) in unconfirmedType {
                    if let grewEnough = grew(label, height) {
                        if grewEnough { continue }
                    } else if uniqueBefore.contains(label) {
                        // Unique on the audited page but not on the AX5 page: no evidence either way.
                        inconclusive.append(label)
                        continue
                    } else if pageGrew {
                        continue
                    }
                    let measured = largeHeights[label].map { String(format: " (%.1f → %.1f pt)", height, $0) } ?? ""
                    result.append("Dynamic Type: '\(label)' did not grow 1.35x at AX5\(measured)")
                    missed = true
                }
                // A clip on a labelled element is waived only when it is fully on screen on both pages and is
                // measured 1.35x taller at AX5 (it grows instead of truncating); otherwise it stays open.
                let largeWindow = large.windows.firstMatch.frame
                for item in clipped {
                    let reason: String
                    if !window.contains(item.frame) {
                        reason = "partly off screen on the audited page"
                    } else if let largeFrame = largeFrames[item.label] {
                        if !largeWindow.contains(largeFrame) {
                            reason = "partly off screen on the AX5 page"
                        } else if largeFrame.height >= item.frame.height * 1.35 {
                            let note = String(format: "Text clipped waived: '%@' grows %.1f → %.1f pt at AX5, fully on screen",
                                              item.label, item.frame.height, largeFrame.height)
                            print(note)
                            XCTContext.runActivity(named: note) { _ in }
                            continue
                        } else {
                            reason = String(format: "grew %.1f → %.1f pt at AX5 (needs 1.35x)", item.frame.height, largeFrame.height)
                        }
                    } else {
                        reason = "not measured on the AX5 page"
                    }
                    result.append(item.issue + " [not waived: \(reason)]")
                    missed = true
                }
                if !inconclusive.isEmpty {
                    let note = "Dynamic Type inconclusive (not on the AX5 page): " + inconclusive.map { "'\($0)'" }.joined(separator: ", ")
                    print(note)
                    XCTContext.runActivity(named: note) { _ in }
                }
                if missed || (unattributedType > 0 && !pageGrew) {
                    let evidence = XCTAttachment(screenshot: large.screenshot())
                    evidence.name = "AX5 screen"
                    evidence.lifetime = .keepAlways
                    XCTContext.runActivity(named: "AX5 relaunch") { $0.add(evidence) }
                }
                if missed || unattributedType > 0, !pageGrew {
                    let pairs = compared.map { String(format: "%.1f → %.1f", $0.0, $0.1) }.joined(separator: ", ")
                    result.append("Page check (\(compared.count) of \(sample.count) sampled texts on the AX5 page): \(pairs)")
                }
                if unattributedType > 0, !pageGrew {
                    result.append("Dynamic Type: \(unattributedType) issue(s) with no element, and the page did not grow 1.35x at AX5")
                }
                return result
            }
            // In place when the app can (a reuse launch): the page just audited, enlarged, with no relaunch or reopen. In-place
            // evidence only ever waives: when it would leave an issue open, the relaunch at AX5 decides, as it did before, since a
            // page can lay out differently after a live text-size change than at a launch (Climate Tracking tab, 2026-10-31).
            if let inPlace = AppReuse.enlargeInPlace(app) {
                var found = judge(inPlace)
                if !found.isEmpty {
                    print("AX5 in place left \(found.count) issue(s) open; measuring a relaunch at AX5")
                    found = judge(try ax5Page())
                }
                open += found
            } else {
                open += judge(try ax5Page())
            }
        }
        if !open.isEmpty {
            let screenshot = auditedScreen ?? XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Audited screen"
            screenshot.lifetime = .keepAlways
            XCTContext.runActivity(named: "Accessibility audit") { $0.add(screenshot) }
            if open.contains(where: { $0.contains("Potentially inaccessible text") && $0.contains("Element:(null)") }) {
                print("AUDIT-DIAG recognised text without an element: \(unlabelledTexts(in: app))")
            }
            if let shots = ProcessInfo.processInfo.environment["FENTON_SHOTS_DIR"], !shots.isEmpty {
                try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
                let name = "audit-failed-\(family)-\(Date().timeIntervalSince1970.rounded()).png"
                try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: shots).appendingPathComponent(name))
            }
            XCTFail("Accessibility audit:\n" + open.joined(separator: "\n"), file: file, line: line)
        }
    }

    /// The attributes of an audit issue's element, read once. Each live property read re-resolves the element's query (one
    /// accessibility request apiece); a single `snapshot()` carries them all. An element that no longer resolves falls back to
    /// live reads, which is what the audit did before (they come back empty after XCTest's retries).
    private struct ElementFacts {
        let elementType: XCUIElement.ElementType
        let label: String
        let identifier: String
        let frame: CGRect
        let isEnabled: Bool

        @MainActor init(_ element: XCUIElement) {
            if let snapshot = try? element.snapshot() {
                elementType = snapshot.elementType
                label = snapshot.label
                identifier = snapshot.identifier
                frame = snapshot.frame
                isEnabled = snapshot.isEnabled
            } else {
                elementType = element.elementType
                label = element.label
                identifier = element.identifier
                frame = element.frame
                isEnabled = element.isEnabled
            }
        }
    }

    /// Diagnostic: the strings text recognition reads in the screen that no element's label or value contains, with their frames in points.
    ///
    /// Whitespace is collapsed on both sides: recognition reads the weather range's two spaces ("H:78°  L:58°", its label's own text) as
    /// one. A string with no letters (a glyph read as text: heavy rain's drops as "111/", a page control's dots as "· · ·") counts as the
    /// element's when it lies inside a leaf element that has a label or value, which speaks for what it draws (Home weather audit, iPhone,
    /// 2026-11-04: the hours from 2 PM on put the heavy-rain glyph on the first page, so the audit failed by day and passed at night).
    /// A string with letters must still be in some label or value.
    private static func unlabelledTexts(in app: XCUIApplication) -> [(text: String, frame: CGRect)] {
        let shot = app.screenshot()
        guard let cg = shot.image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        let window = app.windows.firstMatch.frame
        let squeeze = { (text: String) -> String in
            text.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }
        var known = Set<String>()
        var described: [CGRect] = []
        // One snapshot of the tree: a live read per element is an accessibility request apiece.
        var pending = (try? app.snapshot()).map { [$0] } ?? []
        while let node = pending.popLast() {
            pending += node.children
            // The app's and window's own names are not page text.
            guard node.elementType != .application, node.elementType != .window else { continue }
            let label = squeeze(node.label), value = squeeze(node.value as? String ?? "")
            known.insert(label); known.insert(value)
            // Only a leaf speaks for every pixel inside it: a labelled container also frames text its children must name.
            if node.children.isEmpty, !label.isEmpty || !value.isEmpty { described.append(node.frame) }
        }
        var out: [(text: String, frame: CGRect)] = []
        for case let observation as VNRecognizedTextObservation in request.results ?? [] {
            guard let raw = observation.topCandidates(1).first?.string else { continue }
            // Recognition reads a middle dot as a bullet and a leading symbol glyph (the due label's calendar) as a bullet or dash. The
            // floating bar's plus glyph is read as a "+" on some runs and dropped on others ("+ Add Task" against the button's "Add Task",
            // iPad Chores audit, 2026-11-03: it failed one run in five with the status bar texts beside it), so a leading "+" goes too.
            let text = raw.replacingOccurrences(of: "•", with: "·")
                .replacingOccurrences(of: "^[·•+\\-] ?", with: "", options: .regularExpression)
            let wanted = squeeze(text)
            if known.contains(where: { !$0.isEmpty && $0.contains(wanted) }) { continue }
            // Text clipped at a container's edge (the weather ticker mid-scroll, "1 Hail And Damaging Wind Gl" for the card label's "…With
            // Hail And Damaging Wind Gusts…") reads with a partial word at each end: without those, two or more whole words must still be
            // in a label.
            let words = wanted.split(separator: " ")
            if words.count >= 4, case let middle = words.dropFirst().dropLast().joined(separator: " "),
               known.contains(where: { !$0.isEmpty && $0.contains(middle) }) { continue }
            let b = observation.boundingBox
            let frame = CGRect(x: b.minX * window.width, y: (1 - b.maxY) * window.height, width: b.width * window.width, height: b.height * window.height)
            if wanted.rangeOfCharacter(from: .letters) == nil, described.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(frame) }) { continue }
            out.append((text, frame))
        }
        return out
    }

    private static func isSystemDrawn(_ issue: XCUIAccessibilityAuditIssue, element issueElement: XCUIElement?,
                                      facts: ElementFacts?, in app: XCUIApplication,
                                      popover: CGRect?, homeChipCovered: () -> Bool) -> Bool {
        guard issueElement != nil, let facts else {
            // The folded Duo's vertical bar (the rail) takes a sheet's or page's bar items into a system container whose own frame is
            // zero-sized (its item groups sit outside it, each at 44+ pt). The audit reports that container as an element-less,
            // label-less "Hit area is too small: 0" (UIKit port, 2026-11-02: every sheet and pushed page on the folded Duo). The
            // buttons inside are real elements and are checked on their own. Accepted only on the Duo, only with such a container
            // inside a toolbar.
            if issue.auditType == .hitRegion, family == .iPhoneDuo,
               app.toolbars.descendants(matching: .other).allElementsBoundByIndex.contains(where: { $0.frame.width == 0 && $0.frame.height == 0 }) {
                return true
            }
            // The folded Duo draws the system clock in its rail, the sign-in monogram's initials are decorative (hidden from assistive
            // technologies by design) and a compact date picker's pills are the system's: text recognition reads them with no element
            // (UIKit port, Duo, 2026-11-02: one to four issues per page). Accepted only when every string recognised without an element is
            // one of those (see `unlabelledTexts`).
            // The iPhone's status bar clock (SpringBoard's, top leading) and the compact date picker's time pills read the same way (iPhone,
            // 2026-11-03: Vacation dates and Solo Trip audits, "2:49" and "9:00 AM").
            if issue.auditType == .elementDetection, family == .iPhoneDuo || family == .iPhone {
                let window = app.windows.firstMatch.frame
                let texts = unlabelledTexts(in: app)
                let isClock = { (t: (text: String, frame: CGRect)) -> Bool in
                    let isTime = t.text.range(of: "^[0-9]{1,2}:[0-9]{2}$", options: .regularExpression) != nil
                    return isTime && (t.frame.minX > window.width - 100 && t.frame.minY < 130 || family == .iPhone && t.frame.maxY < 60)
                }
                // Initials count only inside a labelled control (the profile button, the welcome-back avatar), whose label already names
                // the person; stray capitals anywhere else on the page stay a failure.
                let labelled = [XCUIElement.ElementType.button, .image, .other].flatMap { app.descendants(matching: $0).allElementsBoundByIndex }
                    .filter { !$0.label.isEmpty }.map(\.frame)
                // Or the welcome-back monogram (`SignInMonogram`, hidden from assistive technologies in both apps: the title names the
                // person): initials that start with the first letter of the name the title greets ("Welcome back, Alex").
                let greeted = app.staticTexts.allElementsBoundByIndex.compactMap { element -> Character? in
                    guard element.identifier == "login.title" || element.label.hasPrefix("Welcome back, ") else { return nil }
                    return element.label.components(separatedBy: ", ").last?.first
                }
                let initialsOfShownName = { (letters: String) -> Bool in letters.first.map(greeted.contains) ?? false }
                let isInitials = { (t: (text: String, frame: CGRect)) -> Bool in
                    t.text.range(of: "^[A-Z]{1,2}$", options: .regularExpression) != nil
                        && (labelled.contains { $0.width < 120 && $0.height < 120 && $0.insetBy(dx: -2, dy: -2).contains(t.frame) }
                            || initialsOfShownName(t.text))
                }
                let isPickerTime = { (t: (text: String, frame: CGRect)) -> Bool in
                    app.datePickers.firstMatch.exists && t.text.range(of: "^[0-9]{1,2}:[0-9]{2} ?[AP]M$", options: .regularExpression) != nil
                }
                if !texts.isEmpty, texts.allSatisfy({ isClock($0) || isInitials($0) || isPickerTime($0) }) { return true }
            }
            // The iPad's system status bar (clock, date, battery) is drawn by SpringBoard and read by text recognition with no element
            // (UIKit port, iPad, 2026-11-03: one issue per page on the pages whose recognised lines merge differently). Accepted only
            // when every string recognised without an element sits inside the status bar band.
            if issue.auditType == .elementDetection, family == .iPad {
                let texts = unlabelledTexts(in: app)
                if !texts.isEmpty, texts.allSatisfy({ $0.frame.maxY < 32 }) { return true }
            }
            // Same for the content behind an action-sheet popover noted as the audit started (the
            // audit can dismiss it): the popover's dismiss region hides it from assistive technologies.
            if issue.auditType == .elementDetection, popover != nil { return true }
            // Text behind a modal sheet (iPad form sheets leave Home visible around them) is drawn but
            // hidden from assistive technologies by the modal. Accept it only while a sheet is up and
            // Home's own controls can't be reached (the sheet's dimming layer takes the touches).
            // The same page text under the dimming layer also comes back as element-less contrast or clipping
            // (seen 2026-10-12 around the iPad sprinkler schedule sheet, one or the other from run to run).
            // A page pushed inside the sheet shows Back, not Close; the page behind still has its own bar, so two
            // navigation bars also mean a modal over a page (Bedroom editors on iPad, 2026-10-12).
            let behindSheet: XCUIAccessibilityAuditType = [.elementDetection, .contrast, .textClipped]
            let modalUp = app.navigationBars.buttons["Done"].exists || app.navigationBars.buttons["Close"].exists
                || app.navigationBars.count > 1
            if behindSheet.contains(issue.auditType), modalUp, homeChipCovered() {
                return true
            }
            // The same for an inventory page behind an iPad form sheet (Sort, Filter, Add Item, the editor;
            // Add Item's later steps show Back instead of Cancel): its dimmed text is sampled through the scrim, and
            // contrast issues there come back without an element (iPad, 2026-10-12).
            if issue.auditType == .elementDetection || issue.auditType == .contrast,
               app.navigationBars.buttons["Done"].exists || app.navigationBars.buttons["Close"].exists
                || app.navigationBars.buttons["Cancel"].exists
                || app.buttons["scan.back"].exists,
               app.buttons["inventory.row.cart"].firstMatch.exists, !app.buttons["inventory.row.cart"].firstMatch.isHittable {
                return true
            }
            // The same for the navigation flyout: the page under its scrim is drawn but hidden from
            // assistive technologies while it is open. Accept it only while the flyout is up and Home's
            // controls are out of the accessibility tree.
            if issue.auditType == .elementDetection, app.descendants(matching: .any)["nav.flyout"].exists,
               !app.buttons["home.chip.lights"].exists {
                return true
            }
            // A list row scrolled under the glass tab bar is sampled against the bar and sometimes
            // loses its element (iPhone Settings, 2026-10-11: the "Home Assistant" header). Accept an
            // element-less contrast issue only while some page text really sits under the tab bar.
            if issue.auditType == .contrast, isPageTextUnderTabBar(in: app) {
                return true
            }
            // When contrast runs with the Dynamic Type or text-clipping checks, the disabled Sign In
            // button's issue loses its element (probed 2026-10-10: the same audit otherwise reports it
            // on that button). Accept it only while that button is on screen and disabled.
            let submit = app.buttons["login.submit"]
            return issue.auditType == .contrast && submit.exists && !submit.isEnabled
        }
        switch issue.auditType {
        case .contrast:
            if facts.elementType == .button && !facts.isEnabled { return true }
            // Text behind an action-sheet popover (iOS 27 sign-out confirmation) is sampled through
            // the popover's dismiss region; the popover's own buttons stay checked.
            if let popover, !popover.contains(facts.frame) { return true }
            if isScrolledOutOfView(facts, in: app) { return true }
            // A row scrolled under the glass tab bar is sampled against the bar (iPhone Settings'
            // last row, 2026-10-11: 1.2:1); the bar's own items stay checked.
            if isUnderTabBar(facts, in: app) { return true }
            // A sheet's section bar is a glass segmented control floating over its content (`modalTabBar`): a row
            // scrolled under it is sampled against the glass, white text on white in a light sheet (bed Temperature tab,
            // 1.3:1, 2026-10-16). The bar's own segments stay checked.
            if isUnderSectionBar(facts, in: app) { return true }
            // The system's navigation subtitle ("Playing", "3 of 12 On") is drawn by UIKit in the secondary label colour:
            // 3.3:1 on a light sheet, as in Apple's own sheets. The app cannot restyle it; the dark sheets pass.
            if facts.elementType == .staticText,
               app.navigationBars.staticTexts.matching(NSPredicate(format: "label == %@", facts.label)).firstMatch.exists { return true }
            return facts.elementType == .button && app.navigationBars.buttons.matching(label: facts.label).firstMatch.exists
        case .dynamicType, .textClipped:
            // The system's own inline bar title (a collapsed large title, owner 2026-10-27) is drawn by UIKit at a fixed bar size.
            if facts.elementType == .staticText, !facts.label.isEmpty,
               app.navigationBars.staticTexts.matching(NSPredicate(format: "label == %@", facts.label)).firstMatch.exists { return true }
            // Toolbar buttons are system-drawn and offer the Large Content Viewer instead of scaling.
            return facts.elementType == .button && app.navigationBars.buttons.matching(label: facts.label).firstMatch.exists
        default:
            return false
        }
    }

    /// The labelled static texts and buttons fully inside the window that measure under `minimum`:1 rendered in
    /// `capture`, as `label (ratio)`; empty when all clear. One snapshot, so many accessibility requests do not crash
    /// the iPad simulator's backboardd.
    private static func lowestVisibleText(below minimum: Double, in app: XCUIApplication,
                                          capture: RenderedContrast.Capture) -> [String] {
        guard let root = try? app.snapshot() else { return ["no snapshot"] }
        let window = app.windows.firstMatch.frame
        var low: [String] = []
        // The visible frames of the scroll views around a node: text outside one is scrolled out of view (a carousel's
        // next page, whose cards still sit inside the window) and is sampled against whatever covers it.
        func walk(_ node: XCUIElementSnapshot, clips: [CGRect]) {
            // System bars (the tab bar, the folded Duo's rail) are not the app's text. A frame taller than a text line
            // holds a photo (a recipe card, a camera tile): its median surface says nothing about the caption on it,
            // so only text-sized frames are measured.
            if node.elementType == .tabBar || node.elementType == .toolbar { return }
            // A disabled control is exempt from contrast (WCAG 1.4.3, inactive components): a tile's disc that does not apply dims
            // in place (a docked vacuum's Dock, 2.6:1) and is still announced as dimmed.
            // A tile's action disc is a button that draws an SF Symbol and no text: a non-text graphic, held to 3:1 (WCAG 1.4.11),
            // not the 4.5:1 of text. The owner decided "family glyph at 3:1 or better" (action-navigation-tiles.md, Discs) and
            // `TileActionInkTests` enforces it in the host tests, so the audit's text threshold is not applied to
            // `<tile>.action.<id>` elements. Text labels stay at 4.5:1.
            let isDiscGlyph = node.elementType == .button && node.identifier.contains(".action.")
            if [.staticText, .button].contains(node.elementType), !node.label.isEmpty, node.isEnabled, !isDiscGlyph,
               !node.frame.isEmpty, node.frame.height <= 60, window.insetBy(dx: -1, dy: -1).contains(node.frame),
               clips.allSatisfy({ $0.insetBy(dx: -1, dy: -1).contains(node.frame) }),
               let ratio = RenderedContrast.ratio(of: node.frame, in: capture),
               // Under 1.5:1 nothing is drawn at the frame (the existing rule for text hidden behind a bar or a sheet).
               ratio < minimum, ratio >= 1.5 {
                low.append(String(format: "'%@' %.1f at %@", node.label, ratio, "\(node.frame)"))
            }
            var inner = clips
            if [.scrollView, .collectionView, .table].contains(node.elementType), !node.frame.isEmpty { inner.append(node.frame) }
            node.children.forEach { walk($0, clips: inner) }
        }
        walk(root, clips: [])
        return low
    }

    /// Text scrolled (partly) out of its scroll view is sampled against whatever covers it there, such as
    /// the folded iPhone Duo's toolbar rail or the screen edge under a sheet. It is out of view, not low
    /// contrast: accept it only when no scroll view's visible frame fully contains the element.
    private static func isScrolledOutOfView(_ element: ElementFacts, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        let holder = NSPredicate(format: "label == %@", element.label)
        // Below the window's edge (a long sheet column in iPad landscape): the capture holds only part of it.
        let window = app.windows.firstMatch.frame
        if !window.isEmpty, !window.insetBy(dx: -1, dy: -1).contains(frame) { return true }
        // Scrolled under a navigation bar (wholly or partly): the bar's scroll-edge effect deliberately obscures it.
        // The bar's own title and buttons are its descendants and stay checked.
        for navigationBar in app.navigationBars.allElementsBoundByIndex {
            let bar = navigationBar.frame
            guard !bar.isEmpty, bar.intersects(frame), frame.minY < bar.maxY - 1 else { continue }
            if !navigationBar.descendants(matching: element.elementType).matching(holder).firstMatch.exists { return true }
        }
        // Only scroll views that hold this element (not, say, Home's behind a sheet). Each one clips it, so it is out of
        // view when any of them doesn't contain it: an hour on the next page of Home's weather row sat wholly outside the
        // row, inside the page's own scroll view, and measured 1.9:1 against the card edge (folded Duo, 2026-10-14).
        // Not only those it intersects: a cell scrolled wholly out of its row doesn't intersect the row at all.
        let scrollViews = app.scrollViews.allElementsBoundByIndex
            .filter { $0.descendants(matching: element.elementType).matching(holder)
                .allElementsBoundByIndex.contains { $0.frame == frame } }
            .map(\.frame)
        return scrollViews.contains { !$0.insetBy(dx: -1, dy: -1).contains(frame) }
    }

    /// Whether a page text (not the tab bar's own labels) overlaps the tab bar, i.e. is scrolled under it.
    private static func isPageTextUnderTabBar(in app: XCUIApplication) -> Bool {
        let bar = app.tabBars.firstMatch
        guard bar.exists else { return false }
        let barFrame = bar.frame
        return app.staticTexts.allElementsBoundByIndex.contains { text in
            !text.label.isEmpty && text.frame.intersects(barFrame) && !bar.staticTexts.matching(label: text.label).firstMatch.exists
        }
    }

    /// Whether an element overlaps a sheet's section bar (a segmented control), without being one of its segments.
    private static func isUnderSectionBar(_ element: ElementFacts, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        return app.segmentedControls.allElementsBoundByIndex.contains { bar in
            bar.frame.intersects(frame)
                && !bar.descendants(matching: element.elementType).matching(NSPredicate(format: "label == %@", element.label)).firstMatch.exists
        }
    }

    /// Whether a page element (not one of the tab bar's own items) overlaps the tab bar.
    private static func isUnderTabBar(_ element: ElementFacts, in app: XCUIApplication) -> Bool {
        let bar = app.tabBars.firstMatch
        guard bar.exists, element.frame.intersects(bar.frame) else { return false }
        return !bar.descendants(matching: element.elementType).matching(label: element.label).firstMatch.exists
    }

}

// MARK: - Queries

extension XCUIElementQuery {
    /// Elements whose label is exactly `label`. The string subscript throws for identifiers over 128 characters, and
    /// a long label (the Climate Advanced Controls rows) is one; a predicate has no such limit.
    func matching(label: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "label == %@", label))
    }
}

// MARK: - Screenshots

extension XCTestCase {
    /// Keeps a screenshot named `name` in the result bundle for design review.
    ///
    /// XCUIScreen captures only the outer panel, which is dark on an unfolded iPhone Duo. With
    /// `FENTON_CAPTURE_DIR` set, the host captures the lit panel: `<name>.ready` asks, `<name>.done` answers.
    @MainActor
    func keepScreenshot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // `FENTON_SHOTS_DIR`: also written as a PNG there, so a run's pictures can be read without opening the result bundle.
        if let shots = ProcessInfo.processInfo.environment["FENTON_SHOTS_DIR"], !shots.isEmpty {
            try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: shots).appendingPathComponent("\(name).png"))
        }
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return }
        let ready = URL(fileURLWithPath: folder).appendingPathComponent("\(name).ready")
        let done = URL(fileURLWithPath: folder).appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        // A loaded host can take well over 30 s to capture; moving on early let a late capture land on the next
        // screen under this name. Wait longer, and withdraw the request on timeout so a miss is a gap, not a mislabel.
        let deadline = Date().addingTimeInterval(180)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
        if !FileManager.default.fileExists(atPath: done.path) { try? FileManager.default.removeItem(at: ready) }
    }
}
