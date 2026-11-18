@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Chore removals through the generic record list

/// The held swipe on chores, as on Food: the swiped row stays open under "Delete Task?", cancel closes it, confirm lets the row leave
/// announced, and a refused delete brings the row back with no announcement. They run unchanged at the widths of iPhone, iPhone Duo
/// (folded and unfolded) and iPad. Pattern: `.agents/patterns/list-row-removal.md`.
@MainActor
final class ServerUIChoreRemovalHostedTests: XCTestCase {
    override func tearDown() async throws {
        UKListAnnouncements.sink = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private static let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678),
                                CGSize(width: 744, height: 1133), CGSize(width: 1024, height: 768)]

    /// A todo service over canned items; `remove_item` drops the item, or throws when `refuses` is set.
    @MainActor
    private final class Service: TodoServicing {
        var items: [TodoItem] = (0..<4).map { TodoItem(uid: "chore-\($0)", summary: "Chore \($0)") }
        var refuses = false
        func todoItems(entityId: String) async throws -> [TodoItem] { items }
        func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {}
        func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue { .null }
        func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
            if service == "remove_item" {
                if refuses { throw NSError(domain: "ChoreRemoval", code: 1) }
                items.removeAll { $0.uid == (data["item"] as? String) }
            }
        }
    }

    private struct Rig {
        let service: Service
        let source: UKServerUITodoCollection
        let page: UKServerUIPage
        let collection: UKServerUICollectionView
        let controller: UKRecordCollectionController
        let window: UIWindow
    }

    private func fixture() throws -> JSONValue {
        var root = try ServerUIRendererFixture.json()
        let component: JSONValue = .object(["id": "record-list", "title": "Chores", "type": "collection", "layout": .object(["span": .number(1)]),
            "props": .object(["providerId": "demo-items", "template": "todo", "loadingText": "Loading Chores", "emptyText": "No Chores"])])
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array([component]))
        root = try ServerUIRendererFixture.changing(root, path: "/document/navigation/chrome/groups/1/items/0/priority", to: .string("normal"))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.grid@1" } + ["sh.collection@1"]
        return try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
    }

    private func rig(_ size: CGSize) async throws -> Rig {
        let service = Service()
        let configuration = try ServerUITodoProvider.Configuration(entityId: "todo.demo_chores", completionScript: nil, canRename: true,
            canDelete: true, canAdd: true, canCreateTask: false, canEditTask: false, allowsAttachments: false)
        let provider = ServerUITodoProvider(configuration: configuration, store: TodoStore(service: service), service: service)
        let source = UKServerUITodoCollection(provider)
        try await source.load()
        let renderer = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(fixture()),
            context: UKContext(store: EntityStore()), backdrop: ServerUIRendererFixture.backdrop(),
            records: UKServerUIRecords(collections: ["demo-items": source]))
        let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
        let page = try ServerUIRendererFixture.root(renderer)
        let collection = try XCTUnwrap(page.nodes["record-list"]?.view as? UKServerUICollectionView)
        let controller = try XCTUnwrap(collection.recordController)
        let shown = await HostedPage.settle { controller.visibleKeys.count == 4 }
        XCTAssertTrue(shown, "the four chores are drawn")
        return Rig(service: service, source: source, page: page, collection: collection, controller: controller, window: window)
    }

    private func swipeDelete(_ rig: Rig, _ key: String, completion: @escaping (Bool) -> Void) throws {
        let configuration = try XCTUnwrap(rig.collection.recordSwipe(for: key, leading: false), "a deletable chore swipes")
        let action = try XCTUnwrap(configuration.actions.first { $0.title == "Delete" })
        action.handler(action, UIView(), completion)
    }

    func testASwipedChoreStaysOpenUnderTheQuestionAndCancelClosesItOnEveryFamily() async throws {
        for size in Self.sizes {
            let rig = try await rig(size)
            defer { rig.window.isHidden = true }
            let key = try XCTUnwrap(rig.source.records.first?.id)
            var answered: Bool?
            try swipeDelete(rig, key) { answered = $0 }
            let alert = try XCTUnwrap(FeatureHost.alert(on: rig.page), "width \(size.width): Delete asks first")
            XCTAssertNil(answered, "the swipe is held open while the question is up")
            XCTAssertTrue(FeatureHost.answer(alert, "Cancel"))
            XCTAssertEqual(answered, false, "cancel closes the swipe")
            XCTAssertTrue(rig.controller.visibleKeys.contains(key), "the chore stays")
            HostedPage.hideTracked()
        }
    }

    func testConfirmingLetsTheChoreLeaveAnnouncedOnEveryFamily() async throws {
        for size in Self.sizes {
            let rig = try await rig(size)
            defer { rig.window.isHidden = true }
            var announced: [String] = []
            UKListAnnouncements.sink = { announced.append($0) }
            let key = try XCTUnwrap(rig.source.records.last?.id)
            var answered: Bool?
            try swipeDelete(rig, key) { answered = $0 }
            XCTAssertTrue(FeatureHost.answer(try XCTUnwrap(FeatureHost.alert(on: rig.page)), "Delete Task"))
            let gone = await HostedPage.settle { !rig.controller.visibleKeys.contains(key) && answered != nil }
            XCTAssertTrue(gone, "width \(size.width): the chore leaves")
            XCTAssertEqual(answered, true, "confirm completes the swipe as the row leaves")
            XCTAssertEqual(rig.controller.lastPlan?.transition, .animate)
            XCTAssertEqual(rig.controller.lastPlan?.removedByPerson, true)
            XCTAssertEqual(announced, ["Chore 3 deleted"], "VoiceOver hears the removal")
            HostedPage.hideTracked()
        }
    }

    func testARefusedDeleteBringsTheChoreBackWithoutAnnouncingItOnEveryFamily() async throws {
        for size in Self.sizes {
            let rig = try await rig(size)
            defer { rig.window.isHidden = true }
            var announced: [String] = []
            UKListAnnouncements.sink = { announced.append($0) }
            rig.service.refuses = true
            let key = try XCTUnwrap(rig.source.records.first?.id)
            try swipeDelete(rig, key) { _ in }
            XCTAssertTrue(FeatureHost.answer(try XCTUnwrap(FeatureHost.alert(on: rig.page)), "Delete Task"))
            // The row hides at once and the refusal brings it back; both settle before the check.
            let back = await HostedPage.settle { rig.controller.visibleKeys.contains(key) && rig.source.records.map(\.id).contains(key) }
            XCTAssertTrue(back, "width \(size.width): the refused delete restores the chore")
            await HostedPage.pump(passes: 20)
            XCTAssertTrue(rig.controller.visibleKeys.contains(key))
            XCTAssertFalse(announced.contains { $0.hasSuffix("deleted") && $0.hasPrefix("Chore 0") }, "a refused delete is not announced as deleted: \(announced)")
            HostedPage.hideTracked()
        }
    }
}
