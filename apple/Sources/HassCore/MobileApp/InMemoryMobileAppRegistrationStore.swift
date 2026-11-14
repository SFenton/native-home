import Foundation

/// In-memory ``MobileAppRegistrationStore`` for tests and previews.
public final class InMemoryMobileAppRegistrationStore: MobileAppRegistrationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var list = MobileAppRegistrationList()

    /// Creates a store, optionally pre-filled.
    public init(_ registrations: [MobileAppRegistration] = [], active: MobileAppRegistration? = nil,
                pending: [PendingUnregister] = [], tokens: DeviceTokens = DeviceTokens()) {
        list = MobileAppRegistrationList(registrations: registrations, active: active, pending: pending, tokens: tokens)
    }

    public func registration(server: HassServer, userID: String) -> MobileAppRegistration? {
        lock.withLock { list.registration(server: server, userID: userID) }
    }

    public func save(_ registration: MobileAppRegistration) { lock.withLock { list.save(registration) } }
    public func remove(server: HassServer, userID: String) { lock.withLock { list.remove(server: server, userID: userID) } }
    public var active: MobileAppRegistration? { lock.withLock { list.active } }
    public func setActive(_ registration: MobileAppRegistration?) { lock.withLock { list.active = registration } }

    public var pendingUnregisters: [PendingUnregister] { lock.withLock { list.pending } }
    public func addPending(_ entry: PendingUnregister) { lock.withLock { list.addPending(entry) } }
    public func removePending(_ entry: PendingUnregister) { lock.withLock { list.removePending(entry) } }

    public var deviceTokens: DeviceTokens? { lock.withLock { list.tokens } }
    public func setDeviceTokens(_ tokens: DeviceTokens) { lock.withLock { list.tokens = tokens } }
}
