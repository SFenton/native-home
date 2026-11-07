import Foundation
@testable import HassCore
import HassTestSupport
import Testing

// MARK: - Media page

/// The Media page's cards match the web (`DashboardViewPage.tsx` `MediaPage`) and send its service calls.
@MainActor
@Suite(.demoHouse)
struct MediaPageConfigTests {
    typealias M = MediaRemotes.MusicRoom

    @Test func sectionsAndCardsFollowTheWeb() {
        #expect(MediaPageConfig.sections.map(\.title) == ["Living Room", "Studio", "Media room"])
        #expect(MediaPageConfig.sections.map { $0.cards.map(\.device.title) } == [
            ["Living Room STREAMER"],
            ["Studio Remote", "Game Console", "Server", "Computer", "Game"],
            ["Media room", "Handheld Console", "Media STREAMER"],
        ])
        #expect(Set(MediaPageConfig.cards.map(\.id)).count == MediaPageConfig.cards.count, "Ids are unique")
        let music = MediaPageConfig.sections[1]
        #expect(music.lead?.device.title == "Studio Remote")
        #expect(music.followUps.count == 4)
    }

    @Test func leadTilesOpenTheirRoomsRemote() {
        #expect(MediaPageConfig.sections.map { $0.lead?.remote?.id } == ["living-room-streamer", "studio-remote", "media-room-streamer"])
        #expect(MediaPageConfig.sections.allSatisfy { $0.lead?.isFullWidth == true })
        #expect(MediaPageConfig.sections.flatMap(\.followUps).allSatisfy { $0.remote == nil && $0.device.action != nil })
        #expect(MediaPageConfig.cards.first?.offIcon == "mdi:television-off")
    }

    @Test func sourceTilesLabelTheirOwnSourceOnly() {
        let xbox = MediaPageConfig.sections[1].cards[1].device
        #expect(xbox.stateLabels[M.Source.xbox] == "On")
        #expect(xbox.stateLabels[M.Source.fortnite] == "On", "Fortnite runs on the Xbox")
        #expect(xbox.stateLabels[M.Source.server] == "Off")
        #expect(xbox.activeStates == [M.Source.xbox, M.Source.fortnite])
    }

    func run(_ title: String, states: [String: String]) async -> (RecordingCaller, MediaRemoteController.DeviceDisplay) {
        let store = makeStore(states)
        let caller = RecordingCaller()
        let controller = MediaRemoteController(config: MediaRemotes.sourceSelectRemote, store: store, caller: caller, scheduler: ManualScheduler())
        let card = MediaPageConfig.cards.first { $0.device.title == title }!
        controller.tap(card.device)
        await controller.waitForCalls()
        return (caller, controller.display(card.device))
    }

    @Test func xboxStartsTheXboxScriptUnlessItIsTheSource() async {
        let (caller, shown) = await run("Game Console", states: [M.activeMediaSourceEntityId: M.Source.tv])
        #expect(caller.calls.map(\.service) == ["demo_studio_console"])
        #expect(shown.isActive, "The source shows optimistically")
        #expect(shown.subtitle == "On")

        let (offCaller, _) = await run("Game Console", states: [M.activeMediaSourceEntityId: M.Source.fortnite])
        #expect(offCaller.calls.map(\.service) == ["demo_studio_tv_off"], "Fortnite counts as the Xbox")
    }

    @Test func serverAndWindowsToggle() async {
        #expect(await run("Server", states: [M.activeMediaSourceEntityId: M.Source.tv]).0.calls.map(\.service) == ["demo_studio_server"])
        #expect(await run("Server", states: [M.activeMediaSourceEntityId: M.Source.server]).0.calls.map(\.service) == ["demo_studio_tv_off"])
        #expect(await run("Computer", states: [M.activeMediaSourceEntityId: M.Source.tv]).0.calls.map(\.service) == ["demo_studio_windows_pc"])
        #expect(await run("Game", states: [M.activeMediaSourceEntityId: M.Source.tv]).0.calls.map(\.service) == ["demo_studio_game"])
    }

    @Test func theaterTilesRunTheirScriptsWithoutATarget() async {
        let (caller, shown) = await run("Handheld Console", states: ["input_boolean.demo_switch_1": "off"])
        #expect(caller.calls == [RecordingCaller.Call(domain: "script", service: "demo_media_room_handheld_switch", data: [:])])
        #expect(!shown.isActive)
        #expect(shown.semantics == .toggle(isOn: false))
        let (movie, on) = await run("Media STREAMER", states: ["input_boolean.demo_input_boolean_5": "on"])
        #expect(movie.calls.map(\.service) == ["demo_media_room_tv_movie"])
        #expect(on.isActive && on.subtitle == "On")
    }

    @Test func unavailableSourcesDisable() async {
        let (_, shown) = await run("Handheld Console", states: [:])
        #expect(shown.isDisabled)
        #expect(shown.subtitle == "Unavailable")
    }
}

