import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTestSupport
import Observation
import Testing

/// A feed that is driven by hand.
final class FakeFlowFeed: ServerUIFlowFeed, @unchecked Sendable {
    private let state = Locked<(subscriptions: [ServerUIFlow.Subscription], handler: (@Sendable (Result<JSONValue, Error>) -> Void)?, cancelled: Int)>(([], nil, 0))
    var subscriptions: [ServerUIFlow.Subscription] { state.withLock { $0.subscriptions } }
    var cancelled: Int { state.withLock { $0.cancelled } }
    func subscribe(_ subscription: ServerUIFlow.Subscription, handler: @escaping @Sendable (Result<JSONValue, Error>) -> Void) -> @Sendable () -> Void {
        state.withLock { $0.subscriptions.append(subscription); $0.handler = handler }
        return { [weak self] in self?.state.withLock { $0.cancelled += 1 } }
    }
    func send(_ result: Result<JSONValue, Error>) { state.withLock { $0.handler }?(result) }
}

/// The runtime of a Data Flow: a feed, a session and the connection feed over a mock HAKit connection.
@MainActor
struct ServerUIFlowSessionTests {
    // MARK: Flows

    private static let rowOutput = """
    {"kind": "rows", "max": 20, "row": {"id": {"type": "item", "path": ["id"]}, "title": {"type": "item", "path": ["title"]}}}
    """
    private static let rowSchema = """
    {"kind": "array", "of": {"kind": "object", "fields": {"id": {"shape": {"kind": "string"}}, "title": {"shape": {"kind": "string"}}}}}
    """

    private static func decode(_ json: String) throws -> ServerUIFlow {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let issues = ServerUICompositionShape.issues(of: value, against: ServerUICompositionShape.flowInputs)
        try #require(issues.isEmpty, "structure issues \(issues)")
        let decoded = ServerUIFlowDecoder.decode(value, at: "")
        try #require(decoded.issues.isEmpty, "decode issues \(decoded.issues)")
        return try #require(decoded.flow)
    }

    private static func todoFlow() throws -> ServerUIFlow {
        try decode("""
        {"title": "Chores", "parameters": [],
         "request": {"type": "ha-subscription", "kind": "todo-items", "entityId": {"type": "literal", "value": "todo.demo_chores"}},
         "steps": [{"id": "items", "op": "get", "path": ["items"]},
                   {"id": "shape", "op": "map", "fields": {"id": {"type": "item", "path": ["uid"]}, "title": {"type": "item", "path": ["summary"]}}}],
         "output": \(rowOutput), "schema": \(rowSchema)}
        """)
    }

    private static func lightsFlow() throws -> ServerUIFlow {
        try decode("""
        {"title": "Lights", "parameters": [],
         "request": {"type": "entities", "entityIds": [{"type": "literal", "value": "light.demo_den"}], "attributes": []},
         "steps": [{"id": "shape", "op": "map", "fields": {"id": {"type": "item", "path": ["entityId"]}, "title": {"type": "item", "path": ["state"]}}}],
         "output": \(rowOutput), "schema": \(rowSchema)}
        """)
    }

    private static func serviceFlow() throws -> ServerUIFlow {
        try decode("""
        {"title": "Lists", "parameters": [],
         "request": {"type": "service-response", "domain": "todo", "service": "get_items", "timeoutSeconds": 10,
                     "responseShape": {"kind": "array", "of": {"kind": "object", "fields": {"id": {"shape": {"kind": "string"}}, "title": {"shape": {"kind": "string"}}}}}},
         "steps": [], "output": \(rowOutput), "schema": \(rowSchema), "refresh": {"on": ["open", "manual"], "staleAfterSeconds": 300}}
        """)
    }

    private static func push(_ titles: [String]) -> JSONValue {
        .object(["items": .array(titles.enumerated().map { .object(["uid": .string("u\($0.offset)"), "summary": .string($0.element)]) })])
    }

    struct Boom: Error {}

    // MARK: Subscriptions

    @Test func aPushFillsTheCollectionAndTheNextPushReplacesIt() async throws {
        let feed = FakeFlowFeed()
        let collection = ServerUIRowCollection()
        let session = ServerUIFlowSession(flow: try Self.todoFlow(), collection: collection, host: .init(feed: feed))
        session.start()
        #expect(feed.subscriptions == [.todoItems(entityId: "todo.demo_chores")])
        #expect(collection.phase == .loading)

        feed.send(.success(Self.push(["Bins", "Dishes"])))
        #expect(await eventually { collection.rows.map(\.title) == ["Bins", "Dishes"] })
        #expect(collection.phase == .ready)

        feed.send(.success(Self.push(["Bins"])))
        #expect(await eventually { collection.rows.map(\.title) == ["Bins"] })
        #expect(session.publications == 2)
    }

