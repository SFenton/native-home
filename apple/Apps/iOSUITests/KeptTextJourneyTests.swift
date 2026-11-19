import XCTest

/// Kept text in the debug gallery (`FENTON_GALLERY=text-keep`; T-text-keep, options A, B and C): one `whenUnavailable: "keep"` slot per host
/// the contract reaches, on synthetic sensors that the `keptText.set.<state>` buttons drive. Written for iPhone, iPhone Duo and iPad alike:
/// the treatment knows no device. Each test asserts what VoiceOver reads (the element's value) in every state, and keeps a screenshot per
/// state under the `FENTON_CAPTURE_DIR` handshake so the Verifier can look at the pixels.
///
/// The cue is `, last known` in the element's value: once per element in options B (`spoken`) and C (`marked`), never in A (`plain`), and in no
/// treatment while live, before any answer (the fallback shows), loading, or after the source recovers.
@MainActor
final class KeptTextJourneyTests: JourneyTestCase {
    private enum Treatment: String, CaseIterable { case plain, spoken, marked }

    /// The hosts on the page and the words each draws live.
    private let hosts = ["keep-text", "keep-tile-off", "keep-tile-fill", "keep-tile-long", "keep-pill", "keep-row"]

    private func launch(_ treatment: Treatment, state: String = "live", delayMs: Int? = nil, arguments: [String] = [],
                        settings: [FentonHomeApp.SystemSetting] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "text-keep"
        configured.launchEnvironment["FENTON_GALLERY_KEPT_TEXT_TREATMENT"] = treatment.rawValue
        configured.launchEnvironment["FENTON_GALLERY_KEPT_TEXT_STATE"] = state
        if let delayMs { configured.launchEnvironment["FENTON_GALLERY_KEPT_TEXT_DELAY_MS"] = String(delayMs) }
        configured.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment(settings)) { _, new in new }
        configured.launchArguments += arguments
        let app = startApp(configured)
        XCTAssertTrue(element("keptText.state", in: app).appears(timeout: 20), "the gallery never drew")
        XCTAssertFalse(element("keptText.failure", in: app).exists, "the gallery's composition was refused")
        return app
    }

    /// How many times the cue sounds in what VoiceOver reads for `id` (its label and value).
    private func cues(_ id: String, in app: XCUIApplication) -> Int {
        // Every element with the identifier: a row's wrapper and its text element both carry it, and only one speaks.
        let read = reads(id, in: app).joined(separator: " | ")
        return read.components(separatedBy: "last known").count - 1
    }

    /// The label and value of every element with identifier `id`.
    private func reads(_ id: String, in app: XCUIApplication) -> [String] {
        app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.map {
            "\($0.label) / \($0.value as? String ?? "")"
        }
    }

    /// Waits until every host reads `expected` cues, then fails naming the hosts that do not.
    private func expectCues(_ expected: Int, in app: XCUIApplication, _ what: String, timeout: TimeInterval = 8,
                            file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var wrong: [String] = []
        repeat {
            wrong = hosts.filter { !element($0, in: app).exists || cues($0, in: app) != expected }
            if wrong.isEmpty { return }
            usleep(200_000)
        } while Date() < deadline
        let found = wrong.map { "\($0): \(reads($0, in: app))" }
        XCTFail("\(what): expected \(expected) cue(s), these differ: \(found)", file: file, line: line)
    }

    private func press(_ state: String, in app: XCUIApplication) {
        let button = element("keptText.set.\(state)", in: app)
        XCTAssertTrue(button.appears(timeout: 5), "no \(state) button")
        button.tap()
        let deadline = Date().addingTimeInterval(5)
        while element("keptText.state", in: app).label != state, Date() < deadline { usleep(100_000) }
    }

    private func shoot(_ app: XCUIApplication, _ treatment: Treatment, _ state: String, suffix: String = "") {
        keepScreenshot(app, "kept-text-\(treatment.rawValue)-\(state)\(suffix)-\(layout)")
    }

    /// The whole state walk of one treatment: live, kept, loading after an answer, recovered, and a page that never had an answer.
    private func walk(_ treatment: Treatment, settings: [FentonHomeApp.SystemSetting] = [], suffix: String = "", arguments: [String] = []) {
        let kept = treatment == .plain ? 0 : 1
        let app = launch(treatment, arguments: arguments, settings: settings)
        expectCues(0, in: app, "live")
        shoot(app, treatment, "live", suffix: suffix)
        press("kept", in: app)
        expectCues(kept, in: app, "kept")
        shoot(app, treatment, "kept", suffix: suffix)
        press("loading", in: app)
        expectCues(0, in: app, "loading after an answer")
        shoot(app, treatment, "loading", suffix: suffix)
        press("recover", in: app)
        expectCues(0, in: app, "recovered")
        shoot(app, treatment, "recover", suffix: suffix)
        let fresh = launch(treatment, state: "before", arguments: arguments, settings: settings)
        expectCues(0, in: fresh, "unavailable before any answer")
        shoot(fresh, treatment, "before", suffix: suffix)
    }

    // MARK: Journeys

    /// Option A: kept text speaks exactly as it does live, in every state.
    func testPlainSpeaksKeptTextAsLive() { walk(.plain) }

    /// Option B: kept text speaks its cue once per element, and no cue in any other state.
    func testSpokenAddsTheCueOncePerElement() { walk(.spoken) }

    /// Option C: the same cue as B, with the glyph and grey drawn (read from the screenshots).
    func testMarkedAddsTheCueOncePerElement() { walk(.marked) }

    /// At AX5 option C keeps one cue per element and every host stays in the tree.
    func testMarkedAtAX5() { walk(.marked, suffix: "-ax5", arguments: FentonHomeApp.ax5) }

    /// Option C under Increase Contrast and Reduce Transparency: the cue is unchanged.
    func testMarkedUnderIncreaseContrastAndReduceTransparency() {
        walk(.marked, settings: [.increaseContrast, .reduceTransparency], suffix: "-contrast")
    }
}
