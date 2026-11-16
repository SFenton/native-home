import Foundation

// MARK: - Event

/// One reply of `fenton_home/ui_publication/subscribe`, judged off the main thread.
public enum ServerUIPublicationEvent: Sendable {
    /// The newest publication this build can read, already decoded and validated.
    public struct Published: Sendable {
        /// The integration's store epoch. A change invalidates revision ordering.
        public let epoch: String
        /// The integration's revision of the chosen entry (it may be an older one when the newest is incompatible).
        public let revision: Int
        /// The integration's change-detection hash of the envelope; the app's own identity check is the document hash.
        public let envelopeSha256: String
        /// The envelope as the compiler reads it, kept for the cache.
        public let bytes: Data
        /// The compiled publication.
        public let publication: ServerUICompositionPublication
    }

    /// A publication to show.
    case published(Published)
    /// Nothing the server holds is readable by this build.
    case incompatible(epoch: String, revision: Int, missing: [String])
    /// Nothing is published.
    case unpublished
    /// The reply was refused, malformed or failed validation; the last-good publication stays.
    case invalid(ServerUIStoreError)

    /// The one place a raw reply becomes an event. Runs on any queue; parses and compiles the envelope.
    ///
    /// - Parameter reply: The reply's JSON, or the failure HAKit reported for the subscription.
    public static func judge(_ reply: Result<Data, any Error>) -> ServerUIPublicationEvent {
        let data: Data
        switch reply {
        case .failure: return .invalid(.subscription)
        case let .success(value): data = value
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let state = object["state"] as? String else { return .invalid(.malformedEvent) }
        switch state {
        case "unpublished":
            return .unpublished
        case "incompatible":
            guard let epoch = epoch(object), let revision = revision(object),
                  let missing = object["missing"] as? [String], missing.count <= 512 else { return .invalid(.malformedEvent) }
            return .incompatible(epoch: epoch, revision: revision, missing: missing)
        case "published":
            guard let epoch = epoch(object), let revision = revision(object),
                  let hash = object["envelopeSha256"] as? String, isHex64(hash),
                  let envelope = object["envelope"] as? [String: Any],
                  JSONSerialization.isValidJSONObject(envelope),
                  let bytes = try? JSONSerialization.data(withJSONObject: envelope),
                  bytes.count <= ServerUICompositionJSON.maximumBytes else { return .invalid(.malformedEvent) }
            do {
                let publication = try ServerUICompositionPublication.decode(bytes)
                return .published(.init(epoch: epoch, revision: revision, envelopeSha256: hash, bytes: bytes, publication: publication))
            } catch let error as ServerUICompositionError {
                return .invalid(.composition(error))
            } catch { return .invalid(.malformedEvent) }
        default:
            return .invalid(.malformedEvent)
        }
    }

    private static func epoch(_ object: [String: Any]) -> String? {
        guard let value = object["epoch"] as? String, (1...128).contains(value.utf8.count) else { return nil }
        return value
    }

    private static func revision(_ object: [String: Any]) -> Int? {
        guard let number = object["revision"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let value = Int(exactly: number.int64Value), value >= 0, Double(value) == number.doubleValue else { return nil }
        return value
    }

    private static func isHex64(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }
}
