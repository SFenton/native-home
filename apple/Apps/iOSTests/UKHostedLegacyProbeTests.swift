import HassCore
import HassTelemetry
import UIKit
import XCTest
@testable import HassUI

// MARK: - Scroll cost probe

/// What the scroll cost tooling does when it runs: it finds the scroll view a person would be scrolling, drives it at a steady
/// speed for the asked time, and reports how far it went and what the main thread paid.
@MainActor
final class ScrollCostDriverHostedTests: XCTestCase {
    override func tearDown() {
        for key in ["FENTON_SCROLLCOST_SECONDS", "FENTON_SCROLLCOST_SPEED", "FENTON_SCROLLCOST_AXIS"] { unsetenv(key) }
        super.tearDown()
    }

    /// A page whose only content is one scroll view of the given content size.
    private func page(content: CGSize, frame: CGRect = CGRect(x: 0, y: 0, width: 393, height: 852)) -> (UIViewController, UIScrollView) {
        let controller = UIViewController()
        let scroll = UIScrollView(frame: frame)
        scroll.contentSize = content
        controller.view.addSubview(scroll)
        return (controller, scroll)
    }

    func testAScrollRunMovesThePageAndReportsTheDistanceTheFramesAndTheInsetChanges() async throws {
        setenv("FENTON_SCROLLCOST_SECONDS", "0.6", 1)
        setenv("FENTON_SCROLLCOST_SPEED", "2000", 1)
        let (controller, scroll) = page(content: CGSize(width: 393, height: 6000))
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }

