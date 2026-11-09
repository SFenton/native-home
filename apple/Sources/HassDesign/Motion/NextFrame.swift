import Foundation
#if os(iOS)
import QuartzCore
#endif

/// Runs a block on the first display tick after now (a transition's "first frame", `.agents/design/motion.md` §10).
///
/// On iOS a one-shot `CADisplayLink`; elsewhere (the macOS test host) the next main run-loop turn.
public enum NextFrame {
    /// Calls `body` on the main actor after the next frame has been committed.
    @MainActor
    public static func perform(_ body: @escaping @MainActor () -> Void) {
        #if os(iOS)
        let target = DisplayLinkTarget(body)
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        target.link = link
        link.add(to: .main, forMode: .common)
        #else
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
        #endif
    }
}

#if os(iOS)
/// The display link's target: fires once, then invalidates the link (which retains this object).
@MainActor
private final class DisplayLinkTarget: NSObject {
    private var body: (@MainActor () -> Void)?
    var link: CADisplayLink?

    init(_ body: @escaping @MainActor () -> Void) { self.body = body }

    @objc func tick(_ link: CADisplayLink) {
        link.invalidate()
        self.link = nil
        let body = body
        self.body = nil
        body?()
    }
}
#endif
