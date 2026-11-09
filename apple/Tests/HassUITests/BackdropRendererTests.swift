import CoreGraphics
import Foundation
import HassCore
@testable import HassUI
import Testing

/// The house wallpaper's render: the photo covers the window, is blurred as the setting says, and is stored and found again by
/// the name of everything that shaped it.
struct BackdropRendererTests {
    /// A photo that is red on its left half and blue on its right half.
    private func photo(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try #require(context.makeImage())
    }

    private func color(of image: CGImage, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int, a: Int) {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        let i = (y * image.width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
    }

    private func spec(percent: Int = 0, width: Double = 100, height: Double = 200) throws -> BackdropRenderSpec {
        try #require(BackdropRenderSpec(points: CGSize(width: width, height: height), displayScale: 1, percent: percent))
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "backdrop-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theDigestNamesThePhotoByItsPixels() throws {
        let a = try photo(width: 40, height: 20)
        #expect(BackdropRenderer.digest(of: a) == BackdropRenderer.digest(of: try photo(width: 40, height: 20)), "the same photo served again")
        #expect(BackdropRenderer.digest(of: a) != BackdropRenderer.digest(of: try photo(width: 60, height: 20)))
        #expect(BackdropRenderer.digest(of: a).count == 16)
    }

    @Test func aPhotoLargerThanTheWindowIsReducedToCoverItWithBothHalvesWhereTheyWere() throws {
        let render = try #require(BackdropRenderer.render(try photo(width: 600, height: 800), spec: try spec()))
        #expect(render.width == 100 && render.height == 200, "the render is the window's pixels")
        let left = try color(of: render, x: 10, y: 100), right = try color(of: render, x: 90, y: 100)
        #expect(left.r > 200 && left.b < 60, "the left half stays red: \(left)")
        #expect(right.b > 200 && right.r < 60, "the right half stays blue: \(right)")
        #expect(left.a == 255 && right.a == 255, "no transparent edge")
        let corner = try color(of: render, x: 0, y: 0)
        #expect(corner.a == 255, "the photo's edge is extended, never transparent")
    }

    @Test func aPhotoSmallerThanTheWindowIsMagnifiedToCoverIt() throws {
        let render = try #require(BackdropRenderer.render(try photo(width: 20, height: 20), spec: try spec()))
        #expect(render.width == 100 && render.height == 200)
        let left = try color(of: render, x: 5, y: 5), right = try color(of: render, x: 95, y: 195)
        #expect(left.r > 200 && right.b > 200, "left \(left) right \(right)")
    }

    @Test func theBlurMixesTheHalvesAtTheSeamAndMakesASmallerRender() throws {
        let blurred = try spec(percent: 100, width: 400, height: 800)
        #expect(blurred.divisor > 1, "a wide blur is rendered at a fraction of the window")
        let render = try #require(BackdropRenderer.render(try photo(width: 800, height: 1000), spec: blurred))
        #expect(render.width == blurred.renderWidth && render.height == blurred.renderHeight)
        let seam = try color(of: render, x: render.width / 2, y: render.height / 2)
        #expect(seam.r > 40 && seam.b > 40, "red and blue run together at the seam: \(seam)")
    }

    @Test func aRenderIsStoredAsAJpegAndReadBackDecoded() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let render = try #require(BackdropRenderer.render(try photo(width: 300, height: 400), spec: try spec()))
        let url = directory.appending(path: "one.jpg")
        #expect(BackdropRenderer.write(render, to: url))
        let back = try #require(BackdropRenderer.load(url))
        #expect(back.width == render.width && back.height == render.height)
        #expect(BackdropRenderer.load(directory.appending(path: "missing.jpg")) == nil)
        #expect(!BackdropRenderer.write(render, to: URL(fileURLWithPath: "/nonexistent-folder/none.jpg")), "a write that cannot happen says so")
    }

    @Test func theNameOfTheRenderOnScreenIsRememberedForTheNextLaunch() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let render = try #require(BackdropRenderer.render(try photo(width: 300, height: 400), spec: try spec()))
        BackdropRenderer.write(render, to: directory.appending(path: "backdrop-a.jpg"))
        #expect(BackdropRenderer.loadLatest(in: directory) == nil, "nothing is remembered yet")
        BackdropRenderer.markLatest("backdrop-a.jpg", in: directory)
        let latest = try #require(BackdropRenderer.loadLatest(in: directory))
        #expect(latest.name == "backdrop-a.jpg" && latest.image.width == render.width)
        BackdropRenderer.markLatest("backdrop-gone.jpg", in: directory)
        #expect(BackdropRenderer.loadLatest(in: directory) == nil, "the file is gone")
        BackdropRenderer.markLatest("../escape.jpg", in: directory)
        #expect(BackdropRenderer.loadLatest(in: directory) == nil, "a name with a path in it is refused")
        BackdropRenderer.markLatest("", in: directory)
        #expect(BackdropRenderer.loadLatest(in: directory) == nil)
        // The folder is created when it does not exist yet.
        let fresh = directory.appending(path: "later", directoryHint: .isDirectory)
        BackdropRenderer.markLatest("x.jpg", in: fresh)
        #expect(FileManager.default.fileExists(atPath: fresh.appending(path: BackdropRenderer.latestName).path))
    }

    @Test func pruningKeepsTheNewestRendersAndNeverTheProtectedOneOrOtherFiles() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        for index in 0..<6 {
            let url = directory.appending(path: "backdrop-\(index).jpg")
            try Data([1]).write(to: url)
            // Older with a lower index; the oldest is "backdrop-0".
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(Double(index) * 10)], ofItemAtPath: url.path)
        }
        try Data([1]).write(to: directory.appending(path: "latest.txt"))
        try Data([1]).write(to: directory.appending(path: "other.jpg"))
        BackdropRenderer.prune(directory, keep: 2, protecting: "backdrop-0.jpg")
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        #expect(left == ["backdrop-5.jpg", "backdrop-4.jpg", "backdrop-0.jpg", "latest.txt", "other.jpg"], "\(left.sorted())")
        BackdropRenderer.prune(directory.appending(path: "nope"), protecting: "x")   // a missing folder is nothing to prune
        BackdropRenderer.prune(directory, keep: 10, protecting: "x")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 5, "fewer than keep: nothing goes")
    }

    @Test func rendersFromEarlierRecipesAreRemoved() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in BackdropRenderer.retiredNames + ["keep.txt"] { try Data([1]).write(to: directory.appending(path: name)) }
        BackdropRenderer.removeRetired(in: directory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["keep.txt"])
    }

    @Test func aRenderIsMadeOnceAndFoundOnTheNextAsk() throws {
        let directory = try folder().appending(path: "cache", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let source = try photo(width: 300, height: 400)
        let spec = try spec()
        let digest = BackdropRenderer.digest(of: source)
        let first = try #require(BackdropRenderer.renderOrLoad(source, digest: digest, spec: spec, in: directory))
        #expect(first.rendered)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: spec.cacheName(photo: digest)).path))
        let second = try #require(BackdropRenderer.renderOrLoad(source, digest: digest, spec: spec, in: directory))
        #expect(!second.rendered, "the stored file is read, not drawn again")
        #expect(second.image.width == first.image.width)
        let other = try #require(BackdropRenderer.renderOrLoad(source, digest: digest, spec: try self.spec(percent: 40), in: directory))
        #expect(other.rendered, "another blur is another file")
    }
}