        let report = await ScrollCostDriver().run(scrolling: true)
        let run = try XCTUnwrap(report, "a tall page on screen can be scrolled")
        XCTAssertGreaterThan(run.travelledPoints, 100, "the page was driven")
        XCTAssertNotEqual(scroll.contentOffset.y, 0, "and it is not where it started")
        for key in ["deliveries=", "update_ms=", "inset_changes=", "inset_kvo=", "fps=", "mem_mb=", "t0=", "t1="] {
            XCTAssertTrue(run.note.contains(key), "the note carries \(key): \(run.note)")
        }
    }

    func testAnIdleRunMeasuresTheSameTimeWithoutTouchingThePage() async throws {
        setenv("FENTON_SCROLLCOST_SECONDS", "0.4", 1)
        let (controller, scroll) = page(content: CGSize(width: 393, height: 6000))
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }

        let restingOffset = scroll.contentOffset.y
        let ran = await ScrollCostDriver().run(scrolling: false)
        let report = try XCTUnwrap(ran)
        XCTAssertEqual(report.travelledPoints, 0, "nothing moved")
        XCTAssertEqual(scroll.contentOffset.y, restingOffset, "the page stayed where it rested")
        XCTAssertFalse(report.note.contains("inset_changes="), "no scroll view was watched")
        XCTAssertTrue(report.note.contains("fps="))
    }

    func testARunWithNothingToScrollReturnsNothing() async {
        let (controller, _) = page(content: CGSize(width: 393, height: 100))
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let report = await ScrollCostDriver().run(scrolling: true)
        XCTAssertNil(report, "a page that fits has no scroll view worth driving")
    }

    func testTheHorizontalAxisDrivesTheWidestSidewaysRailInsteadOfThePage() async throws {
        setenv("FENTON_SCROLLCOST_SECONDS", "0.5", 1)
        setenv("FENTON_SCROLLCOST_SPEED", "1500", 1)
        setenv("FENTON_SCROLLCOST_AXIS", "horizontal", 1)
        let controller = UIViewController()
        let pageScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        pageScroll.contentSize = CGSize(width: 393, height: 4000)
        let rail = UIScrollView(frame: CGRect(x: 0, y: 100, width: 393, height: 120))
        rail.contentSize = CGSize(width: 3000, height: 120)
        controller.view.addSubview(pageScroll)
        controller.view.addSubview(rail)
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }

        XCTAssertTrue(ScrollCostDriver.frontScrollView(horizontal: true) === rail, "the rail, not the page")
        XCTAssertTrue(ScrollCostDriver.frontScrollView(horizontal: false) === pageScroll, "the page, not the rail")
        let pageRest = pageScroll.contentOffset.y
        let ran = await ScrollCostDriver().run(scrolling: true)
        let report = try XCTUnwrap(ran)
        XCTAssertGreaterThan(report.travelledPoints, 100)
        XCTAssertGreaterThan(rail.contentOffset.x, 0, "the rail moved sideways")
        XCTAssertEqual(pageScroll.contentOffset.y, pageRest, "the page stayed")
    }

    func testTheFrontScrollViewSkipsHiddenSmallAndFittingScrollViews() {
        let controller = UIViewController()
        let hidden = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        hidden.contentSize = CGSize(width: 393, height: 9000)
        hidden.isHidden = true
        let faint = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        faint.contentSize = CGSize(width: 393, height: 9000)
        faint.alpha = 0
        let narrow = UIScrollView(frame: CGRect(x: 0, y: 0, width: 150, height: 852))
        narrow.contentSize = CGSize(width: 150, height: 9000)
        let fitting = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        fitting.contentSize = CGSize(width: 393, height: 852)
        let small = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 400))
        small.contentSize = CGSize(width: 393, height: 3000)
        let large = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 700))
        large.contentSize = CGSize(width: 393, height: 3000)
        for view in [hidden, faint, narrow, fitting, small, large] { controller.view.addSubview(view) }
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        XCTAssertTrue(ScrollCostDriver.frontScrollView() === large, "the biggest visible page-like scroller wins")
        XCTAssertNil(ScrollCostDriver.frontScrollView(horizontal: true), "nothing scrolls sideways")
    }

    func testThePresentedScreenIsTheOneMeasured() {
        let underneath = UIViewController()
        let below = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        below.contentSize = CGSize(width: 393, height: 9000)
        underneath.view.addSubview(below)
        let window = HostedPage.show(underneath)
        defer { window.isHidden = true }
        let sheet = UIViewController()
        let above = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 600))
        above.contentSize = CGSize(width: 393, height: 4000)
        sheet.view.addSubview(above)
        sheet.modalPresentationStyle = .fullScreen
        underneath.present(sheet, animated: false)
        HostedPage.wait(0.3)
        XCTAssertTrue(ScrollCostDriver.frontScrollView() === above, "the presented screen is in front")
    }

    func testTheDescriptionNamesEveryScrollViewAndWhatIsPresented() {
        let (controller, scroll) = page(content: CGSize(width: 393, height: 1234))
        scroll.alpha = 0.5
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let text = ScrollCostDriver.describeScrollViews()
        XCTAssertTrue(text.hasPrefix("presented=none"), text)
        XCTAssertTrue(text.contains("UIScrollView 393x852 content=1234 alpha=0.5 hidden=false"), text)
    }

    func testTheDeliveryNoteIsTheDifferenceBetweenTwoCounterReadings() {
        let note = ScrollCostDriver.deliveryNote(from: ["entity.deliveries": 2, "entity.mainUs": 1000],
                                                 to: ["entity.deliveries": 5, "entity.mainUs": 3500, "connection.pathUpdates": 4])
        XCTAssertTrue(note.contains("deliveries=3"), note)
        XCTAssertTrue(note.contains("path_updates=4"), note)
        XCTAssertTrue(note.contains("delivery_ms=2.5"), note)
        XCTAssertTrue(note.contains("changed=0"), note)
    }

    func testTheLaunchSummaryIsOneLineOfProcessAndDeliveryFacts() {
        let line = ScrollCostDriver.launchSummary()
        XCTAssertTrue(line.hasPrefix("launch=1 up_s="), line)
        for key in ["firstlive_ms=", "cpu_ms=", "instr_m=", "deliveries=", "ping_reconnects="] {
            XCTAssertTrue(line.contains(key), "\(key) in \(line)")
        }
        XCTAssertFalse(line.contains("\n"))
    }

    func testAForcedWorkClosureRunsAboutASecondIntoTheRun() async throws {
        setenv("FENTON_SCROLLCOST_SECONDS", "1.5", 1)
        let (controller, _) = page(content: CGSize(width: 393, height: 6000))
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let ran = LockedFlag()
        let report = await ScrollCostDriver().run(scrolling: true, during: { ran.set() })
        XCTAssertNotNil(report)
        XCTAssertTrue(ran.value, "the forced reconnect work ran inside the measured window")
    }

    func testTheMoverTurnsAroundAtBothEndsAndNeverLeavesTheContent() async throws {
        setenv("FENTON_SCROLLCOST_SECONDS", "1.2", 1)
        setenv("FENTON_SCROLLCOST_SPEED", "6000", 1)
        let (controller, scroll) = page(content: CGSize(width: 393, height: 1300))
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        var lowest = CGFloat.greatestFiniteMagnitude
        var highest = -CGFloat.greatestFiniteMagnitude
        let sampler = Task { @MainActor in
            while !Task.isCancelled {
                lowest = min(lowest, scroll.contentOffset.y)
                highest = max(highest, scroll.contentOffset.y)
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        let ran = await ScrollCostDriver().run(scrolling: true)
        let report = try XCTUnwrap(ran)
        sampler.cancel()
        let top = -scroll.adjustedContentInset.top
        let end = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
        XCTAssertGreaterThan(report.travelledPoints, 3 * (end - top), "fast enough to bounce between the ends")
        XCTAssertGreaterThanOrEqual(lowest, top - 0.5, "never above the top")
        XCTAssertLessThanOrEqual(highest, end + 0.5, "never past the bottom")
        XCTAssertGreaterThan(highest, top + (end - top) * 0.9, "reached the bottom")
    }

    func testTheInsetCounterCountsEveryChangeOfTheAdjustedInsetForTheWatchedViewOnly() {
        let (controller, scroll) = page(content: CGSize(width: 393, height: 3000))
        let other = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 200))
        controller.view.addSubview(other)
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let counter = ScrollCostDriver.InsetChangeCounter(scrollView: scroll)
        scroll.contentInset = UIEdgeInsets(top: 40, left: 0, bottom: 0, right: 0)
        scroll.contentInset = UIEdgeInsets(top: 90, left: 0, bottom: 0, right: 0)
        other.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        HostedPage.wait(0.1)
        XCTAssertGreaterThanOrEqual(counter.hookChanges, 2, "UIKit's own hook saw both changes of the watched view")
        XCTAssertLessThanOrEqual(counter.kvoChanges, counter.hookChanges, "KVO never counts more than the hook (it can miss computed changes)")
        let before = counter.hookChanges
        other.contentInset = UIEdgeInsets(top: 30, left: 0, bottom: 0, right: 0)
        XCTAssertEqual(counter.hookChanges, before, "another view's change is not counted")
    }

    func testTheProbeWritesItsLinesToThePrintedOutputAndAppendsToAnExistingFile() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "uk-append-\(UUID().uuidString).txt").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        ScrollCostProbe.append("one\n", to: path)
        ScrollCostProbe.append("two\n", to: path)
        ScrollCostProbe.append("three\n", to: nil)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "one\ntwo\n", "the second line is appended, not overwritten")
    }

    func testTheDarwinNotificationsArriveAsNamesAndTheObserverGoesWhenTheStreamEnds() async {
        let stream = ScrollCostProbe.notifications()
        let task = Task { @MainActor () -> [String] in
            var seen: [String] = []
            for await name in stream {
                seen.append(name)
                if seen.count == 2 { break }
            }
            return seen
        }
        try? await Task.sleep(for: .milliseconds(100))
        for name in [ScrollCostProbe.scrollNotification, ScrollCostProbe.idleNotification] {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
            try? await Task.sleep(for: .milliseconds(100))
        }
        let seen = await task.value
        XCTAssertEqual(seen, [ScrollCostProbe.scrollNotification, ScrollCostProbe.idleNotification])
    }
}

