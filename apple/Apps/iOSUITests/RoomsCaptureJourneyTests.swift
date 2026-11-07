import XCTest

/// Screenshots of every room, Quick Links, the room grid and one sheet of each kind (a Capture plan class: no source rule selects it). One test per
/// screen, each in one pose (`Pose`): iPad has both, named `room-<id>-<portrait|landscape>`; a phone and the Duo capture `current` and skip the
/// `InIPadLandscape` tests. Run one screen or a subset with an `-only-testing` filter or `testCaptureRoomSheet*` (this replaces `FENTON_CAPTURE_ROOMS` / `FENTON_CAPTURE_SET`).
@MainActor
final class RoomsCaptureJourneyTests: RoomsJourneyTestCase {
    // MARK: - Helpers

    private func captureRoom(_ room: String, _ pose: Pose) throws {
        try enter(pose)
        let app = launch(room: room, clean: true)
        keepScreenshot(app, "room-\(room)-\(pose.captureSuffix)")
    }

    private func captureQuickLinks(_ pose: Pose) throws {
        try enter(pose)
        let app = launch(quickLinks: true, clean: true)
        keepScreenshot(app, "quick-links-\(pose.captureSuffix)")
    }

    private func captureRoomGrid(_ pose: Pose) throws {
        try enter(pose)
        let app = launch(quickLinks: true, clean: true)
        element("quickLinks.rooms", in: app).tap()
        XCTAssertTrue(element("rooms.kitchen", in: app).appears(timeout: 5))
        settleScreen()
        keepScreenshot(app, "room-grid-\(pose.captureSuffix)")
    }

    private func captureSheet(_ name: String, room: String, card: String, _ pose: Pose) throws {
        try enter(pose)
        let app = launch(room: room, clean: true)
        let target = element(card, in: app)
        reveal(target, in: app)
        target.tap()
        settleScreen()
        keepScreenshot(app, "room-sheet-\(name)-\(pose.captureSuffix)")
    }

    // MARK: - Rooms

    func testCaptureRoomLivingRoom() throws { try captureRoom("living-room", .upright) }
    func testCaptureRoomLivingRoomInIPadLandscape() throws { try captureRoom("living-room", .iPadLandscape) }
    func testCaptureRoomGuestRoom() throws { try captureRoom("guest-room", .upright) }
    func testCaptureRoomGuestRoomInIPadLandscape() throws { try captureRoom("guest-room", .iPadLandscape) }
    func testCaptureRoomMasterBedroom() throws { try captureRoom(expectations[.roomBedroomId], .upright) }
    func testCaptureRoomMasterBedroomInIPadLandscape() throws { try captureRoom(expectations[.roomBedroomId], .iPadLandscape) }
    func testCaptureRoomGym() throws { try captureRoom("gym", .upright) }
    func testCaptureRoomGymInIPadLandscape() throws { try captureRoom("gym", .iPadLandscape) }
    func testCaptureRoomHallway() throws { try captureRoom("hallway", .upright) }
    func testCaptureRoomHallwayInIPadLandscape() throws { try captureRoom("hallway", .iPadLandscape) }
    func testCaptureRoomOffice() throws { try captureRoom("office", .upright) }
    func testCaptureRoomOfficeInIPadLandscape() throws { try captureRoom("office", .iPadLandscape) }
    func testCaptureRoomKitchen() throws { try captureRoom("kitchen", .upright) }
    func testCaptureRoomKitchenInIPadLandscape() throws { try captureRoom("kitchen", .iPadLandscape) }
    func testCaptureRoomDiningRoom() throws { try captureRoom("dining-room", .upright) }
    func testCaptureRoomDiningRoomInIPadLandscape() throws { try captureRoom("dining-room", .iPadLandscape) }
    func testCaptureRoomBackDeck() throws { try captureRoom("back-deck", .upright) }
    func testCaptureRoomBackDeckInIPadLandscape() throws { try captureRoom("back-deck", .iPadLandscape) }
    func testCaptureRoomMusicRoom() throws { try captureRoom(expectations[.roomStudioId], .upright) }
    func testCaptureRoomMusicRoomInIPadLandscape() throws { try captureRoom(expectations[.roomStudioId], .iPadLandscape) }
    func testCaptureRoomTheaterRoom() throws { try captureRoom(expectations[.roomMediaId], .upright) }
    func testCaptureRoomTheaterRoomInIPadLandscape() throws { try captureRoom(expectations[.roomMediaId], .iPadLandscape) }
    func testCaptureRoomDownstairsHallway() throws { try captureRoom("downstairs-hallway", .upright) }
    func testCaptureRoomDownstairsHallwayInIPadLandscape() throws { try captureRoom("downstairs-hallway", .iPadLandscape) }
    func testCaptureRoomGarage() throws { try captureRoom("garage", .upright) }
    func testCaptureRoomGarageInIPadLandscape() throws { try captureRoom("garage", .iPadLandscape) }
    func testCaptureRoomGuestBathroom() throws { try captureRoom("guest-bathroom", .upright) }
    func testCaptureRoomGuestBathroomInIPadLandscape() throws { try captureRoom("guest-bathroom", .iPadLandscape) }
    func testCaptureRoomMasterBathroom() throws { try captureRoom("master-bathroom", .upright) }
    func testCaptureRoomMasterBathroomInIPadLandscape() throws { try captureRoom("master-bathroom", .iPadLandscape) }
    func testCaptureRoomEntryway() throws { try captureRoom("entryway", .upright) }
    func testCaptureRoomEntrywayInIPadLandscape() throws { try captureRoom("entryway", .iPadLandscape) }

