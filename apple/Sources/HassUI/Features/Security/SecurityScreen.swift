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
