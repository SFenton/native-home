import Foundation
@testable import HassCore
import Testing

/// Serves canned responses keyed by request path.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: [(status: Int, body: String)]] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let path = request.url!.path()
        guard var queue = Self.responses[path], !queue.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let next = queue.removeFirst()
        Self.responses[path] = queue
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite(.serialized)
struct HassLoginFlowTests {
    private let tokenBody = #"{"access_token":"A","expires_in":1800,"refresh_token":"R","token_type":"Bearer"}"#

    @Test func signsInWithoutMFA() async throws {
        StubURLProtocol.requests = []
        StubURLProtocol.responses = [
            "/auth/login_flow": [(200, #"{"flow_id":"f1","type":"form","step_id":"init"}"#)],
            "/auth/login_flow/f1": [(200, #"{"type":"create_entry","result":"CODE"}"#)],
            "/auth/token": [(200, tokenBody)],
        ]
        let flow = HassLoginFlow(server: .example, session: StubURLProtocol.session())
        let step = try await flow.signIn(username: "alex", password: "pw")
        guard case let .signedIn(tokens) = step else { Issue.record("expected sign-in"); return }
        #expect(tokens.accessToken == "A")
        #expect(tokens.refreshToken == "R")
        let tokenRequest = try #require(StubURLProtocol.requests.last)
        let body = String(decoding: tokenRequest.httpBodyStreamData(), as: UTF8.self)
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=CODE"))
    }

    @Test func asksForMFAThenSignsIn() async throws {
        StubURLProtocol.responses = [
            "/auth/login_flow": [(200, #"{"flow_id":"f2","type":"form","step_id":"init"}"#)],
            "/auth/login_flow/f2": [
                (200, #"{"type":"form","step_id":"mfa","errors":{}}"#),
                (200, #"{"type":"create_entry","result":"CODE2"}"#),
            ],
            "/auth/token": [(200, tokenBody)],
        ]
        let flow = HassLoginFlow(server: .example, session: StubURLProtocol.session())
        #expect(try await flow.signIn(username: "alex", password: "pw") == .needsMFACode)
        guard case .signedIn = try await flow.submitMFACode("123456") else { Issue.record("expected sign-in"); return }
    }

    @Test func rejectsBadPassword() async throws {
        StubURLProtocol.responses = [
            "/auth/login_flow": [(200, #"{"flow_id":"f3","type":"form","step_id":"init"}"#)],
            "/auth/login_flow/f3": [(200, #"{"type":"form","step_id":"init","errors":{"base":"invalid_auth"}}"#)],
        ]
        let flow = HassLoginFlow(server: .example, session: StubURLProtocol.session())
        await #expect(throws: HassLoginFlow.LoginError.invalidCredentials) {
            try await flow.signIn(username: "alex", password: "wrong")
        }
    }

    @Test(arguments: [
        (404, "<html>Not Found</html>"),
        (200, "<html><body>Welcome</body></html>"),
        (200, #"{"message":"hello"}"#),
        (200, "[1,2]"),
        (404, #"{"message":"nope"}"#),
    ])
    func anAddressThatIsNotHomeAssistantIsToldApart(status: Int, body: String) async {
        StubURLProtocol.responses = ["/auth/login_flow": [(status, body)]]
        let flow = HassLoginFlow(server: .example, session: StubURLProtocol.session())
        await #expect(throws: HassLoginFlow.LoginError.notHomeAssistant) {
            try await flow.signIn(username: "alex", password: "pw")
        }
    }

    @Test func aGatewayErrorOrNoAnswerStaysUnreachable() async {
        StubURLProtocol.responses = ["/auth/login_flow": [(502, "<html>Bad Gateway</html>")]]
        let flow = HassLoginFlow(server: .example, session: StubURLProtocol.session())
        await #expect(throws: HassLoginFlow.LoginError.network("HTTP 502")) {
            try await flow.signIn(username: "alex", password: "pw")
        }
        StubURLProtocol.responses = [:]
        await #expect(throws: (any Error).self) {
            try await flow.signIn(username: "alex", password: "pw")
        }
    }

    @Test func refreshKeepsRefreshTokenWhenServerOmitsIt() async throws {
        StubURLProtocol.responses = ["/auth/token": [(200, #"{"access_token":"A2","expires_in":1800,"token_type":"Bearer"}"#)]]
        let tokens = try await HassLoginFlow.refresh(server: .example, refreshToken: "R", session: StubURLProtocol.session())
        #expect(tokens.accessToken == "A2")
        #expect(tokens.refreshToken == "R")
    }

    @Test func formEncodingEscapesReservedCharacters() {
        let body = String(decoding: HassLoginFlow.formEncode(["a": "x+y&z=1"]), as: UTF8.self)
        #expect(body == "a=x%2By%26z%3D1")
    }
}

private extension URLRequest {
    /// URLSession moves `httpBody` into a stream before URLProtocol sees it.
    func httpBodyStreamData() -> Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
