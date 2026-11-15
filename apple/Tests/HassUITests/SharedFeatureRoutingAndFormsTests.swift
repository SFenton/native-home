import CoreGraphics
import Foundation
import HassCore
import HassDesign
import SwiftUI
import Testing
@testable import HassUI
import HassTestSupport

/// Snapshot feedback and the camera split rule: what the UIKit
/// pages ask `HassUI/Features` for.
@MainActor
@Suite(.demoHouse)
struct SharedFeatureRoutingAndFormsTests {
    // MARK: Custom lights

    @Test func aCustomLightSheetSubtitleSaysUnavailableOnOrOffWithPercent() {
        #expect(CustomLightSheet.subtitle(nil) == "Unavailable")
        #expect(CustomLightSheet.subtitle(EntityState(entityId: "light.demo_a", state: "unavailable")) == "Unavailable")
        #expect(CustomLightSheet.subtitle(EntityState(entityId: "light.demo_a", state: "off")) == "Off")
        #expect(CustomLightSheet.subtitle(EntityState(entityId: "light.demo_a", state: "on", attributes: ["brightness": .number(128)])) == "On · 50%")
        #expect(CustomLightSheet.subtitle(EntityState(entityId: "light.demo_a", state: "on")) == "On · 100%")
    }

    @Test func aSwiftUIColourBecomesEightBitSRGBChannels() throws {
        let rgb = try #require(CustomLightsConfig.RGB(color: Color(.sRGB, red: 1, green: 0.5, blue: 0, opacity: 1)))
        #expect(rgb == CustomLightsConfig.RGB(255, 128, 0))
    }

    // MARK: Camera snapshot and split

    @Test func snapshotFeedbackSpeaksEachStage() {
        let stages: [(CameraSnapshotFeedback, String, String, String)] = [
            (.idle, "Snapshot", "camera.fill", ""), (.saving, "Snapshot", "camera.fill", "Saving"),
            (.saved, "Saved", "checkmark.circle.fill", "Saved to Photos"),
            (.failed, "Not Saved", "exclamationmark.triangle.fill", "Couldn't save the snapshot"),
        ]
        for (stage, title, symbol, value) in stages {
            #expect(stage.title == title)
            #expect(stage.symbol == symbol)
            #expect(stage.accessibilityValue == value)
        }
    }

    @Test func aSnapshotNeedsAFrameOrAReachableStill() async throws {
        #expect(await CameraSnapshotSaver.save(frame: nil, fallbackURL: nil) == .failed)
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let jpeg = try #require(CameraSnapshotSaver.jpeg(image))
        #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]), "a JPEG")
        // The Mac host has no Photos library to add to.
        #expect(await CameraSnapshotSaver.save(frame: image, fallbackURL: nil) == .failed)
    }

    @Test func theCameraViewerSplitsOnlyWhenWideAndLandscapeAndRoomy() {
        let landscape = CGSize(width: 1_180, height: 820)
        #expect(CameraViewerLayout.usesSplit(window: landscape, isRegularWidth: true, container: CGSize(width: 700, height: 600)))
        #expect(!CameraViewerLayout.usesSplit(window: landscape, isRegularWidth: true, container: CGSize(width: 500, height: 600)))
        #expect(!CameraViewerLayout.usesSplit(window: landscape, isRegularWidth: false, container: CGSize(width: 700, height: 600)))
        #expect(!CameraViewerLayout.usesSplit(window: CGSize(width: 820, height: 1_180), isRegularWidth: true, container: CGSize(width: 700, height: 600)))
    }
}
