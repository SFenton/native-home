import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The editor sheet while a batch is deleted: the section leaves and the content-fitted sheet follows it down over several frames, not
/// in one (verifier, 2026-11-06: 812 pt to 492.6 pt between adjacent frames).
@MainActor
final class UKHostedListRemovalTests: DemoHouseTestCase {
    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        try await super.tearDown()
    }

    /// - Parameter viaPrompt: Deletes the first batch (two units) through the quantity alert, as a person does: the alert is still
    ///   dismissing when the delete lands.
    private func sheetHeights(reduceMotion: Bool, viaPrompt: Bool = false) async throws -> [Int] {
        UKMotion.reduceMotionOverride = reduceMotion
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(150)
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let list = models.model(for: .pantry)
        await list.load()
        let item = try XCTUnwrap(list.displayItems.first { $0.name == "Black Beans" })
        let model = InventoryEditorModel(item: item, list: list)
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        UKInventoryEditorViewController.presentSheet(model: model, from: host, context: UKGalleryChrome.context().with { $0.surface = .sheet },
                                                     onClose: {}, onDismissed: {})
        await FeatureHost.settleAsync(until: { host.presentedViewController?.presentationController?.presentedView != nil })
        await FeatureHost.settleAsync(1.0)
        let modal = try XCTUnwrap(host.presentedViewController)
        let editor = try XCTUnwrap((modal as? UINavigationController)?.viewControllers.first as? UKInventoryEditorViewController)
        let batch = try XCTUnwrap(viaPrompt ? model.batches.first : model.batches.last)
        // Slowed to a quarter, as the verifier's recordings are, so a one-frame jump cannot hide in fast frames. The sheet's top edge is
        // sampled on the presentation layer each display frame: the model frame jumps to its final value whatever animates.
        window.layer.speed = 0.25
        var tops: [Int] = []
        let sampler = FrameSampler {
            guard let view = modal.presentationController?.presentedView else { return }
            // The presented view sits at the origin of the sheet's own container: its top edge is read in window space.
            let layer = view.layer.presentation() ?? view.layer
            let root = window.layer.presentation() ?? window.layer
            tops.append(Int(layer.convert(CGPoint.zero, to: root).y.rounded()))
        }
        defer { sampler.stop() }
        if viaPrompt {
            editor.ask(.delete(batch, qualifier: model.batchName(batch)))
            await FeatureHost.settleAsync(until: { FeatureHost.alert(on: editor) != nil || FeatureHost.alert(on: modal) != nil })
            let alert = try XCTUnwrap(FeatureHost.alert(on: editor) ?? FeatureHost.alert(on: modal), "the quantity prompt is up")
            alert.textFields?.first?.text = "2"
            alert.dismiss(animated: true) // As a tap does: the delete starts while the alert is still going away.
            FeatureHost.answer(alert, "Delete", dismissing: false)
        } else {
            // Through the editor's own alert, so the delete runs on the app's copy of HassCore: a model changed from the test bundle's
            // copy does not notify the screen (its observation key paths are another type).
            editor.ask(.delete(batch, qualifier: model.batchName(batch)))
            await FeatureHost.settleAsync(until: { FeatureHost.alert(on: editor) != nil || FeatureHost.alert(on: modal) != nil })
            let alert = try XCTUnwrap(FeatureHost.alert(on: editor) ?? FeatureHost.alert(on: modal), "the quantity prompt is up")
            FeatureHost.answer(alert, "Delete")
        }
        try? await Task.sleep(for: .seconds(4))
        sampler.stop()
        return tops
    }

    /// A display-link sampler.
    private final class FrameSampler: NSObject {
        private var link: CADisplayLink?
        private let tick: () -> Void
        init(_ tick: @escaping () -> Void) {
            self.tick = tick
            super.init()
            link = CADisplayLink(target: self, selector: #selector(fire))
            link?.add(to: .main, forMode: .common)
        }
        @objc private func fire() { tick() }
        func stop() { link?.invalidate() }
    }
    func testTheSheetFollowsTheRemovedBatchDownOverSeveralFrames() async throws {
        let tops = try await sheetHeights(reduceMotion: false)
        let first = try XCTUnwrap(tops.first)
        let final = try XCTUnwrap(tops.last)
        XCTAssertGreaterThan(final, first, "the sheet's top edge moves down as the sheet shrinks: \(tops)")
        let between = Set(tops.filter { $0 > first && $0 < final })
        NSLog("SHEETMOTION %@", "\(tops.reduce(into: [Int]()) { if $0.last != $1 { $0.append($1) } })")
        XCTAssertGreaterThanOrEqual(between.count, 4, "the sheet's height change animates through several frames, not one jump: \(tops)")
    }

    /// The path a person takes: the quantity alert's Delete. The sheet follows the content down over several frames, though the alert is
    /// still dismissing when the delete lands (verifier, 2026-11-06: the sheet changed in one frame, outside any animation).
    func testTheSheetFollowsTheContentDownWhenTheDeleteComesFromTheQuantityAlert() async throws {
        let tops = try await sheetHeights(reduceMotion: false, viaPrompt: true)
        let first = try XCTUnwrap(tops.first)
        let final = try XCTUnwrap(tops.last)
        XCTAssertGreaterThan(final, first, "the sheet's top edge moves down as the sheet shrinks: \(tops)")
        let between = Set(tops.filter { $0 > first && $0 < final })
        NSLog("SHEETMOTION prompt %@", "\(tops.reduce(into: [Int]()) { if $0.last != $1 { $0.append($1) } })")
        XCTAssertGreaterThanOrEqual(between.count, 4, "the sheet's height change animates through several frames, not one jump: \(tops)")
    }
}
