import XCTest

/// Reads a screenshot to tell a person's photo from their initials. The avatar is decorative (hidden from VoiceOver), so a
/// journey cannot ask for it; it counts warm pixels instead. The gallery photos (`GalleryAvatarPhotos`) start orange at their top
/// left, and nothing else in the app is that colour: the initials disc is blue, its letters white, the bars and sheets grey.
enum AvatarPixels {
    /// How many warm photo pixels `app`'s screenshot has inside `frame` (in points, window coordinates).
    @MainActor
    static func photoPixels(in frame: CGRect, of app: XCUIApplication) -> Int {
        guard let image = app.screenshot().image.cgImage else { return 0 }
        return photoPixels(in: frame, image: image, windowWidth: app.windows.firstMatch.frame.width)
    }

    static func photoPixels(in frame: CGRect, image: CGImage, windowWidth: CGFloat) -> Int {
        let scale = CGFloat(image.width) / windowWidth
        let region = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !region.isNull, region.width >= 1, region.height >= 1, let cropped = image.cropping(to: region.integral) else { return 0 }
        let width = cropped.width, height = cropped.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let r = Int(buffer[index]), g = Int(buffer[index + 1]), b = Int(buffer[index + 2])
            if r > 140, r > b + 20, r > g + 20 { count += 1 }
        }
        return count
    }

    /// The bounding box, in points, of the pixels in `frame` that are not black, on a plain black page: a disc drawn there.
    /// Nil when nothing is.
    @MainActor
    static func litBounds(in frame: CGRect, of app: XCUIApplication) -> CGRect? {
        guard let image = app.screenshot().image.cgImage else { return nil }
        let scale = CGFloat(image.width) / app.windows.firstMatch.frame.width
        let region = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
        guard !region.isNull, let cropped = image.cropping(to: region) else { return nil }
        let width = cropped.width, height = cropped.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if Int(buffer[i]) + Int(buffer[i + 1]) + Int(buffer[i + 2]) > 90 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: (region.minX + CGFloat(minX)) / scale, y: (region.minY + CGFloat(minY)) / scale,
                      width: CGFloat(maxX + 1 - minX) / scale, height: CGFloat(maxY + 1 - minY) / scale)
    }

    /// Enough warm pixels to be a photo: a 36 pt disc at 3x holds thousands, so a few dozen is a safe floor that still rejects noise.
    static let photoThreshold = 40
}
