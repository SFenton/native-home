import Foundation

/// What the service extension downloads and attaches to a notification (contract v1, rule 3).
public struct PushAttachmentSource: Equatable, Sendable {
    /// What the file is.
    public enum Kind: String, Sendable {
        case image, video, file
    }

    /// Where to fetch it.
    public var url: URL
    /// What it is.
    public var kind: Kind
    /// The request needs the Home Assistant token (the URL is on the signed-in server).
    public var needsAuthorization: Bool

    /// Creates a source.
    public init(url: URL, kind: Kind, needsAuthorization: Bool) {
        self.url = url
        self.kind = kind
        self.needsAuthorization = needsAuthorization
    }

    /// The attachment for a payload, in the order Home Assistant's companion app uses: a camera snapshot for
    /// `entity_id` when it is a camera, then `image`, `video`, and `attachment.url`.
    /// - Parameters:
    ///   - payload: The notification's block.
    ///   - server: The signed-in server; relative paths resolve against it.
    public static func resolve(_ payload: PushPayload, server: HassServer) -> PushAttachmentSource? {
        if let entity = payload.entityID, entity.hasPrefix("camera."),
           let escaped = entity.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            return PushAttachmentSource(url: server.url("/api/camera_proxy/\(escaped)"), kind: .image, needsAuthorization: true)
        }
        let candidates: [(String?, Kind)] = [(payload.image, .image), (payload.video, .video), (payload.attachmentURL, .file)]
        for case let (value?, kind) in candidates {
            if let source = source(value, kind: kind, server: server) { return source }
        }
        return nil
    }

    /// A source for one URL: absolute http(s), or a path on the server.
    static func source(_ value: String, kind: Kind, server: HassServer) -> PushAttachmentSource? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") {
            guard let url = URL(string: trimmed, relativeTo: server.baseURL)?.absoluteURL else { return nil }
            return PushAttachmentSource(url: url, kind: kind, needsAuthorization: true)
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        let sameServer = url.host?.lowercased() == server.baseURL.host?.lowercased()
        return PushAttachmentSource(url: url, kind: kind, needsAuthorization: sameServer)
    }

    /// The file extension for a downloaded attachment, from its MIME type and then its URL; the system reads the
    /// type from the extension.
    /// - Parameter mimeType: The response's MIME type.
    public func fileExtension(mimeType: String?) -> String {
        // `image/jpeg; charset=…` reads as `image/jpeg`.
        switch mimeType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/heic": return "heic"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "audio/mpeg": return "mp3"
        case "application/pdf": return "pdf"
        default:
            // `/api/camera_proxy/camera.<id>` has no file extension, only an entity id.
            let ext = url.pathExtension.lowercased()
            if Self.mediaExtensions.contains(ext) { return ext }
            return kind == .video ? "mp4" : "jpg"
        }
    }

    /// Extensions read from a URL when the response has no known MIME type.
    static let mediaExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "webp", "mp4", "mov", "m4v", "mp3", "m4a", "pdf"]

    /// The largest file the system attaches for each kind (UNNotificationAttachment limits).
    public var byteLimit: Int {
        switch kind {
        case .image: 10_000_000
        case .video: 50_000_000
        case .file: 5_000_000
        }
    }
}
