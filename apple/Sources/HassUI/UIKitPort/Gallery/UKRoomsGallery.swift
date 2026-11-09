#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Owned by the Rooms lane. Pages: rooms, media-page, custom-lights, sprinklers, media-remote.
extension UKGallery {
    static func rooms(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .rooms: UKRoomsGalleryPage.make()
        case .mediaPage: UKMediaPageGalleryPage.make()
        case .customLights: UKCustomLightsGalleryPage.make()
        case .sprinklers: UKSprinklersGalleryPage.make()
        case .mediaRemote: UKMediaRemoteGalleryPage.make()
        default: nil
        }
    }
}

/// `HomePageGallery(kind: .media)`: the Media page on the fixture state. `FENTON_GALLERY_REMOTE=<id>` opens a remote at once and
/// `FENTON_GALLERY_TAB=<tab>` picks its first tab.
@MainActor
enum UKMediaPageGalleryPage {
    static func make() -> UIViewController {
        let (store, recorder) = UKRoomsLastCall.fixture()
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        let environment = ProcessInfo.processInfo.environment
        let page = UKMediaViewController(context: context, openRemote: environment["FENTON_GALLERY_REMOTE"].flatMap(MediaRemotes.config(id:)),
                                         initialTab: environment["FENTON_GALLERY_TAB"].flatMap(MediaRemoteTab.init(rawValue:)) ?? .controls)
        return UKRoomsLastCall.container(wrapping: UKGalleryChrome.wrap(page, context: context), recorder: recorder)
    }
}

/// `RoomsGallery`: room pages, Quick Links and the room grid on fixture state with a recording caller. `FENTON_GALLERY_ROOM=<path>` opens a room
/// at launch; `FENTON_GALLERY_QUICK_LINKS=1` opens Quick Links.
@MainActor
enum UKRoomsGalleryPage {
    static func make() -> UIViewController {
        let store = RoomsFixtures.store()
        let recorder = GalleryServiceRecorder(store: store)
        let caller = RoomsGalleryCaller(recorder: recorder, bedroom: BedroomGalleryRecorder(store: store))
        let context = UKGalleryChrome.context(store: store, caller: caller)
        let list = UKRoomsGalleryList(context: context, recorder: recorder)
        let host = UKGalleryChrome.wrap(list, context: context)
        return UKRoomsBottomLastCall(child: host, recorder: recorder)
    }
}

/// The gallery's list of rooms and the Quick Links button.
@MainActor
private final class UKRoomsGalleryList: UKPageViewController, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var pending: HomeRoute?
    private let environment = ProcessInfo.processInfo.environment

    init(context: UKContext, recorder: GalleryServiceRecorder) {
        super.init(context: context, title: "Rooms")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        install(scrollView: table)
    }

    private var didAutoOpen = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAutoOpen else { return }
        didAutoOpen = true
        if let id = environment["FENTON_GALLERY_ROOM"], RoomsConfig.page(id: id) != nil {
            show(.room(id), animated: false)
        } else if environment["FENTON_GALLERY_QUICK_LINKS"] == "1" {
            openQuickLinksWhenReady(attempt: 0)
        }
    }

    /// A cold launch can reach `viewDidAppear` before the window is key or while the launch ground still covers the screen, and a
    /// sheet presented then is dropped without a sound (the first Quick Links journey of a class, Duo and iPad, 2026-11-02: no sheet in
    /// 30 s). Presents on a later turn and asks again until the sheet is up.
    private func openQuickLinksWhenReady(attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.25)) { [weak self] in
            guard let self else { return }
            if self.view.window != nil { self.showQuickLinks() }
            if self.presentedViewController == nil, attempt < 40 { self.openQuickLinksWhenReady(attempt: attempt + 1) }
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? RoomsConfig.pages.count : 1 }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Rooms" : nil }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let page = RoomsConfig.pages.dropFirst(indexPath.row).first
            content.text = page?.title
            cell.accessibilityIdentifier = "gallery.room.\(page?.id ?? "")"
            cell.accessibilityLabel = page?.title
        } else {
            content.text = "Quick Links"
            cell.accessibilityIdentifier = "gallery.quickLinks"
            cell.accessibilityLabel = "Quick Links"
        }
        cell.contentConfiguration = content
        cell.accessibilityTraits = .button
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            if let page = RoomsConfig.pages.dropFirst(indexPath.row).first { show(.room(page.id), animated: true) }
        } else {
            showQuickLinks()
        }
    }

    private func show(_ route: HomeRoute, animated: Bool) {
        let destination: UIViewController
        if case let .room(id) = route {
            guard let page = RoomsConfig.page(id: id) else { return }
            destination = UKRoomViewController(page: page, context: context, viewer: .resident1)
        } else {
            destination = UKScreens.destination(for: route, context: context)
        }
        navigationController?.pushViewController(destination, animated: animated)
    }

    private func showQuickLinks() {
        guard presentedViewController == nil else { return }
        UKQuickLinks.make(context: context, choose: { [weak self] in self?.pending = $0 }, onDismissed: { [weak self] in
            guard let self, let route = self.pending else { return }
            self.pending = nil
            self.show(route, animated: true)
        }).present(from: self)
    }
}

/// The debug line below the gallery's pages (`safeAreaInset(edge: .bottom)`): the last service call, which journeys read through
/// `gallery.lastCall`. `FENTON_GALLERY_CLEAN=1` leaves it out.
@MainActor
private final class UKRoomsBottomLastCall: UIViewController {
    private let child: UIViewController
    private let recorder: GalleryServiceRecorder
    private let label = UKGalleryLastCallView()
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let bag = UKObservationBag()

    init(child: UIViewController, recorder: GalleryServiceRecorder) {
        self.child = child
        self.recorder = recorder
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
        guard !GalleryEnvironment.isClean else { return }
        label.numberOfLines = 2
        view.addSubview(material)
        material.contentView.addSubview(label)
        bag.observe { [weak self] in
            guard let self else { return }
            self.label.record(self.recorder.lastCall)
            self.view.setNeedsLayout()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !GalleryEnvironment.isClean else { return }
        let inset = HassTokens.Spacing.l
        let size = label.sizeThatFits(CGSize(width: view.bounds.width - 2 * inset, height: .greatestFiniteMagnitude))
        let height = ceil(size.height) + 8 + view.safeAreaInsets.bottom
        material.frame = CGRect(x: 0, y: view.bounds.height - height, width: view.bounds.width, height: height)
        label.frame = CGRect(x: inset, y: 4, width: view.bounds.width - 2 * inset, height: ceil(size.height))
        // Pages stand above the line, as under `safeAreaInset(edge: .bottom)`.
        child.additionalSafeAreaInsets.bottom = max(0, height - view.safeAreaInsets.bottom)
    }
}
#endif
