import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTestSupport
import Testing

@Suite @MainActor struct ServerUIPublicationSubscriptionTests {
    private typealias F = ServerUIPublicationFixtures

    private actor Inbox {
        var events: [String] = []
        func add(_ event: ServerUIPublicationEvent) {
            switch event {
            case let .published(value): events.append("published:\(value.revision)")
            case .unpublished: events.append("unpublished")
            case let .incompatible(_, revision, _): events.append("incompatible:\(revision)")
            case let .invalid(error): events.append("invalid:\(error)")
            }
        }
        func wait(for count: Int) async {
            while events.count < count { await Task.yield() }
        }
    }

    @Test func startSendsTheSupportedCapabilitiesOnceAndStopCancels() async {
        let transport = FakePublicationTransport()
        let subscription = ServerUIPublicationSubscription(transport: transport, capabilities: ["a@1", "b@1"]) { _ in }
        subscription.start()
        subscription.start()
        #expect(transport.subscriptions == 1)
        #expect(transport.capabilities == [["a@1", "b@1"]])
        #expect(subscription.isStarted)
        subscription.stop()
        #expect(!subscription.isStarted)
        subscription.restart()
        #expect(transport.subscriptions == 2)
        subscription.stop()
        await Task.yield()
        #expect(transport.cancels >= 2)
    }

    @Test func theDefaultCapabilitiesAreTheCompilersSupportedSet() {
        let transport = FakePublicationTransport()
        let subscription = ServerUIPublicationSubscription(transport: transport) { _ in }
        subscription.start()
        #expect(transport.capabilities == [ServerUICompositionPublication.supportedCapabilities])
        #expect(ServerUICompositionPublication.supportedCapabilities.count <= 512)
        #expect(ServerUICompositionPublication.supportedCapabilities.allSatisfy { $0.utf8.count <= 128 })
        subscription.stop()
    }

    @Test func repliesAreJudgedOffMainAndDeliveredInOrder() async throws {
        let transport = FakePublicationTransport()
        let inbox = Inbox()
        let subscription = ServerUIPublicationSubscription(transport: transport) { await inbox.add($0) }
        subscription.start()
        transport.send(.success(try F.reply(["state": "unpublished"])))
        await inbox.wait(for: 1)
        transport.send(.success(try F.published(revision: 3)))
        await inbox.wait(for: 2)
        transport.send(.failure(ServerUIStoreError.malformedEvent))
        await inbox.wait(for: 3)
        #expect(await inbox.events == ["unpublished", "published:3", "invalid:subscription"])
        subscription.stop()
    }

    @Test func aStoppedSubscriptionDeliversNothingMore() async throws {
        let transport = FakePublicationTransport()
        let inbox = Inbox()
        let subscription = ServerUIPublicationSubscription(transport: transport) { await inbox.add($0) }
        subscription.start()
        subscription.stop()
        transport.send(.success(try F.reply(["state": "unpublished"])))
        for _ in 0..<20 { await Task.yield() }
        #expect(await inbox.events.isEmpty)
    }

    @Test func theWebsocketTransportAcceptsOnlyAnObjectReply() throws {
        #expect(HassServerUIPublicationTransport.subscribeCommand == "fenton_home/ui_publication/subscribe")
        guard case let .success(data) = HassServerUIPublicationTransport.json(.dictionary(["state": "unpublished"])) else {
            Issue.record("an object is an event"); return
        }
        #expect(try JSONSerialization.jsonObject(with: data) as? [String: String] == ["state": "unpublished"])
        guard case .failure = HassServerUIPublicationTransport.json(.array([])) else {
            Issue.record("an array is not an event"); return
        }
    }

    @Test func theWebsocketSubscriptionSendsTheCapabilitiesWithRetryAndDeliversEachReply() throws {
        let mock = HAMockConnection()
        let snapshot = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "pub-snap-\(UUID()).json"))
        let connection = HassConnection(server: .example, store: EntityStore(), snapshotCache: snapshot, connection: mock)
        let received = Locked<[Result<Data, Error>]>([])
        let cancel = HassServerUIPublicationTransport(connection: connection)
            .subscribe(capabilities: ["sh.a@1"]) { result in received.withLock { $0.append(result) } }
        let subscription = try #require(mock.pendingSubscriptions.first)
        #expect(subscription.request.type == .webSocket("fenton_home/ui_publication/subscribe"))
        #expect(subscription.request.shouldRetry)
        #expect(subscription.request.retryDuration == nil)
        #expect(subscription.request.data["capabilities"] as? [String] == ["sh.a@1"])

        subscription.initiated(.success(.empty))
        subscription.handler(subscription.cancellable, HAData(value: ["state": "unpublished"]))
        subscription.initiated(.failure(.external(.init(code: "unknown_command", message: "no"))))
        #expect(received.withLock { $0.count } == 2)
        #expect(received.withLock { try? $0[0].get() } != nil)
        guard case .failure = received.withLock({ $0[1] }) else { Issue.record("the refusal did not reach the handler"); return }

        cancel()
        #expect(subscription.cancellable.wasCancelled)
    }
}
