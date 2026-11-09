import Foundation

/// Decides whether a live stream has stopped delivering frames (web `stream-manager.js` `FRAME_STALL_MS`: 8 s without the
/// decoded-frame count advancing, checked every `FRAME_CHECK_MS`, 1 s).
///
/// Pure bookkeeping: the caller reads a monotonically increasing frame count (WebRTC decoded frames, HLS play
/// position) about once a second and passes it with the time; no clock is read here, so tests drive it with
/// made-up instants. A count that goes backwards (a restarted stream) counts as progress.
public struct FrameStallDetector: Sendable {
    /// How long the count may stay put before the stream counts as stalled (web: 8 s).
    public static let defaultStallAfter: Duration = .seconds(8)

    public let stallAfter: Duration
    private var count: Int?
    private var changedAt: ContinuousClock.Instant?

    /// - Parameter stallAfter: How long without progress counts as a stall.
    public init(stallAfter: Duration = FrameStallDetector.defaultStallAfter) {
        self.stallAfter = stallAfter
    }

    /// Forgets what it has seen (a new stream, or the app returning).
    public mutating func reset() {
        count = nil
        changedAt = nil
    }

    /// Records one reading.
    /// - Parameters:
    ///   - frames: The stream's frame count now.
    ///   - now: When it was read.
    /// - Returns: `true` when the count has not advanced for ``stallAfter``.
    public mutating func observe(frames: Int, at now: ContinuousClock.Instant) -> Bool {
        guard let previous = count, let since = changedAt else {
            count = frames
            changedAt = now
            return false
        }
        if frames != previous {
            count = frames
            changedAt = now
            return false
        }
        return now - since >= stallAfter
    }
}