/// A flag a `@Sendable` closure can set.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

// MARK: - Launch cost probe

/// The launch cost probe measures a phase from `begin` to `finish`, and only when the launch asked for it.
@MainActor
final class LaunchCostProbeHostedTests: XCTestCase {
    private var wasEnabled = false

    override func setUp() {
        super.setUp()
        wasEnabled = LaunchCostProbe.isEnabled
        _ = LaunchCostProbe.finish(environment: [:])
    }

    override func tearDown() {
        _ = LaunchCostProbe.finish(environment: [:])
        LaunchCostProbe.isEnabled = wasEnabled
        super.tearDown()
    }

    func testAPhaseWritesItsLineAndItsDoneMarkerToTheNamedFileAndBecomesTheLatest() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "uk-launch-\(UUID().uuidString).txt").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        LaunchCostProbe.isEnabled = true
        LaunchCostProbe.begin("intro")
        LaunchCostProbe.begin("ignored")   // a phase is already running
        HostedPage.wait(0.1)
        let line = try XCTUnwrap(LaunchCostProbe.finish(environment: ["FENTON_LAUNCHCOST_FILE": path]))
        XCTAssertEqual(LaunchCostProbe.latest, line)
        XCTAssertTrue(line.contains("turns="), line)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("LAUNCHCOST\tintro\t"), text)
        XCTAssertTrue(text.contains("LAUNCHCOST_DONE\tintro"), text)
        XCTAssertFalse(text.contains("ignored"), "the second begin did nothing")
        XCTAssertNil(LaunchCostProbe.finish(environment: [:]), "nothing is running any more")
    }

    func testNothingIsMeasuredWhenTheLaunchDidNotAsk() {
        LaunchCostProbe.isEnabled = false
        LaunchCostProbe.begin("intro")
        XCTAssertNil(LaunchCostProbe.finish(environment: [:]))
    }

    func testAWindowMeasuresForTheWindowTimeThenFinishes() async {
        LaunchCostProbe.isEnabled = true
        let started = Date()
        await LaunchCostProbe.measureWindow("snapshot")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), LaunchCostProbe.windowSeconds - 0.1)
        XCTAssertNil(LaunchCostProbe.finish(environment: [:]), "the window already finished the phase")
        LaunchCostProbe.isEnabled = false
        let skipped = Date()
        await LaunchCostProbe.measureWindow("snapshot")
        XCTAssertLessThan(Date().timeIntervalSince(skipped), 0.5, "a launch that did not ask does not wait")
    }

    func testTheLineAppendsTheLatestLengthOfEachLaunchInterval() {
        let meter = MainThreadCostMeter()
        meter.begin()
        let report = meter.finish()
        let records = [
            TelemetryRecord(kind: "Launch", durationMs: 100),
            TelemetryRecord(kind: "Launch", durationMs: 120.5),
            TelemetryRecord(kind: "Arrival", durationMs: 33),
            TelemetryRecord(kind: "Other", durationMs: 9),
        ]
        let line = LaunchCostProbe.line(for: report, records: records)
        XCTAssertTrue(line.hasPrefix(report.summary), line)
        XCTAssertTrue(line.contains(" Launch_ms=120.50"), "the latest launch interval wins: \(line)")
        XCTAssertTrue(line.contains(" Arrival_ms=33.00"), line)
        XCTAssertFalse(line.contains("SignIn_ms"), "intervals that never ran are left out")
        XCTAssertFalse(line.contains("Other"), line)
    }
}

