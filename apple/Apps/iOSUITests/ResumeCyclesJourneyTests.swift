import XCTest

/// Backgrounding and resuming must leave the app exactly as the first launch did (owner report 2026-10-16: scrolling
/// got worse after every background and foreground, so something was added on each resume and never removed;
/// `.agents/platforms/apple/connection-lifecycle.md`, "Resume rule").
///
/// The debug build exposes a census of what its lifecycle objects hold (`FENTON_RESOURCE_CENSUS=1`, element
/// `diagnostics.resources`, `HassUI/Diagnostics/ResourceCensusProbe.swift`): notification observers, subscriptions,
/// tasks, display links, players. After the first launch's scroll it is read once; then the app goes to the
/// background and comes back six times (the fifth stays away past `ConnectionLifecycle.backgroundGrace`, so the
/// socket is dropped and resubscribed), Home is scrolled each time, and the census must match.
@MainActor
final class ResumeCyclesJourneyTests: JourneyTestCase {
    /// Gauges that must be identical after every resume: what a resume registers, a background takes away.
    static let exact = [
        "Connection.statesSubscription", "Connection.stateObserver", "CameraPool.observers", "CameraPool.models",
        "CameraPool.resumeTask", "Lifecycle.pendingDisconnect", "Appearance.activationObservers", "Weather.consumers",
    ]

    /// Gauges that follow what is happening (a stream still connecting, a forecast in flight) but can never exceed a
    /// fixed bound; a leak per resume would climb past it.
    static let bounded: [String: Int] = [
        "Camera.players": 4, "Camera.watchdogs": 4, "Camera.signallingSockets": 4, "Camera.attempts": 4, "Camera.observations": 8, "Weather.fetches": 2,
        "Connection.saveTask": 1, "Connection.routeTask": 1, "FrameMonitor.displayLinks": 1, "Weather.timer": 1,
    ]

    private func census(_ app: XCUIApplication) -> [String: Int] {
        let probe = element("diagnostics.resources", in: app)
        XCTAssertTrue(probe.appears(timeout: 10), "The census probe is missing")
        // The probe refreshes twice a second; give it a beat after the last thing that changed.
        usleep(1_200_000)
        var counts: [String: Int] = [:]
        for pair in probe.label.split(separator: " ") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, let value = Int(parts[1]) { counts[String(parts[0])] = value }
        }
        return counts
    }

    private func scrollHome(_ app: XCUIApplication) {
        let scroll = element("home.scroll", in: app)
        XCTAssertTrue(scroll.appears(timeout: 20), "Home did not come back")
        for _ in 0..<2 {
            scroll.swipeUp(velocity: .fast)
            scroll.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(app.buttons["home.chip.lights"].exists, "Home lost its content after scrolling")
    }

    func testFiveBackgroundAndForegroundCyclesLeaveTheFirstLaunchSet() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_RESOURCE_CENSUS": "1"])
        sleep(8) // Connection, snapshots and streams settle.
        scrollHome(app)
        let launch = census(app)
        XCTAssertEqual(launch["Connection.statesSubscription"], 1, "Launch census: \(launch)")
        XCTAssertEqual(launch["Lifecycle.pendingDisconnect"], 0, "Launch census: \(launch)")
        let launchThreads = launch["Process.threads"] ?? 0

        for cycle in 1...6 {
            XCUIDevice.shared.press(.home)
            // Cycle 5 outlasts the 30 s grace period so the socket drops and the return resubscribes.
            sleep(cycle == 5 ? 35 : 4)
            app.activate()
            XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 30), "Cycle \(cycle): Home did not return")
            sleep(6) // The connection answers and the streams restart.
            scrollHome(app)

            var now = census(app)
            // Threads follow work in flight: while four streams reconnect (WebRTC peers starting and stopping) the
            // process holds extra ones, which return once they settle (folded Duo, cycle 6: 27 at launch, 55 mid
            // reconnect). A leak never returns, so wait on the state for up to 30 s before judging it.
            let settleBy = Date().addingTimeInterval(30)
            while (now["Process.threads"] ?? 0) > launchThreads + 25, Date() < settleBy { now = census(app) }
            for name in Self.exact {
                XCTAssertEqual(now[name], launch[name], "Cycle \(cycle): \(name) changed from the first launch.\nlaunch \(launch)\nnow    \(now)")
            }
            for (name, bound) in Self.bounded {
                XCTAssertLessThanOrEqual(now[name] ?? 0, bound, "Cycle \(cycle): \(name) is past its bound.\nnow \(now)")
            }
            // Threads move with work in flight; a thread added per resume would climb well past this.
            XCTAssertLessThanOrEqual(now["Process.threads"] ?? 0, launchThreads + 25, "Cycle \(cycle): threads grew.\nlaunch \(launch)\nnow    \(now)")
        }
    }
}
