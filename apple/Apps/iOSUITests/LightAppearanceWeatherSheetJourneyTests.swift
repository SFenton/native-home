import XCTest

/// The Weather sheet draws over its condition gradient and stays dark in the light appearance (`Features/Home/Weather`).
@MainActor
final class LightAppearanceWeatherSheetJourneyTests: LightAppearanceJourneyTestCase {
    /// The Weather sheet draws over its condition gradient and stays dark in the light appearance.
    func testWeatherSheetStaysDarkInLight() {
        let app = gallery("weather", environment: ["FENTON_GALLERY_WEATHER_OPEN": "1"])
        waitReady("weather.sheet", in: app, what: "Weather sheet")
        guard let capture = RenderedContrast.Capture.screen() else { return XCTFail("No capture") }
        let window = app.windows.firstMatch.frame
        let samples = [0.3, 0.45, 0.6].compactMap {
            RenderedContrast.luminance(at: CGPoint(x: window.midX, y: window.height * $0), in: capture)
        }
        keepScreenshot(app, "light-weather-stays-dark-\(layout)")
        XCTAssertFalse(samples.isEmpty)
        // The middle sample, not all of them: a white title or hero figure crosses the line.
        XCTAssertLessThan(samples.sorted()[samples.count / 2], 0.5, "The Weather sheet must stay dark; luminance \(samples)")
    }
}
