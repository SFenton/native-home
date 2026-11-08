import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Batch d of the house-config flip: the media page and remotes, vacuums, sprinklers, chores, food, vacation and the
/// household settings read the loaded document and answer empty values without one. Every test scopes its own
/// ``HouseConfigSource`` so parallel suites never see its document.
@MainActor
struct HouseConfigFlipDTests {
    /// The demo house with every batch d value changed.
    private static func changedHouse() -> HouseConfig {
        var config = DemoHouse.config
        config.media.pageSections = Array(config.media.pageSections.dropFirst())
        config.media.remotes = Array(config.media.remotes.reversed())
        config.media.remoteIdByMediaPlayer = ["media_player.demo_demo": "demo-remote"]
        config.media.sourceSelect.entityIds["control"] = "media_player.demo_tv"
        config.media.sourceSelect.entityIds["activeMediaSource"] = "sensor.demo_source"
        config.media.sourceSelect.entityIds["syncPower"] = "switch.demo_sync"
        config.media.sourceSelect.syncHdmiStatusEntityIds = ["sensor.demo_hdmi"]
        config.media.sourceSelect.sources["tv"] = "Demo TV"
        config.media.sourceSelect.revertSeconds["sync"] = 3
        config.media.sourceSelect.activeHoldSeconds = 7
        config.media.sourceSelect.activeStates = ["on"]
        config.media.sourceSelect.linkedState = "demo-linked"
        config.vacuums.autoCleanControls = Array(config.vacuums.autoCleanControls.reversed())
        config.vacuums.vacuums = Array(config.vacuums.vacuums.dropFirst())
        config.vacuums.outcomeReconciliations = ["demo_map": [.init(roomId: "demo_room", entityId: "input_text.demo_demo")]]
        config.sprinklers.visibilityEntityId = "input_boolean.demo_sprinklers"
        config.sprinklers.lowBatteryPercent = 35
        config.sprinklers.defaultStartTime = "06:30"
        config.sprinklers.controllers = Array(config.sprinklers.controllers.dropFirst())
        config.chores.adminTodoEntityId = "todo.demo_admin"
        config.chores.groceryEntityId = "todo.demo_grocery"
        config.chores.adminTodoUploadPath = "/api/demo"
        config.chores.vacationEmptyDescription = "Demo vacation"
        config.chores.pages = Array(config.chores.pages.prefix(2))
        config.chores.quickLinks = [
            .init(title: "Demo Groceries", pageId: "groceries", tint: .init(red: 1, green: 2, blue: 3),
                  countsGroceries: true, resident: nil),
            .init(title: "Gone", pageId: "no-such-page", tint: .init(red: 0, green: 0, blue: 0), countsGroceries: false, resident: nil),
        ]
        config.food.expiringSoonEntityId = "sensor.demo_expiring"
        config.food.totalItemsEntityId = "sensor.demo_total"
        config.food.spaces = Array(config.food.spaces.prefix(1))
        config.food.allRecipesTint = .init(red: 9, green: 8, blue: 7)
        config.food.allFoodTint = .init(red: 6, green: 5, blue: 4)
        config.vacation.modeEntityId = "input_boolean.demo_vacation"
        config.vacation.invalidDatesPendingEntityId = "input_boolean.demo_invalid"
        config.vacation.startEntityId = "input_datetime.demo_start"
        config.vacation.endEntityId = "input_datetime.demo_end"
        config.vacation.checklist = Array(config.vacation.checklist.prefix(2))
        config.household.securityTiles = []
        config.household.relayControlEntityId = "input_boolean.demo_relay"
        config.household.relayTiles = [.init(title: "Demo Relay", entityId: "input_boolean.demo_relay", icon: "mdi:toggle-switch")]
        config.household.showSpecificTiles = []
        config.household.powerRecoveryAutomation = "automation.demo_power"
        config.household.presenceRooms = Array(config.household.presenceRooms.prefix(2))
        config.household.highAqiTile = .init(title: "Demo AQI", entityId: "input_boolean.demo_aqi", icon: "mdi:air-purifier")
        config.household.vehicleTiles = [.init(title: "Demo Car", entityId: "lock.demo_car", icon: "mdi:car")]
        return config
    }

