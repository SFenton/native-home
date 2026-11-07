import Foundation
import HassCore
import os

/// A timeline of the camera streams' lifecycle (start, stop, mode failures, resume), for finding why a stream
/// did not come back after the app returned from the background.
///
/// Always goes to the unified log (subsystem `com.sfenton.home`, category `Cameras`); Debug builds also append
/// to the push trace file in the app group (`.agents/platforms/apple/push.md`, "Debugging on a phone"), which
/// `devicectl` can copy off a phone. Lines carry camera ids, modes and counts, never tokens or URLs.
enum CameraTrace {
    private static let logger = Logger(subsystem: "com.sfenton.home", category: "Cameras")

    /// Records one step.
    static func record(_ line: @autoclosure () -> String) {
        let text = line()
        logger.notice("\(text, privacy: .public)")
        PushTrace.shared.record("camera: \(text)")
    }
}
