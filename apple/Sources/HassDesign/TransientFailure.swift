import Observation
import SwiftUI

/// Posts a spoken failure notice without moving VoiceOver focus, through the shared ``Announcer``.
@MainActor
public func announceFailure(_ message: String) {
    Announcer.announce(message)
}

/// A failure message that shows for four seconds, for a control with no tile face to turn red: a slider, a dial, a
/// sheet row (pattern: optimistic-actions, "Failure").
///
/// ``show(_:)`` replaces the message and restarts the timer; ``count`` increases on every call so a view can fire a
/// haptic per failure even when the text is the same.
@MainActor
@Observable
public final class TransientFailure {
    /// How long a failure shows (owner, 2026-10-24).
    public nonisolated static let duration: Duration = .seconds(4)

    /// The message showing now, or `nil`.
    public private(set) var message: String?
    /// Failures shown so far.
    public private(set) var count = 0

    @ObservationIgnored private let showFor: Duration
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Creates a failure holder. Tests pass a short `duration`.
    public init(duration: Duration = TransientFailure.duration) { showFor = duration }

    /// Shows `message` now: bumps ``count`` and restarts the timer.
    public func show(_ message: String) {
        self.message = message
        count += 1
        task?.cancel()
        task = Task { @MainActor [weak self, showFor] in
            try? await Task.sleep(for: showFor)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    /// Hides the message now (the control is used again, or its sheet closes).
    public func clear() {
        task?.cancel()
        message = nil
    }
}