// MARK: - Frame monitor and pacer

/// Collects the userInfo of each end-of-scroll notification; they are delivered on the main queue and read there.
private final class EndedScrollsBox: @unchecked Sendable {
    private(set) var items: [[String: Any]] = []
    func append(_ item: [String: Any]) { items.append(item) }
}

/// Frame pacing: the monitor runs a link only while a page scrolls, and the pacer counts delivered frames.
@MainActor
final class FramePacingHostedTests: XCTestCase {
    func testTheMonitorHoldsOneLinkWhileAnyPageScrollsAndNoneOtherwise() {
        let window = HostedPage.show(UIViewController())
        defer { window.isHidden = true }
        let monitor = FrameMonitor.shared
        XCTAssertEqual(monitor.displayLinkCount, 0)
        XCTAssertFalse(monitor.isMonitoring)
        let endedBox = EndedScrollsBox()
        let token = NotificationCenter.default.addObserver(forName: FrameMonitor.didEndScroll, object: nil, queue: .main) { [endedBox] note in
            endedBox.append(note.userInfo as? [String: Any] ?? [:])
        }
        defer { NotificationCenter.default.removeObserver(token) }

        monitor.beginScroll(page: "LegacyProbeA")
        monitor.beginScroll(page: "LegacyProbeA")   // the same page twice is one scroll
        monitor.beginScroll(page: "LegacyProbeB")
        XCTAssertTrue(monitor.isMonitoring)
        XCTAssertEqual(monitor.displayLinkCount, 1, "one link serves every scrolling page")
        // Frames the system produces meanwhile are observed, and a late one is a hitch.
        monitor.record(frameMs: 8, budgetMs: 8.3)
        monitor.record(frameMs: 40, budgetMs: 8.3)
        HostedPage.wait(0.4)
        monitor.endScroll(page: "LegacyProbeA")
        XCTAssertEqual(monitor.displayLinkCount, 1, "B is still scrolling")
        monitor.endScroll(page: "LegacyProbeA")     // already ended: nothing happens
        monitor.endScroll(page: "LegacyProbeB")
        XCTAssertEqual(monitor.displayLinkCount, 0)
        XCTAssertFalse(monitor.isMonitoring)
        HostedPage.wait(0.1)
        let pages = endedBox.items.compactMap { $0["page"] as? String }
        XCTAssertEqual(pages.filter { $0 == "LegacyProbeA" }.count, 1)
        let frames = endedBox.items.first { ($0["page"] as? String) == "LegacyProbeA" }?["frameMs"] as? [Double]
        XCTAssertEqual(frames?.prefix(2), [8, 40], "the page's frames are handed to whoever listens")
    }

