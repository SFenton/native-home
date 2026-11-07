import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Room pages: config parity with the web, the room grid's ranking, state text, and what each card shows, opens
/// and sends.
@MainActor
@Suite(.demoHouse)
struct RoomsTests {
    func controller(_ id: String, _ states: [String: String], attributes: [String: [String: JSONValue]] = [:])
        -> (RoomController, EntityStore, RecordingCaller, ManualScheduler)
    {
        let store = makeStore(states, attributes: attributes)
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        let page = RoomsConfig.page(id: id)!
        return (RoomController(page: page, store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    func card(_ page: String, _ title: String) -> RoomCard {
        RoomsConfig.page(id: page)!.allCards.first { $0.title == title }!
    }

    // MARK: Tones and sides

    @Test func everyCardKindHasATone() {
        let tones = Dictionary(uniqueKeysWithValues: RoomCardKind.allCases.map { ($0, $0.tone) })
        #expect(tones[.light] == .light && tones[.wakeLight] == .light)
        #expect(tones[.air] == .air && tones[.contact] == .contact && tones[.occupancy] == .presence)
        #expect(tones[.vacuum] == .vacuum && tones[.media] == .media && tones[.power] == .power)
        #expect(tones[.grill] == .warning && tones[.appliance] == .neutral && tones[.laundry] == .neutral)
        #expect(tones[.climate] == .climate && tones[.vent] == .climate && tones[.fan] == .climate && tones[.humidifier] == .climate)
    }

    @Test func residentsAreFoundByTheirHomeAssistantUserId() {
        #expect(HouseholdResident.forUserId(" \(HouseholdResident.resident1.haUserId.uppercased()) ") == .resident1)
        #expect(HouseholdResident.forUserId(HouseholdResident.resident2.haUserId) == .resident2)
        #expect(HouseholdResident.forUserId(nil) == nil && HouseholdResident.forUserId("  ") == nil && HouseholdResident.forUserId("x") == nil)
    }

    @Test func aSectionTakesAnExplicitSideOrNone() {
        #expect(RoomSection("A").foldSide == nil)
        #expect(RoomSection("B", foldSide: .trailing).foldSide == .trailing)
        #expect(RoomSectionSide(rawValue: "leading") == .leading)
    }

    // MARK: Config parity

    @Test func sixteenRoomsInWebOrderMatchTheRoomGrid() {
        #expect(RoomsConfig.pages.count == 16)
        #expect(Set(RoomsConfig.pages.map(\.id)) == Set(RoomNavigation.items.map(\.path)))
        #expect(RoomsConfig.pages.first?.id == "living-room")
        #expect(RoomsConfig.pages.last?.id == "entryway")
        for page in RoomsConfig.pages {
            #expect(RoomNavigation.item(for: page.id)?.title == page.title, "\(page.id)")
            #expect(Set(page.allCards.map(\.id)).count == page.allCards.count, "\(page.id) has duplicate card ids")
        }
    }

    @Test func everyRemoteAPageUsesExists() {
        for page in RoomsConfig.pages {
            for id in page.remoteIds { #expect(MediaRemotes.config(id: id) != nil, "\(page.id) → \(id)") }
        }
    }

    @Test func hiddenSectionsStayOffThePage() {
        let music = RoomsConfig.page(id: "studio")!
        #expect(music.sections.contains { $0.title == "Quick App Launch" })
        #expect(!music.visibleSections.contains { $0.title == "Quick App Launch" })
        #expect(music.optimisticRemoteId == "studio-remote")
    }

    @Test func roomsWithoutSectionsAreEmpty() {
        for id in ["hallway", "entryway"] { #expect(RoomsConfig.page(id: id)!.visibleSections.isEmpty) }
    }

    // MARK: Room grid ranking

    @Test func mostVisitedRoomsComeFirstAndTiesKeepConfigOrder() {
        let counts = ["counter.demo_kitchen_1": "12", "counter.demo_gym_1": "3.0", "counter.demo_office_1": "3"]
        let ranked = RoomNavigation.ranked { counts[$0] }.map(\.path)
        #expect(Array(ranked.prefix(3)) == ["kitchen", "gym", "office"])
        #expect(ranked[3] == "living-room")
        #expect(ranked.count == 16)
    }

    /// The grid re-ranks as Home Assistant's counters change: a visit counted by the script reaches the store through the
    /// websocket, and the next read puts that room first. Equal counts keep the configured order. The counters live in
    /// Home Assistant, so a cold launch from the disk snapshot ranks the same way.
    @Test func theGridReRanksAsVisitCountersChange() {
        let store = EntityStore()
        func counter(_ path: String, _ count: Int) -> EntityState {
            EntityState(entityId: RoomNavigation.item(for: path)!.accessCounterEntityId, state: String(count))
        }
        func ranked(_ store: EntityStore) -> [String] { RoomNavigation.ranked { store.entity($0).state?.state }.map(\.path) }
        #expect(ranked(store) == RoomNavigation.items.map(\.path), "No counters: configured order")
        store.replaceAll([counter("gym", 4), counter("office", 4), counter("kitchen", 1)])
        #expect(Array(ranked(store).prefix(3)) == ["gym", "office", "kitchen"])
        store.apply([counter("kitchen", 5)])
        #expect(Array(ranked(store).prefix(3)) == ["kitchen", "gym", "office"])
        store.apply([counter("office", 6)])
        #expect(Array(ranked(store).prefix(3)) == ["office", "kitchen", "gym"])
        let restored = EntityStore()
        restored.replaceAll(Array(store.allValues.values), freshness: .snapshot(savedAt: Date()))
        #expect(ranked(restored) == ranked(store))
    }

    @Test func unreadableCountersCountAsZero() {
        #expect(RoomNavigation.accessCount(nil) == 0)
        #expect(RoomNavigation.accessCount("unavailable") == 0)
        #expect(RoomNavigation.accessCount("-2") == 0)
        #expect(RoomNavigation.accessCount("7") == 7)
    }

    @Test func openingARoomCountsTheVisit() async {
        let caller = RecordingCaller()
        let item = RoomNavigation.item(for: "studio")!
        #expect(item.accessCounterEntityId == "counter.demo_studio_1")
        try? await caller.call(RoomNavigation.accessIncrementCall(for: item))
        #expect(caller.calls.first?.domain == "script")
        #expect(caller.calls.first?.service == "turn_on")
        #expect(caller.calls.first?.data["entity_id"] == "script.demo_script_2")
        #expect(caller.calls.first?.data["variables"]?.contains("studio") == true)
    }

    // MARK: Quick Links

    @Test func sprinklersShowOnlyWhenEnabled() {
        #expect(!QuickLinks.visible { _ in "off" }.contains { $0.id == "sprinklers" })
        #expect(QuickLinks.visible { $0 == SprinklersConfig.visibilityEntityId ? "on" : nil }.contains { $0.id == "sprinklers" })
        #expect(QuickLinks.visible { _ in nil }.count == 6)
    }

    @Test func foodSubtitleUsesTheTotalElseTheSpaces() {
        #expect(QuickLinks.allFoodSubtitle { [QuickLinks.totalItemsEntityId: "12", QuickLinks.expiringSoonEntityId: "2"][$0] }
            == "12 Items • 2 Expiring Soon")
        let spaces = Dictionary(uniqueKeysWithValues: QuickLinks.foodSpaceEntityIds.map { ($0, "1") })
        #expect(QuickLinks.allFoodSubtitle { spaces[$0] } == "\(QuickLinks.foodSpaceEntityIds.count) \(QuickLinks.foodSpaceEntityIds.count == 1 ? "Item" : "Items") • 0 Expiring Soon")
        #expect(QuickLinks.allFoodSubtitle { _ in nil } == "0 Items • 0 Expiring Soon")
    }

    @Test func securityLooksFollowTheAlarm() {
        #expect(QuickLinks.securityAppearance("armed_away").icon == "mdi:shield")
        #expect(QuickLinks.securityAppearance("disarmed").icon == "mdi:shield-off")
        #expect(QuickLinks.securityAppearance("triggered").icon == "mdi:shield-alert")
    }

    @Test func groceriesSubtitleCountsItems() {
        #expect(RoomsConfig.Groceries.subtitle(count: "0") == "No groceries listed")
        #expect(RoomsConfig.Groceries.subtitle(count: "1") == "1 item")
        #expect(RoomsConfig.Groceries.subtitle(count: "4") == "4 items")
        #expect(RoomsConfig.Groceries.subtitle(count: nil) == "No groceries listed")
    }

    // MARK: Formatting

    @Test func compactStatesMatchTheWeb() {
        #expect(RoomFormat.compact(nil) == "Unavailable")
        #expect(RoomFormat.compact(EntityState(entityId: "binary_sensor.contact_test_front", state: "on")) == "Open")
        #expect(RoomFormat.compact(EntityState(entityId: "binary_sensor.demo_motion", state: "off")) == "Clear")
        #expect(RoomFormat.compact(EntityState(entityId: "light.demo_kitchen_item_1", state: "on")) == "On")
        #expect(RoomFormat.compact(EntityState(entityId: "sensor.demo_temp", state: "71.2")) == "71.2")
        // A status word is title-cased; a time, a range and a unit are left alone.
        #expect(RoomFormat.compact(EntityState(entityId: "sensor.demo_bedroom_1_light_1", state: "scheduled")) == "Scheduled")
        #expect(RoomFormat.compact(EntityState(entityId: "sensor.demo_bedroom_1_light_1", state: "6:45 AM")) == "6:45 AM")
        #expect(RoomFormat.compact(EntityState(entityId: "input_text.demo_input_text_2", state: "21-34")) == "21-34")
        #expect(RoomFormat.compact(EntityState(entityId: "vacuum.demo_x", state: "returning")) == "Returning")
    }

    @Test func occupancyAndContactWords() {
        #expect(RoomFormat.occupancy(EntityState(entityId: "binary_sensor.demo_a", state: "on")) == "Detected")
        #expect(RoomFormat.occupancy(EntityState(entityId: "binary_sensor.demo_a", state: "off")) == "Clear")
        #expect(RoomFormat.contact(EntityState(entityId: "binary_sensor.demo_a", state: "on")) == "Open")
        #expect(RoomFormat.contact(EntityState(entityId: "binary_sensor.demo_a", state: "off")) == "Closed")
        #expect(RoomFormat.contact(EntityState(entityId: "binary_sensor.demo_a", state: "unknown")) == "Unknown")
    }

    @Test(.demoHouse) func unitsAndAirSummaries() {
        let humidity = EntityState(entityId: "sensor.demo_h", state: "45", attributes: ["unit_of_measurement": .string("%")])
        #expect(RoomFormat.withUnit(humidity) == "45%")
        #expect(RoomFormat.aqiEntityId(forPM25: "sensor.demo_office_1") == "sensor.demo_office_1_air_quality_index")
        let pm = EntityState(entityId: "sensor.demo_p", state: "12", attributes: ["unit_of_measurement": .string("µg/m³")])
        let aqi = EntityState(entityId: "sensor.demo_q", state: "40.0")
        #expect(RoomFormat.airSummary(aqi: aqi, pm25: pm) == "40 • 12 µg/m³")
        // Both sensors dead (or never loaded): one word, not "Unavailable • Unavailable" read like a measurement.
        let dead = EntityState(entityId: "sensor.demo_d", state: "unavailable")
        #expect(RoomFormat.airSummary(aqi: dead, pm25: dead) == "Unavailable")
        #expect(RoomFormat.airSummary(aqi: nil, pm25: nil) == "Unavailable")
        #expect(RoomFormat.airSummary(aqi: dead, pm25: pm) == "Unavailable • 12 µg/m³", "one live sensor still reads")
        #expect(RoomFormat.temperature(EntityState(entityId: "sensor.demo_t", state: "70", attributes: ["unit_of_measurement": .string("°F")])) == "70°F")
    }

    @Test func contactSummariesNameWhatIsOpen() {
        let group = RoomGroup("Test", entityId: "binary_sensor.test", [
            RoomGroupItem("Front Door", "binary_sensor.demo_front"),
            RoomGroupItem("Back Door", "binary_sensor.demo_back"),
            RoomGroupItem("Window", "binary_sensor.demo_window"),
        ])
        func summary(_ open: Set<String>) -> String {
            RoomFormat.contactSummary(group) { EntityState(entityId: $0, state: open.contains($0) ? "on" : "off") }
        }
        #expect(summary([]) == "All Closed")
        #expect(summary(["binary_sensor.demo_front"]) == "1 Door Open")
        #expect(summary(["binary_sensor.demo_front", "binary_sensor.demo_back"]) == "All Doors Open")
        #expect(summary(["binary_sensor.demo_window", "binary_sensor.demo_front"]) == "Window Open, 1 Door Open")
    }

    // MARK: Cards

    @Test func lightCardsDimWhileOff() {
        let (room, store, _, _) = controller("kitchen", ["light.demo_kitchen_item_1": "off"])
        let lights = card("kitchen", "Lights")
        #expect(room.display(lights).isOff)
        #expect(room.display(lights).subtitle == "Off")
        #expect(room.display(lights).semantics == .modal)
        set(store, "light.demo_kitchen_item_1", "on")
        #expect(!room.display(lights).isOff)
    }

    @Test func unavailableCardsAreDisabled() {
        let (room, _, caller, _) = controller("guest-bathroom", [:])
        let towel = card("guest-bathroom", "Towel Rack")
        let display = room.display(towel)
        #expect(display.isUnavailable)
        #expect(!display.isEnabled)
        #expect(room.tap(towel) == .none)
        #expect(caller.calls.isEmpty)
    }

    @Test func flipShowsTheNewStateAtOnceAndRollsBackOnFailure() async {
        let id = "switch.demo_switch_2"
        let (room, _, caller, scheduler) = controller("guest-bathroom", [id: "off"])
        let towel = card("guest-bathroom", "Towel Rack")
        #expect(room.tap(towel) == .ran)
        #expect(room.display(towel).semantics == .toggle(isOn: true), "Optimistic on before Home Assistant answers")
        #expect(room.displayedState(id) == "on")
        await room.waitForCalls()
        scheduler.fireAll()
        #expect(room.displayedState(id) == "off", "Gives way to live state when never confirmed")

        caller.failNext = true
        #expect(room.tap(towel) == .ran)
        #expect(room.displayedState(id) == "on")
        await room.waitForCalls()
        #expect(room.displayedState(id) == "off", "A failed call rolls back without waiting for the timer")
        #expect(room.isFailed(towel), "and the tile shows its failed face")
        scheduler.fireAll()
        #expect(!room.isFailed(towel))
    }

    @Test func flipFollowsALiveRevert() async {
        let id = "switch.demo_switch_2"
        let (room, store, _, _) = controller("guest-bathroom", [id: "off"])
        room.tap(card("guest-bathroom", "Towel Rack"))
        await room.waitForCalls()
        // Something else turned it back off: any live change clears the optimistic value.
        set(store, id, "unavailable")
        for _ in 0..<5 { await Task.yield() }
        #expect(room.displayedState(id) == "unavailable")
    }

    @Test func towelRackUsesExplicitTurnOnAndOff() async {
        let id = "switch.demo_switch_2"
        let (room, store, caller, _) = controller("guest-bathroom", [id: "off"])
        let towel = card("guest-bathroom", "Towel Rack")
        #expect(room.display(towel).semantics == .toggle(isOn: false))
        #expect(room.tap(towel) == .ran)
        await room.waitForCalls()
        set(store, id, "on")
        #expect(room.display(towel).background == towel.stateColors["on"])
        #expect(room.tap(towel) == .ran)
        await room.waitForCalls()
        #expect(caller.calls.map(\.service) == ["turn_on", "turn_off"])
        #expect(caller.calls.allSatisfy { $0.domain == "switch" && $0.data["entity_id"] == id })
    }

    @Test func pcCardsPressTheMatchingButton() async {
        let (room, store, caller, _) = controller("office", ["input_boolean.demo_power_2": "off", "input_text.demo_power_1": "Off"])
        let pc = card("office", "Alex's PC")
        #expect(room.display(pc).subtitle == "Off")
        room.tap(pc)
        await room.waitForCalls()
        set(store, "input_boolean.demo_power_2", "on")
        room.tap(pc)
        await room.waitForCalls()
        #expect(caller.calls.map(\.data["entity_id"]) == ["input_button.demo_input_button_8", "input_button.demo_input_button_7"])
    }

    @Test func personalTitlesFollowTheViewer() {
        let (room, _, _, _) = controller("office", [:])
        let pc = card("office", "Alex's PC")
        #expect(room.display(pc, viewer: .resident1).title == "Your PC")
        #expect(room.display(pc, viewer: .resident2).title.hasSuffix("'s PC"), "Another viewer sees the owner's name")
        #expect(room.display(pc).title.hasSuffix("'s PC"))
        let bed = card("bedroom-1", "Sam's Bed")
        #expect(bed.title(for: .resident2) == "Your Side")
        #expect(bed.title(for: .resident1) == "\(Resident.resident2.name)'s Side")
    }

    @Test func bedsTakeTheirClimateActionWash() {
        let id = "climate.demo_climate_1"
        let (room, _, _, _) = controller("bedroom-1", [id: "heat_cool"], attributes: [id: ["hvac_action": .string("heating")]])
        #expect(room.display(card("bedroom-1", "Alex's Bed")).background == RoomColor(136, 64, 26, opacity: 0.6))
    }

    @Test func musicRoomSourcesShareTheRemotesOptimisticState() async {
        typealias M = MediaRemotes.MusicRoom
        let (room, _, caller, _) = controller("studio", [M.controlEntityId: "on", M.activeMediaSourceEntityId: M.Source.server])
        let xbox = card("studio", "Game Console")
        #expect(room.display(xbox).semantics == .selection(isSelected: false))
        #expect(room.tap(xbox) == .ran)
        await room.waitForCalls()
        #expect(!caller.calls.isEmpty)
        #expect(room.remote("studio-remote") != nil)
    }

    // MARK: Chips

    @Test func occupancyChipSwapsItsIcon() {
        let (room, store, _, _) = controller("kitchen", [:])
        let occupancy = RoomsConfig.page(id: "kitchen")!.overviewCards.first { $0.kind == .occupancy }!
        set(store, occupancy.entityId, "off")
        #expect(room.chip(occupancy).summary == "Clear")
        #expect(room.chip(occupancy).icon == "mdi:motion-sensor-off")
        set(store, occupancy.entityId, "on")
        #expect(room.chip(occupancy).summary == "Detected")
        #expect(room.chip(occupancy).isActive)
    }

    @Test func pluralContactChipsReadAllClosed() {
        let (room, store, _, _) = controller("garage", ["binary_sensor.demo_garage_1": "off"])
        let doors = card("garage", "Doors")
        #expect(room.chip(doors).summary == "All Closed")
        set(store, "binary_sensor.demo_garage_1", "on")
        #expect(room.chip(doors).summary == "Open")
        #expect(room.chip(doors).icon == "mdi:door-open")
    }

    /// Owner, 2026-10-16: a contact chip says whether the house is closed, open with someone home, open while away, or open
    /// while the system is armed; the alarm outranks being away.
    @Test func roomContactChipsFollowTheHouse() {
        let (room, store, _, _) = controller("garage", ["binary_sensor.demo_garage_1": "off"])
        let doors = card("garage", "Doors")
        #expect(room.chip(doors).contact == .allClosed)
        set(store, "binary_sensor.demo_garage_1", "on")
        #expect(room.chip(doors).contact == .openHome)
        set(store, ClimateConfig.homeAwayEntityId, "Away")
        #expect(room.chip(doors).contact == .openAway)
        set(store, SecurityConfig.alarmEntityId, "armed_night")
        #expect(room.chip(doors).contact == .openArmed)
        set(store, SecurityConfig.alarmEntityId, "disarmed")
        set(store, ClimateConfig.homeAwayEntityId, "Home")
        #expect(room.chip(doors).contact == .openHome)
        set(store, "binary_sensor.demo_garage_1", "unavailable")
        #expect(room.chip(doors).contact == .unavailable)
        #expect(room.chip(card("garage", "Doors")).webColor == nil)
    }

    @Test(.demoHouse) func roomClimateAndAirChipsCarryTheWebColour() {
        // The colour helpers are named from the range / PM2.5 helper (`_climate_range` to `_climate_color`), so the cards here
        // use ids shaped that way.
        let (room, store, _, _) = controller("living-room", [:])
        let climate = RoomCard("Climate", "input_text.demo_room_climate_range", icon: "mdi:thermometer", kind: .climate)
        let air = RoomCard("Air Quality", RoomOverview.airQualityRooms[0].pm25EntityId, icon: "mdi:air-purifier", kind: .air)
        let lights = card("living-room", "Lights")
        #expect(room.chip(climate).webColor == nil, "No helper and no range: the family navy")
        set(store, climate.entityId, "70.0°F - 74.0°F")
        #expect(room.chip(climate).webColor == RoomOverview.colorFromTemperature(72), "The gradient at the range's mean")
        set(store, "input_text.demo_room_climate_color", "rgba(158, 209, 46, 1)")
        #expect(room.chip(climate).webColor == RoomColor(158, 209, 46), "The helper wins")
        #expect(room.chip(air).webColor == ChipWebColor.airTeal, "No AQI helper yet: the web teal")
        set(store, ChipWebColor.airColorEntityId(forPM25: air.entityId)!, "rgba(255, 190, 0, 1)")
        #expect(room.chip(air).webColor == RoomColor(255, 190, 0))
        #expect(room.chip(lights).webColor == nil)
    }

    // MARK: Sheets

    @Test(.demoHouse) func sheetsRouteByKind() {
        let (living, _, _, _) = controller("living-room", [:])
        let page = RoomsConfig.page(id: "living-room")!
        func sheet(_ title: String) -> RoomSheetContent { living.sheet(for: page.allCards.first { $0.title == title }!) }
        #expect(sheet("Living Room Remote") == .mediaRemote(id: "living-room-streamer"))
        if case .lights = sheet("Lights") {} else { Issue.record("Lights sheet") }
        if case .occupancy = sheet("Occupancy") {} else { Issue.record("Occupancy sheet") }
        if case .items = sheet("Vents") {} else { Issue.record("Vents sheet") }
        #expect(sheet("Main Floor") == .device(.vacuum(entityId: "vacuum.demo_vacuum_1")))
        #expect(sheet("Air Quality") == .device(.airQuality(pm25EntityId: "sensor.demo_living_room_1")))

        let (bedroom, _, _, _) = controller("bedroom-1", [:])
        #expect(bedroom.sheet(for: card("bedroom-1", "Alex's Bed"))
            == .device(.bed(sheet: "alexs-bed", climateEntityId: "climate.demo_climate_1")))
        #expect(bedroom.sheet(for: card("bedroom-1", "Humidifier")) == .device(.humidifier(powerEntityId: HumidifierConfig.all[0].powerEntityId)))
        #expect(bedroom.sheet(for: card("bedroom-1", RoomsConfig.WakeLight.title))
            == .device(.wakeLight(statusEntityId: MasterBedroom.wakeLight.statusEntityId)))

        let (bath, _, _, _) = controller("guest-bathroom", [:])
        #expect(bath.sheet(for: card("guest-bathroom", "Fan")) == .device(.bathroomFan(powerEntityId: BathroomFanConfig.all[0].powerEntityId)))
        #expect(bath.sheet(for: card("guest-bathroom", "Towel Rack")) == .fallback)
    }

    @Test func sheetTitlesAndSubtitles() {
        let (living, store, _, _) = controller("living-room", [:])
        #expect(living.sheetTitle(for: card("living-room", "Lights")) == "Living Room Lights")
        #expect(living.sheetTitle(for: card("living-room", "Main Floor")) == "Living Room: Robot Vacuum")
        #expect(living.sheetSubtitle(for: card("living-room", "Lights")) == nil)
        let occupancy = card("living-room", "Occupancy")
        #expect(living.sheetSubtitle(for: occupancy) == "Clear")
        if let first = RoomGroups.occupancy(room: "Living Room")?.items.first {
            set(store, first.entityId, "on")
            #expect(living.sheetSubtitle(for: occupancy) == "Occupied")
        }
    }

    @Test(.demoHouse) func deviceFallbacksListEveryEntityOnce() {
        let (living, _, _, _) = controller("living-room", [:])
        let purifier = card("living-room", "Air Purifier")
        #expect(living.fallbackEntityIds(for: purifier) == [
            "sensor.demo_living_room_1", RoomFormat.aqiEntityId(forPM25: "sensor.demo_living_room_1"),
            "select.demo_living_room_mode_1", "fan.demo_living_room_1",
        ])
    }

