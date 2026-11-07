import Foundation
@testable import HassCore
import Testing

struct TokenManagerTests {
    @Test func returnsCurrentTokenWhileValid() async throws {
        let manager = TokenManager(
            store: InMemoryTokenStore(),
            initial: AuthTokens(accessToken: "A", expiresAt: Date().addingTimeInterval(600), refreshToken: "R")
        )
        #expect(try await manager.validAccessToken() == "A")
    }

    @Test func validTokensIncludeTheRefreshToken() async throws {
        let tokens = AuthTokens(accessToken: "A", expiresAt: Date().addingTimeInterval(600), refreshToken: "R")
        let manager = TokenManager(store: InMemoryTokenStore(), initial: tokens)
        #expect(try await manager.validTokens() == tokens)
    }

    @Test func signedOutWithoutRefreshToken() async {
        let manager = TokenManager(store: InMemoryTokenStore())
        await #expect(throws: TokenManager.SignedOut.self) { try await manager.validAccessToken() }
    }

    @Test func needsRefreshInsideLeeway() {
        let tokens = AuthTokens(accessToken: "A", expiresAt: Date(timeIntervalSince1970: 100), refreshToken: "R")
        #expect(tokens.needsRefresh(now: Date(timeIntervalSince1970: 50)))
        #expect(!tokens.needsRefresh(now: Date(timeIntervalSince1970: 30)))
    }
}
