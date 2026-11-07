import Foundation
import Observation

/// When the header's reconnecting arc is in the bar and when it is lit (owner, 2026-10-23; ``ReconnectingPolicy``).
///
/// Two flags rather than one because the bar's items cannot fade in or out themselves: the arc is *present* (a bar item) a
/// moment before it is *lit* (opacity 1), and stays present until its fade-out has finished. ``follow(isDown:delay:fade:lead:)``
/// drives both from the connection; one instance lives on the shell, so a page pushed in the middle of an outage already
/// shows the arc.
@MainActor
@Observable
public final class ReconnectingIndicator {
    /// The arc is a bar item.
    public private(set) var isPresent = false
    /// The arc is faded up (it fades to this, and from it).
    public private(set) var isLit = false
    /// The wait is the first connect (no state has arrived yet), not a lost connection: the arc says "Connecting".
    /// Sticky until the arc has faded out, so the closing announcement still names what ended.
    public var isFirstConnect = false

    public init() {}

    /// Follows the connection until the calling task is cancelled or the state changes: run it as `.task(id: isDown)`, so a
    /// change cancels the previous call and starts the next.
    ///
    /// Going down waits `delay` (a blip never shows), places the arc, then lights it `lead` later. Coming back dims it, keeps
    /// it in the bar for `fade`, then removes it. Going down again mid-fade-out lights the arc where it is, with no wait.
    /// - Parameters:
    ///   - isDown: The connection is retrying with a network path (``ReconnectingPolicy/showsReconnecting(_:isOffline:)``).
    ///   - delay: How long it must have been down.
    ///   - fade: How long the arc takes to fade; it leaves the bar after this.
    ///   - lead: How long the arc is placed before it lights.
    public func follow(
        isDown: Bool,
        delay: Duration = ReconnectingPolicy.delay,
        fade: Duration = ReconnectingPolicy.fade,
        lead: Duration = ReconnectingPolicy.insertLead
    ) async {
        if isDown {
            if !isPresent {
                guard (try? await Task.sleep(for: delay)) != nil else { return }
                isPresent = true
                guard (try? await Task.sleep(for: lead)) != nil else { return }
            }
            isLit = true
        } else {
            isLit = false
            guard isPresent else { return }
            guard (try? await Task.sleep(for: fade)) != nil else { return }
            isPresent = false
        }
    }
}