// MARK: - Custom lights

@Suite(.demoHouse)
struct CustomLightsConfigTests {
    typealias RGB = CustomLightsConfig.RGB

    @Test func lightsAndEntitiesMatchTheWeb() {
        #expect(CustomLightsConfig.lights.count == 8)
        #expect(CustomLightsConfig.lights.first?.entityId == "light.demo_front_door_door_1")
        #expect(CustomLightsConfig.lights.last?.title == "Path Light 6")
        #expect(Set(CustomLightsConfig.lights.map(\.entityId)).count == 8)
    }

    @Test func modesFallBackWhenTheSelectHasNoOptions() {
        #expect(CustomLightsConfig.modes(nil) == ["Default", "Custom", "Team Colors", "Holiday Mode"])
        let select = EntityState(entityId: CustomLightsConfig.modeEntityId, state: "Demo Mode",
                                 attributes: ["options": .array([.string("Default"), .string("Demo Mode")])])
        #expect(CustomLightsConfig.modes(select) == ["Default", "Demo Mode"])
        #expect(CustomLightsConfig.mode(select) == "Demo Mode")
        #expect(CustomLightsConfig.mode(nil) == "Default")
    }

    @Test func swatchesComeFromTheAutomations() {
        #expect(CustomLightsConfig.swatch(for: "Seahawks", custom: []) == [RGB(0, 255, 0), RGB(0, 0, 255)])
        #expect(CustomLightsConfig.swatch(for: "Valentine's Day", custom: []) == [RGB(255, 0, 0), RGB(255, 0, 234)])
        #expect(CustomLightsConfig.swatch(for: "Default", custom: [RGB(1, 2, 3)]).isEmpty)
        #expect(CustomLightsConfig.swatch(for: "Custom", custom: [RGB(1, 2, 3)]) == [RGB(1, 2, 3)])
    }

    @Test func customGradientDropsDuplicatesAndSortsDarkToBright() {
        let colors = [RGB(255, 255, 255), RGB(0, 0, 255), RGB(0, 255, 0), RGB(0, 0, 255), RGB(255, 0, 0)]
        #expect(CustomLightsConfig.customGradient(colors) == [RGB(0, 0, 255), RGB(255, 0, 0), RGB(0, 255, 0), RGB(255, 255, 255)])
        #expect(CustomLightsConfig.customGradient([]).isEmpty)
    }

    @Test func readsRGBAndColorSupport() {
        let light = EntityState(entityId: "light.demo_a", state: "on", attributes: [
            "rgb_color": .array([.number(10), .number(20), .number(30)]),
            "supported_color_modes": .array([.string("color_temp"), .string("xy")]),
        ])
        #expect(RGB(entity: light) == RGB(10, 20, 30))
        #expect(RGB(entity: nil) == nil)
        #expect(RGB(entity: EntityState(entityId: "light.demo_b", state: "on", attributes: ["rgb_color": .array([.number(1)])])) == nil)
        #expect(CustomLightsConfig.supportsColor(light))
        #expect(!CustomLightsConfig.supportsColor(EntityState(entityId: "light.demo_c", state: "on",
                                                              attributes: ["supported_color_modes": .array([.string("brightness")])])))
        #expect(RGB(0, 255, 0).luminance > RGB(255, 0, 0).luminance)
    }

    @Test func serviceCalls() {
        #expect(CustomLightsConfig.setManualControl(on: true).serviceData == ["entity_id": .string(CustomLightsConfig.manualControlEntityId)])
        #expect(CustomLightsConfig.setManualControl(on: false).service == "turn_off")
        let select = CustomLightsConfig.selectMode("Demo Mode")
        #expect(select.domain == "input_select" && select.service == "select_option")
        #expect(select.serviceData["option"] == .string("Demo Mode"))
        let reset = CustomLightsConfig.reset()
        #expect(reset.serviceData == ["entity_id": .string("light.demo_front_yard_1"), "color_temp_kelvin": .number(2000),
                                      "brightness": .number(255), "transition": .number(1)])
        let color = CustomLightsConfig.setColor(RGB(1, 2, 3), on: "light.demo_a")
        #expect(color.serviceData == ["entity_id": .string("light.demo_a"), "rgb_color": .array([.number(1), .number(2), .number(3)])])
    }
}

