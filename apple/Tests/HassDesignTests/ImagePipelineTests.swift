import CoreGraphics
import Foundation
@testable import HassDesign
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

// MARK: - Stub server

/// Serves canned responses per URL path and records requests. Tests set `handler` and read `requests`.
final class StubImageProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Reply)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()
        let reply = handler?(request) ?? Reply(status: 404)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A solid PNG `width` × `height` pixels.
func pngData(width: Int, height: Int, gray: CGFloat = 0.5) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

// MARK: - Tests

/// ``ImagePipeline`` and ``CachedImage``: keys, freshness, downsampling, the disk store and revalidation.
@Suite(.serialized)
struct ImagePipelineTests {
    private func makePipeline() -> (ImagePipeline, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("images-\(UUID())")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubImageProtocol.self]
        StubImageProtocol.requests = []
        return (ImagePipeline(directory: directory, session: URLSession(configuration: configuration), diskLimit: 10_000), directory)
    }

    private func collect(_ pipeline: ImagePipeline, _ url: URL, pixels: Int = 64) async -> [CGImage] {
        var images: [CGImage] = []
        for await image in pipeline.images(for: url, maxPixel: pixels) { images.append(image) }
        return images
    }

    @Test func keysDropOnlyAuthorizingQueryItems() {
        let camera = URL(string: "https://example.local/api/camera_proxy/camera.demo_front?token=abc")!
        #expect(ImagePipeline.key(for: camera) == "https://example.local/api/camera_proxy/camera.demo_front")
        let artwork = URL(string: "https://example.local/api/media_player_proxy/media_player.demo_tv?token=x&cache=123")!
        #expect(ImagePipeline.key(for: artwork) == "https://example.local/api/media_player_proxy/media_player.demo_tv?cache=123")
        let plain = URL(string: "https://cdn.example.com/r/1.jpg")!
        #expect(ImagePipeline.key(for: plain) == plain.absoluteString)
    }

    @Test func freshnessComparesURLAndAge() {
        let url = URL(string: "https://example.local/a.jpg")!
        let now = Date(timeIntervalSince1970: 1000)
        let meta = ImagePipeline.Metadata(sourceURL: url, validatedAt: Date(timeIntervalSince1970: 900), maxAge: 300)
        #expect(ImagePipeline.freshness(of: meta, for: url, now: now) == .fresh)
        #expect(ImagePipeline.freshness(of: meta, for: url, now: Date(timeIntervalSince1970: 1300)) == .stale)
        #expect(ImagePipeline.freshness(of: meta, for: URL(string: "https://example.local/a.jpg?token=2")!, now: now) == .replaced)
        #expect(!meta.source.contains("example.local"), "Tokenized URLs are never written to disk")
    }

    @Test func maxAgeReadsCacheControl() {
        func response(_ control: String?) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 200, httpVersion: nil,
                            headerFields: control.map { ["Cache-Control": $0] })!
        }
        #expect(ImagePipeline.maxAge(from: response(nil)) == ImagePipeline.defaultMaxAge)
        #expect(ImagePipeline.maxAge(from: response("public, max-age=86400")) == 86400)
        #expect(ImagePipeline.maxAge(from: response("no-cache")) == 0)
        #expect(ImagePipeline.maxAge(from: response("private")) == ImagePipeline.defaultMaxAge)
    }

    @Test func bucketsRoundUp() {
        #expect(ImagePipeline.bucket(0) == 1024)
        #expect(ImagePipeline.bucket(1) == 128)
        #expect(ImagePipeline.bucket(128) == 128)
        #expect(ImagePipeline.bucket(129) == 256)
    }

    @Test func decodeDownsamplesToTheLongestSide() throws {
        let (pipeline, _) = makePipeline()
        let image = try #require(pipeline.decode(pngData(width: 800, height: 400), maxPixel: 200))
        #expect(image.width == 200)
        #expect(image.height == 100)
        #expect(pipeline.decode(Data("not an image".utf8), maxPixel: 100) == nil)
    }

    @Test func fetchesOnceThenServesFromMemoryAndDisk() async throws {
        let (pipeline, directory) = makePipeline()
        let png = pngData(width: 64, height: 64)
        StubImageProtocol.handler = { _ in .init(status: 200, headers: ["ETag": "\"v1\"", "Cache-Control": "max-age=600"], body: png) }
        let url = URL(string: "https://example.local/fresh.png")!

        #expect(await collect(pipeline, url).count == 1)
        #expect(pipeline.memoryImage(for: url) != nil)
        // Fresh: memory, no request.
        #expect(await collect(pipeline, url).count == 1)
        #expect(StubImageProtocol.requests.count == 1)

        // A new pipeline on the same directory (a cold launch) reads the disk without the network.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubImageProtocol.self]
        let cold = ImagePipeline(directory: directory, session: URLSession(configuration: configuration))
        #expect(cold.memoryImage(for: url) == nil)
        #expect(await collect(cold, url).count == 1)
        #expect(StubImageProtocol.requests.count == 1)
        #expect(pipeline.diskUsage().files == 1)
    }

    @Test func staleImagesRevalidateWithValidators() async throws {
        let (pipeline, _) = makePipeline()
        let png = pngData(width: 32, height: 32)
        StubImageProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" { return .init(status: 304) }
            return .init(status: 200, headers: ["ETag": "\"v1\"", "Last-Modified": "Tue, 13 Oct 2026 10:00:00 GMT", "Cache-Control": "no-cache"], body: png)
        }
        let url = URL(string: "https://example.local/stale.png")!
        #expect(await collect(pipeline, url).count == 1)
        // max-age 0: the cached image shows, then a conditional request answers 304 and nothing new is yielded.
        #expect(await collect(pipeline, url).count == 1)
        let last = try #require(StubImageProtocol.requests.last)
        #expect(last.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(last.value(forHTTPHeaderField: "If-Modified-Since") == "Tue, 13 Oct 2026 10:00:00 GMT")
    }

    @Test func changedImagesReplaceTheCachedOne() async throws {
        let (pipeline, _) = makePipeline()
        let first = pngData(width: 32, height: 32, gray: 0.1)
        let second = pngData(width: 32, height: 32, gray: 0.9)
        StubImageProtocol.handler = { request in
            .init(status: 200, headers: ["Cache-Control": "max-age=600"], body: request.url?.query?.contains("token=2") == true ? second : first)
        }
        let url1 = URL(string: "https://example.local/api/camera_proxy/camera.demo_front?token=1")!
        let url2 = URL(string: "https://example.local/api/camera_proxy/camera.demo_front?token=2")!
        #expect(await collect(pipeline, url1).count == 1)
        // A rotated token: the old snapshot comes first, then the new one.
        #expect(await collect(pipeline, url2).count == 2)
        #expect(StubImageProtocol.requests.count == 2)
    }

    @Test func failuresYieldNothing() async {
        let (pipeline, _) = makePipeline()
        StubImageProtocol.handler = { _ in .init(status: 500) }
        #expect(await collect(pipeline, URL(string: "https://example.local/missing.png")!).isEmpty)
        StubImageProtocol.handler = { _ in .init(status: 200, body: Data("junk".utf8)) }
        #expect(await collect(pipeline, URL(string: "https://example.local/junk.png")!).isEmpty)
    }

    @Test func trimAndRemoveAllKeepTheDiskBounded() async {
        let (pipeline, _) = makePipeline()
        let png = pngData(width: 300, height: 300)
        StubImageProtocol.handler = { _ in .init(status: 200, body: png) }
        for index in 0..<4 { _ = await collect(pipeline, URL(string: "https://example.local/\(index).png")!) }
        pipeline.trimDisk()
        #expect(pipeline.diskUsage().bytes <= pipeline.diskLimit)
        pipeline.removeAll()
        #expect(pipeline.diskUsage().files == 0)
    }
}