    func testThePacerCountsTheFramesItWasHandedAndSummarisesThemWithMemory() {
        let window = HostedPage.show(UIViewController())
        defer { window.isHidden = true }
        let pacer = FramePacer()
        pacer.begin()
        HostedPage.wait(0.6)
        pacer.finish()
        XCTAssertGreaterThan(pacer.frames, 5, "the display link delivered frames")
        XCTAssertGreaterThan(pacer.expected, 0, "and learned the display's interval")
        let pairs = Dictionary(uniqueKeysWithValues: pacer.summary.split(separator: " ").compactMap { pair -> (String, String)? in
            let parts = pair.split(separator: "=")
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        })
        XCTAssertEqual(Set(pairs.keys), ["fps", "hz", "dropped", "hitch_ms_per_s", "mem_mb", "peak_mb"])
        XCTAssertGreaterThan(Double(pairs["fps"] ?? "") ?? 0, 5)
        XCTAssertGreaterThan(Double(pairs["mem_mb"] ?? "") ?? 0, 10, "the process holds some memory")
        XCTAssertGreaterThanOrEqual(Double(pairs["peak_mb"] ?? "") ?? 0, Double(pairs["mem_mb"] ?? "") ?? .infinity - 1)
        XCTAssertEqual(pairs["dropped"], "\(pacer.dropped)")
    }

    func testThePacerReadsAZeroRateBeforeAnyFrame() {
        let pacer = FramePacer()
        XCTAssertTrue(pacer.summary.contains("hz=0"))
        XCTAssertTrue(pacer.summary.contains("fps=0.0"))
        XCTAssertGreaterThan(FramePacer.memory().now, 0)
    }
}
