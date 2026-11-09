import Foundation

/// Files reports through the Fenton Home Feedback integration (`SFenton/ha-fenton-feedback`), which holds the
/// GitHub token, so the app never does: the same split as FestivalNativeApps' app and service.
///
/// Calls, with the app's Home Assistant access token: `GET /api/fenton_feedback/status`, `POST
/// /api/fenton_feedback/media` (one raw file per request) and `POST /api/fenton_feedback/report` (JSON). Like the
/// admin to-do upload, these are plain REST requests, not state: entity reads stay on the websocket.
public struct HomeAssistantFeedbackClient: FeedbackFiling {
    private let server: HassServer
    private let accessToken: @Sendable () async throws -> String
    private let transport: any FeedbackHTTPTransport

    /// Creates a client.
    /// - Parameters:
    ///   - server: The signed-in Home Assistant.
    ///   - accessToken: A valid access token (``TokenManager/validAccessToken()``).
    ///   - transport: The HTTP seam (tests use a stub).
    public init(server: HassServer, accessToken: @escaping @Sendable () async throws -> String,
                transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport()) {
        self.server = server
        self.accessToken = accessToken
        self.transport = transport
    }

    static let statusPath = "/api/fenton_feedback/status"
    static let mediaPath = "/api/fenton_feedback/media"
    static let reportPath = "/api/fenton_feedback/report"

    public func isAvailable() async throws -> Bool {
        let (data, response) = try await send(try await request("GET", Self.statusPath))
        if response.statusCode == 404 { return false }
        guard (200..<300).contains(response.statusCode) else { throw error(response, data) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["available"] as? Bool ?? false
    }

    public func upload(_ attachment: FeedbackAttachment) async throws -> URL {
        guard let body = try? Data(contentsOf: attachment.fileURL) else {
            throw FeedbackFilingError.attachmentRejected(attachment.filename)
        }
        var request = try await request("POST", Self.mediaPath, query: [
            URLQueryItem(name: "name", value: attachment.filename),
            URLQueryItem(name: "content_type", value: attachment.mimeType),
        ])
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw error(response, data, attachment: attachment.filename) }
        guard let text = object(data)?["url"] as? String, let url = URL(string: text), url.scheme == "https" else {
            throw FeedbackFilingError.unexpectedResponse
        }
        return url
    }

    public func submit(_ report: FeedbackReport) async throws -> FiledIssue {
        var request = try await request("POST", Self.reportPath)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(report)
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw error(response, data) }
        guard let json = object(data), let number = json["number"] as? Int,
              let text = json["url"] as? String, let url = URL(string: text) else {
            throw FeedbackFilingError.unexpectedResponse
        }
        return FiledIssue(number: number, url: url)
    }

    // MARK: - HTTP

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        let token: String
        do {
            token = try await accessToken()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FeedbackFilingError.signedOut
        }
        var components = URLComponents(url: server.url(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as FeedbackFilingError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FeedbackFilingError.network
        }
    }

    private func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func error(_ response: HTTPURLResponse, _ data: Data, attachment: String? = nil) -> FeedbackFilingError {
        FeedbackFilingError.forResponse(status: response.statusCode, code: object(data)?["code"] as? String, attachment: attachment)
    }
}
