import Foundation

/// Downloads a notification attachment to a file the system can attach.
public struct PushAttachmentLoader: Sendable {
    private let transport: any FeedbackHTTPTransport
    private let directory: URL
    private let trace: PushTrace

    /// Creates a loader.
    /// - Parameters:
    ///   - transport: The HTTP seam.
    ///   - directory: Where downloaded files go.
    ///   - trace: Where each outcome is noted (debug builds).
    public init(transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport(),
                directory: URL = FileManager.default.temporaryDirectory, trace: PushTrace = PushTrace(directory: nil)) {
        self.transport = transport
        self.directory = directory
        self.trace = trace
    }

    /// Fetches a source; nil on any failure, an empty body, or a file over the kind's limit.
    /// - Parameters:
    ///   - source: What to fetch.
    ///   - accessToken: The Home Assistant token, for sources that need it.
    public func load(_ source: PushAttachmentSource, accessToken: String?) async -> URL? {
        var request = URLRequest(url: source.url, timeoutInterval: 20)
        if source.needsAuthorization {
            guard let accessToken else {
                trace.record("attachment skipped: no token for \(source.url.path)")
                return nil
            }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        let data: Data, response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            trace.record("attachment failed: \(source.url.path) \(type(of: error)) \((error as NSError).code)")
            return nil
        }
        trace.record("attachment HTTP \(response.statusCode) \(data.count) bytes \(source.url.path)")
        guard (200..<300).contains(response.statusCode), !data.isEmpty, data.count <= source.byteLimit else { return nil }
        let file = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.fileExtension(mimeType: response.mimeType ?? response.value(forHTTPHeaderField: "Content-Type")))
        guard (try? data.write(to: file)) != nil else { return nil }
        return file
    }
}
