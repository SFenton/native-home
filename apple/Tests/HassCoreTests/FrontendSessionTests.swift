import Foundation
@testable import HassCore
import Testing

struct FrontendSessionTests {
    private let server = HassServer(baseURL: URL(string: "https://ha.example.com/")!)
    private let now = Date(timeIntervalSince1970: 1_000)

    private func session(expiresAt: Date) -> FrontendSession {
        FrontendSession(server: server, tokens: AuthTokens(accessToken: "ACCESS", expiresAt: expiresAt, refreshToken: "REFRESH"))
    }

    @Test func tokensMatchTheFrontendShape() throws {
        let json = try session(expiresAt: now.addingTimeInterval(1_800)).tokensJSON(now: now)
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["access_token"] as? String == "ACCESS")
        #expect(object["refresh_token"] as? String == "REFRESH")
        #expect(object["token_type"] as? String == "Bearer")
        #expect(object["expires_in"] as? Int == 1_800)
        #expect((object["expires"] as? NSNumber)?.int64Value == 2_800_000)
        #expect(object["hassUrl"] as? String == "https://ha.example.com")
        #expect(object["clientId"] as? String == HassServer.clientID)
    }

    @Test func longLivedTokensStayInsideJavaScriptIntegers() throws {
        let json = try session(expiresAt: .distantFuture).tokensJSON(now: now)
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let expires = try #require((object["expires"] as? NSNumber)?.int64Value)
        #expect(expires <= 9_007_199_254_740_991)
        #expect(object["expires_in"] as? Int == 31_536_000)
    }

    @Test func scriptOnlyWritesOnTheServerOrigin() throws {
        let script = try session(expiresAt: now.addingTimeInterval(60)).bootstrapScript(now: now)
        #expect(script.contains(#"window.location.origin !== "https://ha.example.com""#))
        #expect(script.contains(#"localStorage.setItem("hassTokens""#))
    }

    @Test func onlyServerURLsStayInside() {
        let session = session(expiresAt: now)
        #expect(session.isInternal(URL(string: "https://ha.example.com/config/integrations")!))
        #expect(session.isInternal(URL(string: "https://HA.example.com/profile")!))
        #expect(session.isInternal(URL(string: "about:blank")!))
        #expect(!session.isInternal(URL(string: "https://www.home-assistant.io/docs")!))
        #expect(!session.isInternal(URL(string: "http://ha.example.com/config")!))
        #expect(!session.isInternal(URL(string: "https://ha.example.com:8123/config")!))
    }
}
