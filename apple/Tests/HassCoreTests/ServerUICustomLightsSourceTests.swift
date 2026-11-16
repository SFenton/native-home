import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Authored custom-light session

/// The session that owns the group's transport: manual control, modes, resets, copies, debounced colours and tickets.
@MainActor @Suite
struct ServerUICustomLightsSourceTests {
    private typealias RGB = CustomLightsConfig.RGB

    private func make(manual: String = "on", mode: String = "Personal", group: String = "on")
        throws -> (ServerUICustomLightsSource, EntityStore, RecordingCaller) {
        let settings = try CustomLightsSettings(
            sectionTitle: "Garden", manualTitle: "Manual", modeTitle: "Scene",
            manualEntityId: "input_boolean.demo_manual", modeEntityId: "input_select.demo_mode", groupEntityId: "light.demo_group",
            customMode: "Personal", fallbackModes: ["Normal", "Personal"], modeSwatches: ["Normal": [.init(3, 5, 7)]],
            lights: [.init(entityId: "light.demo_one", title: "One"), .init(entityId: "light.demo_two", title: "Two")],
            resetKelvin: 2300, resetBrightness: 200, resetTransition: 2)
        func light(_ id: String, _ color: [Double]) -> EntityState {
            EntityState(entityId: id, state: "on", attributes: ["rgb_color": .array(color.map(JSONValue.number)),
                                                               "supported_color_modes": .array([.string("rgb")])])
        }
        let store = EntityStore()
        store.apply([
            EntityState(entityId: "input_boolean.demo_manual", state: manual),
            EntityState(entityId: "input_select.demo_mode", state: mode, attributes: ["options": .array([.string("Normal"), .string("Personal")])]),
            EntityState(entityId: "light.demo_group", state: group),
            light("light.demo_one", [10, 20, 30]), light("light.demo_two", [200, 100, 50])
        ])
        let caller = RecordingCaller()
        return (ServerUICustomLightsSource(settings: settings, store: store, caller: caller), store, caller)
    }

    @Test func theGroupReadsItsManualSwitchModeAndSwatch() throws {
        let (source, store, _) = try make()
        #expect(source.manual?.state == "on" && source.mode?.state == "Personal")
        #expect(source.isCustom)
        #expect(source.modes == ["Normal", "Personal"])
        #expect(source.swatch == [RGB(10, 20, 30), RGB(200, 100, 50)])
        #expect(source.light("light.demo_one") != nil)
        #expect(source.light("light.demo_other") == nil)
        #expect(source.canEdit("light.demo_one"))
        #expect(!source.canEdit("light.demo_other"))
        set(store, "input_select.demo_mode", "Normal")
        #expect(!source.isCustom && !source.canEdit("light.demo_one"))
        #expect(source.swatch == [RGB(3, 5, 7)])
    }

    @Test func aGestureInProgressHoldsPublication() throws {
        let (source, _, _) = try make()
        #expect(!source.protectsPublication)
        source.setEditing("light.demo_one", true)
        #expect(source.protectsPublication)
        source.setEditing("light.demo_one", false)
        #expect(!source.protectsPublication)
    }

    @Test func manualControlAndModeChangesCallTheirServices() async throws {
        let (source, store, caller) = try make()
        #expect(await source.setManual(false))
        #expect(caller.calls.last?.service == "turn_off")
        #expect(await source.selectMode("Normal"))
        #expect(caller.calls.last?.service == "select_option")
        #expect(await source.selectMode("Other") == false)
        #expect(source.error == "The lights changed or are unavailable. Try again.")
        set(store, "input_boolean.demo_manual", "off")
        #expect(await source.selectMode("Normal") == false, "a mode needs manual control on")
        set(store, "input_boolean.demo_manual", "unavailable")
        #expect(await source.setManual(true) == false)
        #expect(caller.calls.count == 2)
    }

    @Test func aFailedCallSaysSoAndLeavesNothingPending() async throws {
        let (source, _, caller) = try make()
        caller.failNext = true
        #expect(await source.setManual(true) == false)
        #expect(source.error == "Couldn't change lights. Check the connection and try again.")
        #expect(source.pendingCalls == 0 && !source.protectsPublication)
        #expect(await source.setManual(true))
        #expect(source.error == nil)
    }

