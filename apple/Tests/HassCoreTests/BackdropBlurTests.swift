import Foundation
@testable import HassCore
import Testing

/// Background Blur: the web mapping, the saved setting and the render spec that names a cached render
/// (pattern: `.agents/patterns/page-backdrop.md`).
@MainActor
struct BackdropBlurTests {
    private func defaults() -> UserDefaults {
        let suite = "BackdropBlurTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: Mapping

    /// `AppShell.module.css:58-65` blurs by 16px then scales the element by 1.05: 16.8 on screen.
    @Test func defaultIsTheWebsBlurOnScreen() {
        #expect(BackdropBlur.webRadius == 16)
        #expect(BackdropBlur.webScale == 1.05)
        #expect(abs(BackdropBlur.defaultRadius - 16.8) < 1e-9)
        #expect(BackdropBlur.radius(forPercent: BackdropBlur.defaultPercent) == BackdropBlur.defaultRadius)
    }

    @Test func sliderRunsFromSharpToTwiceTheDefault() {
        #expect(BackdropBlur.radius(forPercent: 0) == 0)
        #expect(abs(BackdropBlur.radius(forPercent: 100) - 33.6) < 1e-9)
        #expect(BackdropBlur.radius(forPercent: 25) == BackdropBlur.defaultRadius / 2)
        #expect(BackdropBlur.percentRange == 0...100)
        #expect(BackdropBlur.step == 5)
    }

    @Test func percentsAreClamped() {
        #expect(BackdropBlur.clamp(-20) == 0)
        #expect(BackdropBlur.clamp(37) == 37)
        #expect(BackdropBlur.clamp(250) == 100)
        #expect(BackdropBlur.radius(forPercent: 250) == BackdropBlur.maxRadius)
        #expect(BackdropBlur.radius(forPercent: -3) == 0)
    }

    @Test func storedValuesMeanTheirPercentOrTheDefault() {
        #expect(BackdropBlur.percent(fromStored: nil) == 50)
        #expect(BackdropBlur.percent(fromStored: "lots") == 50)
        #expect(BackdropBlur.percent(fromStored: NSNumber(value: 80)) == 80)
        #expect(BackdropBlur.percent(fromStored: NSNumber(value: 61.6)) == 62)
        #expect(BackdropBlur.percent(fromStored: NSNumber(value: -5)) == 0)
        #expect(BackdropBlur.percent(fromStored: NSNumber(value: 900)) == 100)
    }

    @Test func labelsReadAsPercent() {
        #expect(BackdropBlur.label(forPercent: 50) == "50%")
        #expect(BackdropBlur.label(forPercent: 120) == "100%")
        #expect(BackdropBlur.spokenValue(forPercent: 35) == "35 percent")
    }

    // MARK: Setting

    @Test func startsAtTheDefaultAndPersists() {
        let store = defaults()
        let first = BackdropBlurSettings(defaults: store)
        #expect(first.percent == 50 && first.isDefault)
        #expect(first.radius == BackdropBlur.defaultRadius)
        first.set(15)
        #expect(first.percent == 15 && !first.isDefault)
        #expect(store.integer(forKey: BackdropBlur.defaultsKey) == 15)
        // A later launch reads it back.
        let second = BackdropBlurSettings(defaults: store)
        #expect(second.percent == 15)
        #expect(second.radius == BackdropBlur.radius(forPercent: 15))
    }

    @Test func settingIsClampedAndOnlyChangesNotify() {
        let settings = BackdropBlurSettings(defaults: defaults())
        var seen: [Int] = []
        settings.onChange = { seen.append($0) }
        settings.set(50) // unchanged
        settings.set(300)
        settings.set(100) // clamped to the same
        settings.set(-4)
        #expect(seen == [100, 0])
        #expect(settings.percent == 0)
    }

    @Test func resetReturnsToTheWebDefault() {
        let store = defaults()
        let settings = BackdropBlurSettings(defaults: store)
        var seen: [Int] = []
        settings.set(90)
        settings.onChange = { seen.append($0) }
        settings.reset()
        #expect(settings.percent == 50 && settings.isDefault)
        #expect(store.integer(forKey: BackdropBlur.defaultsKey) == 50)
        #expect(seen == [50])
        settings.reset()
        #expect(seen == [50])
    }

    @Test func sliderValueReadsAndWritesThePercent() {
        let settings = BackdropBlurSettings(defaults: defaults())
        #expect(settings.sliderValue == 50)
        settings.sliderValue = 64.6
        #expect(settings.percent == 65 && settings.sliderValue == 65)
    }

    @Test func aSavedOutOfRangeValueIsClamped() {
        let store = defaults()
        store.set(999, forKey: BackdropBlur.defaultsKey)
        #expect(BackdropBlurSettings(defaults: store).percent == 100)
    }

    // MARK: Render spec

    @Test func specNeedsAWindow() {
        #expect(BackdropRenderSpec(points: .zero, displayScale: 3, percent: 50) == nil)
        #expect(BackdropRenderSpec(points: CGSize(width: 0.5, height: 800), displayScale: 3, percent: 50) == nil)
        #expect(BackdropRenderSpec(points: CGSize(width: 400, height: 800), displayScale: 0, percent: 50) == nil)
    }

    @Test func specSizesTheRenderFromThePhonesPixels() throws {
        let spec = try #require(BackdropRenderSpec(points: CGSize(width: 402, height: 874), displayScale: 3, percent: 50))
        #expect(spec.pixelWidth == 1206 && spec.pixelHeight == 2622 && spec.pixelsPerPoint == 3)
        // The web's 16.8 pt is 50.4 px here; a blur that wide is rendered at a quarter of the resolution.
        #expect(abs(spec.sigmaPixels - 50.4) < 1e-9)
        #expect(spec.divisor == 4)
        #expect(spec.renderWidth == 302 && spec.renderHeight == 656)
        #expect(abs(spec.renderSigma - 12.6) < 1e-9)
    }

    @Test func sharpAndLightRendersKeepTheirResolution() throws {
        let window = CGSize(width: 402, height: 874)
        let sharp = try #require(BackdropRenderSpec(points: window, displayScale: 3, percent: 0))
        #expect(sharp.sigmaPixels == 0 && sharp.divisor == 1)
        #expect(sharp.renderWidth == 1206 && sharp.renderHeight == 2622 && sharp.renderSigma == 0)
        let light = try #require(BackdropRenderSpec(points: window, displayScale: 3, percent: 10))
        #expect(light.divisor == 1)
        let medium = try #require(BackdropRenderSpec(points: window, displayScale: 3, percent: 30))
        #expect(medium.divisor == 3)
        // The blur never drops under the minimum in render pixels once the render is made smaller.
        for percent in stride(from: 0, through: 100, by: 5) {
            let spec = try #require(BackdropRenderSpec(points: window, displayScale: 3, percent: percent))
            if spec.divisor > 1 { #expect(spec.renderSigma >= BackdropRenderSpec.minimumSigma) }
            #expect(spec.divisor <= BackdropRenderSpec.maxDivisor)
        }
    }

    @Test func largeScreensAreCappedInPixels() throws {
        let spec = try #require(BackdropRenderSpec(points: CGSize(width: 1200, height: 1600), displayScale: 3, percent: 50))
        #expect(max(spec.pixelWidth, spec.pixelHeight) == BackdropRenderSpec.maxPixels)
        #expect(spec.pixelsPerPoint < 3)
        // The blur is still 16.8 pt on screen whatever the density.
        #expect(abs(spec.sigmaPixels / spec.pixelsPerPoint - BackdropBlur.defaultRadius) < 1e-9)
    }

    @Test func percentIsClampedInTheSpec() throws {
        let spec = try #require(BackdropRenderSpec(points: CGSize(width: 400, height: 800), displayScale: 2, percent: 500))
        #expect(spec.percent == 100)
    }

    @Test func cacheNameIsKeyedByEverythingThatShapesThePicture() throws {
        let base = try #require(BackdropRenderSpec(points: CGSize(width: 402, height: 874), displayScale: 3, percent: 50))
        let name = base.cacheName(photo: "abc123")
        #expect(name == base.cacheName(photo: "abc123"))
        #expect(name.hasPrefix("backdrop-\(BackdropRenderSpec.recipe)-abc123-1206x2622-d3000-b50"))
        #expect(name.hasSuffix(".jpg"))
        let others = [
            base.cacheName(photo: "other"),
            try #require(BackdropRenderSpec(points: CGSize(width: 402, height: 874), displayScale: 3, percent: 55)).cacheName(photo: "abc123"),
            try #require(BackdropRenderSpec(points: CGSize(width: 874, height: 402), displayScale: 3, percent: 50)).cacheName(photo: "abc123"),
            try #require(BackdropRenderSpec(points: CGSize(width: 402, height: 874), displayScale: 2, percent: 50)).cacheName(photo: "abc123"),
        ]
        #expect(Set(others + [name]).count == 5)
    }
}
