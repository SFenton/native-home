import CoreGraphics
import HassCore
import HassDesign
import ImageIO
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Store

/// The blurred photo of the house behind every page (web `AppShell.module.css` `.backdrop`: the image served by
/// Home Assistant at `/local/images/house.webp`; pattern: `.agents/patterns/page-backdrop.md`).
///
/// The photo itself loads through ``ImagePipeline`` (disk cache, conditional revalidation, updates when the server's
/// file changes; `.agents/patterns/image-cache.md`). The blur happens once, not per frame: ``BackdropRenderer`` makes
/// the finished wallpaper for the window's pixel size and the Background Blur setting (``BackdropBlurSettings``), and
/// the view only draws it. A render is kept in memory and on disk by what shaped it, so going back to a slider position
/// or relaunching reuses it, and the previous render stays up until a new one is ready (no blank, no flash; AGENTS.md
/// "No reload on reopen"). Renders run off the main thread and are coalesced: while one runs, any number of changes
/// (a slider drag, a rotation, a resized window) collapse into one more render of the latest.
@MainActor
@Observable
final class HouseBackdropStore {
    /// The wallpaper on screen, once known.
    private(set) var image: CGImage?

    /// The Background Blur setting; changing it re-renders.
    @ObservationIgnored let blur: BackdropBlurSettings
    /// Renders Core Image has drawn (stored renders that were loaded do not count).
    @ObservationIgnored private(set) var renderCount = 0

    @ObservationIgnored private let source: URL
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let photos: @Sendable (URL) -> AsyncStream<CGImage>
    @ObservationIgnored private let renderGap: Duration
    @ObservationIgnored private var refreshed = false
    @ObservationIgnored private var photo: (image: CGImage, digest: String)?
    @ObservationIgnored private var window: (size: CGSize, scale: Double)?
    @ObservationIgnored private var shownName: String?
    @ObservationIgnored private var recent: [(name: String, image: CGImage)] = []
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var isDirty = false

    /// Creates the store and loads the render that was on screen when the app last ran.
    /// - Parameters:
    ///   - server: The signed-in server, which serves the photo.
    ///   - directory: Where renders are cached.
    ///   - blur: The Background Blur setting.
    ///   - renderGap: How long to wait between back-to-back renders while the setting keeps changing.
    ///   - photos: The photo's images, cached first then fresh (tests pass a stub).
    init(server: HassServer, directory: URL = HouseBackdropStore.defaultDirectory,
         blur: BackdropBlurSettings = BackdropBlurSettings(), renderGap: Duration = HouseBackdropStore.defaultRenderGap,
         photos: @escaping @Sendable (URL) -> AsyncStream<CGImage> = HouseBackdropStore.pipelinePhotos) {
        source = Self.imageURL(for: server)
        self.directory = directory
        self.blur = blur
        self.renderGap = renderGap
        self.photos = photos
        if let latest = BackdropRenderer.loadLatest(in: directory) {
            image = latest.image
            shownName = latest.name
            recent = [(latest.name, latest.image)]
        }
        blur.onChange = { [weak self] _ in self?.requestRender() }
    }

    /// Loads the photo and renders each one the pipeline yields (the cached photo, then a changed one), once per store.
    /// Returns when the renders it asked for are done. Failures keep the render on screen.
    func refresh() async {
        guard !refreshed else { return }
        refreshed = true
        let directory = directory
        // Renders from an older recipe are never read again; drop them off the main thread.
        Task.detached(priority: .background) { BackdropRenderer.removeRetired(in: directory) }
        for await photo in photos(source) {
            let digest = await Task.detached(priority: .utility) { BackdropRenderer.digest(of: photo) }.value
            self.photo = (photo, digest)
            requestRender()
        }
        await settled()
    }

    /// Tells the store how big the window is (points) and how dense (pixels per point); a change re-renders.
    func setWindow(_ size: CGSize, scale: Double) {
        guard window?.size != size || window?.scale != scale else { return }
        window = (size, scale)
        requestRender()
    }

    /// Returns once no render is running or waiting.
    func settled() async {
        while let task = renderTask { await task.value }
    }

    // MARK: Rendering