    // MARK: - Quick Links and the room grid

    func testCaptureRoomQuickLinks() throws { try captureQuickLinks(.upright) }
    func testCaptureRoomQuickLinksInIPadLandscape() throws { try captureQuickLinks(.iPadLandscape) }
    func testCaptureRoomGrid() throws { try captureRoomGrid(.upright) }
    func testCaptureRoomGridInIPadLandscape() throws { try captureRoomGrid(.iPadLandscape) }

    // MARK: - Sheets

    func testCaptureRoomSheetLights() throws { try captureSheet("lights", room: "living-room", card: "room.chip.Lights", .upright) }
    func testCaptureRoomSheetLightsInIPadLandscape() throws { try captureSheet("lights", room: "living-room", card: "room.chip.Lights", .iPadLandscape) }
    func testCaptureRoomSheetVents() throws { try captureSheet("vents", room: "living-room", card: "room.card.Vents", .upright) }
    func testCaptureRoomSheetVentsInIPadLandscape() throws { try captureSheet("vents", room: "living-room", card: "room.card.Vents", .iPadLandscape) }
    func testCaptureRoomSheetDeviceFallback() throws { try captureSheet("device-fallback", room: "living-room", card: "room.card.Main Floor", .upright) }
    func testCaptureRoomSheetDeviceFallbackInIPadLandscape() throws { try captureSheet("device-fallback", room: "living-room", card: "room.card.Main Floor", .iPadLandscape) }
    func testCaptureRoomSheetOccupancy() throws { try captureSheet("occupancy", room: expectations[.roomBedroomId], card: "room.chip.Occupancy", .upright) }
    func testCaptureRoomSheetOccupancyInIPadLandscape() throws { try captureSheet("occupancy", room: expectations[.roomBedroomId], card: "room.chip.Occupancy", .iPadLandscape) }
    func testCaptureRoomSheetContacts() throws { try captureSheet("contacts", room: "garage", card: "room.chip.Doors", .upright) }
    func testCaptureRoomSheetContactsInIPadLandscape() throws { try captureSheet("contacts", room: "garage", card: "room.chip.Doors", .iPadLandscape) }
}
