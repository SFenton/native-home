#if DEBUG
import CoreGraphics
import Foundation
import HassCore
import ImageIO
import UniformTypeIdentifiers

/// People photos for the galleries (`FENTON_GALLERY_PHOTOS=1`): generated gradients for Alex and Sam in a throwaway directory,
/// so journeys can see a photo without a server. Nothing reads the network. The top-left of each gradient is orange, a colour no
/// part of the app uses, so a journey can tell a photo from the blue initials disc by its pixels (`AvatarPixels`).
@MainActor
enum GalleryAvatarPhotos {
    /// People photos over a fresh temporary directory: none, or (`enabled`) a generated photo for the two residents with
    /// `viewerPersonID` as the signed-in person. The guest never gets one.
    static func avatars(enabled: Bool, viewerPersonID: String) -> PersonAvatars {
        let store = PersonAvatarStore(directory: FileManager.default.temporaryDirectory.appending(path: "gallery-avatars-\(UUID().uuidString)"))
        guard enabled else { return PersonAvatars(store: store) }
        let people: [(id: String, hue: (CGFloat, CGFloat))] = [("person.demo_alex", (0.0, 0.55)), ("person.demo_sam", (0.8, 0.35))]
        for person in people {
            let metadata = PersonAvatarStore.Metadata(pictureKey: "/gallery/\(person.id)", validatedAt: .now)
            if let data = gradientPNG(from: person.hue.0, to: person.hue.1) { try? store.save(data, metadata: metadata, for: person.id) }
        }
        store.viewerPersonID = viewerPersonID
        return PersonAvatars(store: store)
    }

    /// A 512 px diagonal gradient between two hues, standing in for a photo.
    private static func gradientPNG(from start: CGFloat, to end: CGFloat) -> Data? {
        let side = 512
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [CGColor(red: 0.95, green: 0.7 - start * 0.2, blue: 0.4 + start * 0.3, alpha: 1),
                                                 CGColor(red: 0.1 + end * 0.3, green: 0.2, blue: 0.5 + end * 0.4, alpha: 1)] as CFArray,
                                        locations: [0, 1]) else { return nil }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])
        let data = NSMutableData()
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
#endif