    // MARK: - Without a document

    @Test func withoutADocumentEveryFlippedValueIsEmpty() {
        HouseConfigSource.$scoped.withValue(HouseConfigSource()) {
            #expect(MediaPageConfig.sections.isEmpty)
            #expect(MediaRemotes.all.isEmpty)
            #expect(MediaRemotes.remoteIdByMediaPlayer.isEmpty)
            #expect(MediaRemotes.sourceSelectRemote == .unconfigured)
            #expect(MediaRemotes.MusicRoom.controlEntityId.isEmpty)
            #expect(MediaRemotes.MusicRoom.Source.tv.isEmpty)
            #expect(MediaRemotes.MusicRoom.Revert.hueSync == .zero)
            #expect(MediaRemotes.MusicRoom.xboxActiveHold == .zero)
            #expect(MediaRemotes.MusicRoom.xboxActiveStates.isEmpty)
            #expect(Vacuums.all.isEmpty)
            #expect(Vacuums.autoCleanControls.isEmpty)
            #expect(Vacuums.outcomeReconciliations("any").isEmpty)
            #expect(SprinklersConfig.visibilityEntityId.isEmpty)
            #expect(SprinklersConfig.lowBatteryPercent == 0)
            #expect(SprinklersConfig.defaultStartTime.isEmpty)
            #expect(SprinklersConfig.controllers.isEmpty)
            #expect(ChoresConfig.adminTodoEntityId.isEmpty)
            #expect(ChoresConfig.groceryEntityId.isEmpty)
            #expect(ChoresConfig.vacationEmptyDescription.isEmpty)
            #expect(ChoresConfig.pages.isEmpty)
            #expect(ChoresConfig.quickLinks.isEmpty)
            #expect(ChoresConfig.people.isEmpty)
            #expect(ChoresConfig.groceries.lists.isEmpty && ChoresConfig.groceries.id == "groceries")
            #expect(FoodConfig.expiringSoonEntityId.isEmpty)
            #expect(FoodConfig.spaces.isEmpty)
            #expect(Vacation.modeEntityId.isEmpty)
            #expect(Vacation.checklist.isEmpty)
            #expect(HouseholdSettingsConfig.Admin.securityTiles.isEmpty)
            #expect(HouseholdSettingsConfig.Admin.presenceRooms.isEmpty)
            #expect(HouseholdSettingsConfig.SpecialDeviceModes.highAqiTile.entityId.isEmpty)
            #expect(HouseholdSettingsConfig.Vehicle.tiles.isEmpty)
        }
    }

    // MARK: - With a document

