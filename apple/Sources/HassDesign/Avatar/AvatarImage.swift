import CoreGraphics

/// A decoded person photo and which photo it is. Equality is the ``identity``, never the pixels, so comparing two is free.
public struct AvatarImage: Equatable, Sendable {
    /// Which photo this is: the person and that person's revision. Two people's revision 1 are different photos, so a view that
    /// is handed another person's box fades instead of silently swapping.
    public struct Identity: Hashable, Sendable {
        /// The person (the `person.*` entity id).
        public let owner: String
        /// The person's photo revision (`AvatarBox.revision`).
        public let revision: Int
    }

    /// The decoded photo.
    public let cgImage: CGImage
    /// Which photo it is.
    public let identity: Identity
    /// The photo's revision for its person.
    public var revision: Int { identity.revision }

    /// Creates an avatar image.
    public init(_ cgImage: CGImage, owner: String, revision: Int) {
        self.cgImage = cgImage
        self.identity = Identity(owner: owner, revision: revision)
    }

    public static func == (lhs: AvatarImage, rhs: AvatarImage) -> Bool { lhs.identity == rhs.identity }
}
