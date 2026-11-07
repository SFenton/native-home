import Foundation
@testable import HassCore
import Testing
import HassTestSupport

/// The pure logic behind the redesigned vacuum sheet (owner, 2026-10-28): which settings a mode shows, the status tiles,
/// the Rooms and Auto-Clean choice tiles and the command tiles. The views only draw what these say.
@MainActor
@Suite(.demoHouse)
struct VacuumSheetModelTests {
    let fixtures = VacuumControllerTests()

    // MARK: Mode and row visibility

    @Test(arguments: [
        ("vacuum", VacuumCleaningMode.vacuum), ("mop", .mop), ("vacuum_and_mop", .vacuumAndMop), ("Vacuum And Mop", .vacuumAndMop),
        ("Vacuum & Mop", .vacuumAndMop), (" MOP ", .mop), ("unavailable", .unknown), ("", .unknown),
    ])
    func modeReadsTheSelectOptions(option: String, expected: VacuumCleaningMode) {
        #expect(VacuumCleaningMode(option: option) == expected)
    }

    @Test func nilModeIsUnknownAndKeepsEverySetting() {
        let mode = VacuumCleaningMode(option: nil)
        #expect(mode == .unknown && mode.showsFan && mode.showsWater && mode.label == nil)
    }

    @Test func waterIsAbsentForVacuumOnlyAndFanForMopOnly() {
        #expect(VacuumCleaningMode.vacuum.showsFan && !VacuumCleaningMode.vacuum.showsWater)
        #expect(!VacuumCleaningMode.mop.showsFan && VacuumCleaningMode.mop.showsWater)
        #expect(VacuumCleaningMode.vacuumAndMop.showsFan && VacuumCleaningMode.vacuumAndMop.showsWater)
        #expect(VacuumCleaningMode.vacuumAndMop.label == "Vacuum and Mop")
        #expect(VacuumCleaningMode.vacuum.label == "Vacuum" && VacuumCleaningMode.mop.label == "Mop")
    }

    @Test func settingRowsKeepHiddenRowsInTheListSoTheSheetCanAnimateThem() {
        let (vacuum, store, _, _, _) = fixtures.make()
        func shown() -> [String] { vacuum.settingRows(in: .full).filter(\.isShown).map(\.setting.title) }
        #expect(vacuum.settingRows(in: .full).map(\.setting.title) == ["Mode", "Fan", "Water", "Passes"])
        #expect(shown() == ["Mode", "Fan", "Water", "Passes"])
        set(store, Vacuums.mainFloor.modeEntityId!, "vacuum")
        #expect(vacuum.settingRows(in: .full).map(\.setting.title) == ["Mode", "Fan", "Water", "Passes"], "Water stays in the tree")
        #expect(shown() == ["Mode", "Fan", "Passes"], "Water is absent for Vacuum")
        set(store, Vacuums.mainFloor.modeEntityId!, "mop")
        #expect(shown() == ["Mode", "Water", "Passes"], "Fan is absent for Mop")
        #expect(vacuum.settingRows(in: .full).map(\.role) == [.mode, .fan, .water, .passes])
    }

    @Test func aPendingModeChoiceDrivesVisibilityBeforeHomeAssistantConfirms() {
        let (vacuum, _, _, _, _) = fixtures.make()
        vacuum.select(Vacuums.mainFloor.modeEntityId!, option: "vacuum")
        #expect(vacuum.settingRows(in: .full).first { $0.role == .water }?.isShown == false)
        vacuum.select(Vacuums.mainFloor.modeEntityId!, option: "vacuum_and_mop")
        #expect(vacuum.settingRows(in: .full).first { $0.role == .water }?.isShown == true)
    }

    @Test func settingRowsAreEmptyWhileCleaningAndPassesNeedASetup() {
        let (vacuum, _, _, _, _) = fixtures.make()
        #expect(vacuum.settingRows(in: .minimal).isEmpty)
        let (resumable, _, _, _, _) = fixtures.make([Vacuums.mainFloor.statusFlagEntityId: "resumable"])
        #expect(resumable.settingRows(in: .full).map(\.role) == [.mode, .fan, .water], "No Passes while a resume is pending")
        #expect(resumable.powerSettings(in: .full).map(\.title) == ["Mode", "Fan", "Water"])
    }

    @Test func titlesAreModeFanWaterPasses() {
        let (vacuum, _, _, _, _) = fixtures.make()
        #expect(vacuum.passesSetting?.title == "Passes")
        let mode = vacuum.settingRows(in: .full)[0].setting
        #expect(mode.label(for: "vacuum_and_mop") == "Vacuum and Mop")
        #expect(mode.label(for: "mop") == "Mop")
        #expect(vacuum.settingRows(in: .full)[1].setting.label(for: "turbo") == "Turbo")
    }