    @Test func resetAndCopyOnlyTouchEditableLights() async throws {
        let (source, store, caller) = try make()
        #expect(await source.resetLight("light.demo_one"))
        #expect(caller.calls.last?.data["entity_id"] == "light.demo_one")
        #expect(await source.resetLight("light.demo_other") == false)
        #expect(await source.copyColor(from: "light.demo_one", to: "light.demo_two"))
        #expect(caller.calls.last?.data["entity_id"] == "light.demo_two")
        #expect(await source.copyColor(from: "light.demo_one", to: "light.demo_one") == false)
        #expect(await source.copyColor(from: "light.demo_one", to: "light.demo_other") == false)
        store.apply([EntityState(entityId: "light.demo_two", state: "on", attributes: ["supported_color_modes": .array([.string("onoff")])])])
        #expect(await source.copyColor(from: "light.demo_one", to: "light.demo_two") == false, "the target must support colour")
        store.apply([EntityState(entityId: "light.demo_one", state: "on", attributes: ["supported_color_modes": .array([.string("rgb")])])])
        store.apply([EntityState(entityId: "light.demo_two", state: "on", attributes: ["supported_color_modes": .array([.string("rgb")])])])
        #expect(await source.copyColor(from: "light.demo_one", to: "light.demo_two") == false, "the source needs a colour to copy")
        #expect(caller.calls.count == 2)
    }

    @Test func aColourWaitsOutItsDebounceThenSendsOnce() async throws {
        let (source, _, caller) = try make()
        source.setColor(RGB(1, 2, 3), on: "light.demo_one")
        #expect(source.protectsPublication, "the pending colour is pinned at once")
        source.setColor(RGB(4, 5, 6), on: "light.demo_one")
        await source.waitForCalls()
        #expect(caller.calls.count == 1)
        #expect(caller.calls.first?.data["entity_id"] == "light.demo_one")
        #expect(!source.protectsPublication && source.pendingCalls == 0)
        await source.waitForCalls()
    }

    @Test func aColourOutOfRangeOrForAnUneditableLightIsRefusedAtOnce() async throws {
        let (source, store, caller) = try make()
        source.setColor(RGB(300, 0, 0), on: "light.demo_one")
        #expect(source.error != nil && !source.protectsPublication)
        source.setColor(RGB(1, 2, 3), on: "light.demo_other")
        set(store, "input_select.demo_mode", "Normal")
        source.setColor(RGB(1, 2, 3), on: "light.demo_one")
        await source.waitForCalls()
        #expect(caller.calls.isEmpty)
    }

    @Test func aColourIsDroppedWhenTheGroupLeavesCustomModeDuringTheDebounce() async throws {
        let (source, store, caller) = try make()
        source.setColor(RGB(1, 2, 3), on: "light.demo_one")
        set(store, "input_select.demo_mode", "Normal")
        await source.waitForCalls()
        #expect(caller.calls.isEmpty)
        #expect(source.error == "The lights changed or are unavailable. Try again.")
    }

    @Test func aTicketAppliesOnlyWhileTheGroupIsUnchanged() async throws {
        let (source, store, caller) = try make()
        let reset = try #require(source.confirmation(.reset))
        #expect(await source.confirm(reset))
        #expect(caller.calls.last?.data["entity_id"] == "light.demo_group")
        let apply = try #require(source.confirmation(.applyColor("light.demo_one", RGB(10, 20, 30))))
        #expect(await source.confirm(apply))
        #expect(caller.calls.last?.data["rgb_color"] != nil)
        #expect(source.confirmation(.applyColor("light.demo_one", RGB(9, 9, 9))) == nil, "the colour must be the light's own")
        #expect(source.confirmation(.applyColor("light.demo_one", RGB(-1, 0, 0))) == nil)
        #expect(source.confirmation(.applyColor("light.demo_other", RGB(10, 20, 30))) == nil)
        set(store, "light.demo_group", "unavailable")
        #expect(source.confirmation(.reset) == nil)
        #expect(await source.confirm(reset) == false)
        set(store, "light.demo_group", "on")
        set(store, "input_select.demo_mode", "Normal")
        #expect(source.confirmation(.reset) == nil)
    }
}
