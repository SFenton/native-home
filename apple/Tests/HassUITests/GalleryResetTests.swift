@testable import HassUI
import Foundation
import Testing

/// The in-place gallery reset the UI-test classes reuse one app with (`GalleryReset`, `.agents/testing/apple/app-reuse.md`).
@MainActor
struct GalleryResetTests {
    private func url(_ query: String) -> URL { URL(string: "fentonhome://uitest-reset?\(query)")! }

    @Test func aResetReplacesTheGalleryVariablesAndUnsetsTheRest() {
        let plan = GalleryReset.plan(
            for: url("FENTON_GALLERY=bedroom&FENTON_GALLERY_SCENARIO=ringing"),
            environment: ["FENTON_GALLERY": "food", "FENTON_GALLERY_SHEET": "wake-light", "FENTON_GALLERY_TAB": "x", "PATH": "/bin"])
        #expect(plan?.set == ["FENTON_GALLERY": "bedroom", "FENTON_GALLERY_SCENARIO": "ringing"])
        #expect(plan?.unset == ["FENTON_GALLERY_SHEET", "FENTON_GALLERY_TAB"])
    }

    @Test func variablesOutsideThePrefixAreNeverTouched() {
        let plan = GalleryReset.plan(for: url("FENTON_GALLERY=bedroom&FENTON_SKIP_INTRO=0&PATH=/x"),
                                     environment: ["FENTON_SKIP_INTRO": "1"])
        #expect(plan?.set == ["FENTON_GALLERY": "bedroom"])
        #expect(plan?.unset == [])
    }

    @Test func valuesArePercentDecoded() {
        let plan = GalleryReset.plan(for: url("FENTON_GALLERY=bedroom&FENTON_GALLERY_SCENARIO=solo%20trip"), environment: [:])
        #expect(plan?.set["FENTON_GALLERY_SCENARIO"] == "solo trip")
    }

    @Test func otherURLsAreNotResets() {
        #expect(GalleryReset.plan(for: URL(string: "fentonhome://activity/job")!, environment: [:]) == nil)
        #expect(GalleryReset.plan(for: URL(string: "https://uitest-reset?FENTON_GALLERY=x")!, environment: [:]) == nil)
    }

    @Test func aLaunchThatDidNotOptInIgnoresTheRequest() {
        #expect(!GalleryReset.isEnabled(environment: [:]))
        #expect(GalleryReset.isEnabled(environment: ["FENTON_UITEST_REUSE": "1"]))
        let reset = GalleryReset()
        // The test process did not launch with FENTON_UITEST_REUSE, so the request is refused and nothing changes.
        #expect(!reset.apply(url("FENTON_GALLERY=bedroom")))
        #expect(reset.generation == 0)
    }

    @Test func aTextSizeRequestCarriesASequenceAndASize() {
        let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"
        #expect(GalleryReset.textSizeRequest(from: "2\n\(ax5)")?.sequence == 2)
        #expect(GalleryReset.textSizeRequest(from: "2\n\(ax5)")?.size == ax5)
        // Empty or missing: back to the launch's own size.
        #expect(GalleryReset.textSizeRequest(from: "3\n")?.size == nil)
        #expect(GalleryReset.textSizeRequest(from: "3")?.sequence == 3)
        #expect(GalleryReset.textSizeRequest(from: "3")?.size == nil)
        #expect(GalleryReset.textSizeRequest(from: "x\n\(ax5)") == nil)
        #expect(GalleryReset.textSizeRequest(from: "") == nil)
    }

    @Test func theTextSizeFilesSitInTheRequestDirectory() {
        #expect(GalleryReset.textSizeFile(environment: ["FENTON_UITEST_REUSE": "/tmp/r"]) == "/tmp/r/textSize")
        #expect(GalleryReset.textSizeDoneFile(environment: ["FENTON_UITEST_REUSE": "/tmp/r"]) == "/tmp/r/textSize.done")
        #expect(GalleryReset.textSizeFile(environment: [:]) == nil)
        #expect(GalleryReset.textSizeFile(environment: ["FENTON_UITEST_REUSE": ""]) == nil)
    }

    @Test func aRequestFileCarriesASequenceAndAQuery() {
        let request = GalleryReset.request(from: "3\nFENTON_GALLERY=bedroom&FENTON_GALLERY_SHEET=wake-light")
        #expect(request?.sequence == 3)
        #expect(request.flatMap { GalleryReset.plan(for: $0.url, environment: [:]) }?.set["FENTON_GALLERY_SHEET"] == "wake-light")
        #expect(GalleryReset.request(from: "x\nFENTON_GALLERY=a") == nil)
        #expect(GalleryReset.request(from: "4") == nil)
        #expect(GalleryReset.request(from: "") == nil)
    }

    @Test func theRequestFileLivesInTheLaunchDirectory() {
        #expect(GalleryReset.requestFile(environment: ["FENTON_UITEST_REUSE": "/tmp/x"]) == "/tmp/x/request")
        #expect(GalleryReset.requestFile(environment: [:]) == nil)
        #expect(GalleryReset.requestFile(environment: ["FENTON_UITEST_REUSE": ""]) == nil)
    }

    /// The reset works by changing the process environment; the galleries read `ProcessInfo` live, so it must reflect it.
    @Test func processInfoReflectsAnEnvironmentChangeMadeInProcess() {
        let key = "FENTON_GALLERY_RESET_PROBE"
        setenv(key, "a", 1)
        #expect(ProcessInfo.processInfo.environment[key] == "a")
        setenv(key, "b", 1)
        #expect(ProcessInfo.processInfo.environment[key] == "b")
        unsetenv(key)
        #expect(ProcessInfo.processInfo.environment[key] == nil)
    }
}
