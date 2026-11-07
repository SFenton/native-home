import HassCore
import HassDesign

extension AvatarBox {
    /// The photo as ``AvatarView`` takes it, nil when the person has none. Reading it tracks both the image and its revision.
    var avatarImage: AvatarImage? {
        image.map { AvatarImage($0, owner: id, revision: revision) }
    }
}
