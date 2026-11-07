import Foundation

/// Retries sign-out removals that could not reach Home Assistant (``PendingUnregister``): at launch and when the
/// network returns, whether or not anyone is signed in. The request carries no token; the webhook id is the proof.
public actor PendingUnregisterRetrier {
    private let store: any MobileAppRegistrationStore
    private let transport: any FeedbackHTTPTransport
    private let device: @Sendable () async -> MobileAppDevice
    private var running = false

    /// Creates a retrier.
    /// - Parameters:
    ///   - store: Where the pending removals are kept.
    ///   - transport: HTTP to Home Assistant.
    ///   - device: This phone, for the clear-push-details fallback on a server without 1.1.
    public init(store: any MobileAppRegistrationStore, transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport(),
                device: @escaping @Sendable () async -> MobileAppDevice) {
        self.store = store
        self.transport = transport
        self.device = device
    }

    /// Sends each pending removal once. 200, 410, 404 (after a best-effort push clear) and 400/403 (it can never
    /// succeed) drop the entry; no answer or a server error keeps it for next time.
    public func run() async {
        guard !running else { return }
        running = true
        defer { running = false }
        for entry in store.pendingUnregisters {
            let client = HomeAssistantPushClient(server: entry.server, accessToken: { throw PushClientError.signedOut },
                                                 transport: transport)
            do {
                switch try await client.unregister(webhookID: entry.webhookID, authenticated: false) {
                case .removed, .gone:
                    break
                case .unsupported:
                    let registration = MobileAppRegistration(server: entry.server, userID: "", webhookID: entry.webhookID)
                    try? await client.updateRegistration(registration, device: await device(), appData: .cleared)
                }
                store.removePending(entry)
            } catch PushClientError.status(let code) where code == 400 || code == 403 {
                store.removePending(entry)
            } catch {}
        }
    }
}
