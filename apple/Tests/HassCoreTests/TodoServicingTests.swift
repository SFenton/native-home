import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTestSupport
import Testing

@MainActor
@Suite(.demoHouse)
struct TodoServicingTests {
    private func makeConnection() -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "todo-\(UUID()).json"))
        return (HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock), mock)
    }

    private func pendingRequest(_ mock: HAMockConnection) async throws -> HAMockConnection.PendingRequest {
        for _ in 0..<1_000 where mock.pendingRequests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return try #require(mock.pendingRequests.first)
    }

    @Test func listsItemsOverTheWebsocket() async throws {
        let (connection, mock) = makeConnection()
        async let items = connection.todoItems(entityId: "todo.demo_todo_2")
        let request = try await pendingRequest(mock)
        #expect(request.request.type == .webSocket("todo/item/list"))
        #expect(request.request.data["entity_id"] as? String == "todo.demo_todo_2")
        request.completion(.success(HAData(value: ["items": [["uid": "1", "summary": "Milk", "status": "needs_action"]]])))
        #expect(try await items == [TodoItem(uid: "1", summary: "Milk")])
    }

    @Test func listWithoutItemsIsAnError() async throws {
        let (connection, mock) = makeConnection()
        let items = Task { try await connection.todoItems(entityId: "todo.demo_x") }
        try await pendingRequest(mock).completion(.success(HAData(value: ["other": 1])))
        await #expect(throws: HassConnection.UnexpectedResponse.self) { _ = try await items.value }
    }

    @Test func serviceResponsesComeBackAsJSON() async throws {
        let (connection, mock) = makeConnection()
        async let response = connection.callServiceForResponse("donetick", "get_task", data: ["task_id": 4])
        let request = try await pendingRequest(mock)
        #expect(request.request.type == .webSocket("call_service"))
        #expect(request.request.data["return_response"] as? Bool == true)
        #expect(request.request.data["domain"] as? String == "donetick")
        request.completion(.success(HAData(value: ["response": ["id": 4, "name": "Mow"]])))
        #expect(try await response["name"]?.string == "Mow")
    }

    @Test func nonDictionaryResultsAndErrors() async throws {
        let (connection, mock) = makeConnection()
        async let empty = connection.callServiceForResponse("script", "x", data: [:])
        try await pendingRequest(mock).completion(.success(.empty))
        #expect(try await empty == .null)

        let (failing, failingMock) = makeConnection()
        let call = Task { try await failing.callServiceForResponse("script", "x", data: [:]) }
        try await pendingRequest(failingMock).completion(.failure(.internal(debugDescription: "offline")))
        await #expect(throws: HAError.self) { _ = try await call.value }
    }
}

@Suite(.demoHouse)
struct AdminTodoUploadTests {
    @Test func buildsAnAuthorizedMultipartRequest() throws {
        let image = AdminTodoUpload.Image(data: Data([0xFF, 0xD8]), filename: "a\"b.jpg", mimeType: "image/jpeg")
        let upload = AdminTodoUpload(entityId: "todo.demo_todo_1", item: "Fix it", images: [image], boundary: "B")
        let request = upload.request(server: .example, accessToken: "token")
        #expect(request.url?.absoluteString == HassServer.example.baseURL.absoluteString + ChoresConfig.adminTodoUploadPath)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")
        let body = try #require(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"entity_id\"\r\n\r\ntodo.demo_todo_1\r\n"))
        #expect(text.contains("name=\"item\"\r\n\r\nFix it\r\n"))
        #expect(text.contains("name=\"images\"; filename=\"ab.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"))
        #expect(text.hasSuffix("--B--\r\n"))
        #expect(AdminTodoUpload(entityId: "e", item: "i", images: []).boundary.hasPrefix("FentonHome-"))
    }

    @Test func validatesLikeTheWeb() {
        #expect(AdminTodoUpload.validationError(count: 5, sizes: [], mimeTypes: []) == "Select no more than four images.")
        #expect(AdminTodoUpload.validationError(count: 1, sizes: [1], mimeTypes: ["image/gif"]) == "Select PNG, JPEG, or WebP images.")
        #expect(AdminTodoUpload.validationError(count: 1, sizes: [11 * 1024 * 1024], mimeTypes: ["image/png"]) == "Each image must be 10 MB or smaller.")
        #expect(AdminTodoUpload.validationError(count: 2, sizes: [1, 2], mimeTypes: ["image/png", "image/webp"]) == nil)
    }
}