    @Test func roomsWithoutContactGroupsOpenEveryContact() {
        let (garage, _, _, _) = controller("garage", [:])
        let doors = card("garage", "Doors")
        let content = garage.sheet(for: doors)
        if RoomGroups.contacts(room: "Garage") == nil {
            #expect(content == .allContacts)
        } else if case .contacts = content {} else {
            Issue.record("Garage doors sheet")
        }
    }

    // MARK: Residents and visits

    @Test func residentsResolveFromTheSignedInUser() {
        for resident in HouseholdResident.allCases {
            #expect(HouseholdResident.forUserId(resident.haUserId) == resident)
            #expect(HouseholdResident.forUserId(" \(resident.haUserId.uppercased()) ") == resident)
        }
        #expect(HouseholdResident.forUserId(nil) == nil)
        #expect(HouseholdResident.forUserId("  ") == nil)
        #expect(HouseholdResident.forUserId("someone-else") == nil)
    }

    @Test(.demoHouse) func cardAndItemIdsAreUnique() {
        for page in RoomsConfig.pages {
            #expect(Set(page.allCards.map(\.id)).count == page.allCards.count, "\(page.id)")
        }
        let item = RoomModalItem("Vent 1", "cover.demo_living_room_vent_1", icon: "mdi:air-filter")
        #expect(item.id == "cover.demo_living_room_vent_1Vent 1")
    }

