#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

/// `FENTON_GALLERY=media-remote` in the port (``MediaRemoteGallery``): every remote on fixture state with a recording service
/// caller, so journeys exercise real controls without touching the house. `FENTON_GALLERY_REMOTE=<id>` opens a remote at launch and
/// `FENTON_GALLERY_TAB=<tab>` picks its first tab; `FENTON_GALLERY_CLEAN=1` leaves the debug line out and
/// `FENTON_GALLERY_OFFLINE=1` forces the icon fallbacks for app artwork.
@MainActor
enum UKMediaRemoteGalleryPage {
    static func make() -> UIViewController {
        let store = MediaRemoteFixtures.store()
        let recorder = GalleryServiceRecorder(store: store)
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        let page = UKMediaRemoteGalleryController(context: context, store: store, recorder: recorder)
        return UKGalleryChrome.wrap(page, context: context)
    }
}

/// The list of remotes: a button per remote (`gallery.remote.<id>`) and, while no remote is open, the last service call.
@MainActor
private final class UKMediaRemoteGalleryController: UKPageViewController, UICollectionViewDelegate {
    private let store: EntityStore
    private let recorder: GalleryServiceRecorder
    private let initialTab: MediaRemoteTab
    private let footerLabel = UKGalleryLastCallView()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private let opener = UKGalleryAutoOpener(label: "media-remote")

    init(context: UKContext, store: EntityStore, recorder: GalleryServiceRecorder) {
        self.store = store
        self.recorder = recorder
        initialTab = ProcessInfo.processInfo.environment["FENTON_GALLERY_TAB"].flatMap(MediaRemoteTab.init(rawValue:)) ?? .controls
        super.init(context: context, title: "Media Remote")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.footerMode = .supplementary
        collectionView = UICollectionView(frame: contentView.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        install(scrollView: collectionView)

        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, id in
            let title = MediaRemotes.config(id: id)?.title ?? id
            var content = UIListContentConfiguration.cell()
            content.text = title
            content.textProperties.color = .tintColor
            cell.contentConfiguration = content
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = title
            cell.accessibilityTraits = .button
            cell.accessibilityIdentifier = "gallery.remote.\(id)"
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { [footerLabel] cell, _, _ in
            cell.backgroundConfiguration = .clear()
            cell.contentConfiguration = UKCellContent(view: footerLabel, insets: NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0), minHeight: 0)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, path in
            collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: path)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(MediaRemotes.all.map(\.id), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)

        let recorder = recorder
        bag.observe { [weak self] in self?.footerLabel.record(recorder.lastCall) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let config = ProcessInfo.processInfo.environment["FENTON_GALLERY_REMOTE"].flatMap(MediaRemotes.config(id:)) else { return }
        opener.start(on: self) { [weak self] in self?.open(config) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentedViewController == nil { opener.cancel() }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        if let id = dataSource.itemIdentifier(for: indexPath), let config = MediaRemotes.config(id: id) { open(config) }
    }

    private func open(_ config: MediaRemoteConfig) {
        guard presentedViewController == nil else { return }
        let controller = MediaRemoteController(config: config, store: store, caller: recorder)
        let root = UKMediaRemoteSheet.root(controller: controller, imageServer: MediaRemoteFixtures.imageServer, initialTab: initialTab, context: context)
        var options = UKMediaRemoteSheet.options(for: config)
        options.onDismissed = { [weak self] in self?.footerLabel.isHidden = GalleryEnvironment.isClean }
        // FENTON_GALLERY_CLEAN=1 (screenshots) leaves the debug line out; otherwise it sits in a bar above the sheet's content.
        let page: UIViewController = GalleryEnvironment.isClean
            ? root
            : UKPinnedBarViewController(content: root, bar: UKMediaRemoteLastCallBar(recorder: recorder), edge: .top, barMaterial: true)
        // Only while no remote is open: behind an iPad page sheet the dimmed copy fails contrast.
        footerLabel.isHidden = true
        UKHassModalController(root: page, options: options).present(from: self)
    }
}

/// The last service call above the sheet's content (`safeAreaInset(edge: .top)` with `.background(.bar)`), which journeys read through
/// `gallery.lastCall`.
@MainActor
private final class UKMediaRemoteLastCallBar: UIVisualEffectView {
    private let label = UKGalleryLastCallView()
    private let bag = UKObservationBag()

    init(recorder: GalleryServiceRecorder) {
        super.init(effect: UIBlurEffect(style: .systemChromeMaterial))
        contentView.addSubview(label)
        label.ukPin(to: contentView, insets: UIEdgeInsets(top: 4, left: HassTokens.Spacing.l, bottom: 4, right: HassTokens.Spacing.l))
        bag.observe { [weak self] in self?.label.record(recorder.lastCall) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
