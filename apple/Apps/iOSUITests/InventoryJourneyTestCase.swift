import XCTest

/// The base of the Inventory journeys: the gallery launch (through ``AppReuse``, so every area class opts into app reuse), the row,
/// last-call and reveal helpers, and the tap-until-done retry the sheet and alert journeys share. The old single
/// `InventoryJourneyTests` class was split by area (`contracts/test-map.json`) so a change to one area runs only its journeys;
/// nothing here is specific to one area. The pages run in the debug gallery (fixture EverShelf server; nothing reaches the house)
/// on iPhone, iPhone Duo and iPad (`.agents/pages/inventory/`).
@MainActor
class InventoryJourneyTestCase: JourneyTestCase {
    /// - Parameter fresh: Relaunches the process instead of resetting the resident app (``AppReuse``): the audit loops terminate
    ///   the app between pages on purpose, to keep the simulator's backboardd alive.
    func launch(space: String = "pantry", open: String? = nil, state: String? = nil, arguments: [String] = [],
                clean: Bool = false, environment: [String: String] = [:], fresh: Bool = false) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment.merge(environment) { $1 }
        configured.launchEnvironment["FENTON_GALLERY"] = "inventory"
        configured.launchEnvironment["FENTON_GALLERY_SPACE"] = space
        configured.launchEnvironment["FENTON_SCAN_CAMERA"] = "simulated"
        if let open { configured.launchEnvironment["FENTON_GALLERY_OPEN"] = open }
        if let state { configured.launchEnvironment["FENTON_GALLERY_STATE"] = state }
        if clean { configured.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        configured.launchArguments += arguments
        let app: XCUIApplication
        if fresh {
            configured.launch()
            app = configured
        } else {
            app = startApp(configured)
        }
        return app
    }

    /// `values`, or the comma-separated subset named in the `key` environment variable. Runs can split a long audit
    /// loop across simulator boots: many audits in one session crash the iPad simulator's backboardd.
    static func only<T: LosslessStringConvertible & Equatable>(_ values: [T], _ key: String) -> [T] {
        guard let list = ProcessInfo.processInfo.environment[key], !list.isEmpty else { return values }
        let wanted = list.split(separator: ",").compactMap { T(String($0)) }
        return values.filter { wanted.contains($0) }
    }

    /// Scrolls until `element` is hittable and clear of Add Item's pinned footer. At AX5 wrapped text pushes
    /// controls below the fold, where the form loads them once scrolled to; on short sheets (iPad landscape,
    /// unfolded Duo landscape) a row behind the footer still reads as hittable, and tapping it pressed the
    /// footer's forward button instead.
    @discardableResult
    func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        // One snapshot of the element per look (frame and existence together), one of the footer; `isHittable` only once the frame
        // is clear. Stops after 3 drags that do not move the element (a row at the foot of a short form can never clear).
        func clear() -> (clear: Bool, minY: CGFloat?) {
            guard let frame = (try? element.snapshot())?.frame, !frame.isEmpty else { return (false, nil) }
            if let forward = (try? app.buttons["scan.forward"].snapshot())?.frame, !forward.isEmpty, element.identifier != "scan.forward" {
                guard frame.maxY <= forward.minY - 8 || frame.minY >= forward.maxY else { return (false, frame.minY) }
            }
            return (element.isHittable, frame.minY)
        }
        // Drag in the form's leading gutter: a swipe from the window's centre starts on the camera feed and does not
        // scroll the form (unfolded Duo landscape).
        let form = app.collectionViews.matching(NSPredicate(format: "identifier BEGINSWITH 'scan.'")).firstMatch
        var look = clear()
        if look.minY == nil, element.appears(timeout: 2) { look = clear() } // Just after a transition the element may not be built yet.
        var swipes = 0
        var stuck = 0
        var lastMinY = look.minY
        while !look.clear, swipes < 10, stuck < 3 {
            if (try? form.snapshot()) != nil {
                form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                    .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25)))
            } else {
                app.swipeUp()
            }
            swipes += 1
            look = clear()
            if let minY = look.minY, let lastMinY, abs(minY - lastMinY) < 1 { stuck += 1 } else { stuck = 0 }
            lastMinY = look.minY
        }
        XCTAssertTrue(element.exists, "\(element) not found")
        return element
    }

    func row(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)["inventory.row.\(name)"]
    }

    /// Cancels the delete confirmation: its Cancel on an action sheet, a tap outside it on the popover that iPad shows (which has none).
    func cancelConfirmation(_ app: XCUIApplication) {
        let cancel = app.sheets.buttons["Cancel"].firstMatch
        if cancel.appears(timeout: 2) {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        }
    }

    func lastCall(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].label
    }
}

extension XCUIElement {
    /// Taps, then retries (up to three taps) until `done` holds: a tap that lands while a sheet or alert is
    /// still animating in is dropped on a loaded host. `stillOn` guards a retry: a slow transition can put a
    /// same-identifier button of the next step (Add Item's forward) under the retry, which would skip a step.
    func tap(until done: () -> Bool, stillOn: () -> Bool = { true }) {
        for _ in 0..<3 {
            tap()
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if done() { return }
                usleep(100_000)
            }
            guard !done(), stillOn(), exists, isHittable else { return }
        }
    }

    func clearAndType(_ text: String) {
        tap()
        if let value = value as? String, !value.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        typeText(text)
    }
}