    @Test func sheetTilesSendExplicitCommands() async {
        let (room, _, caller, _) = controller("living-room", [:])
        room.send(LightControl.flip("light.demo_living_room_item_1", shownOn: true))
        await room.waitForCalls()
        #expect(caller.calls.map(\.service) == ["turn_off"])
        #expect(caller.calls.first?.data["entity_id"] == "light.demo_living_room_item_1")
    }

    @Test func openingARoomFromTheGridCountsAVisit() async {
        let caller = RecordingCaller()
        RoomController.recordVisit(RoomNavigation.item(for: "kitchen")!, caller: caller)
        for _ in 0..<200 where caller.calls.isEmpty { await Task.yield() }
        #expect(caller.calls.map { "\($0.domain).\($0.service)" } == ["script.turn_on"])
        #expect(caller.calls.first?.data["entity_id"] == RoomNavigation.accessIncrementScript)
        #expect(caller.calls.first?.data["variables"]?.contains("kitchen") == true)
    }

    @Test func aFailedVisitCountIsLoggedAndDoesNotSurface() async {
        let caller = RecordingCaller()
        caller.failNext = true
        RoomController.recordVisit(RoomNavigation.item(for: "kitchen")!, caller: caller)
        for _ in 0..<200 where caller.calls.isEmpty { await Task.yield() }
        #expect(caller.calls.count == 1)
    }

