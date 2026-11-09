import CoreGraphics
import Observation

/// One person's decoded photo, observable on its own, so a change redraws only the views bound to that person
/// (the same shape as ``EntityBox``).
@MainActor
@Observable
public final class AvatarBox: Identifiable {
    /// The `person.*` entity id; stable for the box's life.
    public let id: String
    /// The decoded photo, nil when the person has none on this device.
    public private(set) var image: CGImage?
    /// Counts changes of ``image``, so a view can tell "the same photo" from "a new photo" without comparing pixels.
    public private(set) var revision = 0

    init(id: String, image: CGImage?) {
        self.id = id
        self.image = image
    }

    /// Replaces the photo: one write, one observation, one redraw.
    func apply(_ image: CGImage?) {
        if image == nil, self.image == nil { return }
        self.image = image
        revision += 1
    }
}
