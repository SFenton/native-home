#if os(iOS) && DEBUG
import Foundation
import HassCore

// MARK: - Injected call failure

/// The failure the `failCalls` preview flag injects: what a service call that Home Assistant answered with an error reply looks
/// like to the caller. The text is the one ``ServiceErrorText`` shows.
enum UKServerUIPreviewFault: Error, LocalizedError, Equatable {
    case callFailed

    var errorDescription: String? { "Home Assistant could not complete the call." }
}

/// A caller whose every call fails with ``UKServerUIPreviewFault/callFailed``: the `failCalls` fake for a preview with no gallery
/// fixtures. It records the calls it refused, so a test can see that the app reached it and nothing reached a server.
@MainActor
final class UKServerUIPreviewFailingCaller: HassServiceResponding {
    /// Every refused call as `domain.service`.
    private(set) var refused: [String] = []

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        refused.append(domain + "." + service)
        throw UKServerUIPreviewFault.callFailed
    }

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        refused.append(domain + "." + service)
        throw UKServerUIPreviewFault.callFailed
    }
}
#endif