// MARK: - Sprinklers

/// Builds B-hyve fixture states.
enum SprinklerFixture {
    static var front: SprinklersConfig.Controller { SprinklersConfig.controllers[0] }
    static var back: SprinklersConfig.Controller { SprinklersConfig.controllers[1] }

    static func program(station: Int, days: [Double], times: [String], budget: Double = 100, minutes: Double = 20) -> [String: JSONValue] {
        [
            "frequency": .object(["type": .string("days"), "days": .array(days.map(JSONValue.number))]),
            "start_times": .array(times.map(JSONValue.string)),
            "budget": .number(budget),
            "run_times": .array([.object(["station": .number(Double(station)), "run_time": .number(minutes)])]),
            "friendly_name": .string("Program"),
        ]
    }

    /// A ready front yard controller.
    static func frontStates(valve: String = "closed") -> ([String: String], [String: [String: JSONValue]]) {
        let zone = front.zones[0]
        return ([
            front.stateEntityId: "auto", front.modeEntityId: "auto", front.batteryEntityId: "86",
            front.faultEntityId: "off", front.hubConnectedEntityId: "on",
            front.nextWateringEntityId: "2026-10-12T13:30:00+00:00",
            front.rainDelayEntityId: "off", front.smartWateringEntityId: "on",
            zone.valveEntityId: valve, zone.programEntityId: "on",
            zone.historyEntityId: "2026-10-10T13:30:00+00:00",
        ], [
            zone.valveEntityId: ["zone_name": .string("Front Yard"), "station": .number(1)],
            zone.programEntityId: program(station: 1, days: [1, 3, 5], times: ["06:30"]),
            zone.historyEntityId: ["start_time": .string("2026-10-10T13:30:00+00:00"), "run_time": .number(20)],
        ])
    }
}

@Suite(.demoHouse)
struct SprinklerSnapshotTests {
    typealias F = SprinklerFixture

    func snapshot(_ config: SprinklersConfig.Controller, _ states: [String: String], _ attributes: [String: [String: JSONValue]] = [:]) -> SprinklerSnapshot {
        SprinklerSnapshot(config: config) { id in
            states[id].map { EntityState(entityId: id, state: $0, attributes: attributes[id] ?? [:]) }
        }
    }

    @Test func readyController() {
        let (states, attributes) = F.frontStates()
        let shot = snapshot(F.front, states, attributes)
        #expect(shot.available && shot.status == .ready && !shot.watering)
        #expect(shot.mode == "auto")
        #expect(shot.batteryPercent == 86 && !shot.batteryLow)
        #expect(shot.hubConnected && shot.smartWatering && !shot.rainDelay)
        #expect(shot.nextStart == SprinklerSnapshot.date("2026-10-12T13:30:00+00:00"))
        #expect(shot.zones.first?.name == "Front Yard")
        let program = shot.zones[0].program
        #expect(program.days == [1, 3, 5] && program.startTimes == ["06:30"] && program.budget == 100)
        #expect(program.runTimeMinutes == 20 && program.enabled && program.available && program.name == "Program")
        #expect(shot.lastRun.runTimeMinutes == 20)
    }

