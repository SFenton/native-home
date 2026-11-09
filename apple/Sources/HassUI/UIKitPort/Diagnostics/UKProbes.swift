#if os(iOS)
import HassTelemetry
import UIKit

/// An invisible 2 pt element that an XCUITest journey or `tools/ios_*.sh` reads or drives through its accessibility label and
/// identifier: the UIKit counterpart of the `Color.clear.frame(width: 2, height: 2).accessibilityElement()` every SwiftUI probe uses.
final class UKProbeElementView: UIView {
    init(identifier: String, label: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 2).isActive = true
        heightAnchor.constraint(equalToConstant: 2).isActive = true
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = identifier
        accessibilityLabel = label
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ text: String) { accessibilityLabel = text }
}

#if DEBUG
/// `FENTON_APPEARANCE_DEBUG=1`: an element (`appearance.probe`) whose label says what the screen, the scene and the window report
/// as their interface style (`screen=2 scene=2 window=2`; 1 light, 2 dark), refreshed when the scene's style changes and when the
/// app becomes active. The SwiftUI app's `SystemAppearance` probe, for the system-appearance journeys.
@MainActor
final class UKAppearanceProbe {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["FENTON_APPEARANCE_DEBUG"] == "1" }
    let element = UKProbeElementView(identifier: "appearance.probe", label: "screen=? scene=? window=?")
    private var registration: (any UITraitChangeRegistration)?
    nonisolated(unsafe) private var activation: (any NSObjectProtocol)?
    private var task: Task<Void, Never>?

    init() {
        // The element is in a window one turn later.
        task = Task { @MainActor [weak self] in
            for _ in 0..<50 where self?.element.window == nil { try? await Task.sleep(for: .milliseconds(100)) }
            self?.attach()
        }
    }

    deinit {
        task?.cancel()
        if let activation { NotificationCenter.default.removeObserver(activation) }
    }

    private func attach() {
        guard let scene = element.window?.windowScene else { return }
        report()
        registration = scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: UIWindowScene, _) in self?.report() }
        activation = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
    }

    private func report() {
        guard let window = element.window else { return }
        element.show("screen=\(window.screen.traitCollection.userInterfaceStyle.rawValue) scene=\(window.windowScene?.traitCollection.userInterfaceStyle.rawValue ?? -1) window=\(window.traitCollection.userInterfaceStyle.rawValue)")
    }
}
#endif

/// Scroll cost runs (`FENTON_SCROLLCOST=1`, any build): `tools/ios_scrollcost.sh` measures the SwiftUI app and the port the same way.
/// The same invisible element (`diagnostics.scrollcost`), the same Darwin notifications, the same `FENTON_SCROLLCOST_AUTORUN` /
/// `_FILE` / `_NAME` / `_OPEN` behaviour, and the very same driver (``ScrollCostDriver``): it finds the front scroll view in the
/// view hierarchy, scrolls it on a display link and reports the main thread's cost.
@MainActor
final class UKScrollCostProbe {
    /// A hosted test turns the probe on without the launch environment.
    nonisolated(unsafe) static var forceEnabled = false
    static var isEnabled: Bool { forceEnabled || ScrollCostProbe.isEnabled }
    let element = UKProbeElementView(identifier: "diagnostics.scrollcost", label: "ready")
    private let driver = ScrollCostDriver()
    private var tasks: [Task<Void, Never>] = []

    init() {
        tasks.append(Task { [weak self] in await self?.listen() })
        tasks.append(Task { [weak self] in await self?.autorun() })
    }

    deinit { tasks.forEach { $0.cancel() } }

    private func listen() async {
        for await name in ScrollCostProbe.notifications() {
            element.show("running")
            let report = await driver.run(scrolling: name == ScrollCostProbe.scrollNotification)
            element.show(report.map(\.summary) ?? "no scroll view: " + ScrollCostDriver.describeScrollViews())
        }
    }

    private func autorun() async {
        let environment = ProcessInfo.processInfo.environment
        guard let delay = environment["FENTON_SCROLLCOST_AUTORUN"].flatMap(Double.init) else { return }
        let path = environment["FENTON_SCROLLCOST_FILE"]
        let name = environment["FENTON_SCROLLCOST_NAME"] ?? "surface"
        try? await Task.sleep(for: .seconds(delay))
        #if DEBUG
        if environment["FENTON_LAYER_CENSUS"] == "1" {
            ScrollCostProbe.append("LAYERCENSUS\t\(name)\n\(LayerCensus.run())\n", to: path)
        }
        #endif
        for kind in ["idle", "scroll", "scroll"] {
            let report = await driver.run(scrolling: kind == "scroll")
            let line = report.map(\.summary) ?? "no scroll view: " + ScrollCostDriver.describeScrollViews()
            element.show(line)
            ScrollCostProbe.append("SCROLLCOST\t\(name)\t\(kind)\t\(line)\n", to: path)
            if report == nil { break }
        }
        ScrollCostProbe.append("SCROLLCOST_DONE\t\(name)\n", to: path)
        // `devicectl --console` waits for the app to end, so a phone launch asks it to.
        if environment["FENTON_SCROLLCOST_EXIT"] == "1" { exit(0) }
    }
}

/// Navigation cost runs (`FENTON_NAVPERF=1`): an invisible element `NavigationPerformanceTests` reads after it drives the app.
@MainActor
final class UKNavigationPerfProbe {
    /// A hosted test turns the probe on without the launch environment.
    nonisolated(unsafe) static var forceEnabled = false
    static var isEnabled: Bool { forceEnabled || NavigationPerfProbe.isEnabled }
    let element = UKProbeElementView(identifier: "diagnostics.navperf", label: "ready")
    private var task: Task<Void, Never>?

    init() {
        task = Task { [weak self] in
            for await name in NavigationPerfProbe.notifications() {
                guard let self else { return }
                if name == NavigationPerfProbe.resetNotification {
                    Telemetry.log.reset()
                    self.element.show("reset")
                } else {
                    self.element.show(NavigationTelemetry.summary(from: Telemetry.log.phaseStats))
                }
            }
        }
    }

    deinit { task?.cancel() }
}

/// Launch cost runs (`FENTON_LAUNCHCOST=1`, any build): an invisible element a test reads the last measurement from.
@MainActor
final class UKLaunchCostProbe {
    /// A hosted test turns the probe on without the launch environment.
    nonisolated(unsafe) static var forceEnabled = false
    static var isEnabled: Bool { forceEnabled || LaunchCostProbe.isEnabled }
    let element = UKProbeElementView(identifier: "diagnostics.launchcost", label: LaunchCostProbe.latest)
    private var link: CADisplayLink?

    init() {
        // The label is read from the probe's latest line whenever it changes; a light poll on the main run loop's idle time.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.element.show(LaunchCostProbe.latest) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    nonisolated(unsafe) private var timer: Timer?
    deinit { timer?.invalidate() }
}

#if DEBUG
/// Resource census runs (`FENTON_RESOURCE_CENSUS=1`): an invisible element with the live counts, refreshed every half second.
@MainActor
final class UKResourceCensusProbe {
    /// A hosted test turns the probe on without the launch environment.
    nonisolated(unsafe) static var forceEnabled = false
    static var isEnabled: Bool { forceEnabled || ResourceCensusProbe.isEnabled }
    let element = UKProbeElementView(identifier: "diagnostics.resources", label: "")
    private var task: Task<Void, Never>?

    init() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.element.show(ResourceCensusProbe.currentSummary())
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    deinit { task?.cancel() }
}
#endif
#endif
