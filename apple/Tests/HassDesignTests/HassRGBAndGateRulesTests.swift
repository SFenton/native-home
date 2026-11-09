import CoreGraphics
@testable import HassDesign
import Testing

/// The adaptive colour token, the Duo sheet rules and the readiness tracker the content gate waits on.
struct HassRGBTests {
    @Test func aFixedColourIsTheSameInEveryAppearanceAndAnAdaptiveOneIsNot() {
        let red = HassRGB(rgb: 0xFF0000)
        #expect(red.isFixed)
        #expect(red.components(isDark: true, increasedContrast: true) == red.components(isDark: false, increasedContrast: false))
        let adaptive = HassRGB.adaptive(light: 0x000000, dark: 0xFFFFFF)
        #expect(!adaptive.isFixed)
        #expect(adaptive.components(isDark: false, increasedContrast: false).red == 0)
        #expect(adaptive.components(isDark: true, increasedContrast: false).red == 1)
        #expect(adaptive.components(isDark: false, increasedContrast: true) == adaptive.light, "increased variants default to the base")
        #expect(adaptive.components(isDark: true, increasedContrast: true) == adaptive.dark)
        #expect(HassRGB.label.light.red == 0 && HassRGB.label.dark.red == 1)
        #expect(HassRGB.white.light.blue == 1 && HassRGB.black.light.blue == 0 && HassRGB.clear.light.alpha == 0)
    }

    @Test func increasedContrastVariantsAreKeptWhenGiven() {
        let token = HassRGB(light: .init(rgb: 0x111111), dark: .init(rgb: 0xEEEEEE),
                            lightIncreased: .init(rgb: 0x000000), darkIncreased: .init(rgb: 0xFFFFFF))
        #expect(token.components(isDark: false, increasedContrast: true).red == 0)
        #expect(token.components(isDark: true, increasedContrast: true).red == 1)
    }

    @Test func opacityScalesAlphaWhileWithAlphaReplacesItAndMixedBlendsEveryVariant() {
        let half = HassRGB(rgb: 0x336699, alpha: 0.5)
        #expect(half.opacity(0.5).light.alpha == 0.25)
        #expect(half.withAlpha(0.9).dark.alpha == 0.9)
        let mid = HassRGB.black.mixed(with: .white, amount: 0.5)
        #expect(mid.light.red == 0.5 && mid.darkIncreased.green == 0.5)
        #expect(HassRGB.black.mixed(with: .white, amount: 0) == .black)
        #expect(HassRGB.black.mixed(with: .white, amount: 1) == .white)
    }
}

struct DuoSheetPolicyTests {
    @Test func aSheetFillsTheHeightOnlyOnAHingedDeviceWithoutAHorizontalFold() {
        #expect(!DuoSheetPolicy.fillsHeight(hasHinge: false, hinge: nil))
        #expect(DuoSheetPolicy.fillsHeight(hasHinge: true, hinge: nil))
        #expect(DuoSheetPolicy.fillsHeight(hasHinge: true, hinge: CGRect(x: 400, y: 0, width: 10, height: 800)), "a vertical hinge")
        #expect(!DuoSheetPolicy.fillsHeight(hasHinge: true, hinge: CGRect(x: 0, y: 400, width: 800, height: 10)), "a horizontal one")
    }

    @MainActor @Test func theDeviceFlagMakesAHingeRequirementEvenWhenNoneIsReported() {
        DuoSheetPolicy.deviceHasHinge = false
        defer { DuoSheetPolicy.deviceHasHinge = false }
        #expect(!DuoSheetPolicy.fillsHeight(hinge: nil))
        #expect(DuoSheetPolicy.fillsHeight(hinge: CGRect(x: 400, y: 0, width: 10, height: 800)))
        DuoSheetPolicy.deviceHasHinge = true
        #expect(DuoSheetPolicy.fillsHeight(hinge: nil))
    }

    @Test func theLeadingHalfEndsAtTheHingeOrTheMidpointLessItsMargin() throws {
        let hinge = CGRect(x: 400, y: 0, width: 20, height: 800)
        let folding = WindowFold(hinge: hinge, isFolding: true)
        #expect(DuoSheetPolicy.leadingHalfWidth(fold: folding, freeWidth: 820) == 392)
        #expect(DuoSheetPolicy.leadingHalfWidth(hinge: hinge) == 392)
        let flat = WindowFold(hinge: hinge, isFolding: false)
        let expected = ((821 - DuoSheetPolicy.midpointBand) / 2 - DuoSheetPolicy.halfMargin).rounded(.down)
        #expect(DuoSheetPolicy.leadingHalfWidth(fold: flat, freeWidth: 821) == expected)
        #expect(DuoSheetPolicy.leadingHalfWidth(fold: .none, freeWidth: 800) == nil)
        let horizontal = WindowFold(hinge: CGRect(x: 0, y: 400, width: 800, height: 10), isFolding: true)
        #expect(DuoSheetPolicy.leadingHalfWidth(fold: horizontal, freeWidth: 800) == nil)
        #expect(DuoSheetPolicy.leadingHalfWidth(hinge: nil) == nil)
        let tiny = WindowFold(hinge: CGRect(x: 3, y: 0, width: 10, height: 800), isFolding: true)
        #expect(DuoSheetPolicy.leadingHalfWidth(fold: tiny, freeWidth: 800) == 0, "never negative")
    }
}

@MainActor
struct ReadinessTrackerTests {
    @Test func theTrackerIsSettledOnlyWhenNothingIsPending() {
        let tracker = ReadinessTracker()
        #expect(tracker.isSettled)
        tracker.set("image:a", ready: false)
        tracker.set("image:b", ready: false)
        tracker.set("image:b", ready: false)
        #expect(!tracker.isSettled)
        #expect(tracker.pending == ["image:a", "image:b"])
        tracker.set("image:a", ready: true)
        tracker.set("image:unknown", ready: true)
        #expect(tracker.pending == ["image:b"])
        tracker.set("image:b", ready: true)
        #expect(tracker.isSettled)
    }
}
