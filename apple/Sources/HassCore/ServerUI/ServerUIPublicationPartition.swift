import CryptoKit
import Foundation

// MARK: - Partition

/// The Home Assistant server one publication cache belongs to.
///
/// The cache is keyed by the server origin and, inside its record, by the signed-in Home Assistant user id
/// (``ServerUIPublicationStore/bind(userID:)``). The origin alone names the directory so a cold launch can restore before the
/// socket has said who is signed in; a record written for another user is discarded once the user is known.
public struct ServerUIPublicationPartition: Sendable, Equatable {
    /// `scheme://host[:port]`, lower-cased.
    public let origin: String

    /// Creates a partition for a server, or throws ``ServerUIStoreError/invalidPartition`` for an origin without an http(s) scheme or host.
    public init(server: HassServer) throws {
        guard var parts = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = parts.percentEncodedHost?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil
        else { throw ServerUIStoreError.invalidPartition }
        parts.scheme = scheme
        parts.percentEncodedHost = host
        parts.percentEncodedPath = ""
        parts.query = nil
        parts.fragment = nil
        guard let text = parts.string else { throw ServerUIStoreError.invalidPartition }
        origin = text
    }

    /// One opaque subdirectory for this origin, holding the cache record, staged assets and renders.
    public func storageDirectory(in privateRoot: URL) -> URL {
        privateRoot.appendingPathComponent(digest, isDirectory: true)
    }

    /// The hex digest naming this partition's files.
    var digest: String {
        SHA256.hash(data: Data("\(origin.utf8.count):\(origin)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `value` is a plausible Home Assistant user id.
    static func isUserID(_ value: String) -> Bool {
        (1...128).contains(value.utf8.count) && value.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5a) || ($0 >= 0x61 && $0 <= 0x7a) || $0 == 0x2d || $0 == 0x5f
        }
    }
}
