import XCTest

/// The air purifier, humidifier and grill sheets in the light appearance (`Features/RoomDevices`).
@MainActor
final class LightAppearanceRoomDeviceSheetJourneyTests: LightAppearanceJourneyTestCase {
    private func auditDevice(_ device: String, ready: String) throws {
        try auditLight("device-\(device)") { arguments in
            let app = self.gallery("room-devices", environment: [
                "FENTON_GALLERY_DEVICE": device, "FENTON_GALLERY_TAB": "controls", "FENTON_GALLERY_CLEAN": "1",
            ], arguments: arguments)
            self.waitReady(ready, in: app, what: "\(device) sheet")
            return app
        }
    }

    /// The air purifier sheet.
    func testRoomDevicePurifierSheetPassesAuditInLight() throws { try auditDevice("purifier-auto", ready: "purifier.mode") }

    /// The humidifier's dial.
    func testRoomDeviceHumidifierSheetPassesAuditInLight() throws { try auditDevice("humidifier", ready: "humidifier.power") }

    /// The grill sheet.
    func testRoomDeviceGrillSheetPassesAuditInLight() throws { try auditDevice("grill", ready: "grill.header") }
}
