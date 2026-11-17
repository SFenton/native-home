import CryptoKit
import HassCore
import HassDemoHouse
import XCTest
@testable import HassUI

// MARK: - A publication the gallery fixtures can serve

/// The publication the preview's gallery fixtures are tested with: every settings provider, a groceries collection over the
/// fixture todo list, and (with `header`) the native shell header, so the connection flags have something to draw on.
@MainActor
enum ServerUIPreviewGalleryFixture {
    /// The grocery collection's node id.
    static let collectionID = "fixture-groceries"
    /// What the collection says when it has no record.
    static let emptyText = "No groceries"

    /// The fixture publication.
    /// - Parameter header: Adds the native shell header (and its capability), for the connection flags to draw on.
    static func publication(header: Bool = false) throws -> ServerUICompositionPublication {
        var json = try ServerUIRendererFixture.json()
        json = try ServerUIRendererFixture.changing(json, path: "/document/assets", to: .array([]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/theme/background",
            to: .object(["type": "solid", "token": "shell-base@1"]))
        json = try ServerUIRendererFixture.changing(json, path: "/assetManifestSha256",
            to: .string(SHA256.hash(data: Data("[]".utf8)).map { String(format: "%02x", $0) }.joined()))
        let ids = ["household", "away", "profile", "preferences", "performance", "feedback-bug", "feedback-feature"]
        let sources: [JSONValue] = ids.map { id in
            .object(["id": .string("fixture-" + id), "kind": "model", "model": "settings-provider@1",
                     "inputs": .object(["providerId": .string(id), "domain": .string(id.hasPrefix("feedback") ? "feedback" : id)])])
        }
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources",
            to: .array(try XCTUnwrap(json["document"]?["dataSources"]?.array) + sources))
        let collection: JSONValue = .object(["id": .string(collectionID), "type": "collection", "title": "Groceries",
            "layout": .object(["span": .number(1)]), "props": .object(["providerId": "records-groceries", "template": "todo",
                "loadingText": "Loading", "emptyText": .string(emptyText)])])
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components",
            to: .array(try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array) + [collection]))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.assets.publisher@1" }
            + ["sh.collection@1", "sh.settings-controls@1"] + (header ? ["sh.shell-header@1"] : [])
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        json = try ServerUITodoPublicationFixture.adding(DemoHouse.config.chores.pages.filter { $0.id == "groceries" }, to: json)
        if header {
            let modalID = try XCTUnwrap(json["document"]?["modals"]?.array?.first?["id"])
            let action = JSONValue.object(["type": .string("present"), "modalId": modalID, "arguments": .object([:]),
                                           "ifPresented": .string("reject")])
            json = try ServerUIRendererFixture.changing(json, path: "/document/navigation/chrome/groups/1/items",
                to: .array([.object(["id": .string("native-header"), "type": .string("shell-header"), "visibility": .string("always"),
                                    "quickLinksAction": action, "profileAction": action])]))
        }
        return try ServerUIRendererFixture.publication(json)
    }
}