    @Test func accessCountsParseLikeTheWeb() {
        #expect(RoomNavigation.accessCount("7") == 7)
        #expect(RoomNavigation.accessCount("7.0") == 7)
        #expect(RoomNavigation.accessCount(" 4 ") == 4)
        #expect(RoomNavigation.accessCount("7.5") == 0)
        #expect(RoomNavigation.accessCount("-1") == 0)
        #expect(RoomNavigation.accessCount("unavailable") == 0)
        #expect(RoomNavigation.accessCount("") == 0)
        #expect(RoomNavigation.accessCount(nil) == 0)
    }

    // MARK: Formatting edge cases

    @Test func compactAndLabelStatesCoverEveryBranch() {
        func e(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
            EntityState(entityId: id, state: state, attributes: attributes)
        }
        #expect(RoomFormat.compact(e("sensor.demo_a", "unavailable")) == "Unavailable")
        #expect(RoomFormat.compact(e("binary_sensor.contact_test_front_door", "on")) == "Open")
        #expect(RoomFormat.compact(e("binary_sensor.contact_test_front_door", "off")) == "Closed")
        #expect(RoomFormat.compact(e("binary_sensor.demo_motion", "on")) == "Active")
        #expect(RoomFormat.compact(e("binary_sensor.demo_motion", "off")) == "Clear")
        #expect(RoomFormat.occupancy(e("binary_sensor.demo_motion", "unavailable")) == "Unavailable")
        #expect(RoomFormat.occupancy(e("binary_sensor.demo_motion", "unknown")) == "Unknown")
        #expect(RoomFormat.occupancy(e("binary_sensor.demo_motion", "paused")) == "Paused")
        #expect(RoomFormat.contact(e("binary_sensor.demo_door", "unavailable")) == "Unavailable")
        #expect(RoomFormat.contact(e("binary_sensor.demo_door", "unknown")) == "Unknown")
        #expect(RoomFormat.contact(e("binary_sensor.demo_door", "ajar")) == "Ajar")
        #expect(RoomFormat.isActive(e("alarm_control_panel.demo_home", "armed_away")))
        #expect(!RoomFormat.isActive(e("alarm_control_panel.demo_home", "disarmed")))
        #expect(RoomFormat.airMetric(e("sensor.demo_pm", "unavailable")) == "Unavailable")
        #expect(RoomFormat.airMetric(e("sensor.demo_pm", " ")) == " ")
        #expect(RoomFormat.temperature(e("sensor.demo_t", "unavailable")) == "Unavailable")
        #expect(RoomFormat.temperature(e("sensor.demo_t", "71.2", ["unit_of_measurement": .string("°F")])) == "71.2°F")
        #expect(RoomFormat.temperature(nil) == "Unavailable")
        #expect(RoomFormat.temperature(e("sensor.demo_t", "21")) == "21")
    }

    @Test func bedWashesFollowEveryClimateAction() {
        let bed = card("bedroom-1", "Alex's Bed")
        func wash(_ action: String?, state: String = "heat_cool", presence: String? = nil) -> RoomColor? {
            let attributes: [String: JSONValue] = action.map { ["hvac_action": .string($0)] } ?? [:]
            return RoomFormat.background(bed, EntityState(entityId: bed.entityId, state: state, attributes: attributes),
                                         presence: presence.map { EntityState(entityId: "binary_sensor.demo_bed_presence", state: $0) })
        }
        #expect(wash("cooling") == RoomColor(25, 84, 130, opacity: 0.6))
        #expect(wash("idle") == RoomColor(229, 57, 53, opacity: 0.6))
        #expect(wash(nil, state: "off", presence: "on") == RoomColor(0, 150, 136, opacity: 0.6))
        #expect(wash(nil, state: "off", presence: "off") == nil)
        #expect(RoomFormat.background(bed, nil, presence: nil) == nil)
    }
}
