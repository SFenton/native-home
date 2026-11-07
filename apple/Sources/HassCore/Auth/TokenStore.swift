import Foundation
import Security

/// What survives an app restart: the server and its refresh token.
public struct StoredCredentials: Codable, Sendable, Equatable {
    /// The server signed in to.
    public var server: HassServer
    /// Long-lived refresh token.
    public var refreshToken: String

    /// Creates stored credentials.
    public init(server: HassServer, refreshToken: String) {
        self.server = server
        self.refreshToken = refreshToken
    }
}

/// Persists ``StoredCredentials``. The production implementation is ``KeychainTokenStore``.
public protocol TokenStore: Sendable {
    /// Loads saved credentials, or `nil` when signed out.
    func load() -> StoredCredentials?
    /// Saves credentials, replacing any previous value.
    func save(_ credentials: StoredCredentials) throws
    /// Deletes saved credentials.
    func clear()
}

/// Keychain-backed ``TokenStore``. Items are this-device-only and readable after first unlock,
/// so background refreshes work but the token never migrates to another device via backup.
///
/// With an access group the item is shared with the app's extensions (the notification service extension fetches
/// camera snapshots with it). An item an earlier build saved outside the group moves into it on first read, and a
/// build without the group entitlement keeps working with an unshared item.
public struct KeychainTokenStore: TokenStore {
    /// The app group the app and its extensions share; also their Keychain access group.
    public static let sharedAccessGroup = "group.com.sfenton.home"

    private let service: String
    private let account = "credentials"
    private let accessGroup: String?

    /// Creates a store.
    /// - Parameters:
    ///   - service: Keychain service name.
    ///   - accessGroup: Shared access group (``sharedAccessGroup`` in the app and its extensions).
    public init(service: String = "com.sfenton.home.auth", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    /// The item, in `group` when given, else in any group the process can read.
    private func query(group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    public func load() -> StoredCredentials? {
        let (credentials, status) = read(group: accessGroup)
        if let credentials { return credentials }
        guard accessGroup != nil, let legacy = read(group: nil).credentials else { return nil }
        // An item saved before the shared group existed moves in, unless this build can't reach the group.
        if status != errSecMissingEntitlement { try? save(legacy) }
        return legacy
    }

    public func save(_ credentials: StoredCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        clear()
        var status = add(data, group: accessGroup)
        // Without the group entitlement (a build missing the capability), keep an unshared item.
        if status == errSecMissingEntitlement, accessGroup != nil { status = add(data, group: nil) }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    /// Deletes the item from every group the process can reach.
    public func clear() {
        SecItemDelete(query(group: nil) as CFDictionary)
    }

    private func read(group: String?) -> (credentials: StoredCredentials?, status: OSStatus) {
        var query = query(group: group)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return (nil, status) }
        return (try? JSONDecoder().decode(StoredCredentials.self, from: data), status)
    }

    private func add(_ data: Data, group: String?) -> OSStatus {
        var query = query(group: group)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil)
    }
}

/// In-memory ``TokenStore`` for tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredCredentials?

    /// Creates a store, optionally pre-filled.
    public init(_ value: StoredCredentials? = nil) { self.value = value }

    public func load() -> StoredCredentials? { lock.withLock { value } }
    public func save(_ credentials: StoredCredentials) throws { lock.withLock { value = credentials } }
    public func clear() { lock.withLock { value = nil } }
}
