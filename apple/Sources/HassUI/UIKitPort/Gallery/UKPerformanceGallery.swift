#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

/// Debug gallery for the performance pieces (`FENTON_GALLERY=performance`), chosen with `FENTON_GALLERY_PERF` like the SwiftUI
/// `PerformanceGallery`:
/// - `screen` (default): the performance screen, which belongs to the Diagnostics lane (a placeholder until it lands).
/// - `gate`: a page whose data loads after a delay (`FENTON_GALLERY_GATE_DELAY_MS`), with a Reload button. The content gate itself
///   is the shell lane's; this stands in with the same phases (a spinner, then the content fading in).
/// - `grid`: 300 glass tiles in a `UKDynamicGridLayout`, the fixed workload for the fast-scroll tests and the frame rate, CPU and
///   GPU comparison.
/// - `chips`: Home's six-chip rail over a column of tiles on fixture state, for the sideways-swipe tests.
@MainActor
enum UKPerformanceGallery {
    static func make() -> UIViewController {
        let root: UIViewController
        switch ProcessInfo.processInfo.environment["FENTON_GALLERY_PERF"] ?? "screen" {
        case "gate": root = UKGateDemoViewController()
        case "grid": root = UKGridWorkloadViewController()
        case "chips": root = UKChipRailWorkloadViewController()
        default: root = UKPlaceholderViewController(title: "Performance", symbol: "gauge.with.needle")
        }
        return UKGalleryGround.navigation(root: root)
    }
}

// MARK: - Grid workload

/// A long tile grid that the fast-scroll tests flick through: 300 tiles in a `DynamicGridLayout(minCellWidth: 150, maxColumns: 6)`.
///
/// Built the way the UIKit app builds every long grid: a collection view with reused cells, a layout that measures through a
/// prototype once per width (text only, no layers) and places by arithmetic, tiles whose sheen, hairline and stroke are one cached
/// image per size, and no per-frame work anywhere.
@MainActor
final class UKGridWorkloadViewController: UIViewController, UICollectionViewDataSource, UKDynamicGridLayoutDelegate {
    private static let count = 300
    private let layout = UKDynamicGridLayout(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 6, spacing: HassTokens.Spacing.m, fill: .none))
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    /// Measures every tile: configured with text and glyph only.
    private let prototype = UKGlassTileFaceView(content: UKTileFaceContent(title: "", symbol: "lightbulb", isActive: false))
    private let environment = UKTileEnvironment()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Grid Workload"
        view.backgroundColor = UKGalleryGround.color
        navigationItem.largeTitleDisplayMode = .always
        layout.delegate = self
        layout.contentInsets = UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.register(UKTileCell.self, forCellWithReuseIdentifier: UKTileCell.reuseIdentifier)
        collectionView.accessibilityIdentifier = "perf.grid"
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = true
        collectionView.isPrefetchingEnabled = true
        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)
        navigationItem.largeTitleDisplayMode = .always
    }

    // MARK: Fixtures

    /// The i-th tile: "Tile n", On every third, a lightbulb tinted with the light tint.
    private static func model(_ index: Int) -> UKGlassTileModel {
        UKGlassTileModel(title: "Tile \(index + 1)", subtitle: index.isMultiple(of: 3) ? "On" : "Off", symbol: "lightbulb",
                         tint: UIColor(HassTokens.RGB.Tint.light), isActive: index.isMultiple(of: 3))
    }

    // MARK: Data source

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { Self.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UKTileCell.reuseIdentifier, for: indexPath) as! UKTileCell
        let model = Self.model(indexPath.item)
        if let tile = cell.hosted as? UKGlassTileView {
            tile.configure(model, environment: environment, animated: false)
        } else {
            cell.host(UKGlassTileView(model: model, environment: environment))
        }
        return cell
    }

    // MARK: Layout

    func gridLayout(_ layout: UKDynamicGridLayout, heightAt indexPath: IndexPath, width: CGFloat) -> CGFloat {
        let model = Self.model(indexPath.item)
        return prototype.measuredHeight(content: model.faceContent(trailingInset: 0, bottomInset: 0), environment: environment, width: width,
                                        traits: collectionView.traitCollection)
    }
}

// MARK: - Chip rail workload

/// Home's status rail over a page of tiles, on fixture state: the sideways-swipe test flicks the rail. The page is deliberately busy,
/// because a nested scroll's cost grows with the page around it (`.agents/patterns/status-rail.md`, Scrolling). Lights alternate on and
/// off so every chip draws its fill.
@MainActor
final class UKChipRailWorkloadViewController: UIViewController {
    private let store: EntityStore

