import Foundation
import Security

/// Keychain-backed ``MobileAppRegistrationStore``: one this-device-only item holding every user's webhook, readable
/// after first unlock so a notification button works from the lock screen.
public final class KeychainMobileAppRegistrationStore: MobileAppRegistrationStore, @unchecked Sendable {
    private let service: String
    private let account = "registrations"
    private let lock = NSLock()

    /// Creates a store.
    /// - Parameter service: Keychain service name. The default keeps push's original name, so a phone that
    ///   registered before registration was shared keeps its webhook (and its one Home Assistant device).
    public init(service: String = "com.sfenton.home.push") {
        self.service = service
    }

    public func registration(server: HassServer, userID: String) -> MobileAppRegistration? {
        lock.withLock { read().registration(server: server, userID: userID) }
    }

    public func save(_ registration: MobileAppRegistration) {
        update { $0.save(registration) }
    }

    public func remove(server: HassServer, userID: String) {
        update { $0.remove(server: server, userID: userID) }
    }

    public var active: MobileAppRegistration? { lock.withLock { read().active } }

    public func setActive(_ registration: MobileAppRegistration?) {
        update { $0.active = registration }
    }

    public var pendingUnregisters: [PendingUnregister] { lock.withLock { read().pending } }

    public func addPending(_ entry: PendingUnregister) {
        update { $0.addPending(entry) }
    }

    public func removePending(_ entry: PendingUnregister) {
        update { $0.removePending(entry) }
    }

    public var deviceTokens: DeviceTokens { lock.withLock { read().tokens } }

    public func setDeviceTokens(_ tokens: DeviceTokens) {
        update { $0.tokens = tokens }
    }

    // MARK: - Keychain

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func update(_ change: (inout MobileAppRegistrationList) -> Void) {
        lock.withLock {
            var list = read()
            change(&list)
            write(list)
        }
    }

    private func read() -> MobileAppRegistrationList {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return MobileAppRegistrationList()
        }
        return (try? JSONDecoder().decode(MobileAppRegistrationList.self, from: data)) ?? MobileAppRegistrationList()
    }

    private func write(_ list: MobileAppRegistrationList) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let data = try? JSONEncoder().encode(list) else { return }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }
}
