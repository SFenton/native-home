import Foundation
import HassCore
import XCTest

/// Builds `todo-collection@1` sources from synthetic ``ChoresConfig/Page`` values, so a hosted test's publication defines its
/// chores, grocery and admin pages the way the Studio does: the page is the publication's, never house configuration's.
@MainActor
enum ServerUITodoPublicationFixture {
    /// The `todo-collection@1` source for `page`, named `records-<page id>`.
    static func source(_ page: ChoresConfig.Page) -> JSONValue {
        func literal(_ value: String) -> JSONValue { .object(["type": "literal", "value": .string(value)]) }
        let lists: [JSONValue] = page.lists.map { list in
            var item: [String: JSONValue] = [
                "title": .string(list.title), "entityId": literal(list.entityId),
                "hideCompleted": .bool(list.hideCompleted), "hideWhenNoOpenItems": .bool(list.hideWhenNoOpenItems),
            ]
            if let script = list.completionScript { item["completionScript"] = literal(script) }
            if !list.userIds.isEmpty {
                item["visibleWhen"] = .object(["type": "viewer", "userIds": .array(list.userIds.map(JSONValue.string))])
                item["whenUnknown"] = "hide"
            }
            return .object(item)
        }
        let action: JSONValue = switch page.addAction {
        case .assignedTask(let assignee): .object(["type": "task", "defaultAssignee": .string(assignee)])
        case .groceryItem(let id): .object(["type": "grocery", "entityId": literal(id)])
        case .adminTodo(let id): .object(["type": "admin", "entityId": literal(id)])
        }
        var inputs: [String: JSONValue] = [
            "title": .string(page.title), "lists": .array(lists), "addAction": action,
            "hideListHeaders": .bool(page.hideListHeaders), "hiddenByVacation": .bool(page.hiddenByVacation),
            "empty": .object(["title": .string(page.emptyTitle), "description": .string(page.emptyDescription)]),
        ]
        if let resident = page.resident {
            var personalization: [String: JSONValue] = ["residentId": .string(resident.key), "ownTitle": .string("Your " + page.title),
                                                        "otherTitle": .string(page.title)]
            if let own = page.ownEmptyDescription { personalization["ownEmptyDescription"] = .string(own) }
            inputs["personalization"] = .object(personalization)
        }
        return .object(["id": .string("records-" + page.id), "kind": "model", "model": "todo-collection@1", "inputs": .object(inputs)])
    }

    /// `json` with a source per page appended to its data sources and the capability the sources need.
    static func adding(_ pages: [ChoresConfig.Page], to json: JSONValue) throws -> JSONValue {
        let sources = try XCTUnwrap(json["document"]?["dataSources"]?.array) + pages.map(source)
        var result = try ServerUIRendererFixture.changing(json, path: "/document/dataSources", to: .array(sources))
        var capabilities = Set(try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string))
        if !pages.isEmpty { capabilities.insert("sh.todo-collection@1") }
        if pages.contains(where: { $0.lists.contains { !$0.userIds.isEmpty } }) { capabilities.insert("sh.visible-when@1") }
        result = try ServerUIRendererFixture.changing(result, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        return result
    }
}
