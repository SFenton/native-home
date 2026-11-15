#if os(iOS) && DEBUG
import Foundation
import HassCore

/// A UI-test seam: `FENTON_UI_PUBLICATION=unpublished` or `incompatible` answers the publication subscription with that state
/// at once, so a journey that signs in against the stubbed OAuth server (which has no websocket) reaches the recovery boundary
/// a real integration would produce. Compiled out of release builds; absent unless the variable is set.
@MainActor
struct UKServerUIPublicationStub: ServerUIPublicationTransport {
    private let reply: Data

    init?(environment: [String: String]) {
        let object: [String: Any]
        switch environment["FENTON_UI_PUBLICATION"] {
        case "unpublished": object = ["state": "unpublished"]
        case "incompatible": object = ["state": "incompatible", "epoch": "stub", "revision": 1, "missing": ["sh.future@1"]]
        default: return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        reply = data
    }

    func subscribe(capabilities: [String], handler: @escaping @Sendable (Result<Data, any Error>) -> Void) -> @Sendable () -> Void {
        handler(.success(reply))
        return {}
    }
}
#endif
