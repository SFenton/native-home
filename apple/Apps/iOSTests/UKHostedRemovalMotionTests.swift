import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// How a deleted inventory row moves against a stock list: the same removal on a plain `UICollectionView` list with a diffable data
/// source and `animatingDifferences: true`, and on the inventory list. Each frame the next row's presentation-layer position and the
/// removed cell's opacity are sampled; the inventory list must take as long as the stock one (verifier, 2026-11-06: "the way iOS removes
/// a row", ours looked shorter).
@MainActor
final class UKHostedRemovalMotionTests: DemoHouseTestCase {
    /// A display-link sampler.
    private final class Sampler: NSObject {
        private var link: CADisplayLink?
        private let tick: (CFTimeInterval) -> Void
        init(_ tick: @escaping (CFTimeInterval) -> Void) {
            self.tick = tick
            super.init()
            link = CADisplayLink(target: self, selector: #selector(fire(_:)))
            link?.add(to: .main, forMode: .common)
        }
        @objc private func fire(_ link: CADisplayLink) { tick(link.timestamp) }
        func stop() { link?.invalidate() }
    }

    /// What one removal looked like: seconds the next row moved for, the frames that saw it move, and the removed cell's fade.
    private struct Trace {
        var moveSeconds: Double
        var moveFrames: Int
        var fadeSeconds: Double
        var positions: [Int]
        var alphas: [Int]
    }

    private func trace(neighbour: @escaping () -> CALayer?, removed: @escaping () -> CALayer?, start: () -> Void) async -> Trace {
        var times: [CFTimeInterval] = []
        var ys: [CGFloat] = []
        var alphas: [CGFloat] = []
        var lastAlpha: CGFloat = 1
        let sampler = Sampler { time in
            times.append(time)
            ys.append(neighbour()?.presentation()?.frame.minY ?? neighbour()?.frame.minY ?? 0)
            if let layer = removed() { lastAlpha = layer.presentation()?.opacity.cgFloat ?? CGFloat(layer.opacity) }
            alphas.append(lastAlpha)
        }
        start()
        try? await Task.sleep(for: .milliseconds(1500))
        sampler.stop()
        guard let first = ys.first, let final = ys.last else { return Trace(moveSeconds: 0, moveFrames: 0, fadeSeconds: 0, positions: [], alphas: []) }
        let moving = ys.indices.filter { ys[$0] != first && abs(ys[$0] - final) > 0.5 }
        let begin = ys.firstIndex { $0 != first } ?? 0
        let end = ys.firstIndex { abs($0 - final) <= 0.5 && $0 != first } ?? begin
        let fading = alphas.indices.filter { alphas[$0] < 0.99 && alphas[$0] > 0.01 }
        let fade = (fading.last.map { times[$0] } ?? 0) - (fading.first.map { times[$0] } ?? 0)
        return Trace(moveSeconds: end > begin ? times[end] - times[begin] : 0, moveFrames: moving.count, fadeSeconds: fade,
                     positions: ys.map { Int($0.rounded()) }.reduce(into: []) { if $0.last != $1 { $0.append($1) } },
                     alphas: alphas.map { Int(($0 * 100).rounded()) }.reduce(into: []) { if $0.last != $1 { $0.append($1) } })
    }

    // MARK: Stock list

    private func stockTrace() async -> Trace {
        let layout = UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
        let controller = UIViewController()
        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.addSubview(collection)
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, name in
            var content = UIListContentConfiguration.cell()
            content.text = name
            cell.contentConfiguration = content
        }
        let source = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { collection, path, name in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: name)
        }
        let names = ["Black Beans", "Honey", "Jasmine Rice", "Spaghetti", "Tea"]
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(names)
        let window = HostedPage.show(controller, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        await source.apply(snapshot, animatingDifferences: false)
        await FeatureHost.settleAsync(0.6)
        let gone = collection.cellForItem(at: IndexPath(item: 1, section: 0))
        let next = collection.cellForItem(at: IndexPath(item: 2, section: 0))
        return await trace(neighbour: { next?.layer }, removed: { gone?.layer }) {
            snapshot.deleteItems(["Honey"])
            source.apply(snapshot, animatingDifferences: true)
        }
    }

    // MARK: Inventory list

    private func rowViews(in view: UIView) -> [UKInventoryRowView] {
        (view as? UKInventoryRowView).map { [$0] } ?? view.subviews.flatMap { rowViews(in: $0) }
    }

    private func cell(of view: UIView) -> UICollectionViewCell? {
        var current: UIView? = view
        while let candidate = current, !(candidate is UICollectionViewCell) { current = candidate.superview }
        return current as? UICollectionViewCell
    }

    private func inventoryTrace() async throws -> Trace {
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(10)
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let model = models.model(for: .pantry)
        let presentation = InventoryPresentation()
        let context = UKGalleryChrome.context()
        let page = UKInventoryViewController(context: context, model: model, models: models, presentation: presentation)
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(1.0)
        let rows = rowViews(in: page.view)
        let gone = rows.first { $0.item?.name == "Honey" }.flatMap { cell(of: $0) }
        let next = rows.first { $0.item?.name == "Jasmine Rice" }.flatMap { cell(of: $0) }
        let honey = try XCTUnwrap(model.displayItems.first { $0.name == "Honey" })
        XCTAssertNotNil(gone)
        XCTAssertNotNil(next)
        return await trace(neighbour: { next?.layer }, removed: { gone?.layer }) {
            // Through the page's own swipe path, so the delete runs on the app's copy of HassCore: a model changed from the test bundle's
            // copy does not notify the screen (its observation key paths are another type).
            UKInventoryRowActionsHost.swipeDelete(honey, in: model, presentation: presentation, done: { _ in })
            Task { @MainActor in
                await FeatureHost.settleAsync(until: { FeatureHost.alert(on: page) != nil })
                if let alert = FeatureHost.alert(on: page), let title = alert.actions.first(where: { $0.style == .destructive })?.title {
                    FeatureHost.answer(alert, title)
                }
            }
        }
    }

    func testAnInventoryRowLeavesAsLongAsAStockListRow() async throws {
        let stock = await stockTrace()
        let ours = try await inventoryTrace()
        NSLog("REMOVALMOTION stock move=%.3fs frames=%d fade=%.3fs y=%@ alpha=%@", stock.moveSeconds, stock.moveFrames, stock.fadeSeconds, "\(stock.positions)", "\(stock.alphas)")
        NSLog("REMOVALMOTION ours  move=%.3fs frames=%d fade=%.3fs y=%@ alpha=%@", ours.moveSeconds, ours.moveFrames, ours.fadeSeconds, "\(ours.positions)", "\(ours.alphas)")
        XCTAssertGreaterThan(stock.moveFrames, 3, "the stock list animates the neighbour over several frames: \(stock)")
        XCTAssertGreaterThanOrEqual(ours.moveSeconds, stock.moveSeconds * 0.8, "ours takes as long as the stock removal. stock \(stock) ours \(ours)")
        XCTAssertGreaterThanOrEqual(ours.moveFrames, Int(Double(stock.moveFrames) * 0.8), "and passes through as many frames. stock \(stock) ours \(ours)")
    }
}

private extension Float {
    var cgFloat: CGFloat { CGFloat(self) }
}
