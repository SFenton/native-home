import Foundation
import Testing
@testable import HassCore

// MARK: - Bootstrap contract parity

@Suite struct ServerUIBootstrapTests {
    static let policy = """
        {"type":"native-bootstrap@1","arrivalAnnouncement":"Your sample home is ready.",
         "recovery":{"loadingTitle":"Getting the sample layout","unavailableTitle":"Sample layout unavailable",
          "unavailableMessage":"Try again when the sample publisher is available.","retryLabel":"Retry Layout"},
         "setup":[{"permission":"notifications","explanation":"Choose sample home alerts."},
                  {"permission":"time-sensitive","explanation":"Review urgent sample alerts."},
                  {"permission":"location","explanation":"Choose sample location sharing."}]}
        """

    private func bytes(policy: String = Self.policy, capabilities: [String]? = nil,
                       extra: [String: Any] = [:]) throws -> Data {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json")
        var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var bootstrap = try #require(JSONSerialization.jsonObject(with: Data(policy.utf8)) as? [String: Any])
        bootstrap.merge(extra) { _, new in new }
        document["bootstrap"] = bootstrap
        root["document"] = document
        root["capabilities"] = capabilities ?? (ServerUICompositionPublication.firstSliceCapabilities + ["sh.bootstrap-policy@1"]).sorted()
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test func trustedCopyAndOrderedPermissionExplanationsCompileWithoutAuthConfiguration() throws {
        let publication = try ServerUICompositionPublication.decode(bytes())
        let policy = try #require(publication.document.bootstrap)
        #expect(policy.setup.map(\.permission) == [.notifications, .timeSensitive, .location])
        #expect(policy.arrivalAnnouncement == "Your sample home is ready.")
        #expect(policy.recovery.retryLabel == "Retry Layout")
        #expect(publication.document.navigation.initialPageId == "page-orbit")
    }

    @Test func omittedSupplementKeepsEveryNativePermissionStateAndItsCanonicalCopy() throws {
        let data = try bytes(extra: ["setup": [
            ["permission": "notifications"], ["permission": "time-sensitive"], ["permission": "location"]
        ]])
        let policy = try #require(ServerUICompositionPublication.decode(data).document.bootstrap)
        #expect(policy.setup.map(\.permission) == [.notifications, .timeSensitive, .location])
        #expect(policy.setup.allSatisfy { $0.explanation == nil })
    }

    @Test(arguments: [
        #"{"endpoint":"https://sample.invalid"}"#, #"{"credential":"synthetic"}"#,
        #"{"oauthClient":"synthetic"}"#, #"{"skipConfirmation":true}"#
    ])
    func authAndConsentFieldsAreNotAuthorable(extra: String) throws {
        let fields = try #require(JSONSerialization.jsonObject(with: Data(extra.utf8)) as? [String: Any])
        #expect(throws: ServerUICompositionError.self) {
            try ServerUICompositionPublication.decode(bytes(extra: fields))
        }
    }

    @Test func capabilityClosureIsExactAndDuplicateOrDependencyViolatingSetupIsRejected() throws {
        #expect(throws: ServerUICompositionError(.capabilityManifestMismatch, "/capabilities")) {
            try ServerUICompositionPublication.decode(bytes(capabilities: ServerUICompositionPublication.firstSliceCapabilities))
        }
        for invalid in [
            Self.policy.replacingOccurrences(of: #""permission":"location""#, with: #""permission":"notifications""#),
            Self.policy.replacingOccurrences(of: #""permission":"notifications""#, with: #""permission":"location""#)
                .replacingOccurrences(of: #""permission":"location","explanation":"Choose sample location sharing.""#,
                                      with: #""permission":"notifications","explanation":"Choose sample location sharing.""#)
        ] {
            #expect(throws: ServerUICompositionError(.invalidCombination, "/document/bootstrap/setup")) {
                try ServerUICompositionPublication.decode(bytes(policy: invalid))
            }
        }
    }

    @Test(arguments: ["bootstrap-message", "notification-permission-banner"])
    func atomicBootstrapNodesCompileOnlyWithTheirExactCapability(type: String) throws {
        var root = try #require(JSONSerialization.jsonObject(with: bytes()) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var pages = try #require(document["pages"] as? [[String: Any]])
        var components = try #require(pages[0]["components"] as? [[String: Any]])
        var node: [String: Any] = [
            "id": "sample-bootstrap", "type": type, "title": "Sample Status", "layout": ["span": 1],
            "props": ["message": "A sample explanation."]
        ]
        let capability: String
        if type == "bootstrap-message" {
            capability = "sh.bootstrap-message@1"
            node["icon"] = ["type": "sf-symbol", "name": "person.crop.circle", "rendering": "canonical", "unavailable": "reject"]
        } else {
            capability = "sh.bootstrap-notifications@1"
            node["props"] = ["message": "A sample explanation.", "enableLabel": "Continue", "dismissLabel": "Later"]
        }
        components.append(node)
        pages[0]["components"] = components
        document["pages"] = pages
        root["document"] = document
        var capabilities = try #require(root["capabilities"] as? [String])
        capabilities.append(capability)
        root["capabilities"] = capabilities.sorted()
        let publication = try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
        #expect(publication.document.pages[0].surface.components.last?.node.title == "Sample Status")
        root["capabilities"] = capabilities.filter { $0 != capability }.sorted()
        #expect(throws: ServerUICompositionError(.capabilityManifestMismatch, "/capabilities")) {
            try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
        }
    }
}
