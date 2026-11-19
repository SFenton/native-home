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

    // MARK: - Background

    /// Nothing renders in the background; the change made there renders on the return to the foreground.
    @Test func aSuspendedStoreRendersOnlyOnceBackInTheForeground() async throws {
        let (store, directory, cleanup) = try makeStore()
        defer { cleanup() }
        store.setSuspended(true)
        store.setWindow(CGSize(width: 60, height: 90), scale: 1)
        await store.refresh()
        #expect(store.image == nil)
        #expect(store.renderCount == 0)
        #expect(BackdropRenderer.loadLatest(in: directory) == nil, "nothing is stored while suspended")

        store.setSuspended(false)
        // The publication's retried preparation refreshes again: that waits for the render the return started.
        await store.refresh()
        #expect(store.image != nil)
        #expect(store.renderCount == 1)
    }

    /// A change in the background (the system's snapshot layout) waits; the shown render stays until the return.
    @Test func aChangeInTheBackgroundWaitsForTheForeground() async throws {
        let (store, _, cleanup) = try makeStore()
        defer { cleanup() }
        store.setWindow(CGSize(width: 60, height: 90), scale: 1)
        await store.refresh()
        let shown = try #require(store.image)

        store.setSuspended(true)
        store.setWindow(CGSize(width: 90, height: 60), scale: 1)
        await store.settled()
        #expect(store.image === shown)
        #expect(store.renderCount == 1)

        store.setSuspended(false)
        await store.settled()
        #expect(store.image !== shown)
        #expect(store.renderCount == 2)
    }

    /// A render the app went to the background during may be blank: it is thrown away, not shown or stored, and made again.
    @Test func aRenderOverlappingTheBackgroundIsDiscardedAndRedone() async throws {
        let (store, directory, cleanup) = try makeStore()
        defer { cleanup() }
        store.setWindow(CGSize(width: 60, height: 90), scale: 1)
        let refresh = Task { await store.refresh() }
        // The render runs off the main thread; the app leaves before it comes back.
        try #require(await until { store.renderCount == 0 && store.isRendering })
        store.setSuspended(true)
        await refresh.value
        #expect(store.image == nil, "the overlapping render is not shown")
        #expect(store.renderCount == 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(BackdropRenderer.loadLatest(in: directory) == nil, "nor stored")

        store.setSuspended(false)
        await store.settled()
        #expect(store.image != nil)
        #expect(store.renderCount == 1)
    }

    /// The render folder is the publication's, not the window's: the next launch shows the stored render on its first frame.
    @Test func aRelaunchInTheSameFolderShowsTheStoredRenderAtOnce() async throws {
        let (store, directory, cleanup) = try makeStore()
        defer { cleanup() }
        store.setWindow(CGSize(width: 60, height: 90), scale: 1)
        await store.refresh()
        let rendered = try #require(store.image)
        try #require(await until { BackdropRenderer.loadLatest(in: directory) != nil })

        let relaunch = HouseBackdropStore(verifiedPhoto: try makePhoto(), directory: directory, blur: store.blur)
        let first = try #require(relaunch.image, "the stored render is up before any render runs")
        #expect(first.width == rendered.width && first.height == rendered.height)
        relaunch.setWindow(CGSize(width: 60, height: 90), scale: 1)
        await relaunch.refresh()
        #expect(relaunch.renderCount == 0, "the stored render is reused, not made again")
    }

    // MARK: - Fixture

    private func makeStore() throws -> (HouseBackdropStore, URL, () -> Void) {
        let directory = URL.temporaryDirectory.appending(path: "backdrop-life-\(UUID().uuidString)")
        let suiteName = "backdrop-life-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = HouseBackdropStore(verifiedPhoto: try makePhoto(), directory: directory, blur: BackdropBlurSettings(defaults: defaults))
        return (store, directory, {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        })
    }

    private func until(_ seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            await Task.yield()
        }
        return true
    }
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
