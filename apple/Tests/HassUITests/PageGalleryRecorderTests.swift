#if os(macOS) && DEBUG
import Foundation
import HassCore
import HassTestSupport
@testable import HassUI
import Testing

/// The Media, Custom Lights and Sprinklers galleries' recorder: the echoes the device's Power and Next get, so a journey
/// can flip a remote's action set from the page.
@MainActor
@Suite(.demoHouse)
struct PageGalleryRecorderTests {
    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(25)) }
    }

    @Test func powerTurnsAnOnShieldIntoAPlayingOneAndNextStopsIt() async throws {
        let store = EntityStore()
        store.replaceAll(HomePageFixtures.states, freshness: .live)
        store.apply([EntityState(entityId: PageGalleryRecorder.theaterShield, state: "on")])
        let recorder = PageGalleryRecorder(store: store)
        try await recorder.callService("script", ScriptPowerActions.toggleScript, data: [:])
        await settle { store.value(PageGalleryRecorder.theaterShield)?.state == "playing" }
        #expect(store.value(PageGalleryRecorder.theaterShield)?.state == "playing")
        try await recorder.callService("media_player", "media_next_track", data: ["entity_id": PageGalleryRecorder.theaterShield])
        await settle { store.value(PageGalleryRecorder.theaterShield)?.state == "off" }
        #expect(store.value(PageGalleryRecorder.theaterShield)?.state == "off")
        #expect(recorder.lastCall.contains("media_next_track"))
    }

    @Test func aSwitchOfAnEntityTheStoreHasNotSeenCreatesIt() async throws {
        let store = EntityStore()
        let recorder = PageGalleryRecorder(store: store)
        try await recorder.callService("input_boolean", "turn_on", data: ["entity_id": "input_boolean.demo_unseen"])
        await settle { store.value("input_boolean.demo_unseen")?.state == "on" }
        #expect(store.value("input_boolean.demo_unseen")?.state == "on")
    }
}
#endif
