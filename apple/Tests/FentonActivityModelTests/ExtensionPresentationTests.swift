import Foundation
import Testing
@testable import FentonActivityModel

@Suite struct ExtensionPresentationTests {
    private let activity = """
        {"id":"appearance","jobId":"fan.demo_unit","type":"activity-presentation@1","title":"Authored Fan",
         "glyph":"fan","tint":"air","source":"activity-engine@1","privacy":"system-sensitive@1",
         "updates":"engine@1","intents":"engine-safe@1"}
        """
    private let targets = """
        {"type":"native-extensions@1","watch":"stub@1",
         "routes":[{"id":"home","path":"home","pageId":"page-home","title":"Home","summary":"Your house","icon":"house.fill"}],
         "cameras":[{"entityId":"camera.demo_unit","title":"Entry","liveLabel":"Live","unavailableLabel":"Stream unavailable"}]}
        """

    @Test func deliversExactJobAppearanceAndCameraCopyWithoutNavigationOrState() throws {
        let appearance = try JSONDecoder().decode(ActivityPresentation.self, from: Data(activity.utf8))
        let target = try NativeExtensionPresentation.decode(Data(targets.utf8))
        let snapshot = try ExtensionPresentationSnapshot(sessionID: String(repeating: "a", count: 64),
            revision: 1, activities: [appearance], targets: target)
        #expect(snapshot.targets?.routes.isEmpty == true)
        #expect(snapshot.targets?.cameras.first?.title == "Entry")
        #expect(snapshot.presentation(for: .init(tag: "job.fan.other")) == nil)
        let attributes = HomeActivityAttributes(tag: "job.fan.demo_unit", title: "Fan", kind: "fan")
        var state = HomeActivityState()
        state.controls = [.init(id: "stop", title: "Stop")]
        let card = ActivityCard(attributes: attributes, state: state, presentation: snapshot.presentation(for: attributes))
        #expect(card.deviceTitle == "Authored Fan")
        #expect(card.tag == "job.fan.demo_unit")
        #expect(card.buttons.map(\.control) == state.controls)
        #expect(card.buttons.first?.accessibilityLabel == "Stop Authored Fan")
        state.pending = .init(control: "stop", label: "Stopping", sinceTs: 1)
        #expect(ActivityCard(attributes: attributes, state: state, presentation: appearance).buttons.isEmpty)
        #expect(ActivityCard(attributes: attributes, state: state, isStale: true, presentation: appearance).buttons.count == 1)
    }

    @Test func diskDeliveryRetainsLastGoodAndFencesAccountsAndLateWriters() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("extension-delivery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionPresentationStore(directory: directory)
        let first = String(repeating: "a", count: 64), next = String(repeating: "b", count: 64)
        let appearance = try JSONDecoder().decode(ActivityPresentation.self, from: Data(activity.utf8))
        let snapshot = try ExtensionPresentationSnapshot(sessionID: first, revision: 1, activities: [appearance], targets: nil)
        try store.beginSession(first)
        try store.write(snapshot)
        #expect(try store.read() == snapshot)
        #expect(throws: (any Error).self) {
            try ExtensionPresentationSnapshot(sessionID: first, revision: 2, activities: [appearance, appearance], targets: nil)
        }
        #expect(try store.read() == snapshot)
        try store.beginSession(next)
        #expect(try store.read() == nil)
        #expect(throws: (any Error).self) { try store.write(snapshot) }
        try store.endSession(first)
        let second = try ExtensionPresentationSnapshot(sessionID: next, revision: 2, activities: [], targets: nil)
        try store.write(second)
        #expect(try store.read() == second)
        try store.endSession(next)
        #expect(try store.read() == nil)
        #expect(throws: (any Error).self) { try store.write(second) }
    }

    @Test func aWidgetRenderReusesTheDecodedSnapshotUntilTheFileChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("extension-cache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionPresentationStore(directory: directory)
        let session = String(repeating: "c", count: 64)
        try store.beginSession(session)
        let one = try ExtensionPresentationSnapshot(sessionID: session, revision: 1, activities: [], targets: nil)
        try store.write(one)
        #expect(try store.read() == one)
        #expect(try store.read() == one, "a second render in the same state answers from the cache")
        let two = try ExtensionPresentationSnapshot(sessionID: session, revision: 2, activities: [], targets: nil)
        try store.write(two)
        #expect(try store.read() == two, "a replaced file is decoded again, not served stale")
        try store.endSession(session)
        #expect(try store.read() == nil, "ending the session never serves the cached copy")
    }

    @Test func closedTargetDecoderRejectsActionsURLsUnknownWatchAndDuplicates() throws {
        for invalid in [
            targets.replacingOccurrences(of: "\"stub@1\"", with: "\"watch-dashboard@1\""),
            targets.replacingOccurrences(of: "\"title\":\"Entry\"", with: "\"title\":\"Entry\",\"action\":\"unlock\""),
            targets.replacingOccurrences(of: "\"camera.demo_unit\"", with: "\"https://example.test/image\""),
            targets.replacingOccurrences(of: "\"watch\":\"stub@1\"", with: "\"watch\":\"stub@1\",\"watch\":\"stub@1\""),
            targets.replacingOccurrences(of: "\"Entry\"", with: "\"Entry\\nSecret\""),
        ] {
            #expect(throws: (any Error).self) { try NativeExtensionPresentation.decode(Data(invalid.utf8)) }
        }
        #expect(throws: (any Error).self) {
            try NativeExtensionPresentation.decode(Data(repeating: 32, count: 32_769))
        }
    }

    @Test func engineTintPreservesJobModeChangesWhileAuthoredCopyStaysApplied() throws {
        let appearance = try JSONDecoder().decode(ActivityPresentation.self,
            from: Data(activity.replacingOccurrences(of: "\"tint\":\"air\"", with: "\"tint\":\"engine\"").utf8))
        var attributes = HomeActivityAttributes(tag: "job.fan.demo_unit", tint: "water")
        #expect(ActivityCard(attributes: attributes, state: .init(), presentation: appearance).tint == "water")
        attributes.tint = "cleaning"
        let card = ActivityCard(attributes: attributes, state: .init(), presentation: appearance)
        #expect(card.tint == "cleaning")
        #expect(card.deviceTitle == "Authored Fan")
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ActivityPresentation.self,
                from: Data(activity.replacingOccurrences(of: "Authored Fan", with: "Fan\\nHidden").utf8))
        }
    }
}
