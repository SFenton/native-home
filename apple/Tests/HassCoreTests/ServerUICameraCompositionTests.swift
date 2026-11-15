import Foundation
import Testing
@testable import HassCore

// MARK: - Configured camera contract

@Suite struct ServerUICameraCompositionTests {
    typealias P = ServerUICompositionPublication
    typealias E = ServerUICompositionError

    private func fixture() throws -> [String: Any] {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("ServerUICompositionFixture.json"))) as? [String: Any])
        let camera = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("ServerUICameraFixture.json"))) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var sources = try #require(document["dataSources"] as? [[String: Any]])
        sources.append(try #require(camera["source"] as? [String: Any]))
        document["dataSources"] = sources
        var pages = try #require(document["pages"] as? [[String: Any]])
        var components = try #require(pages[0]["components"] as? [[String: Any]])
        components.append(try #require(camera["tile"] as? [String: Any]))
        pages[0]["components"] = components
        document["pages"] = pages
        var modals = try #require(document["modals"] as? [[String: Any]])
        modals[0]["components"] = [camera["viewer"]!]
        var presentation = try #require(modals[0]["presentation"] as? [String: Any])
        presentation["width"] = "page"
        presentation["appearance"] = "dark"
        modals[0]["presentation"] = presentation
        document["modals"] = modals
        root["document"] = document
        root["capabilities"] = (P.firstSliceCapabilities + [
            "sh.camera-stream@1", "sh.camera-tile@1", "sh.camera-video@1", "sh.camera-controls@1", "sh.camera-viewer@1"
        ]).sorted()
        return root
    }

    private func decode(_ root: [String: Any]) throws -> P {
        try P.decode(JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))
    }

    private func changing(_ value: Any, path: [String], replacement: Any) throws -> Any {
        guard let key = path.first else { return replacement }
        if var object = value as? [String: Any] {
            object[key] = try changing(#require(object[key]), path: Array(path.dropFirst()), replacement: replacement)
            return object
        }
        var array = try #require(value as? [Any])
        let index = try #require(Int(key))
        array[index] = try changing(array[index], path: Array(path.dropFirst()), replacement: replacement)
        return array
    }

    @Test func cameraPlanKeepsExplicitTargetsCopyOrderAndNativeSemantics() throws {
        let document = try decode(fixture()).document
        guard case .camera(_, let configuration) = document.dataSources.last,
              case .cameraViewer(let viewer) = document.modals[0].surface.components[0] else {
            Issue.record("Expected configured camera values"); return
        }
        #expect(configuration.camera(title: "Entry").recordCall == ServiceCall("script", "turn_on", target: "script.demo_recording"))
        #expect(configuration.snapshotEntityId == "camera.demo_still")
        #expect(viewer.controls.map(\.intent) == [.snapshot, .sound, .record])
        #expect(viewer.controls[0].activeTitle == "Saved to Photos")
        #expect(viewer.controls[0].failureIcon.name == "exclamationmark.triangle.fill")
        #expect(viewer.controls.map(\.tint) == [.action, .action, .danger])
        #expect(document.modals[0].presentation.height == .full)
        #expect(P.firstSliceCapabilities.contains("sh.camera-stream@1") == false)
    }

    @Test func invalidTargetsCapabilitiesAndAttachmentsAreRejected() throws {
        let root = try fixture()
        let source = "/document/dataSources/2"
        let viewer = "/document/modals/0/components/0/props"
        let cases: [(String, Any, E.Code)] = [
            (source + "/inputs/entityId/value", "switch.demo_entry", .invalidCombination),
            (source + "/inputs/snapshotEntityId/value", "camera.demo_still\n", .invalidValue),
            (source + "/inputs/rtcStreamId", "https://example.invalid/stream", .invalidValue),
            (source + "/inputs/aspectRatio", 0, .limitExceeded),
            (source + "/inputs/recording/scriptEntityId/value", "light.demo_record", .invalidCombination),
            (source + "/labels/hidden", " ", .invalidValue),
            (viewer + "/sourceId", "source-power", .bindingType),
            (viewer + "/controls/1/intent", "snapshot", .invalidCombination),
            (viewer + "/controls/0/tint", "arbitrary-color", .unknownVariant),
            ("/document/modals/0/presentation/width", "form", .invalidCombination),
            ("/document/modals/0/presentation/appearance", "system", .invalidCombination),
            ("/capabilities", P.firstSliceCapabilities, .capabilityManifestMismatch)
        ]
        for (path, replacement, code) in cases {
            let changed = try #require(changing(root, path: path.split(separator: "/").map(String.init), replacement: replacement) as? [String: Any])
            #expect(throws: E(code, path == "/capabilities" ? path : path)) { try decode(changed) }
        }
    }

    @Test func viewerInAnInitiallyHiddenSharedContainerSatisfiesItsCameraRoute() throws {
        var root = try fixture()
        var document = try #require(root["document"] as? [String: Any])
        var modals = try #require(document["modals"] as? [[String: Any]])
        let viewers = try #require(modals[0]["components"] as? [[String: Any]])
        document["localState"] = [["id": "camera-tab", "type": "choice", "initial": "details",
                                   "options": [["id": "details", "label": "Details"], ["id": "video", "label": "Video"]]]]
        modals[0]["components"] = [[
            "id": "camera-section", "title": "Camera", "type": "section", "layout": ["span": 1],
            "props": ["header": "", "footer": "", "style": "plain", "density": "thin",
                      "hasGlyphs": false, "spacing": ["type": "token", "name": "m"]],
            "children": [[
                "id": "camera-tabs", "title": "Camera tabs", "type": "local-tabs", "layout": ["span": 1],
                "props": ["stateId": "camera-tab", "transition": "canonical-swap@1"],
                "tabs": [["id": "details", "label": "Details", "children": []],
                         ["id": "video", "label": "Video", "children": viewers]]
            ]]
        ]]
        document["modals"] = modals
        root["document"] = document
        root["capabilities"] = (try #require(root["capabilities"] as? [String])
            + ["sh.section@1", "sh.local-tabs@1", "sh.local-state@1"]).sorted()
        let accepted = try decode(root)
        guard case .section(let section) = accepted.document.modals[0].surface.components[0],
              case .localTabs(let tabs) = section.children[0] else {
            Issue.record("Expected shared camera containers"); return
        }
        #expect(tabs.tabs[1].children.count == 1)
    }

    @Test func statusFixturesCoverLoadingPrivacyUnavailableOfflineAndHLS() throws {
        guard case .camera(_, let camera) = try decode(fixture()).document.dataSources.last else { return }
        var state = CameraStreamState(modes: [.webRTC, .hls])
        #expect(camera.status(state: state, entityState: nil, pending: true, hidden: false, offline: false) == "Reading camera")
        #expect(camera.status(state: state, entityState: "idle", pending: false, hidden: true, offline: false) == "Private camera")
        #expect(camera.status(state: state, entityState: "unavailable", pending: false, hidden: false, offline: false) == "Camera unavailable")
        #expect(camera.status(state: state, entityState: "idle", pending: false, hidden: false, offline: true) == "Camera unavailable")
        state.failed(.webRTC)
        state.firstFrame(.hls)
        #expect(camera.status(state: state, entityState: "idle", pending: false, hidden: false, offline: true) == "Live, a few seconds behind")
        state.failed(.hls)
        #expect(camera.status(state: state, entityState: "idle", pending: false, hidden: false, offline: false) == "Snapshot")
    }
}
