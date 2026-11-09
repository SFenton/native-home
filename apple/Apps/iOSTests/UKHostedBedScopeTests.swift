import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Changing a bed's temperature while a schedule stage runs asks "Tonight or All Nights?" before anything is sent.
@MainActor
final class UKHostedBedScopeTests: DemoHouseTestCase {
    private func open() throws -> (UKHassModalController, BedSideController, LoggingResponder, UIWindow) {
        let store = EntityStore()
        store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
        let log = LoggingResponder(BedroomGalleryRecorder(store: store))
        let devices = BedroomDevices(store: store, caller: log)
        let context = UKGalleryChrome.context(store: store, caller: log)
        let bed = try XCTUnwrap(devices.beds.first { $0.config.side == MasterBedroom.beds[0].side })
        let modal = UKBedSideSheet.make(devices: devices, side: bed.config.side, initialTab: .temperature, context: context)
        let window = HostedPage.show(modal, size: HostedDriver.tall)
        FeatureHost.settle(0.5)
        return (modal, bed, log, window)
    }

    func testChoosingTonightSendsTheChangeAfterTheQuestion() throws {
        let (modal, bed, log, window) = try open()
        defer { window.isHidden = true }
        let before = log.calls.count
        bed.setTarget(6)
        XCTAssertTrue(HostedPage.until(4) { FeatureHost.alert(on: modal) != nil }, "a schedule stage asks which nights the change is for")
        let sheet = try XCTUnwrap(FeatureHost.alert(on: modal))
        XCTAssertEqual(sheet.title, BedScopeCopy.title)
        XCTAssertEqual(sheet.actions.map(\.title), [BedScopeCopy.tonight, BedScopeCopy.allNights, "Cancel"])
        XCTAssertNotNil(bed.scopeRequest, "the question is pending")
        XCTAssertTrue(FeatureHost.answer(sheet, BedScopeCopy.tonight))
        XCTAssertTrue(HostedPage.until(4) { bed.scopeRequest == nil }, "answering closes the question")
        XCTAssertTrue(HostedPage.until(4) { log.calls.count > before }, "the change reaches Home Assistant; saw \(log.calls)")
    }

    func testCancellingTheQuestionClosesIt() throws {
        let (modal, bed, _, window) = try open()
        defer { window.isHidden = true }
        bed.setTarget(-6)
        XCTAssertTrue(HostedPage.until(4) { FeatureHost.alert(on: modal) != nil })
        let sheet = try XCTUnwrap(FeatureHost.alert(on: modal))
        XCTAssertTrue(FeatureHost.answer(sheet, "Cancel"))
        FeatureHost.settle(0.6)
        XCTAssertNil(bed.scopeRequest, "cancelling closes the question")
    }
}