    // MARK: Status tiles

    @Test func statusTilesAreStatusBatteryDock() {
        let (vacuum, _, _, _, _) = fixtures.make()
        let tiles = vacuum.statusTiles
        #expect(tiles.map(\.kind) == [.status, .battery, .dock])
        #expect(tiles.map(\.caption) == ["Status", "Battery", "Dock"])
        #expect(tiles.map(\.value) == ["Docked", "87%", "Idle"])
        #expect(tiles[0].symbol == "checkmark.circle.fill" && !tiles[0].symbolIsMDI, "Docked reads as a green check")
        #expect(tiles[0].tint == .tone(.ok))
        #expect(tiles[1].symbol == "battery.75percent" && tiles[1].tint == .primary)
        #expect(tiles[2].symbol == "ev.charger" && tiles[2].tint == .primary)
    }

    @Test func dockTileSaysWashingWhileTheDockCleans() {
        let (vacuum, _, _, _, _) = fixtures.make([Vacuums.mainFloor.dockControls!.dockStatusEntityId: "cleaning"])
        let dock = vacuum.statusTiles[2]
        #expect(dock.value == "Washing" && dock.tint == .tone(.active) && dock.symbolIsMDI)
        let (drying, _, _, _, _) = fixtures.make([Vacuums.mainFloor.dockControls!.dockStatusEntityId: "drying"])
        #expect(drying.statusTiles[2].value == "Drying")
    }

    @Test func statusTilesGoQuietWhenTheRobotDoesNotAnswer() {
        let (vacuum, _, _, _, _) = fixtures.make([Vacuums.mainFloor.entityId: "unavailable"])
        let tiles = vacuum.statusTiles
        #expect(tiles[0].value == "Unavailable" && tiles[0].tint == .tone(.unavailable))
        #expect(tiles[1].value == "Unknown" && tiles[1].tint == .secondary && tiles[1].symbol == "battery.0percent")
        #expect(tiles[2].value == "Unknown" && tiles[2].tint == .tone(.unavailable))
    }

    @Test func batteryGlyphFollowsTheLevel() {
        #expect(VacuumStatusTile.batterySymbol("100%") == "battery.100percent")
        #expect(VacuumStatusTile.batterySymbol("64%") == "battery.75percent")
        #expect(VacuumStatusTile.batterySymbol("40%") == "battery.50percent")
        #expect(VacuumStatusTile.batterySymbol("20%") == "battery.25percent")
        #expect(VacuumStatusTile.batterySymbol("5%") == "battery.0percent")
        #expect(VacuumStatusTile.batterySymbol("Unknown") == "battery.0percent")
    }

    @Test func tileValuesAreEqualLengthIndependentLabels() {
        #expect(VacuumStatusTile.dockValue("emptying", available: true) == "Emptying")
        #expect(VacuumStatusTile.dockValue(nil, available: true) == "Unknown")
        #expect(VacuumStatusTile.dockValue("cleaning", available: false) == "Unknown")
    }

    // MARK: Choice tiles

    @Test func roomTilesCarryTheCleaningOrder() {
        let tile = VacuumChoiceTile.room(title: "Kitchen", icon: "mdi:fridge", order: 2, editable: true)
        #expect(tile.isChosen && tile.order == 2 && !tile.isUnavailable)
        #expect(tile.accessibilityLabel == "Kitchen, cleaning order 2" && tile.accessibilityValue == "Selected")
        let off = VacuumChoiceTile.room(title: "Office", icon: "mdi:desk", order: nil, editable: true)
        #expect(!off.isChosen && off.order == nil && off.accessibilityLabel == "Office" && off.accessibilityValue == "Not selected")
        #expect(VacuumChoiceTile.room(title: "Office", icon: "x", order: nil, editable: false).isUnavailable, "Locked while cleaning")
    }

    @Test func roomTilesFollowTheControllersSelection() {
        let (vacuum, _, _, _, clock) = fixtures.make()
        #expect(vacuum.roomTiles.allSatisfy { !$0.tile.isChosen })
        let zones = vacuum.vacuum.zones
        vacuum.toggleRoom(zones[2])
        clock.advance(1)
        vacuum.toggleRoom(zones[0])
        let tiles = vacuum.roomTiles
        #expect(tiles.count == zones.count)
        #expect(tiles[2].tile.order == 1 && tiles[0].tile.order == 2, "Order is the order they were chosen")
        #expect(tiles.filter { $0.tile.isChosen }.count == 2)
    }