    @Test func aFailureKeepsTheLastGoodRowsAndTheNextPushRecovers() async throws {
        let feed = FakeFlowFeed()
        let collection = ServerUIRowCollection()
        let session = ServerUIFlowSession(flow: try Self.todoFlow(), collection: collection, host: .init(feed: feed))
        session.start()
        feed.send(.failure(Boom()))
        #expect(await eventually { collection.phase == .failed })
        #expect(collection.rows.isEmpty)

        feed.send(.success(Self.push(["Bins"])))
        #expect(await eventually { collection.phase == .ready })
        feed.send(.failure(Boom()))
        #expect(await eventually { collection.phase == .stale })
        #expect(collection.rows.map(\.title) == ["Bins"])

        feed.send(.success(Self.push(["Bins", "Dishes"])))
        #expect(await eventually { collection.phase == .ready && collection.rows.count == 2 })
    }

    @Test func stoppingEndsTheFeedAndPublishesNothingMore() async throws {
        let feed = FakeFlowFeed()
        let collection = ServerUIRowCollection()
        let session = ServerUIFlowSession(flow: try Self.todoFlow(), collection: collection, host: .init(feed: feed))
        session.start()
        session.stop()
        #expect(feed.cancelled == 1)
        feed.send(.success(Self.push(["Bins"])))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(collection.rows.isEmpty)
        #expect(session.publications == 0)
    }

    @Test func aSubscriptionWithoutAFeedFails() async throws {
        let collection = ServerUIRowCollection()
        ServerUIFlowSession(flow: try Self.todoFlow(), collection: collection, host: .init()).start()
        #expect(collection.phase == .failed)
    }

    // MARK: Entities

    @Observable final class Light { var state = "on" }

    @Test func aChangeToAHeldEntityRunsTheFlowOnce() async throws {
        let light = Light()
        let collection = ServerUIRowCollection()
        let host = ServerUIFlowHost(held: { _ in .init(state: light.state) })
        let session = ServerUIFlowSession(flow: try Self.lightsFlow(), collection: collection, host: host)
        session.start()
        #expect(await eventually { collection.rows.map(\.title) == ["on"] })
        #expect(session.publications == 1)

        light.state = "off"
        #expect(await eventually { collection.rows.map(\.title) == ["off"] })
        #expect(session.publications == 2)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(session.publications == 2)
    }

    // MARK: Service responses

    @Test func aServiceFlowCallsOnOpenAndAgainOnRefreshAndKeepsRowsWhenTheCallFails() async throws {
        var answers: [Result<JSONValue, Error>] = [
            .success(.array([.object(["id": .string("a"), "title": .string("One")])])),
            .failure(Boom()),
            .success(.array([.object(["id": .string("a"), "title": .string("One")]), .object(["id": .string("b"), "title": .string("Two")])])),
        ]
        let collection = ServerUIRowCollection()
        let host = ServerUIFlowHost(call: { domain, service, _, _ in
            #expect(domain == "todo" && service == "get_items")
            return try answers.removeFirst().get()
        })
        let session = ServerUIFlowSession(flow: try Self.serviceFlow(), collection: collection, host: host)
        session.start()
        #expect(await eventually { collection.rows.count == 1 })

        await session.refresh()
        #expect(collection.phase == .stale)
        #expect(collection.rows.map(\.title) == ["One"])

        await session.refresh()
        #expect(collection.phase == .ready)
        #expect(collection.rows.map(\.title) == ["One", "Two"])
    }

    @Test func aFlowThatGivesNoRowsIsUnavailable() throws {
        let flow = try Self.decode("""
        {"title": "n", "parameters": [], "request": {"type": "none", "value": {"type": "literal", "value": 1}}, "steps": [],
         "output": {"kind": "scalar"}, "schema": {"kind": "number"}}
        """)
        let collection = ServerUIRowCollection()
        ServerUIFlowSession(flow: flow, collection: collection, host: .init()).start()
        #expect(collection.phase == .unavailable)
    }

    // MARK: A corpus document's own flow