    @Test func aLoadedDocumentProvidesTheMediaValues() {
        let source = HouseConfigSource()
        let house = Self.changedHouse()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(MediaPageConfig.sections == house.media.pageSections)
            #expect(MediaPageConfig.sections.count == 2)
            #expect(MediaRemotes.all == house.media.remotes)
            #expect(MediaRemotes.config(id: MediaRemotes.sourceSelectRemoteId) == MediaRemotes.sourceSelectRemote)
            #expect(MediaRemotes.remoteIdByMediaPlayer == ["media_player.demo_demo": "demo-remote"])
            #expect(MediaRemotes.config(forMediaPlayer: "media_player.demo_demo") == nil)
            #expect(MediaRemotes.MusicRoom.controlEntityId == "media_player.demo_tv")
            #expect(MediaRemotes.MusicRoom.activeMediaSourceEntityId == "sensor.demo_source")
            #expect(MediaRemotes.MusicRoom.hueSyncPowerEntityId == "switch.demo_sync")
            #expect(MediaRemotes.MusicRoom.xboxEntityId == house.media.sourceSelect.entityIds["console"])
            #expect(MediaRemotes.MusicRoom.hueSyncHdmiStatusEntityIds == ["sensor.demo_hdmi"])
            #expect(MediaRemotes.MusicRoom.Source.tv == "Demo TV")
            #expect(MediaRemotes.MusicRoom.Source.xbox == house.media.sourceSelect.sources["console"])
            #expect(MediaRemotes.MusicRoom.Revert.hueSync == .seconds(3))
            #expect(MediaRemotes.MusicRoom.Revert.xbox == house.media.sourceSelect.revertSeconds["console"].map { .seconds($0) })
            #expect(MediaRemotes.MusicRoom.xboxActiveHold == .seconds(7))
            #expect(MediaRemotes.MusicRoom.xboxActiveStates == ["on"])
            #expect(MediaRemotes.MusicRoom.xboxLinkedState == "demo-linked")
            #expect(MediaRemotes.MusicRoom.mediaOptimisticEntityIds.first == "sensor.demo_source")
            #expect(SourceSelectActions.trackedEntityIds.first == "sensor.demo_source")
        }
    }

    @Test func aLoadedDocumentProvidesTheVacuumAndSprinklerValues() {
        let source = HouseConfigSource()
        let house = Self.changedHouse()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(Vacuums.all == house.vacuums.vacuums)
            #expect(Vacuums.autoCleanControls == house.vacuums.autoCleanControls)
            #expect(Vacuums.outcomeReconciliations("demo_map").map(\.entityId) == ["input_text.demo_demo"])
            #expect(Vacuums.outcomeReconciliations("another_map").isEmpty)
            #expect(SprinklersConfig.visibilityEntityId == "input_boolean.demo_sprinklers")
            #expect(SprinklersConfig.lowBatteryPercent == 35)
            #expect(SprinklersConfig.defaultStartTime == "06:30")
            #expect(SprinklersConfig.controllers == house.sprinklers.controllers)
            #expect(SprinklersConfig.controllers.count == 1)
        }
    }

    @Test func aLoadedDocumentProvidesTheChoresFoodAndVacationValues() {
        let source = HouseConfigSource()
        let house = Self.changedHouse()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(ChoresConfig.adminTodoEntityId == "todo.demo_admin")
            #expect(ChoresConfig.groceryEntityId == "todo.demo_grocery")
            #expect(ChoresConfig.adminTodoUploadPath == "/api/demo")
            #expect(ChoresConfig.vacationEmptyDescription == "Demo vacation")
            #expect(ChoresConfig.pages.count == 2)
            #expect(ChoresConfig.page("groceries")?.id == "groceries")
            #expect(ChoresConfig.page("to-do") == nil)
            #expect(ChoresConfig.quickLinks.map(\.title) == ["Demo Groceries"], "A link whose page is gone is dropped")
            #expect(ChoresConfig.quickLinks.first?.countsGroceries == true)
            #expect(ChoresConfig.quickLinks.first?.color.green == 2)
            #expect(ChoresConfig.vacationModeEntityId == "input_boolean.demo_vacation")
            #expect(ProfileSummary.Empty.vacation == "Demo vacation")
            #expect(FoodConfig.expiringSoonEntityId == "sensor.demo_expiring")
            #expect(FoodConfig.totalItemsEntityId == "sensor.demo_total")
            #expect(FoodConfig.spaces == house.food.spaces)
            #expect(FoodConfig.allRecipesTint.red == 9)
            #expect(FoodConfig.allFoodTint.blue == 4)
            #expect(Vacation.modeEntityId == "input_boolean.demo_vacation")
            #expect(Vacation.invalidDatesPendingEntityId == "input_boolean.demo_invalid")
            #expect(Vacation.startEntityId == "input_datetime.demo_start")
            #expect(Vacation.endEntityId == "input_datetime.demo_end")
            #expect(Vacation.checklist == house.vacation.checklist)
            #expect(Vacation.pageEntityIds.contains("input_boolean.demo_vacation"))
        }
    }

    @Test func aLoadedDocumentProvidesTheHouseholdValues() {
        let source = HouseConfigSource()
        let house = Self.changedHouse()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            typealias H = HouseholdSettingsConfig
            #expect(H.Admin.securityTiles.isEmpty)
            #expect(H.Admin.relayControlEntityId == "input_boolean.demo_relay")
            #expect(H.Admin.relayTiles == house.household.relayTiles)
            #expect(H.Admin.showSpecificTiles.isEmpty)
            #expect(H.Admin.powerRecoveryAutomation == "automation.demo_power")
            #expect(H.Admin.presenceRooms.count == 2)
            #expect(H.Admin.autoResetTiles.count == 2)
            #expect(H.SpecialDeviceModes.highAqiTile.entityId == "input_boolean.demo_aqi")
        }
    }

    // MARK: - Empty lists

    @Test func aDocumentWithEmptyListsNeverCrashesAndAnswersPlaceholdersWhereAValueIsNeeded() {
        var house = DemoHouse.config
        house.media.pageSections = []
        house.media.remotes = []
        house.vacuums.vacuums = []
        house.vacuums.autoCleanControls = []
        house.sprinklers.controllers = []
        house.chores.pages = []
        house.chores.quickLinks = []
        house.food.spaces = []
        house.vacation.checklist = []
        house.household.securityTiles = []
        house.household.presenceRooms = []
        let source = HouseConfigSource()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(MediaPageConfig.sections.isEmpty)
            #expect(MediaPageConfig.cards.isEmpty)
            #expect(MediaRemotes.all.isEmpty)
            #expect(MediaRemotes.config(id: MediaRemotes.sourceSelectRemoteId) == nil)
            #expect(MediaRemotes.sourceSelectRemote == .unconfigured, "A missing remote answers the unconfigured placeholder")
            #expect(Vacuums.all.isEmpty)
            #expect(Vacuums.config(entityId: "vacuum.demo_none") == nil)
            #expect(SprinklersConfig.controllers.isEmpty)
            #expect(ChoresConfig.page("chores") == nil)
            #expect(ChoresConfig.quickLinks.isEmpty)
            #expect(FoodConfig.spaces.isEmpty)
            #expect(Vacation.pageEntityIds.count == 4)
            #expect(HouseholdSettingsConfig.Admin.autoResetTiles.isEmpty)
            #expect(HouseholdTileActions.autoLockEntityId.isEmpty)
        }
    }

    // MARK: - Duplicates and frozen actions

    @Test func aDocumentThatMapsTwoSourceRolesToOneStateNeverCrashes() async {
        var house = DemoHouse.config
        let console = house.media.sourceSelect.sources["console"] ?? ""
        house.media.sourceSelect.sources["launcher"] = console
        var controls = house.vacuums.autoCleanControls
        controls.append(controls[0])
        house.vacuums.autoCleanControls = controls
        let source = HouseConfigSource()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(MediaRemotes.MusicRoom.Source.all.filter { $0 == console }.count == 1, "Each source appears once")
            #expect(MediaRemotes.MusicRoom.sourceLabels(active: console)[console] == "On")
            let controller = VacuumAutoCleanController(store: makeStore([:]), caller: RecordingCaller(), scheduler: ManualScheduler())
            #expect(controller.display(controls[0]).isUnavailable)
        }
    }

    @Test func thePowerRecoveryActionFollowsTheDocument() {
        var house = DemoHouse.config
        house.household.powerRecoveryAutomation = "automation.demo_power"
        let source = HouseConfigSource()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            let spec = CommandActions.powerRecovery.actions(for: EntityState(entityId: "automation.demo_power", state: "unavailable"))[0]
            #expect(spec.call?.target == "automation.demo_power")
            #expect(spec.phase == .unavailable, "Availability is read from the document's automation")
        }
        HouseConfigSource.$scoped.withValue(HouseConfigSource()) {
            #expect(CommandActions.powerRecovery.call.target == "")
        }
    }

    @Test func aChoresPageFromTheDocumentIsFoundByIdAndKeepsItsOwnList() {
        var house = DemoHouse.config
        house.chores.groceryEntityId = "todo.demo_grocery"
        if let index = house.chores.pages.firstIndex(where: { $0.id == "groceries" }) {
            house.chores.pages[index].lists = [.init(title: "Demo Grocery", entityId: "todo.demo_grocery")]
        }
        let source = HouseConfigSource()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(ChoresConfig.page("groceries")?.lists.map(\.entityId) == ["todo.demo_grocery"])
            #expect(ChoresConfig.groceries.lists.map(\.entityId) == ["todo.demo_grocery"])
        }
    }
}
