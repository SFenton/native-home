import HassTelemetry
import SwiftUI

/// Reports the navigation measurements to a UI test or `tools/ios_navperf.sh` (design: `.agents/design/motion.md` §10; tests:
/// `NavigationPerformanceTests`).
///
/// With `FENTON_NAVPERF=1` the root view carries an invisible element, `diagnostics.navperf`. A test drives the app, then posts the
/// Darwin notification `com.sfenton.home.navperf.report`; the element's label becomes ``NavigationTelemetry/summary(from:)`` of
/// what the app measured. Nothing is computed until asked, so the measurement is not disturbed by the report.
struct NavigationPerfProbe {
    /// Whether this launch carries the probe.
    static let isEnabled = ProcessInfo.processInfo.environment["FENTON_NAVPERF"] == "1"
    static let reportNotification = "com.sfenton.home.navperf.report"
    static let resetNotification = "com.sfenton.home.navperf.reset"

    /// The two Darwin notifications as an async stream of their names.
    static func notifications() -> AsyncStream<String> {
        AsyncStream { continuation in
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let observer = Unmanaged.passRetained(Sink { continuation.yield($0) })
            for name in [reportNotification, resetNotification] {
                CFNotificationCenterAddObserver(center, observer.toOpaque(), { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    Unmanaged<Sink>.fromOpaque(observer).takeUnretainedValue().handler(name.rawValue as String)
                }, name as CFString, nil, .deliverImmediately)
            }
            continuation.onTermination = { _ in
                CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer.toOpaque())
                observer.release()
            }
        }
    }

    private final class Sink: @unchecked Sendable {
        let handler: @Sendable (String) -> Void
        init(_ handler: @escaping @Sendable (String) -> Void) { self.handler = handler }
    }
}