    @Test func theUpcomingChoresFlowOfTheCorpusRunsThroughASession() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "ContractCorpus/accept/list-parts-row-action.json")
        let publication = try ServerUICompositionPublication.decode(Data(contentsOf: url))
        var found: ServerUIFlow?
        for case .pipeline("upcoming", let flow) in publication.document.dataSources { found = flow }
        let flow = try #require(found)
        let response: JSONValue = .object(["todo.demo_chores": .object(["items": .array([
            .object(["uid": "a", "summary": "Water", "status": "needs_action", "due": "2026-11-17"]),
        ])])])
        let collection = ServerUIRowCollection()
        let host = ServerUIFlowHost(call: { _, _, _, _ in response },
                                    environment: { (ServerUIClock(now: "2026-11-16T09:00:00", utcOffsetMinutes: 0),
                                                    ServerUIViewer(userId: "user-2", isAdmin: false, personEntityId: nil), nil) })
        let session = ServerUIFlowSession(flow: flow, collection: collection, host: host)
        session.start()
        #expect(await eventually { collection.phase != .loading })
        #expect(collection.rows.map(\.title) == ["Water"])
        #expect(collection.rows.first?.subtitle == "Due tomorrow")
    }

    // MARK: Parameter reads

    @Test func aParametersReadsAreWalkedForTheSnapshot() {
        let read = ServerUIOperand.read(sourceId: "s", path: ["a", "b"], as: .string)
        #expect(read.flowReads == [.init(sourceId: "s", path: ["a", "b"])])
        let nested = ServerUIOperand.format(pattern: "{x}", args: ["x": read], formats: [:])
        #expect(nested.flowReads.count == 1)
        #expect(ServerUIOperand.literal(.null).flowReads.isEmpty)
    }

    // MARK: The connection feed

    @Test func theConnectionFeedSubscribesWithRetryAndDeliversPushes() throws {
        let mock = HAMockConnection()
        let snapshot = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "snap-\(UUID()).json"))
        let connection = HassConnection(server: .example, store: EntityStore(), snapshotCache: snapshot, connection: mock)
        let received = Locked<[Result<JSONValue, Error>]>([])
        let cancel = HassFlowFeed(connection: connection).subscribe(.weatherForecast(entityId: "weather.demo_home", forecastType: .hourly)) { result in
            received.withLock { $0.append(result) }
        }
        let subscription = try #require(mock.pendingSubscriptions.first)
        #expect(subscription.request.type == .webSocket("weather/subscribe_forecast"))
        #expect(subscription.request.shouldRetry)
        #expect(subscription.request.retryDuration == nil)
        #expect(subscription.request.data["entity_id"] as? String == "weather.demo_home")
        #expect(subscription.request.data["forecast_type"] as? String == "hourly")

        subscription.handler(subscription.cancellable, HAData(value: ["type": "hourly", "forecast": []]))
        subscription.initiated(.failure(.external(.init(code: "unknown", message: "no"))))
        #expect(received.withLock { $0.count } == 2)
        #expect(received.withLock { try? $0[0].get()["type"] } == .string("hourly"))
        cancel()
        #expect(subscription.cancellable.wasCancelled)
    }

    @Test func theTodoSubscriptionUsesTheItemCommand() {
        #expect(ServerUIFlowSubscriptionCommand.command(.todoItems(entityId: "todo.demo_chores")) == "todo/item/subscribe")
        #expect(ServerUIFlowSubscriptionCommand.data(.todoItems(entityId: "todo.demo_chores")) == ["entity_id": "todo.demo_chores"])
    }

    @Test func aResubscribeAfterAReconnectKeepsTheLastGoodRows() async throws {
        let mock = HAMockConnection()
        let snapshot = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "snap-\(UUID()).json"))
        let connection = HassConnection(server: .example, store: EntityStore(), snapshotCache: snapshot, connection: mock)
        let collection = ServerUIRowCollection()
        let session = ServerUIFlowSession(flow: try Self.todoFlow(), collection: collection,
                                          host: .init(feed: HassFlowFeed(connection: connection)))
        session.start()
        let subscription = try #require(mock.pendingSubscriptions.first)
        subscription.initiated(.success(.empty))
        subscription.handler(subscription.cancellable, HAData(value: ["items": [["uid": "1", "summary": "Bins", "status": "needs_action"]]]))
        #expect(await eventually { collection.rows.map(\.title) == ["Bins"] })

        // The socket drops: the rows stay, and the one subscription HAKit sends again answers with the new state.
        subscription.initiated(.failure(.internal(debugDescription: "socket closed")))
        #expect(await eventually { collection.phase == .stale })
        #expect(collection.rows.map(\.title) == ["Bins"])
        #expect(mock.pendingSubscriptions.count == 1)
        subscription.handler(subscription.cancellable, HAData(value: ["items": [["uid": "1", "summary": "Bins"], ["uid": "2", "summary": "Dishes"]]]))
        #expect(await eventually { collection.phase == .ready && collection.rows.count == 2 })
    }
}
