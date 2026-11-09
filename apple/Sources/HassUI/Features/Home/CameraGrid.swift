import HassCore
import HassDesign
import ImageIO
import SwiftUI

/// One camera tile: the camera's shared live stream (web `CameraTile` → `RtcPilotCamera variant="tile"`) over
/// its latest snapshot, with a small name label and nothing else over the picture (direction G; HIG: HomeKit,
/// "avoid covering camera views"); at accessibility text sizes the name sits below the picture. VoiceOver still reads whether the tile is live (``statusText(_:)``).
struct CameraTile {
    var camera: HomeConfig.Camera

    /// What the slot before the camera's name shows.
    enum Indicator: Equatable {
        /// The stream shows frames: the red dot.
        case live
        /// A stream is connecting or reconnecting: the inline arc.
        case connecting
        /// The app has no network, or every way of streaming the camera failed: `icloud.slash`, as the shell's offline badge.
        case offline
    }

    /// Width over height of a card: 1 : 0.78, nearly square, as the web's tile (`ha-sfenton-react-dash@f5a7bf9`
    /// `src/components/hass/CameraTile.module.css:2`, `aspect-ratio: 1 / 0.78`). The video and the snapshot fill
    /// and crop to it, centred (`RtcPilotCamera.tsx:89`, `object-fit: cover`); the viewer keeps each camera's own
    /// aspect ratio.
    static let aspectRatio: CGFloat = 1 / 0.78

    private let shape = RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)




    /// Which indicator the tile shows. A live stream keeps the dot while its frames flow, even if the network path has
    /// just dropped; anything else shows the offline icon when the app is offline or every mode failed, and the arc
    /// while a stream connects.
    static func indicator(for state: CameraStreamState, isOffline: Bool) -> Indicator {
        switch state.phase {
        case .live: .live
        case .failed: .offline
        case .connecting: isOffline ? .offline : .connecting
        }
    }

    /// The tile's VoiceOver value: live, or the snapshot it is showing.
    static func statusText(_ state: CameraStreamState) -> String {
        state.phase == .live ? "Live" : "Snapshot"
    }
}
