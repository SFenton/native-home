import Foundation

// MARK: - Map orientation

/// How a picture is mirrored after its rotation, in screen space (`sh.surface-orientation@1`).
///
/// Both flips on is the owner's "invert". It lives with the picture's source, so every drawing of that picture (the sheet's map, the area
/// editor, the outcome report) agrees about left and right. The default is no flip, which draws the picture as before.
public struct MapOrientation: Codable, Hashable, Sendable {
    /// Mirrors the picture left to right, whatever its rotation.
    public var flipHorizontal: Bool
    /// Mirrors the picture top to bottom, whatever its rotation.
    public var flipVertical: Bool

    /// Draws the picture as the source gives it.
    public static let none = MapOrientation()

    public init(flipHorizontal: Bool = false, flipVertical: Bool = false) {
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    /// Whether the orientation changes anything.
    public var flips: Bool { flipHorizontal || flipVertical }

    /// The screen-space flip as a transform: `-1` on an axis that is mirrored, `1` on one that is not.
    var affine: Affine {
        .init(a: flipHorizontal ? -1 : 1, b: 0, c: 0, d: flipVertical ? -1 : 1, e: 0, f: 0)
    }
}
