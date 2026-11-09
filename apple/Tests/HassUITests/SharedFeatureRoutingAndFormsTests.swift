import CoreGraphics
import Foundation
import HassCore
import HassDesign
import SwiftUI
import Testing
@testable import HassUI
import HassTestSupport

/// Routes, device-sheet resolution, the Donetick due-date bindings, snapshot feedback and the camera split rule: what the UIKit
/// pages ask `HassUI/Features` for.
@MainActor
@Suite(.demoHouse)
struct SharedFeatureRoutingAndFormsTests {
    // MARK: Home routes

    @Test func everyFixedRouteRoundTripsThroughItsPathAndHasATitleAndIcon() {
        let fixed: [(HomeRoute, String, String)] = [
            (.media, "Media", "mdi:remote"), (.customLights, "Custom Lights", "mdi:lightbulb-group"),
            (.sprinklers, "Sprinklers", "mdi:sprinkler-variant"), (.vacuums, "Vacuums", "mdi:robot-vacuum"),
            (.food, "Food & Recipes", "mdi:food-fork-drink"), (.groceryList, "Grocery List", "mdi:cart"),
        ]
        for (route, title, icon) in fixed {
            #expect(route.title == title)
            #expect(route.mdiIcon == icon)
            #expect(HomeRoute(path: route.path) == route)
            #expect(route.id == route.path)
        }
    }

    @Test func aRoomRouteResolvesFromItsIdOrAnyPathEndingInIt() throws {
        let page = try #require(RoomsConfig.pages.first)
        let route = try #require(HomeRoute(path: "rooms/\(page.id)"))
        #expect(route == .room(page.id))
        #expect(route.title == page.title)
        #expect(!route.mdiIcon.isEmpty)
        #expect(HomeRoute(path: "no-such-room") == nil)
        #expect(HomeRoute.room("ghost").title == "ghost")
        #expect(HomeRoute.room("ghost").mdiIcon == "mdi:home")
    }

    @Test func foodDetailPushPathsLandOnTheFoodHub() {
        for path in HomeRoute.foodDetailPaths { #expect(HomeRoute(pushPath: path) == .food) }
        #expect(HomeRoute(pushPath: "vacuums") == .vacuums)
        #expect(HomeRoute(pushPath: "nonsense") == nil)
    }

    // MARK: Room device sheets

    @Test func aGrillOpensWithoutAConnectionButAVacuumNeedsOne() throws {
        let vacuum = try #require(Vacuums.all.first)
        #expect(RoomDeviceModal.resolve(.grill(entityId: "g"), hasConnection: false, fan: { _ in nil })?.id == "grill")
        #expect(RoomDeviceModal.resolve(.vacuum(entityId: vacuum.entityId), hasConnection: false, fan: { _ in nil }) == nil)
        let opened = RoomDeviceModal.resolve(.vacuum(entityId: vacuum.entityId), hasConnection: true, fan: { _ in nil })
        #expect(opened?.id == "vacuum.\(vacuum.entityId)")
        #expect(RoomDeviceModal.resolve(.vacuum(entityId: "vacuum.demo_unknown"), hasConnection: true, fan: { _ in nil }) == nil)
    }

    @Test func missingControllersAndUnbuiltDevicesResolveToNothing() {
        #expect(RoomDeviceModal.resolve(.bathroomFan(powerEntityId: "switch.fan"), hasConnection: true, fan: { _ in nil }) == nil)
        #expect(RoomDeviceModal.resolve(.dishwasher, hasConnection: true, fan: { _ in nil }) == nil)
        #expect(RoomDeviceModal.resolve(.wakeLight(statusEntityId: "x"), hasConnection: true, fan: { _ in nil }) == nil, "no bedroom")
        #expect(RoomDeviceModal.resolve(.bed(sheet: "alexs-bed", climateEntityId: "c"), hasConnection: true, fan: { _ in nil }) == nil)
        #expect(RoomDeviceModal.resolve(.humidifier(powerEntityId: "switch.demo_none"), hasConnection: false, fan: { _ in nil }) == nil)
        #expect(RoomDeviceModal.resolve(.airQuality(pm25EntityId: "sensor.demo_none"), hasConnection: true, fan: { _ in nil }) == nil)
    }

    // MARK: Donetick due date and time

    @Test func theDueDateAndTimeSwitchesFillAndClearTheForm() {
        var form = DonetickTaskForm()
        let binding = Binding(get: { form }, set: { form = $0 })
        let hasDate = DonetickDueBinding.hasDate(binding, now: Date(timeIntervalSince1970: 1_700_000_000))
        let hasTime = DonetickDueBinding.hasTime(binding)
        #expect(!hasDate.wrappedValue && !hasTime.wrappedValue)
        hasDate.wrappedValue = true
        hasTime.wrappedValue = true
        #expect(form.dueDate.count == 10)
        #expect(form.dueTime == "12:00")
        #expect(hasDate.wrappedValue && hasTime.wrappedValue)
        hasDate.wrappedValue = false
        hasTime.wrappedValue = false
        #expect(form.dueDate.isEmpty && form.dueTime.isEmpty)
    }

    @Test func thePickersReadAndWriteTheStoredStrings() {
        var form = DonetickTaskForm()
        form.dueDate = "2026-11-03"
        form.dueTime = "09:30"
        let binding = Binding(get: { form }, set: { form = $0 })
        let calendar = Calendar(identifier: .gregorian)
        let date = DonetickDueBinding.date(binding).wrappedValue
        #expect(calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 2026, month: 11, day: 3))
        let time = DonetickDueBinding.time(binding).wrappedValue
        #expect(calendar.dateComponents([.hour, .minute], from: time) == DateComponents(hour: 9, minute: 30))
        DonetickDueBinding.date(binding).wrappedValue = date.addingTimeInterval(86_400)
        #expect(form.dueDate == "2026-11-04")
        DonetickDueBinding.time(binding).wrappedValue = time.addingTimeInterval(3_600)
        #expect(form.dueTime == "10:30")
        #expect(DonetickDueBinding.formatter("yyyy").dateFormat == "yyyy", "any other format builds its own")
        #expect(DonetickTaskFormFields.nameFooter.contains("short name"))
        #expect(DonetickTaskFormFields.descriptionFooter.hasPrefix("Optional."))
    }

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