    @Test func theSelectedRoomsRowSpeaksTheOrder() {
        let (vacuum, _, _, _, clock) = fixtures.make()
        #expect(vacuum.selectedRoomsSpokenValue == VacuumSheetCopy.fullCleanSpoken)
        #expect(vacuum.selectedRoomsMapValue.isEmpty)
        let zones = vacuum.vacuum.zones
        vacuum.toggleRoom(zones[1])
        clock.advance(1)
        vacuum.toggleRoom(zones[0])
        #expect(vacuum.selectedRoomsSpokenValue == "1. \(zones[1].title), 2. \(zones[0].title)")
        #expect(vacuum.selectedRoomsMapValue == "Selected rooms: 1. \(zones[1].title), 2. \(zones[0].title)", "The map names the rooms for VoiceOver, in order")
    }

    @Test func onlyTheModeSettingSpellsItsOptionsAsModes() {
        let (vacuum, _, _, _, _) = fixtures.make()
        let rows = vacuum.settingRows(in: .full)
        let mode = rows.first { $0.role == .mode }!.setting
        #expect(mode.role == .mode && mode.label(for: "vacuum_and_mop") == "Vacuum and Mop")
        let fan = rows.first { $0.role == .fan }!.setting
        #expect(fan.role == .fan && fan.label(for: "vacuum_and_mop") == VacuumFormat.state("vacuum_and_mop"), "A fan option named like a mode keeps its own label")
        #expect(rows.first { $0.role == .water }?.setting.label(for: "vacuum_and_mop") == VacuumFormat.state("vacuum_and_mop"))
    }

    @Test func autoCleanChecksAreTheInverseOfDisabled() {
        let included = VacuumChoiceTile.autoClean(title: "Gym", icon: "x", skipped: false, unavailable: false)
        #expect(included.isChosen && included.order == nil && included.subtitle == nil && included.accessibilityValue == "Included")
        let skipped = VacuumChoiceTile.autoClean(title: "Gym", icon: "x", skipped: true, unavailable: false)
        #expect(!skipped.isChosen && skipped.subtitle == "Skipped" && skipped.accessibilityValue == "Skipped")
        #expect(skipped.accessibilityLabel == "Gym auto-clean")
        let unavailable = VacuumChoiceTile.autoClean(title: "Gym", icon: "x", skipped: false, unavailable: true)
        #expect(!unavailable.isChosen && unavailable.isUnavailable && unavailable.subtitle == "Unavailable" && unavailable.accessibilityValue == "Unavailable")
    }

    @Test func autoCleanTilesReadTheDisabledEntities() {
        let room = Vacuums.mainFloor.autoCleanDisabledRooms[0]
        let (vacuum, _, _, _, _) = fixtures.make([room.entityId: "on"])
        let tiles = vacuum.autoCleanTiles
        #expect(tiles.count == Vacuums.mainFloor.autoCleanDisabledRooms.count)
        #expect(!tiles[0].tile.isChosen && tiles[0].tile.subtitle == "Skipped", "A disabled room is unchecked")
        #expect(tiles.dropFirst().allSatisfy { $0.tile.isChosen })
        let (broken, _, _, _, _) = fixtures.make([room.entityId: "unavailable"])
        #expect(broken.autoCleanTiles[0].tile.isUnavailable)
    }

    // MARK: Command tiles

    @Test func everyCommandHasADiscGlyph() {
        let kinds: [VacuumController.Action.Kind] = [.clean, .cleanArea, .dock, .stop, .resume, .cancelResume, .pause, .cancelSession,
                                                    .cleanDock, .stopDockClean, .dryMops, .stopDrying, .emptyBin]
        #expect(kinds.allSatisfy { !$0.symbol.isEmpty })
        #expect(VacuumController.Action.Kind.pause.symbol == "pause.fill" && VacuumController.Action.Kind.dock.symbol == "house.fill")
        #expect(VacuumController.Action.Kind.cleanDock.symbol == "drop" && VacuumController.Action.Kind.stopDockClean.symbol == "stop.fill")
    }

    @Test func runTilesCarryNoFooterAndKeepTheReasonAsDetail() {
        let (vacuum, _, _, _, _) = fixtures.make([Vacuums.mainFloor.entityId: "cleaning"])
        let tiles = vacuum.runtimeTiles
        #expect(tiles.map(\.action.kind) == [.pause, .stop])
        #expect(tiles.allSatisfy { $0.footer == nil && $0.subtitle == nil }, "No text under Pause and Stop")
        #expect(tiles.allSatisfy { $0.spec.feedback == .momentary && $0.spec.phase == .ready })
        #expect(tiles[0].action.detail == "Pause the current cleaning run.", "The reason stays as the accessibility value")
    }

