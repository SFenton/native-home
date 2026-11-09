#if DEBUG
import Foundation

/// Debug builds only: canned Home Assistant login answers, so a journey sees every error state without a failed sign-in on
/// the real server (repeated refusals can get an address banned). `FENTON_SIGNIN_STUB` picks the answer:
///
/// | Value | The sign-in ends with |
/// |---|---|
/// | `wrong` | Home Assistant refusing the username and password |
/// | `slow` | the same, after three seconds (the busy state stays up long enough to look at) |
/// | `success` | tokens, as if the password were right (journeys that look at the arrival, with `FENTON_HASS_SERVER` pointing nowhere) |
/// | `unreachable` | the phone being offline |
/// | `failed` | the flow being aborted (too many attempts) |
/// | `twostep` | a second step, which the app does not do |
/// | `nothomeassistant` | an address that answers, but not with a login flow (a 404 web page) |
final class DebugSignInStub: URLProtocol, @unchecked Sendable {
    /// The answer a launch asked for, or nil for the real server.
    static func mode(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let value = environment["FENTON_SIGNIN_STUB"], ["wrong", "slow", "success", "unreachable", "failed", "twostep", "nothomeassistant"].contains(value) else {
            return nil
        }
        return value
    }

    /// A session that answers from the stub, or nil when the launch did not ask for one.
    static func session(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> URLSession? {
        guard let mode = mode(environment) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DebugSignInStub.self]
        configuration.httpAdditionalHeaders = ["X-Fenton-Stub": mode]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let mode = request.value(forHTTPHeaderField: "X-Fenton-Stub") ?? "wrong"
        let path = request.url?.path() ?? ""
        if mode == "unreachable" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let body: String
        var status = 200
        if mode == "nothomeassistant" {
            status = 404
            body = "<html><body>404: Not Found</body></html>"
        } else if path.hasSuffix("/auth/login_flow") {
            body = #"{"flow_id":"stub","type":"form","step_id":"init"}"#
        } else if path.hasSuffix("/auth/token") {
            body = #"{"access_token":"stub-access","expires_in":1800,"refresh_token":"stub-refresh","token_type":"Bearer"}"#
        } else {
            switch mode {
            case "success": body = #"{"type":"create_entry","result":"stub-code"}"#
            case "failed": body = #"{"type":"abort","reason":"too_many_attempts"}"#
            case "twostep": body = #"{"type":"form","step_id":"mfa","errors":{}}"#
            default: body = #"{"type":"form","step_id":"init","errors":{"base":"invalid_auth"}}"#
            }
        }
        let delay = mode == "slow" && !path.hasSuffix("/auth/login_flow") ? 3.0 : 0
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
#endif
