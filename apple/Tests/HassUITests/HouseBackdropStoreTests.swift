import CoreGraphics
import Foundation
import HassCore
import ImageIO
@testable import HassUI
import Testing

/// Publication assets use the canonical render pipeline without requiring a Home Assistant image URL.
@MainActor
struct HouseBackdropStoreTests {
    // MARK: - Publication source

    @Test func verifiedPhotoUsesTheCanonicalRecipeAndRendersOnlyOnce() async throws {
        let directory = URL.temporaryDirectory.appending(path: "backdrop-source-\(UUID().uuidString)")
        let suiteName = "backdrop-source-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let photo = try #require(HouseBackdropStore.fixturePhoto())
        let bytes = try #require(HouseBackdropStore.fixturePhotoData())
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let blur = BackdropBlurSettings(defaults: defaults)
        let store = HouseBackdropStore(verifiedPhoto: decoded, directory: directory, blur: blur)
        let size = CGSize(width: 120, height: 180)
        let spec = try #require(BackdropRenderSpec(points: size, displayScale: 1, percent: blur.percent))
        let expected = try #require(BackdropRenderer.render(photo, spec: spec))

        store.setWindow(size, scale: 1)
        await store.refresh()
        let image = try #require(store.image)
        try #require(try pixels(image).elementsEqual(pixels(expected)),
                     "Source: \(String(describing: photo.colorSpace)), \(photo.alphaInfo); decoded: \(String(describing: decoded.colorSpace)), \(decoded.alphaInfo)")
        #expect(store.renderCount == 1)
        if let output = ProcessInfo.processInfo.environment["FENTON_SERVERUI_FIXTURE_PHOTO_OUTPUT"] {
            try bytes.write(to: URL(fileURLWithPath: output), options: .withoutOverwriting)
        }

        await store.refresh()
        store.setWindow(size, scale: 1)
        await store.settled()
        #expect(store.renderCount == 1)
        #expect(store.image === image)

        blur.set(0)
        #expect(store.image === image, "The existing render stays visible until its replacement is ready.")
        await store.settled()
        #expect(store.renderCount == 2)
        #expect(store.image !== image)
    }

    // MARK: - Fixture

    private func pixels(_ image: CGImage) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
    }

    private func makePhoto() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0.3, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 20, y: 0, width: 20, height: 40))
        return try #require(context.makeImage())
    }
}