    /// Asks for a render of the current photo, window and setting. Runs one at a time: a request while one is running
    /// marks the store dirty, and the loop renders the latest once the running one is done.
    private func requestRender() {
        guard photo != nil, window != nil else { return }
        isDirty = true
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            while let self, self.isDirty {
                self.isDirty = false
                await self.renderCurrent()
                if self.isDirty, self.renderGap > .zero { try? await Task.sleep(for: self.renderGap) }
            }
            self?.renderTask = nil
        }
    }

    private func renderCurrent() async {
        guard let photo, let window,
              let spec = BackdropRenderSpec(points: window.size, displayScale: window.scale, percent: blur.percent) else { return }
        let name = spec.cacheName(photo: photo.digest)
        if name == shownName { return }
        if let hit = recent.first(where: { $0.name == name }) {
            show(hit.image, name: name)
            return
        }
        let directory = directory
        let (picture, digest) = (photo.image, photo.digest)
        let result = await Task.detached(priority: .utility) {
            BackdropRenderer.renderOrLoad(picture, digest: digest, spec: spec, in: directory)
        }.value
        guard let result else { return }
        if result.rendered { renderCount += 1 }
        show(result.image, name: name)
    }

    private func show(_ render: CGImage, name: String) {
        image = render
        shownName = name
        recent.removeAll { $0.name == name }
        recent.append((name, render))
        if recent.count > Self.memoryRenders { recent.removeFirst(recent.count - Self.memoryRenders) }
        let directory = directory
        Task.detached(priority: .utility) { BackdropRenderer.markLatest(name, in: directory) }
    }

    // MARK: Pure helpers

    /// Renders kept in memory: the last few slider positions.
    nonisolated static let memoryRenders = 4
    /// The pause between back-to-back renders while the slider moves: about seven live previews a second.
    nonisolated static let defaultRenderGap: Duration = .milliseconds(140)
    /// The longest side the photo is decoded at: enough for the densest phone at the sharpest setting.
    nonisolated static let photoPixels = 2560

    /// `<server>/local/images/house.webp`, Home Assistant's public `www` folder (no sign-in needed).
    nonisolated static func imageURL(for server: HassServer) -> URL {
        server.baseURL.appending(path: "local/images/house.webp")
    }

    /// The photo from the shared ``ImagePipeline``, decoded at ``photoPixels``.
    nonisolated static func pipelinePhotos(_ url: URL) -> AsyncStream<CGImage> {
        ImagePipeline.shared.images(for: url, maxPixel: photoPixels)
    }

    /// The store a signed-in session shows. Debug builds honour `FENTON_BACKDROP_FIXTURE=1` (UI tests): a bright
    /// synthetic photo rendered into a throwaway folder with its own settings, so a journey can tell wallpaper from
    /// the plain base color whatever the house photo looks like, and never touches the real cached render or the
    /// saved Background Blur.
    static func session(for server: HassServer) -> HouseBackdropStore {
        #if DEBUG
        if let fixture = fixture(for: server) { return fixture }
        #endif
        return HouseBackdropStore(server: server)
    }

    #if DEBUG
    /// The fixture store when `FENTON_BACKDROP_FIXTURE=1`; `FENTON_BACKDROP_BLUR=<percent>` starts it at that setting.
    static func fixture(for server: HassServer) -> HouseBackdropStore? {
        let environment = ProcessInfo.processInfo.environment
        // The `FENTON_GALLERY_BACKDROP_*` forms are gallery settings a reused journey app can change between tests; they win.
        guard (environment["FENTON_GALLERY_BACKDROP_FIXTURE"] ?? environment["FENTON_BACKDROP_FIXTURE"]) == "1" else { return nil }
        let folder = URL.temporaryDirectory.appending(path: "HouseBackdropFixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suite = UserDefaults(suiteName: "HouseBackdropFixture-\(UUID().uuidString)") ?? .standard
        if let percent = (environment["FENTON_GALLERY_BACKDROP_BLUR"] ?? environment["FENTON_BACKDROP_BLUR"]).flatMap(Int.init) {
            suite.set(percent, forKey: BackdropBlur.defaultsKey)
        }
        // `FENTON_BACKDROP_PHOTO=<path>` shows that image instead (side-by-side screenshots with the web).
        let photo = environment["FENTON_BACKDROP_PHOTO"].flatMap { BackdropRenderer.load(URL(fileURLWithPath: $0)) } ?? fixturePhoto()
        return HouseBackdropStore(server: server, directory: folder, blur: BackdropBlurSettings(defaults: suite)) { _ in
            AsyncStream { continuation in
                if let photo { continuation.yield(photo) }
                continuation.finish()
            }
        }
    }

    /// A bright, detailed photo: diagonal orange to sky blue crossed by cream bands, so the blur setting shows in it. After the darkest scrim stop (0.64) it still measures about ten times the plain base color's luminance.
    nonisolated static func fixturePhoto() -> CGImage? {
        guard let context = CGContext(data: nil, width: 960, height: 640, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                CGColor(red: 1, green: 0.63, blue: 0.24, alpha: 1), CGColor(red: 0.47, green: 0.78, blue: 1, alpha: 1),
              ] as CFArray, locations: [0, 1]) else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 960, y: 640), options: [])
        context.setFillColor(CGColor(red: 1, green: 1, blue: 0.85, alpha: 1))
        // Full-width cream bands, so any crop of the photo crosses them.
        for row in 0..<4 {
            context.fill(CGRect(x: 0, y: 70 + row * 140, width: 960, height: 70))
        }
        return context.makeImage()
    }
    #endif

    /// The cache folder: Caches/HouseBackdrop.
    nonisolated static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "HouseBackdrop", directoryHint: .isDirectory)
    }
}

