import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTestSupport
import Testing

/// Records each service call and answers with the next queued response.
@MainActor
final class RecordingResponder: HassServiceResponding {
    struct Call { var domain: String; var service: String; var data: [String: any Sendable] }
    private(set) var calls: [Call] = []
    var responses: [Result<JSONValue, Error>] = []

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append(Call(domain: domain, service: service, data: data))
    }

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        calls.append(Call(domain: domain, service: service, data: data))
        return try responses.isEmpty ? .null : responses.removeFirst().get()
    }
}

@MainActor
@Suite(.demoHouse)
struct RecipeServiceTests {
    @Test func recommendationsAndBrowseSendTheWebBodies() async throws {
        let responder = RecordingResponder()
        responder.responses = [
            .success(json(#"{"items": [{"id": 1, "title": "A"}]}"#)),
            .success(json(#"{"items": [{"id": 2, "title": "B"}], "next_cursor": "c2"}"#)),
        ]
        let service = EverShelfRecipeService(caller: responder)

        #expect(try await service.recommendations(limit: 40).map(\.id) == [1])
        let criteria = RecipeBrowseCriteria(query: "  lemon   chicken ", sort: .expiry, availabilityWeight: 62.5, expiryWeight: 140, minimumCoverage: -5, expiringWithinDays: 3)
        let page = try await service.browse(criteria, cursor: "c1")
        #expect(page.items.map(\.id) == [2])
        #expect(page.nextCursor == "c2")

        #expect(responder.calls.map(\.service) == ["recipe_query", "recipe_query"])
        #expect(responder.calls.allSatisfy { $0.domain == "evershelf" })
        #expect(responder.calls[0].data["kind"] as? String == "recommendations")
        #expect(responder.calls[0].data["limit"] as? Int == 40)
        let body = responder.calls[1].data
        #expect(body["kind"] as? String == "browse")
        #expect(body["q"] as? String == "lemon chicken")
        #expect(body["sort"] as? String == "expiry")
        #expect(body["availability_weight"] as? Double == 62.5)
        #expect(body["expiry_weight"] as? Int == 100)
        #expect(body["minimum_coverage"] as? Int == 0)
        #expect(body["limit"] as? Int == 50)
        #expect(body["expiring_within_days"] as? Int == 3)
        #expect(body["cursor"] as? String == "c1")
    }

    @Test func browseBodyOmitsOptionalKeys() {
        let body = RecipeServiceData.browse(RecipeBrowseCriteria(), cursor: "")
        #expect(body["cursor"] == nil)
        #expect(body["expiring_within_days"] == nil)
        #expect(RecipeServiceData.recommendations(limit: 0).count == 1)
        #expect(RecipeServiceData.detail(recipeId: -4)["recipe_id"] as? Int == 1)
    }

    @Test func hydrationStartsThenPolls() async throws {
        let responder = RecordingResponder()
        responder.responses = [
            .success(json(#"{"search_id": "s1", "status": "running", "next_poll_ms": 800}"#)),
            .success(json(#"{"search_id": "s1", "status": "complete", "new_items": [{"id": 5, "title": "E"}]}"#)),
        ]
        let service = EverShelfRecipeService(caller: responder)
        let started = try await service.hydrate(RecipeBrowseCriteria(query: "taco"), searchId: nil)
        #expect(started.searchId == "s1")
        let polled = try await service.hydrate(RecipeBrowseCriteria(query: "taco"), searchId: "s1")
        #expect(polled.isComplete)
        #expect(polled.newItems.map(\.id) == [5])
        #expect(responder.calls.map(\.service) == ["recipe_hydration", "recipe_hydration"])
        #expect(responder.calls[0].data["query"] as? String == "taco")
        #expect(responder.calls[1].data["search_id"] as? String == "s1")
        #expect(responder.calls[1].data["query"] == nil)
    }

    @Test func detailThrowsTheServerFailure() async throws {
        let responder = RecordingResponder()
        responder.responses = [
            .success(json(RecipeParsingTests.detailJSON)),
            .success(json(#"{"success": false, "error_kind": "unsupported", "message": "Upgrade"}"#)),
        ]
        let service = EverShelfRecipeService(caller: responder)
        #expect(try await service.detail(recipeId: 7).title == "Roast Chicken")
        #expect(responder.calls[0].data["recipe_id"] as? Int == 7)
        await #expect(throws: RecipeServiceFailure(unsupported: true, message: "Upgrade")) { try await service.detail(recipeId: 7) }
    }

    @Test func groceryAddSendsValidSelections() async throws {
        let responder = RecordingResponder()
        responder.responses = [.success(json(#"{"success": true, "summary": {"added": 1}}"#))]
        let service = EverShelfRecipeService(caller: responder)
        let rows: [RecipeDetail.Ingredient] = [
            .init(key: "ri:0:0123456789abcdef", position: 0, name: "a"),
            .init(key: "bogus", position: 1, name: "b"),
        ]
        let result = try await service.addToGroceries(recipeId: 9, ingredients: rows, idempotencyKey: String(repeating: "k", count: 200))
        #expect(result.backend.added == 1)
        let body = responder.calls[0].data
        #expect(responder.calls[0].service == "recipe_grocery_add")
        #expect(body["recipe_id"] as? Int == 9)
        #expect(body["todo_entity_id"] as? String == "todo.demo_todo_2")
        #expect((body["idempotency_key"] as? String)?.count == 128)
        let selections = try #require(body["selections"] as? [[String: any Sendable]])
        #expect(selections.count == 1)
        #expect(selections.first?["key"] as? String == "ri:0:0123456789abcdef")
        #expect(selections.first?["position"] as? Int == 0)
    }

    @Test func transportErrorsPropagate() async {
        struct Offline: Error {}
        let responder = RecordingResponder()
        responder.responses = [.failure(Offline())]
        let service = EverShelfRecipeService(caller: responder)
        await #expect(throws: Offline.self) { try await service.recommendations(limit: 4) }
    }

    @Test func idempotencyKeysAreSafeAndBounded() {
        let key = RecipeServiceData.idempotencyKey(recipeId: 12, now: Date(timeIntervalSince1970: 1_700_000_000), uuid: UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!)
        #expect(key == "native-recipe:12:\(String(1_700_000_000_000, radix: 36)):00000000-0000-0000-0000-0000000000ab")
        #expect(RecipeServiceData.idempotencyKey(recipeId: 0).hasPrefix("native-recipe:1:"))
    }

    // MARK: - Transport

    private func makeConnection() -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "recipes-\(UUID()).json"))
        return (HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock), mock)
    }

    private func pendingRequest(_ mock: HAMockConnection) async throws -> HAMockConnection.PendingRequest {
        for _ in 0..<1_000 where mock.pendingRequests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return try #require(mock.pendingRequests.first)
    }

    @Test func callServiceWithResponseResultsUnwrapForRecipes() async throws {
        let (connection, mock) = makeConnection()
        async let value = connection.callServiceWithResponse("evershelf", "recipe_query", data: ["kind": "recommendations"])
        let request = try await pendingRequest(mock)
        #expect(request.request.type == .webSocket("call_service"))
        #expect(request.request.data["domain"] as? String == "evershelf")
        #expect(request.request.data["service"] as? String == "recipe_query")
        #expect(request.request.data["return_response"] as? Bool == true)
        #expect((request.request.data["service_data"] as? [String: Any])?["kind"] as? String == "recommendations")
        request.completion(.success(HAData(value: ["context": ["id": "x"], "response": ["items": []]])))
        // The connection returns the whole result; the recipe parsers unwrap `response`.
        #expect(RecipeParsing.payload(try await value) == .object(["items": .array([])]))
    }

    @Test func callServiceWithResponseHandlesBareAndFailedResults() async throws {
        let (connection, mock) = makeConnection()
        let bare = Task { try await connection.callServiceWithResponse("evershelf", "recipe_detail", data: [:]) }
        let first = try await pendingRequest(mock)
        first.completion(.success(.empty))
        #expect(try await bare.value == .null)

        mock.pendingRequests.removeAll()
        let failed = Task { try await connection.callServiceWithResponse("evershelf", "recipe_detail", data: [:]) }
        let second = try await pendingRequest(mock)
        second.completion(.failure(.internal(debugDescription: "offline")))
        await #expect(throws: HAError.self) { try await failed.value }
    }
}
