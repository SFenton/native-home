import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTestSupport
import Testing

/// ``HassHouseConfigTransport`` over a mock HAKit connection, and the store end to end on top of it.
@MainActor
struct HouseConfigTransportTests {
    let mock = HAMockConnection()
    let cacheURL = FileManager.default.temporaryDirectory.appending(path: "house-transport-\(UUID()).json")

    private func makeConnection() -> HassConnection {
        let snapshot = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "snap-\(UUID()).json"))
        return HassConnection(server: .example, store: EntityStore(), snapshotCache: snapshot, connection: mock)
    }

    /// The document as the dictionary HAKit hands over.
    private func replyObject(_ config: HouseConfig = DemoHouse.config, hash: String = "h1") throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: HouseReply.document(config, hash: hash)) as? [String: Any])
    }

    // MARK: - Replies

    @Test func aReplyThatIsNotAnObjectFails() throws {
        for data in [HAData.empty, .array([]), .primitive("x")] {
            guard case let .failure(error) = HassHouseConfigTransport.json(data) else {
                Issue.record("accepted a non-object reply")
                continue
            }
            #expect(error as? HouseConfig.DecodeError == .malformed("reply is not an object"))
        }
    }

    // MARK: - Subscribe

    @Test func subscribeUsesTheSubscribeCommandWithRetryAndDeliversEachMessage() throws {
        let transport = HassHouseConfigTransport(connection: makeConnection())
        let received = Locked<[Result<Data, Error>]>([])
        let cancel = transport.subscribe { result in received.withLock { $0.append(result) } }
        let subscription = try #require(mock.pendingSubscriptions.first)
        #expect(subscription.request.type == .webSocket("fenton_home/house_config/subscribe"))
        #expect(subscription.request.shouldRetry)
        #expect(subscription.request.retryDuration == nil)

        subscription.initiated(.success(.empty))
        subscription.handler(subscription.cancellable, HAData(value: try replyObject()))
        subscription.initiated(.failure(.external(.init(code: "unknown_command", message: "no"))))
        #expect(received.withLock { $0.count } == 2)
        #expect(received.withLock { try? $0[0].get() } != nil)
        if case let .failure(error) = received.withLock({ $0[1] }) {
            #expect(HouseConfigStore.isUnknownCommand(error))
        } else {
            Issue.record("the refusal did not reach the handler")
        }

        cancel()
        #expect(subscription.cancellable.wasCancelled)
    }

    // MARK: - End to end

    private func makeStore(_ transport: HassHouseConfigTransport) -> HouseConfigStore {
        HouseConfigStore(server: .example, transport: transport, cache: HouseConfigCache(fileURL: cacheURL))
    }

    private func pendingSubscription() async throws -> HAMockConnection.PendingSubscription {
        for _ in 0..<1_000 where mock.pendingSubscriptions.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return try #require(mock.pendingSubscriptions.first)
    }

    @Test func theStoreFollowsTheMockConnectionAndSendsNoOneShotRequest() async throws {
        let store = makeStore(HassHouseConfigTransport(connection: makeConnection()))
        store.start()
        let subscription = try await pendingSubscription()
        subscription.initiated(.success(.empty))
        subscription.handler(subscription.cancellable, HAData(value: try replyObject(hash: "first")))
        #expect(await eventually { store.hash == "first" })

        subscription.handler(subscription.cancellable, HAData(value: try replyObject(HouseReply.changedHouse(), hash: "second")))
        #expect(await eventually { store.hash == "second" })
        #expect(store.current == HouseReply.changedHouse())
        #expect(mock.pendingRequests.isEmpty, "the subscription is the only request: nothing a socket reset could drop")

        store.clear()
        #expect(subscription.cancellable.wasCancelled)
        #expect(store.current == nil)
    }

    @Test func aSocketResetBeforeTheFirstReplyHangsNothingAndTheResentSubscriptionDelivers() async throws {
        let store = makeStore(HassHouseConfigTransport(connection: makeConnection()))
        store.start()
        let subscription = try await pendingSubscription()
        // The socket drops before the server answers, then comes back; HAKit resends the subscription (initiated again).
        mock.setState(.disconnected(reason: .disconnected), waitForQueue: false)
        mock.setState(.ready(version: "1.0-mock"), waitForQueue: false)
        #expect(store.status == .loading && store.current == nil)
        subscription.initiated(.success(.empty))
        subscription.handler(subscription.cancellable, HAData(value: try replyObject(hash: "after")))
        #expect(await eventually { store.hash == "after" })
        #expect(store.status == .ready)
        #expect(mock.pendingSubscriptions.count == 1)
    }

    @Test func anOlderServerRefusesTheSubscriptionOverTheMock() async throws {
        let store = makeStore(HassHouseConfigTransport(connection: makeConnection()))
        store.start()
        let subscription = try await pendingSubscription()
        subscription.initiated(.failure(.external(.init(code: "unknown_command", message: "Unknown command."))))
        #expect(await eventually { store.status == .integrationMissing })
        #expect(store.current == nil)
    }
}

/// A small lock-protected box for values written from HAKit's callback queue.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T { lock.withLock { body(&value) } }
}
