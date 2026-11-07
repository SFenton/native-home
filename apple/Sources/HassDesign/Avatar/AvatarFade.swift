import CoreGraphics

/// The layers of an ``AvatarView`` and how they fade (design: `.agents/design/profile-photos.md`; pattern: `.agents/patterns/avatar.md`).
///
/// The initials disc is always underneath. Above it sit at most two photo layers: `base`, drawn at full opacity, and `top`, drawn at
/// ``topOpacity``. A change is three steps the view runs, so the incoming layer exists at 0 before it animates to 1:
/// 1. ``begin(to:)`` places the layers (instant, not animated).
/// 2. ``reveal()`` moves ``topOpacity`` to its goal (inside `withAnimation(MotionTokens.state)`).
/// 3. ``finish(epoch:)`` drops the layer that is no longer visible (when the animation ends).
///
/// | From → to | `base` | `top` | `topOpacity` |
/// |---|---|---|---|
/// | none → photo | none | new | 0 → 1: fades in over the initials |
/// | photo → none | none | old | 1 → 0: fades out onto the initials |
/// | photo → photo | old | new | 0 → 1: the new one fades in over the old, never through the initials |
///
/// A view created with a photo has it at once (`init(image:)`): a cold launch and a reopen never fade.
///
/// A change that arrives while another is fading is **coalesced**: only the latest is kept, and it begins when the fade in
/// flight ends (``finish(epoch:)`` returns true), so a half-visible photo never jumps to full opacity and the layers under it never
/// vanish. The initials disc is hidden once a photo is settled (``discHidden``), so a transparent photo shows the background,
/// not the monogram, through it.
public struct AvatarFade: Equatable, Sendable {
    /// The photo underneath at full opacity: the old photo while a new one fades in.
    public private(set) var base: AvatarImage?
    /// The photo on top, at ``topOpacity``.
    public private(set) var top: AvatarImage?
    /// The top layer's opacity goal: 1 with a photo to show, 0 when the photo is going away or arriving.
    public private(set) var topOpacity: Double
    /// The photo the view is showing or heading to; nil for the initials.
    public private(set) var target: AvatarImage?
    /// Counts fades, so a stale completion cannot drop a newer fade's layers.
    public private(set) var epoch = 0
    /// The initials disc is not drawn: a photo is settled on top of it. It comes back, instantly, when a photo starts to leave.
    public private(set) var discHidden: Bool
    /// The latest change that arrived mid-fade, begun when the fade ends. The outer optional is "nothing waiting".
    private var pending: AvatarImage??
    /// A fade has begun and ``finish(epoch:)`` has not yet run.
    public private(set) var inFlight = false

    /// A settled state: the photo, or the initials alone.
    public init(image: AvatarImage?) {
        top = image
        target = image
        topOpacity = image == nil ? 0 : 1
        discHidden = image != nil
    }

    /// The hairline follows the photo: shown while any photo is visible, fading with it.
    public var hairlineOpacity: Double { base != nil ? 1 : topOpacity }

    /// Whether every layer has reached its goal (nothing is mid-fade).
    public var isSettled: Bool { !inFlight && base == nil && topOpacity == (target == nil ? 0 : 1) && (target != nil || top == nil) }

    /// Starts a change to `image`.
    /// - Returns: False when it is already the target (nothing to animate) or a fade is in flight (the change waits for it);
    ///   true when the caller should run ``reveal()`` in an animation and then ``finish(epoch:)``.
    @discardableResult
    public mutating func begin(to image: AvatarImage?) -> Bool {
        if inFlight {
            // Coalesce: keep only the latest, and drop it if it is where this fade is heading.
            pending = image?.identity == target?.identity ? nil : .some(image)
            return false
        }
        guard image?.identity != target?.identity else { return false }
        epoch += 1
        inFlight = true
        let from = target
        switch (from, image) {
        case (nil, .some):
            base = nil
            top = image
            topOpacity = 0
        case (.some, .some):
            base = from
            top = image
            topOpacity = 0
        case (.some, nil):
            base = nil
            top = from
            topOpacity = 1
            discHidden = false
        case (nil, nil):
            break
        }
        target = image
        return true
    }

    /// Moves the top layer to its goal; run inside `withAnimation`.
    public mutating func reveal() {
        topOpacity = target == nil ? 0 : 1
    }

    /// Drops the layer that is no longer visible, if `epoch` is still the current change.
    /// - Returns: True when a change that arrived mid-fade has now begun: the caller runs ``reveal()`` in an animation and
    ///   ``finish(epoch:)`` again.
    @discardableResult
    public mutating func finish(epoch: Int) -> Bool {
        guard epoch == self.epoch else { return false }
        base = nil
        inFlight = false
        if target == nil { top = nil } else { discHidden = true }
        guard let waiting = pending else { return false }
        pending = nil
        return begin(to: waiting)
    }
}
