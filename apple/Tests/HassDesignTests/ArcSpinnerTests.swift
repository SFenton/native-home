import Foundation
@testable import HassDesign
import SwiftUI
import Testing

struct ArcSpinnerTests {
    @Test func turnsOncePerPeriod() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(ArcSpinner.angle(at: start, reduceMotion: false) == 0)
        let quarter = Date(timeIntervalSinceReferenceDate: ArcSpinner.period / 4)
        #expect(abs(ArcSpinner.angle(at: quarter, reduceMotion: false) - 90) < 0.001)
    }

    @Test func reduceMotionHalvesTheSpeed() {
        let quarter = Date(timeIntervalSinceReferenceDate: ArcSpinner.period / 4)
        #expect(abs(ArcSpinner.angle(at: quarter, reduceMotion: true) - 45) < 0.001)
    }

    @Test(arguments: [ArcSpinner.Size.page, .compact, .inline])
    @MainActor func drawsAtItsDiameter(_ size: ArcSpinner.Size) throws {
        let image = try #require(ImageRenderer(content: ArcSpinner(size).foregroundStyle(.white)).cgImage)
        let scale = CGFloat(image.width) / size.diameter
        #expect(abs(CGFloat(image.height) / scale - size.diameter) < 0.5)
        #expect(size.lineWidth < size.diameter / 4)
    }

    @Test @MainActor func pausedSpinnerStillDraws() {
        let still = ArcSpinner(.page).environment(\.animationsPaused, true).foregroundStyle(.white)
        #expect(ImageRenderer(content: still).cgImage != nil)
    }

    @Test @MainActor func progressStyleDrawsTitledAndDeterminateViews() {
        let titled = ProgressView("Loading recipes").progressViewStyle(.arc)
        let compact = ProgressView("Finding more recipes").progressViewStyle(.arc(.compact))
        let determinate = ProgressView(value: 0.4) { Text("Sending") }.progressViewStyle(.arc)
        #expect(ImageRenderer(content: titled.frame(width: 240)).cgImage != nil)
        #expect(ImageRenderer(content: compact.frame(width: 240)).cgImage != nil)
        #expect(ImageRenderer(content: determinate.frame(width: 240)).cgImage != nil)
    }

    @Test func determinateTaskSpeaksPercentWithoutChangingStyle() {
        #expect(ArcProgressViewStyle.spokenValue(nil).isEmpty)
        #expect(ArcProgressViewStyle.spokenValue(0.4) == "40 percent")
        #expect(ArcProgressViewStyle.spokenValue(7) == "100 percent")
    }
}
