#if os(iOS)
import OSLog
import UIKit

// MARK: - Rejected nodes

/// The stand-in for a document node that no native control can serve.
///
/// A published document is preflighted, but a cached publication, a teardown race or a provider that changed
/// between preflight and render can still leave a render path holding a node it cannot build. Those paths
/// return this inert view and report a ``UKServerUIRendererError`` instead of trapping, so the app keeps the
/// last good screen and never enters a launch crash loop.
@MainActor
enum UKServerUIRejected {
    private static let log = Logger(subsystem: "app.sh.server-ui", category: "rejected-node")

    /// An empty, zero-size, hidden view carrying a stable identifier for tests and diagnostics.
    ///
    /// - Parameters:
    ///   - reason: A short description for the log; it carries no document content.
    ///   - pointer: The document location to report.
    ///   - onError: Receives the renderer error when the caller has a reporting channel.
    static func view(_ reason: String, pointer: String = "/document",
                     onError: ((UKServerUIRendererError) -> Void)? = nil) -> UIView {
        log.error("Rejected server-ui node: \(reason, privacy: .public)")
        onError?(.init(code: .unavailableSource, pointer: pointer))
        let view = UIView()
        view.isHidden = true
        view.isAccessibilityElement = false
        view.accessibilityIdentifier = "server-ui.rejected"
        return view
    }
}
#endif