    @Test func wateringFaultAndUnavailable() {
        var (states, attributes) = F.frontStates(valve: "open")
        #expect(snapshot(F.front, states, attributes).status == .watering)
        #expect(snapshot(F.front, states, attributes).activeValveEntityId == F.front.zones[0].valveEntityId)
        states[F.front.faultEntityId] = "on"
        #expect(snapshot(F.front, states, attributes).status == .fault, "Fault outranks watering")
        states[F.front.zones[0].valveEntityId] = "unavailable"
        let off = snapshot(F.front, states, attributes)
        #expect(off.status == .unavailable && !off.fault && !off.smartWatering, "No zone available: the controller is unavailable")
        #expect(snapshot(F.front, [:]).status == .unavailable)
        #expect(snapshot(F.front, [:]).mode == "unavailable")
    }

    @Test func modeFallsBackToTheControllerStateAndBatteryWarns() {
        var (states, attributes) = F.frontStates()
        states[F.front.modeEntityId] = "unavailable"
        states[F.front.stateEntityId] = "off"
        states[F.front.batteryEntityId] = "20"
        states[F.front.nextWateringEntityId] = "unknown"
        let shot = snapshot(F.front, states, attributes)
        #expect(shot.mode == "off")
        #expect(shot.batteryLow, "20% is low (web: <= 20)")
        #expect(shot.nextStartUnknown && shot.nextStart == nil)
    }

    @Test func zonesMatchProgramsByStationAndKeepTheLatestRun() {
        let back = F.back
        var states: [String: String] = [back.stateEntityId: "auto", back.modeEntityId: "auto"]
        var attributes: [String: [String: JSONValue]] = [:]
        for (index, zone) in back.zones.enumerated() {
            states[zone.valveEntityId] = "closed"
            // Valve stations run 4, 3, 2, 1; programs list stations 1...4, so each zone takes the reversed program.
            attributes[zone.valveEntityId] = ["station": .number(Double(4 - index)), "friendly_name": .string("Zone \(index)")]
            states[zone.programEntityId] = "on"
            attributes[zone.programEntityId] = F.program(station: index + 1, days: [Double(index)], times: [])
        }
        states[back.zones[2].historyEntityId] = "2026-10-11T15:00:00.123+00:00"
        states[back.zones[0].historyEntityId] = "2026-10-11T12:00:00+00:00"
        let shot = snapshot(back, states, attributes)
        #expect(shot.zones.map { $0.program.days } == [[3], [2], [1], [0]])
        #expect(shot.zones.first?.name == "Zone 0", "friendly_name when no zone_name")
        #expect(shot.lastRun.startTime == SprinklerSnapshot.date("2026-10-11T15:00:00.123+00:00"))
        #expect(SprinklerSnapshot.date("not a date") == nil && SprinklerSnapshot.date(nil) == nil)
    }

    @Test func missingProgramFallsBackToDefaults() {
        let shot = snapshot(F.front, [F.front.stateEntityId: "auto", F.front.zones[0].valveEntityId: "closed"])
        let program = shot.zones[0].program
        #expect(!program.available && program.budget == 100 && program.days.isEmpty && program.runTimeMinutes == nil)
        #expect(shot.zones[0].name == F.front.zones[0].valveEntityId)
        #expect(SprinklerSnapshot.entityIds(F.back).count == 8 + 4 * 3)
    }
}

@MainActor
@Suite(.demoHouse)
struct SprinklerControllerTests {
    typealias F = SprinklerFixture

    func make(valve: String = "closed") -> (SprinklerController, EntityStore, RecordingCaller, ManualScheduler) {
        let (states, attributes) = F.frontStates(valve: valve)
        let store = makeStore(states, attributes: attributes)
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        return (SprinklerController(config: F.front, store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    @Test func startWateringShowsTheValveAtOnceThenConfirms() async {
        let (controller, store, caller, _) = make()
        #expect(controller.canStartWatering && !controller.isWatering)
        let ok = await controller.startWatering(zone: 0, minutes: 15)
        #expect(ok)
        #expect(caller.calls == [.init(domain: "bhyve", service: "start_watering",
                                       data: ["entity_id": "valve.demo_front_yard_zone_item_1", "minutes": "15"])])
        #expect(controller.isWatering && !controller.canStartWatering)
        set(store, F.front.zones[0].valveEntityId, "open")
        controller.liveDidChange()
        #expect(controller.overlay.pending.isEmpty, "Confirmed")
        #expect(controller.isWatering)
    }