    init() {
        let store = EntityStore()
        store.replaceAll(Self.states, freshness: .live)
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Chip Rail Workload"
        view.backgroundColor = UKGalleryGround.color
        let rail = UKChipRailView()
        rail.setChips(HomeConfig.statusChips.map { chip in
            let summary = HomeConfig.summary(for: chip) { [store] in store.entity($0).state }
            let appearance = StatusChipAppearance.home(chip) { [store] in store.entity($0).state }
            let view = UKGalleryChipView(title: chip.title, summary: summary, symbol: appearance.symbol, family: appearance.family,
                                         isActive: appearance.isFilled, tint: appearance.tint)
            view.accessibilityIdentifier = "home.chip.\(chip.sheet.rawValue)"
            return view
        })
        let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 2, spacing: HassTokens.Spacing.m))
        grid.setItems((0..<120).map { index in
            UKGridItem(UKGlassTileView(model: UKGlassTileModel(
                title: "Tile \(index + 1)", subtitle: index.isMultiple(of: 3) ? "On" : "Off", symbol: "lightbulb",
                tint: UIColor(HassTokens.RGB.Tint.light), isActive: index.isMultiple(of: 3))))
        })
        let column = UKColumnView(spacing: HassTokens.Spacing.xl, insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: 0, bottom: HassTokens.Spacing.m, right: 0))
        column.setViews([rail, UKInsetView(grid, insets: UIEdgeInsets(top: 0, left: HassTokens.Spacing.l, bottom: 0, right: HassTokens.Spacing.l))])
        let scroll = UKColumnScrollView(content: column)
        scroll.accessibilityIdentifier = "perf.chips"
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scroll)
    }

    private static var states: [EntityState] {
        var states = RoomOverview.lightEntityIds.enumerated().map {
            EntityState(entityId: $1, state: $0.isMultiple(of: 3) ? "on" : "off")
        }
        states += RoomOverview.contactEntityIds.enumerated().map {
            EntityState(entityId: $1, state: $0 == 0 ? "on" : "off")
        }
        states += [
            EntityState(entityId: SecurityConfig.alarmEntityId, state: "armed_home"),
        ]
        states += HomeFixtures.statusChipStates
        return states
    }
}

/// One child with insets around it, sized at its natural height.
@MainActor
final class UKInsetView: UIView, UKGridMeasuring {
    let child: UIView
    var insets: UIEdgeInsets

    init(_ child: UIView, insets: UIEdgeInsets) {
        self.child = child
        self.insets = insets
        super.init(frame: .zero)
        addSubview(child)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let inner = max(0, width - insets.left - insets.right)
        let height = (child as? UKGridMeasuring)?.gridHeight(forWidth: inner) ?? child.sizeThatFits(CGSize(width: inner, height: CGFloat.greatestFiniteMagnitude)).height
        return height + insets.top + insets.bottom
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        child.frame = bounds.inset(by: insets)
    }
}

// MARK: - Gate demo

/// A page whose data arrives after a delay; Reload fades it out and back in. `FENTON_GALLERY_GATE_DELAY_MS=<ms>` sets the delay
/// (default 900); a journey that watches the spinner stretches it.
@MainActor
final class UKGateDemoViewController: UIViewController {
    private var generation = 0
    private var loadTask: Task<Void, Never>?
    private let spinner = UKArcSpinnerView(.page, label: "Loading gallery")
    private var scroll: UKColumnScrollView?

    private static var loadDelay: Duration {
        .milliseconds(ProcessInfo.processInfo.environment["FENTON_GALLERY_GATE_DELAY_MS"].flatMap { Int($0) } ?? 900)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Content Gate"
        view.backgroundColor = UKGalleryGround.color
        let reload = UIBarButtonItem(title: "Reload", primaryAction: UIAction { [weak self] _ in
            self?.generation += 1
            self?.load()
        })
        reload.accessibilityIdentifier = "gate.reload"
        navigationItem.rightBarButtonItem = reload
        spinner.color = .white
        view.addSubview(spinner)
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = spinner.intrinsicContentSize
        spinner.frame = CGRect(x: (view.bounds.width - size.width) / 2, y: (view.bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    private func load() {
        scroll?.removeFromSuperview()
        scroll = nil
        spinner.alpha = 1
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.loadDelay)
            guard !Task.isCancelled, let self else { return }
            show()
        }
    }

    private func show() {
        let column = UKColumnView(spacing: HassTokens.Spacing.m, insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        column.setViews((0..<8).map { index in
            UKGlassTileView(model: UKGlassTileModel(title: "Item \(index + 1)", subtitle: "Loaded \(generation)", symbol: "square.grid.2x2",
                                                    tint: UIColor(HassTokens.RGB.Tint.light), isActive: index.isMultiple(of: 2)))
        })
        let scroll = UKColumnScrollView(content: column)
        scroll.accessibilityIdentifier = "gate.content"
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alpha = 0
        view.insertSubview(scroll, belowSubview: spinner)
        self.scroll = scroll
        UIView.animate(withDuration: UKDesign.reduceMotion ? 0.35 : 0.3) {
            scroll.alpha = 1
            self.spinner.alpha = 0
        }
    }
}
#endif
