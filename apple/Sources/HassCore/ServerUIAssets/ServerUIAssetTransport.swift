import Foundation
import os

// MARK: - Authenticated asset transport

/// Sanitized staging failures; no server address, credential, or response body is exposed.
public enum ServerUIAssetError: Error, Equatable, Sendable {
    case assetOrigin
    case assetIntegrity
    case assetBudget
    case credentialUnavailable
    case invalidCredential
    case redirectRejected
    case unexpectedResponse
    /// The server has no asset with this hash (404).
    case missing
    case timedOut
    case network
    case storage
    case busy
}

/// Where staged assets come from. Production uses ``ServerUIAssetTransport``; a debug preview may read local files.
public protocol ServerUIAssetFetching: Sendable {
    /// Fetches one bounded response. The caller must still verify the returned bytes.
    func download(_ asset: ServerUICompositionDocument.Asset) async throws -> Data
}

/// Downloads content-addressed assets from the Home Assistant integration (`GET /api/fenton_home/ui_assets/{sha256}`).
///
/// The request carries the connection's current access token and goes only to the signed-in server. Each asset is fetched once:
/// the stager asks only for hashes it does not already hold, so there is no stored copy to revalidate and a conditional request
/// would have nothing to match; a `304` is therefore refused rather than treated as bytes. An injected session is a trusted test seam.
public struct ServerUIAssetTransport: ServerUIAssetFetching {
    /// The route for one asset.
    public static func path(for sha256: String) -> String { "/api/fenton_home/ui_assets/\(sha256)" }

    private let server: HassServer
    private let tokenProvider: @Sendable () async throws -> String
    private let session: URLSession

    /// Creates a transport that fetches content-addressed assets from `server`.
    /// - Parameters:
    ///   - server: The signed-in Home Assistant server.
    ///   - tokenProvider: The current access token, normally `TokenManager.validAccessToken()`.
    ///   - session: A test seam; the default has no cache, cookies or stored credentials.
    public init(server: HassServer, tokenProvider: @escaping @Sendable () async throws -> String, session: URLSession? = nil) {
        self.server = server
        self.tokenProvider = tokenProvider
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Downloads the asset bytes.
    public func download(_ asset: ServerUICompositionDocument.Asset) async throws -> Data {
        try Task.checkCancellation()
        guard ServerUICompositionShape.matches(asset.sha256, "^[0-9a-f]{64}$") else { throw ServerUIAssetError.assetOrigin }
        let url = server.url(Self.path(for: asset.sha256))

        let token: String
        do { token = try await tokenProvider() }
        catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw ServerUIAssetError.credentialUnavailable
        }
        try Task.checkCancellation()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~+/")
        let unpadded = token.dropLast(token.reversed().prefix(while: { $0 == "=" }).count)
        guard !unpadded.isEmpty, unpadded.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ServerUIAssetError.invalidCredential
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(asset.mimeType.rawValue, forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await AssetDownloadOperation(expected: asset.byteLength, mime: asset.mimeType).run(request, session: session)
    }
}

// MARK: - Bounded streaming

private final class AssetDownloadOperation: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var completed = false
        var continuation: CheckedContinuation<Data, any Error>?
        var task: URLSessionDataTask?
        var timer: DispatchSourceTimer?
        var receivedResponse = false
        var bytes = Data()
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let expected: Int
    private let mime: ServerUICompositionDocument.MIMEType

    init(expected: Int, mime: ServerUICompositionDocument.MIMEType) {
        self.expected = expected
        self.mime = mime
    }

    func run(_ request: URLRequest, session: URLSession) async throws -> Data {
        guard (1...ServerUIAssetStager.maximumAssetBytes).contains(expected) else {
            throw ServerUIAssetError.assetIntegrity
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                task.delegate = self
                let timer = DispatchSource.makeTimerSource()
                timer.setEventHandler { [weak self] in self?.finish(.failure(ServerUIAssetError.timedOut)) }
                timer.schedule(deadline: .now() + 15)
                let start = state.withLock {
                    guard !$0.completed else { return false }
                    $0.continuation = continuation
                    $0.task = task
                    $0.timer = timer
                    return true
                }
                timer.resume()
                if start { task.resume() }
                else {
                    timer.cancel()
                    task.cancel()
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: { self.finish(.failure(CancellationError())) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(ServerUIAssetError.redirectRejected))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            finish(.failure(ServerUIAssetError.unexpectedResponse)); completionHandler(.cancel); return
        }
        guard http.statusCode != 304, !(300..<400).contains(http.statusCode) else {
            finish(.failure(http.statusCode == 304 ? ServerUIAssetError.unexpectedResponse : .redirectRejected))
            completionHandler(.cancel); return
        }
        guard http.statusCode != 404 else {
            finish(.failure(ServerUIAssetError.missing)); completionHandler(.cancel); return
        }
        guard http.statusCode == 200,
              http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces).lowercased() == mime.rawValue,
              http.value(forHTTPHeaderField: "Content-Encoding").map({ $0.lowercased() == "identity" }) ?? true
        else {
            finish(.failure(ServerUIAssetError.unexpectedResponse)); completionHandler(.cancel); return
        }
        if let length = http.value(forHTTPHeaderField: "Content-Length") {
            guard !length.isEmpty, length.utf8.allSatisfy({ (48...57).contains($0) }),
                  Int(length) == expected else {
                finish(.failure(ServerUIAssetError.assetIntegrity)); completionHandler(.cancel); return
            }
        }
        guard response.expectedContentLength < 0 || response.expectedContentLength == expected else {
            finish(.failure(ServerUIAssetError.assetIntegrity)); completionHandler(.cancel); return
        }
        let active = state.withLock {
            guard !$0.completed else { return false }
            $0.receivedResponse = true
            return true
        }
        completionHandler(active ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let oversized = state.withLock {
            guard !$0.completed else { return false }
            guard data.count <= expected - $0.bytes.count else { return true }
            $0.bytes.append(data)
            return false
        }
        if oversized { finish(.failure(ServerUIAssetError.assetIntegrity)) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    willCacheResponse: CachedURLResponse,
                    completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            finish(.failure((error as? URLError)?.code == .timedOut ? ServerUIAssetError.timedOut : .network))
            return
        }
        let result = state.withLock { ($0.receivedResponse, $0.bytes) }
        guard result.0, result.1.count == expected else {
            finish(.failure(ServerUIAssetError.assetIntegrity)); return
        }
        finish(.success(result.1))
    }

    private func finish(_ result: Result<Data, any Error>) {
        let pending = state.withLock { state -> (CheckedContinuation<Data, any Error>?, URLSessionDataTask?, DispatchSourceTimer?) in
            guard !state.completed else { return (nil, nil, nil) }
            state.completed = true
            let result = (state.continuation, state.task, state.timer)
            state.continuation = nil
            state.task = nil
            state.timer = nil
            state.bytes = Data()
            return result
        }
        pending.2?.cancel()
        pending.1?.cancel()
        pending.0?.resume(with: result)
    }
}
