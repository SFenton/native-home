import Foundation

/// Hands out valid access tokens, refreshing them when needed.
///
/// Concurrent callers during a refresh share one network request.
public actor TokenManager {
    /// Thrown when there is no refresh token (signed out) or the server rejected it.
    public struct SignedOut: Error {}

    private let store: TokenStore
    private let session: URLSession
    private var current: AuthTokens?
    private var refreshTask: Task<AuthTokens, Error>?

    /// Creates a manager.
    /// - Parameters:
    ///   - store: Where the refresh token lives.
    ///   - initial: Tokens just obtained from sign-in, if any.
    ///   - session: URL session for refreshes.
    public init(store: TokenStore, initial: AuthTokens? = nil, session: URLSession = .shared) {
        self.store = store
        self.current = initial
        self.session = session
    }

    /// Returns an access token that is valid for at least another minute.
    public func validAccessToken() async throws -> String {
        try await validTokens().accessToken
    }

    /// Returns the full token set (access token valid for at least another minute, plus the refresh
    /// token), e.g. to hand the Home Assistant web frontend its own session in the settings web view.
    public func validTokens() async throws -> AuthTokens {
        if let current, !current.needsRefresh() { return current }
        if let refreshTask { return try await refreshTask.value }
        guard let stored = store.load() else { throw SignedOut() }
        let session = session
        let task = Task { try await HassLoginFlow.refresh(server: stored.server, refreshToken: stored.refreshToken, session: session) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let tokens = try await task.value
            current = tokens
            if tokens.refreshToken != stored.refreshToken {
                try? store.save(StoredCredentials(server: stored.server, refreshToken: tokens.refreshToken))
            }
            return tokens
        } catch HassLoginFlow.LoginError.invalidCredentials {
            throw SignedOut()
        }
    }

    /// Forgets the in-memory access token (e.g. after the server rejects it).
    public func invalidate() { current = nil }
}