    @Test func pauseIsDimWhileTheDockWashesBeforeALeaves() {
        let (vacuum, _, _, _, _) = fixtures.make([Vacuums.mainFloor.entityId: "cleaning", Vacuums.mainFloor.dockControls!.dockStatusEntityId: "cleaning"])
        let pause = vacuum.runtimeTiles.first { $0.action.kind == .pause }
        #expect(pause?.spec.phase == .unavailable && pause?.action.detail == "Pause becomes available after the robot leaves the dock.")
    }

    @Test func dockTilesExplainThemselvesInFooters() {
        let (vacuum, _, _, _, _) = fixtures.make(services: VacuumFixturesServices.all)
        let tiles = vacuum.dockTiles
        #expect(tiles.map(\.action.kind) == [.cleanDock, .dryMops, .emptyBin])
        #expect(tiles.allSatisfy { $0.footer == $0.action.detail && $0.footer != nil })
        #expect(tiles.allSatisfy { $0.spec.feedback != .tracked || $0.spec.phase == .ready })
        #expect(tiles.allSatisfy { !$0.isFilled && $0.subtitle == nil })
    }

    @Test func washingTurnsCleanMopDockIntoAFilledStopTile() {
        let (vacuum, _, _, _, _) = fixtures.make([Vacuums.mainFloor.dockControls!.dockStatusEntityId: "cleaning"], services: VacuumFixturesServices.all)
        let tiles = vacuum.dockTiles
        // A washing dock is busy, so the sheet is in its minimal mode and only the active command shows.
        #expect(tiles.map(\.action.kind) == [.stopDockClean])
        #expect(tiles[0].isFilled && tiles[0].subtitle == "Washing" && tiles[0].action.title == "Stop Dock Clean")
        #expect(tiles[0].spec.phase == .ready && tiles[0].spec.feedback == .tracked)
    }

    @Test func aDockTapShowsTheTrackedSpinnerUntilTheDockReports() {
        let (vacuum, store, _, _, _) = fixtures.make(services: VacuumFixturesServices.all)
        #expect(!vacuum.dockCommandPending)
        vacuum.run(.cleanDock)
        #expect(vacuum.dockCommandPending)
        let pending = vacuum.dockTiles[0]
        #expect(pending.action.kind == .stopDockClean && pending.spec.phase == .inFlight && pending.subtitle == "Starting…")
        fixtures.confirm(vacuum, store, Vacuums.mainFloor.dockControls!.dockStatusEntityId, "cleaning")
        #expect(!vacuum.dockCommandPending)
        #expect(vacuum.dockTiles[0].spec.phase == .ready && vacuum.dockTiles[0].subtitle == "Washing")
    }

    @Test func dryingSaysDryingAndMopPadsOffDimTheWashTiles() {
        let (vacuum, _, _, _, _) = fixtures.make([Vacuums.mainFloor.dockControls!.dockStatusEntityId: "drying"], services: VacuumFixturesServices.all)
        #expect(vacuum.dockTiles.first { $0.action.kind == .stopDrying }?.subtitle == "Drying")
        let (bare, _, _, _, _) = fixtures.make([Vacuums.mainFloor.dockControls!.mopAttachmentEntityId: "off"], services: VacuumFixturesServices.all)
        #expect(bare.dockTiles.filter { $0.action.kind != .emptyBin }.allSatisfy { $0.spec.phase == .unavailable })
        #expect(bare.dockTiles.first { $0.action.kind == .emptyBin }?.spec.phase == .ready)
    }

    @Test func areaSizeReadsInMetres() {
        let area = MapGridRect(x0: 0, x1: 76, y0: 0, y1: 52)
        #expect(VacuumFormat.areaSize(area, pixelSize: 5) == "3.8 m × 2.6 m")
    }

    @Test func theCleanButtonReadsCleanInBothModes() {
        let (vacuum, _, _, _, _) = fixtures.make()
        #expect(vacuum.cleanAction.title == "Clean")
        #expect(vacuum.areaCleanAction(mapReady: true, selectionAllowed: true).title == "Clean")
    }
}

/// Every script the dock and area commands check for, as the gallery offers them.
enum VacuumFixturesServices {
    static let all: Set<String> = {
        var names: Set<String> = ["valetudo_vacuum_coordinator.dock_action"]
        for vacuum in Vacuums.all {
            names.insert(vacuum.cleanScript)
            if let area = vacuum.areaCleaning { names.insert(area.script) }
            if let dock = vacuum.dockControls { names.formUnion([dock.cleanScript, dock.dryScript]) }
        }
        return names
    }()
}