    @Test func failedCallsRevertAndReport() async {
        let (controller, _, caller, _) = make()
        caller.failNext = true
        let ok = await controller.startWatering(zone: 0, minutes: 5)
        #expect(!ok && !controller.isWatering)
        #expect(controller.errorMessage != nil)
        controller.clearError()
        #expect(controller.errorMessage == nil)
        #expect(await controller.startWatering(zone: 9, minutes: 5) == false)
    }

    @Test func optimisticValuesRevertAfterTenSeconds() async {
        let (controller, _, _, scheduler) = make()
        controller.setRainDelay(true)
        await controller.waitForCalls()
        #expect(controller.rainDelay)
        #expect(scheduler.pending.first?.delay == .seconds(10))
        scheduler.fireAll()
        #expect(!controller.rainDelay)
    }

    @Test func stopTargetsTheRunningValve() async {
        let (controller, _, caller, _) = make(valve: "open")
        controller.stopWatering()
        await controller.waitForCalls()
        #expect(caller.calls.map(\.service) == ["stop_watering"])
        #expect(caller.calls.first?.data["entity_id"] == "valve.demo_front_yard_zone_item_1")
        #expect(!controller.isWatering, "Shows stopped at once")
    }

    @Test func switchesAndPrograms() async {
        let (controller, _, caller, _) = make()
        controller.setSmartWatering(false)
        controller.setProgramEnabled(zone: 0, false)
        controller.startProgram(zone: 0)
        await controller.waitForCalls()
        #expect(caller.calls.map { "\($0.domain).\($0.service) \($0.data["entity_id"] ?? "")" } == [
            "switch.turn_off switch.demo_front_yard_2",
            "switch.turn_off switch.demo_front_yard_program_1",
            "bhyve.start_program switch.demo_front_yard_program_1",
        ])
        #expect(!controller.smartWatering)
        #expect(controller.program(0)?.enabled == false)
        #expect(controller.program(3) == nil)
    }

    @Test func saveScheduleSendsTheProgramAndShowsItAtOnce() async {
        let (controller, _, caller, _) = make()
        let ok = await controller.saveSchedule(zone: 0, days: [5, 0], startTimes: ["07:00", "", "19:30"], budget: 85)
        #expect(ok)
        let data = caller.raw.first ?? [:]
        #expect(caller.calls.first?.service == "update_program")
        #expect(data["budget"] as? Int == 85)
        #expect(data["start_times"] as? [String] == ["07:00", "19:30"])
        let frequency = data["frequency"] as? [String: any Sendable]
        #expect(frequency?["days"] as? [Int] == [0, 5])
        #expect(frequency?["type"] as? String == "days")
        let shown = controller.program(0)
        #expect(shown?.days == [0, 5] && shown?.startTimes == ["07:00", "19:30"] && shown?.budget == 85)
    }

    @Test func valueKeysRoundTrip() {
        #expect(SprinklerController.days(SprinklerController.dayKey([1, 3])) == [1, 3])
        #expect(SprinklerController.days("").isEmpty)
        #expect(SprinklerController.times(SprinklerController.timeKey(["06:00", "07:00"])) == ["06:00", "07:00"])
        #expect(SprinklerController.times("").isEmpty)
        #expect(SprinklerController.message(for: RecordingCaller.Failure()).isEmpty == false)
    }
}