/// The backdrop's layers (direction G, Layers: the photo magnified 1.06 under a black scrim).
enum HouseBackdropStyle {
    /// Under the photo, and the whole backdrop with Reduce Transparency: the web shell's `#111723`.
    static let base = Color(red: 17 / 255, green: 23 / 255, blue: 35 / 255)

    /// The page's window position the photo is shifted by: `origin` with negative values held at zero. A page sliding
    /// out (the outgoing page of a push moves left, partly off screen) has a negative origin, and shifting the photo
    /// by it pulled the photo off the edge that still shows, leaving a strip of plain base color (a black flash).
    static func shift(origin: CGPoint) -> CGPoint {
        CGPoint(x: max(origin.x, 0), y: max(origin.y, 0))
    }

    /// How far the photo is magnified past the window, so the blur's soft edges stay off screen. Baked into the render
    /// (``BackdropRenderSpec/scale``), not applied by the view.
    static let scale = BackdropRenderSpec.scale

    /// The scrim's black opacity from top to bottom, denser behind the tab bar. The top half carries the large title and
    /// the first section headers in white, so it never drops below 0.44. At G's original 0.18 an iPhone's light sky
    /// measured 3.0:1 for the section header. When the blur went from sigma 20 on a 480 px copy (about 58 pt on screen)
    /// to the web's 16.8 pt (2026-10-17) the photo kept more detail, and the brightest sky pixels behind the 30 to 40%
    /// band (the roofline) rose to 4.3:1 against white at the old 0.40; 0.45 and 0.46 in the middle stops keep every
    /// band above 4.9:1 at the default blur and 4.7:1 at 25% (measured on the house photo, `page-backdrop.md` R5).
    static let scrimOpacities: [(location: Double, value: Double)] = [(0, 0.44), (0.28, 0.45), (0.50, 0.46), (0.75, 0.52), (1, 0.64)]

    /// ``scrimOpacities`` as gradient stops.
    static let scrimStops: [Gradient.Stop] = scrimOpacities.map { .init(color: .black.opacity($0.value), location: $0.location) }

    /// How much denser every scrim stop is with Increase Contrast.
    static let increasedContrastBoost = 0.12

    /// The scrim's stops, `increasedContrastBoost` denser when the system asks for more contrast.
    static func scrimStops(increasedContrast: Bool) -> [Gradient.Stop] {
        guard increasedContrast else { return scrimStops }
        return scrimOpacities.map { .init(color: .black.opacity($0.value + increasedContrastBoost), location: $0.location) }
    }

    /// Over the photo.
    static var scrim: some View { scrimView(increasedContrast: false) }

    /// Over the photo, denser with Increase Contrast.
    static func scrimView(increasedContrast: Bool) -> some View {
        LinearGradient(stops: scrimStops(increasedContrast: increasedContrast), startPoint: .top, endPoint: .bottom)
    }
}
