import XCTest

/// The media remote sheet in the light appearance (`Features/MediaRemote`).
@MainActor
final class LightAppearanceMediaRemoteSheetJourneyTests: LightAppearanceJourneyTestCase {
    private func auditRemote(_ remote: String, tab: String, ready: String) throws {
        try auditLight("remote-\(tab)") { arguments in
            let app = self.gallery("media-remote", environment: [
                "FENTON_GALLERY_REMOTE": remote, "FENTON_GALLERY_TAB": tab, "FENTON_GALLERY_OFFLINE": "1",
            ], arguments: arguments)
            self.waitReady(ready, in: app, what: "remote sheet")
            return app
        }
    }

    /// The media remote's keys.
    func testMediaRemoteControlsPassesAuditInLight() throws {
        try auditRemote(expectations[.remoteLivingRoomId], tab: "controls", ready: "remote.power")
    }

    /// The media remote's apps grid.
    func testMediaRemoteAppsPassesAuditInLight() throws {
        try auditRemote(expectations[.remoteLivingRoomId], tab: "apps", ready: "remote.app.\(expectations[.remoteLivingRoomAppTitle])")
    }

    /// The media remote's devices list.
    func testMediaRemoteDevicesPassesAuditInLight() throws {
        try auditRemote(expectations[.remoteMediaRoomId], tab: "devices", ready: "remote.device.Projector")
    }
}
