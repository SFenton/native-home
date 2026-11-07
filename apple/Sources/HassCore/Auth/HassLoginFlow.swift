import Foundation

/// Signs in with a username and password through Home Assistant's login flow API.
///
/// This is the same path the Home Assistant web login uses, so no long-lived token ever ships in the app.
/// The flow is: create a flow, submit credentials, optionally submit an MFA code, then exchange the
/// authorization code for tokens. See `.agents/platforms/apple/auth.md`.
public actor HassLoginFlow {
    // MARK: - Types

    /// What the caller should do after a step.
    public enum Step: Sendable, Equatable {
        /// Signed in; persist ``AuthTokens/refreshToken``.
        case signedIn(AuthTokens)
        /// The server wants a one-time code (TOTP or notify module).
        case needsMFACode
    }

    /// Failures surfaced to the sign-in screen.
    public enum LoginError: Error, Sendable, Equatable {
        /// Wrong username or password.
        case invalidCredentials
        /// Wrong or expired one-time code.
        case invalidCode
        /// The server answered with something this client doesn't understand.
        case unexpectedResponse(String)
        /// Transport or HTTP failure.
        case network(String)
        /// Something answered at the address, but not with a Home Assistant login flow (a 404, a web page, or JSON without a
        /// `flow_id`). DNS, TLS, timeout and offline failures stay ``network(_:)``.
        case notHomeAssistant
    }

    // MARK: - State

    private let server: HassServer
    private let session: URLSession
    private var flowID: String?

    /// Creates a login flow.
    /// - Parameters:
    ///   - server: The server to sign in to.
    ///   - session: URL session; tests inject a stubbed one.
    public init(server: HassServer, session: URLSession = .shared) {
        self.server = server
        self.session = session
    }

    // MARK: - Steps

    /// Starts a flow and submits the username and password.
    /// - Returns: ``Step/signedIn(_:)`` or ``Step/needsMFACode``.
    public func signIn(username: String, password: String) async throws -> Step {
        let start = try await postJSON("/auth/login_flow", startsFlow: true, body: [
            "client_id": HassServer.clientID,
            "handler": ["homeassistant", NSNull()] as [Any],
            "redirect_uri": HassServer.redirectURI,
        ])
        guard let id = start["flow_id"] as? String else { throw LoginError.notHomeAssistant }
        flowID = id
        let reply = try await postJSON("/auth/login_flow/\(id)", body: [
            "client_id": HassServer.clientID,
            "username": username,
            "password": password,
        ])
        return try await handle(reply, credentialError: .invalidCredentials)
    }

    /// Submits the one-time code after ``Step/needsMFACode``.
    public func submitMFACode(_ code: String) async throws -> Step {
        guard let id = flowID else { throw LoginError.unexpectedResponse("no active flow") }
        let reply = try await postJSON("/auth/login_flow/\(id)", body: [
            "client_id": HassServer.clientID,
            "code": code,
        ])
        return try await handle(reply, credentialError: .invalidCode)
    }

    // MARK: - Token endpoint

    /// Exchanges a refresh token for a new access token.
    public static func refresh(
        server: HassServer,
        refreshToken: String,
        session: URLSession = .shared
    ) async throws -> AuthTokens {
        let response = try await postForm(server: server, session: session, fields: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": HassServer.clientID,
        ])
        return AuthTokens(
            accessToken: response.access_token,
            expiresAt: Date().addingTimeInterval(response.expires_in),
            refreshToken: response.refresh_token ?? refreshToken
        )
    }

    /// Revokes a refresh token (sign out). Errors are ignored by callers; the Keychain is cleared regardless.
    public static func revoke(server: HassServer, refreshToken: String, session: URLSession = .shared) async {
        var request = URLRequest(url: server.url("/auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(["action": "revoke", "token": refreshToken])
        _ = try? await session.data(for: request)
    }

    // MARK: - Private

    private func handle(_ reply: [String: Any], credentialError: LoginError) async throws -> Step {
        switch reply["type"] as? String {
        case "create_entry":
            guard let code = reply["result"] as? String else {
                throw LoginError.unexpectedResponse("create_entry without result")
            }
            flowID = nil
            let response = try await Self.postForm(server: server, session: session, fields: [
                "grant_type": "authorization_code",
                "code": code,
                "client_id": HassServer.clientID,
            ])
            guard let refresh = response.refresh_token else {
                throw LoginError.unexpectedResponse("token response without refresh_token")
            }
            return .signedIn(AuthTokens(
                accessToken: response.access_token,
                expiresAt: Date().addingTimeInterval(response.expires_in),
                refreshToken: refresh
            ))
        case "form":
            if let errors = reply["errors"] as? [String: Any], !errors.isEmpty {
                throw credentialError
            }
            if reply["step_id"] as? String == "mfa" { return .needsMFACode }
            throw LoginError.unexpectedResponse("unexpected step \(reply["step_id"] ?? "nil")")
        case "abort":
            throw LoginError.unexpectedResponse("flow aborted: \(reply["reason"] ?? "unknown")")
        default:
            throw LoginError.unexpectedResponse("unknown flow type")
        }
    }

    /// - Parameter startsFlow: True for step 1, where an answer that is not a login flow means the address is not Home Assistant.
    private func postJSON(_ path: String, startsFlow: Bool = false, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: server.url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await Self.send(request, session: session)
        guard (200..<300).contains(response.statusCode) || response.statusCode == 400 else {
            if startsFlow, response.statusCode == 404 { throw LoginError.notHomeAssistant }
            throw LoginError.network("HTTP \(response.statusCode)")
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if startsFlow { throw LoginError.notHomeAssistant }
            throw LoginError.unexpectedResponse("non-object JSON")
        }
        return object
    }

    private static func postForm(
        server: HassServer,
        session: URLSession,
        fields: [String: String]
    ) async throws -> TokenResponse {
        var request = URLRequest(url: server.url("/auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(fields)
        let (data, response) = try await send(request, session: session)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 400 { throw LoginError.invalidCredentials }
            throw LoginError.network("HTTP \(response.statusCode)")
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw LoginError.unexpectedResponse("token response: \(error)")
        }
    }

    private static func send(_ request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LoginError.network("not HTTP") }
            return (data, http)
        } catch let error as LoginError {
            throw error
        } catch {
            throw LoginError.network(error.localizedDescription)
        }
    }

    static func formEncode(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }
}
