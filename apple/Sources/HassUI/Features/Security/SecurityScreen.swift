import HassCore
import HassDesign
import SwiftUI

/// The Security tab (web `SecurityDashboard.tsx`). Spec: `.agents/pages/security/spec.md`.
struct SecurityScreen {


    /// Whether a command can go out now (web `connectionCannotSend`: not while disconnected or suspended).
    static func canSend(_ status: HassConnection.Status) -> Bool {
        switch status {
        case .connected, .connecting: true
        case .disconnected, .waitingToReconnect, .rejected: false
        }
    }
}

/// The page body, shared by ``SecurityScreen`` and the debug gallery (which passes a recording caller and no
/// cameras, so journeys never reach the house). Direction G mockup n3: the status chips, the alarm card, the Doors
/// tiles, guests, cameras and the car.
struct SecurityPage {
    var caller: any HassServiceCalling
    var canSend: Bool
    var showsCameras: Bool
    var showsVehicle: Bool

    /// The widest the alarm card runs in a sheet or a Quick Links detail (HIG Layout: readable width). The page's card is full width.
    static let alarmWidth: CGFloat = 560

    /// The Security and Contact Sensors chips (`SECURITY_STATUS_CHIPS`).
    static var chips: [HomeConfig.StatusChip] { HomeConfig.statusChips.filter { [.security, .contacts].contains($0.sheet) } }

    /// The locks and garage doors, in web order (the alarm tile became the card above them).
    static var doorTiles: [SecurityConfig.Tile] { SecurityConfig.controlTiles.filter { $0.kind != .alarm } }


}