@Suite(.demoHouse)
struct SprinklerFormatTests {
    /// en_US in UTC, with ICU's narrow no-break spaces ("1:30\u{202F}PM") written as plain spaces.
    struct Plain {
        let base = SprinklerFormat(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
        func clean(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ") }
        func status(_ shot: SprinklerSnapshot) -> String { clean(base.status(shot)) }
        func nextStart(_ shot: SprinklerSnapshot) -> String { clean(base.nextStart(shot)) }
        func subtitle(_ shot: SprinklerSnapshot) -> String { clean(base.subtitle(shot)) }
        func battery(_ shot: SprinklerSnapshot) -> String { clean(base.battery(shot)) }
        func lastStart(_ run: SprinklerSnapshot.LastRun) -> String { clean(base.lastStart(run)) }
        func summary(_ program: SprinklerSnapshot.Program) -> String { clean(base.summary(program)) }
        func details(_ program: SprinklerSnapshot.Program, zone: String) -> String { base.details(program, zone: zone) }
        func programName(zone: String) -> String { base.programName(zone: zone) }
        func days(_ days: [Int]) -> String { base.days(days) }
        func minutes(_ value: Double) -> String { base.minutes(value) }
        func clock(_ text: String) -> String { clean(base.clock(text)) }
    }

    let format = Plain()
    typealias F = SprinklerFixture

    func snapshot(_ states: [String: String], _ attributes: [String: [String: JSONValue]]) -> SprinklerSnapshot {
        SprinklerSnapshot(config: F.front) { id in states[id].map { EntityState(entityId: id, state: $0, attributes: attributes[id] ?? [:]) } }
    }

    @Test func controllerText() {
        let (states, attributes) = F.frontStates()
        let shot = snapshot(states, attributes)
        #expect(format.status(shot) == "Auto")
        #expect(format.nextStart(shot) == "1:30 PM")
        #expect(format.subtitle(shot) == "Auto · Next 1:30 PM")
        #expect(format.battery(shot) == "86%")
        #expect(format.lastStart(shot.lastRun) == "1:30 PM")
        #expect(format.lastStart(SprinklerSnapshot.LastRun.none) == "No history")
        let off = snapshot([:], [:])
        #expect(format.status(off) == "Unavailable" && format.subtitle(off) == "Unavailable")
        #expect(format.nextStart(off) == "Unavailable" && format.battery(off) == "Unavailable")
        var watering = states
        watering[F.front.zones[0].valveEntityId] = "open"
        #expect(format.status(snapshot(watering, attributes)) == "Watering")
        watering[F.front.faultEntityId] = "on"
        #expect(format.status(snapshot(watering, attributes)) == "Fault")
        var unscheduled = states
        unscheduled[F.front.nextWateringEntityId] = "unavailable"
        #expect(format.nextStart(snapshot(unscheduled, attributes)) == "Not scheduled")
        unscheduled[F.front.nextWateringEntityId] = "unknown"
        #expect(format.nextStart(snapshot(unscheduled, attributes)) == "Unknown")
    }

    @Test func programText() {
        let (states, attributes) = F.frontStates()
        let program = snapshot(states, attributes).zones[0].program
        #expect(format.summary(program) == "Monday, Wednesday, and Friday · 6:30 AM")
        #expect(format.details(program, zone: "Front Yard") == "Front Yard · 20 min · 100%")
        #expect(format.programName(zone: "Bushes") == "Bushes schedule")
        #expect(format.days(Array(0...6)) == "Every day")
        var empty = program
        empty.days = []
        empty.startTimes = []
        #expect(format.summary(empty) == "Unavailable · Unavailable")
        #expect(format.minutes(12.5) == "12.5 min" && format.minutes(15) == "15 min")
    }

    @Test func clockConversions() {
        let utc = TimeZone(identifier: "UTC")!
        let date = SprinklerFormat.date(clock: "19:05", timeZone: utc)
        #expect(date != nil)
        #expect(date.map { SprinklerFormat.clock(from: $0, timeZone: utc) } == "19:05")
        #expect(SprinklerFormat.date(clock: "25:00") == nil && SprinklerFormat.date(clock: "7") == nil)
        #expect(format.clock("07:00") == "7:00 AM")
        #expect(format.clock("later") == "later")
    }

    @Test func pageConfig() {
        #expect(SprinklersConfig.controllers.map(\.title) == ["Front Yard", "Garden Faucet"])
        #expect(SprinklersConfig.controllers[1].zones.count == 4)
        let stop = SprinklersConfig.stopWatering(valve: "valve.demo_x")
        #expect(stop.target == nil && stop.serviceData == ["entity_id": .string("valve.demo_x")])
        #expect(SprinklersConfig.setSwitch("switch.demo_x", on: true).serviceData == ["entity_id": .string("switch.demo_x")])
    }
}
