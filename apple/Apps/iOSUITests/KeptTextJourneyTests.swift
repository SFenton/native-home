import XCTest

/// Kept text in the debug gallery (`FENTON_GALLERY=text-keep`; `sh.text-keep@1`, owner pick 2026-11-19): kept text is drawn and spoken
/// exactly as a live value. One `whenUnavailable: "keep"` slot per host the contract reaches, on synthetic sensors that the
/// `keptText.set.<state>` buttons drive. Written for iPhone, iPhone Duo and iPad alike: the rule knows no device.
///
/// Each test compares what VoiceOver reads (an element's label and value), the glyph elements inside it and its frame height between the live
/// state and the kept state, and asserts that a page that never had an answer draws its fallback and not the loading look. A screenshot per
/// state is kept under the `FENTON_CAPTURE_DIR` handshake so the Verifier can look at the pixels.
@MainActor
final class KeptTextJourneyTests: JourneyTestCase {
    /// The hosts on the page.
    private let hosts = ["keep-text", "keep-tile-off", "keep-tile-fill", "keep-tile-long", "keep-pill", "keep-row"]
    /// What the sensors answer, and what the slots draw before any answer.
    private let live = "21.5 degrees"
    private let fallback = "No reading"

    /// What one host reads and how it looks: the label and value of every element carrying its identifier, the glyph elements inside, the
    /// frame heights.
    private struct Face: Equatable {
        var reads: [String]
        var glyphs: Int
        var heights: [CGFloat]
    }

    private func launch(state: String = "live", delayMs: Int? = nil, arguments: [String] = [],
                        settings: [FentonHomeApp.SystemSetting] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "text-keep"
        configured.launchEnvironment["FENTON_GALLERY_KEPT_TEXT_STATE"] = state
        if let delayMs { configured.launchEnvironment["FENTON_GALLERY_KEPT_TEXT_DELAY_MS"] = String(delayMs) }
        configured.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment(settings)) { _, new in new }
        configured.launchArguments += arguments
        let app = startApp(configured)
        XCTAssertTrue(element("keptText.state", in: app).appears(timeout: 20), "the gallery never drew")
        XCTAssertFalse(element("keptText.failure", in: app).exists, "the gallery's composition was refused")
        return app
    }

    private func face(_ id: String, in app: XCUIApplication) -> Face {
        // Every element with the identifier: a row's wrapper and its text element both carry it, and only one speaks.
        let matches = app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex
        return Face(reads: matches.map { "\($0.label) / \($0.value as? String ?? "")" },
                    glyphs: element(id, in: app).descendants(matching: .image).count,
                    heights: matches.map { $0.frame.height })
    }

    private func faces(in app: XCUIApplication) -> [String: Face] {
        Dictionary(uniqueKeysWithValues: hosts.map { ($0, face($0, in: app)) })
    }

    /// Waits until every host reads `text`, then fails naming the hosts that do not.
    private func expectText(_ text: String, in app: XCUIApplication, _ what: String, timeout: TimeInterval = 8,
                            file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        let subjects = hosts.filter { $0 != "keep-pill" }
        var wrong: [String] = []
        repeat {
            wrong = subjects.filter { !face($0, in: app).reads.joined(separator: " | ").contains(text) }
            if wrong.isEmpty { return }
            usleep(200_000)
        } while Date() < deadline
        XCTFail("\(what): expected \"\(text)\", these differ: \(wrong.map { "\($0): \(face($0, in: app).reads)" })", file: file, line: line)
    }

    private func press(_ state: String, in app: XCUIApplication) {
        let button = element("keptText.set.\(state)", in: app)
        XCTAssertTrue(button.appears(timeout: 5), "no \(state) button")
        button.tap()
        let deadline = Date().addingTimeInterval(5)
        while element("keptText.state", in: app).label != state, Date() < deadline { usleep(100_000) }
    }

    private func shoot(_ app: XCUIApplication, _ state: String, suffix: String = "") {
        keepScreenshot(app, "kept-text-\(state)\(suffix)-\(layout)")
    }

    /// Live, then kept: every host reads, and takes the room of, exactly what it did live.
    private func walk(settings: [FentonHomeApp.SystemSetting] = [], suffix: String = "", arguments: [String] = []) {
        let app = launch(arguments: arguments, settings: settings)
        expectText(live, in: app, "live")
        let before = faces(in: app)
        shoot(app, "live", suffix: suffix)

        press("kept", in: app)
        expectText(live, in: app, "kept text keeps the last answer")
        let kept = faces(in: app)
        for host in hosts {
            XCTAssertEqual(kept[host], before[host], "\(host): kept text must read, look and measure as live")
            XCTAssertFalse((kept[host]?.reads ?? []).joined().contains("last known"), "\(host): kept text speaks no cue")
        }
        shoot(app, "kept", suffix: suffix)

        press("loading", in: app)
        shoot(app, "loading", suffix: suffix)
        press("recover", in: app)
        expectText(live, in: app, "recovered")
        XCTAssertEqual(faces(in: app), before, "recovered text reads and measures as before")
        shoot(app, "recover", suffix: suffix)

        // A page built after the server answered "unavailable" to a slot that never had an answer: its fallback, not the loading look.
        let fresh = launch(state: "before", arguments: arguments, settings: settings)
        expectText(fallback, in: fresh, "before any answer draws the authored fallback")
        for host in hosts where host != "keep-pill" {
            XCTAssertFalse(face(host, in: fresh).reads.joined(separator: " | ").contains("Loading"), "\(host): before any answer is not loading")
        }
        XCTAssertTrue(face("keep-pill", in: fresh).reads.joined(separator: " | ").contains("No reading"), "the pill draws its fallback")
        shoot(fresh, "before", suffix: suffix)
    }

    // MARK: Journeys

    /// Kept text reads, looks and measures exactly as live in every host, and before any answer the fallback shows.
    func testKeptTextIsLiveText() { walk() }

    /// At AX5 the same holds and every host stays in the tree.
    func testKeptTextAtAX5() { walk(suffix: "-ax5", arguments: FentonHomeApp.ax5) }

    /// Under Increase Contrast and Reduce Transparency the same holds.
    func testKeptTextUnderIncreaseContrastAndReduceTransparency() {
        walk(settings: [.increaseContrast, .reduceTransparency], suffix: "-contrast")
    }

    /// Opening the sheet while live and letting the source go unavailable keeps the sheet's row and text as they were.
    func testKeptTextInASheetReadsAsLive() {
        let app = launch(delayMs: 6000)
        expectText(live, in: app, "live")
        let sheetHosts = ["keep-sheet-row", "keep-sheet-text"]
        let palette = app.buttons["Palette"]
        XCTAssertTrue(palette.appears(timeout: 10), "no Palette button")
        palette.tap()
        XCTAssertTrue(element(sheetHosts[0], in: app).appears(timeout: 10), "the sheet never opened")
        let liveFaces = sheetHosts.map { face($0, in: app) }
        let deadline = Date().addingTimeInterval(15)
        while element("keptText.state", in: app).label != "kept", Date() < deadline { usleep(200_000) }
        XCTAssertEqual(sheetHosts.map { face($0, in: app) }, liveFaces, "the sheet's kept text reads and measures as live")
    }
}
