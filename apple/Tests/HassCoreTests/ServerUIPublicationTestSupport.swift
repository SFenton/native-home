import Foundation
import Testing
@testable import HassCore

// MARK: - Shared fixtures

/// Builds the replies the integration sends and the fakes the publication tests share.
enum ServerUIPublicationFixtures {
    static let server = HassServer(baseURL: URL(string: "https://home.example")!)
    static let sha = String(repeating: "b", count: 64)

    static func envelope(name: String? = nil) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("ServerUICompositionFixture.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        if let name {
            var document = try #require(object["document"] as? [String: Any])
            document["name"] = name
            object["document"] = document
        }
        return object
    }

    /// A `published` reply.
    static func published(epoch: String = "epoch-1", revision: Int, name: String? = nil, hash: String? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "state": "published", "epoch": epoch, "revision": revision,
            "envelopeSha256": hash ?? String(format: "%064x", revision &* 31 &+ (name?.count ?? 0)),
            "envelope": try envelope(name: name),
        ] as [String: Any])
    }

    static func reply(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    /// A judged `published` event.
    static func event(epoch: String = "epoch-1", revision: Int, name: String? = nil, hash: String? = nil) throws -> ServerUIPublicationEvent {
        ServerUIPublicationEvent.judge(.success(try published(epoch: epoch, revision: revision, name: name, hash: hash)))
    }

    static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("serverui-publication-\(UUID().uuidString)", isDirectory: true)
    }
}

/// A transport that records its subscription and lets a test push replies.
@MainActor
final class FakePublicationTransport: ServerUIPublicationTransport {
    private(set) var capabilities: [[String]] = []
    private(set) var cancels = 0
    private var handlers: [@Sendable (Result<Data, any Error>) -> Void] = []

    func subscribe(capabilities: [String],
                   handler: @escaping @Sendable (Result<Data, any Error>) -> Void) -> @Sendable () -> Void {
        self.capabilities.append(capabilities)
        handlers.append(handler)
        return { [weak self] in Task { @MainActor in self?.cancels += 1 } }
    }

    var subscriptions: Int { capabilities.count }

    func send(_ reply: Result<Data, any Error>) { handlers.last?(reply) }
}
