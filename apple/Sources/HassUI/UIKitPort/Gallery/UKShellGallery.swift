#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Owned by the Shell lane. Pages: backdrop, shell-header.
extension UKGallery {
    static func shell(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .backdrop:
            // A page with nothing on it: the wallpaper and its scrim and no navigation bar.
            let context = UKGalleryChrome.context()
            return UKGalleryChrome.wrap(UKBackdropOnlyPage(context: context), context: context)
        case .shellHeader:
            return UKShellHeaderGallery.make()
        default:
            return nil
        }
    }
}

/// `FENTON_GALLERY=backdrop`: the wallpaper and nothing else.
final class UKBackdropOnlyPage: UKPageViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
}

/// Gallery page for the shell's two trailing header buttons: Quick Links and Profile in the real navigation bar, on fixtures, with
/// no sign-in (``ShellHeaderGallery``). Launch with `FENTON_GALLERY=shell-header`, with the same switches:
/// `FENTON_GALLERY_PROFILE` (name, or `none`), `_BADGE` (attention count), `_OFFLINE=1`, `_RECONNECTING=1`, `_SCHEME=light`,
/// `_PUSHED=1`, `_PHONE=1`, `_TITLE`, `_SCROLL=1` (`_SCROLL_TO=row`), `_PLAIN=1`.
@MainActor
enum UKShellHeaderGallery {
    /// Read on every use, not once: a journey reset (`GalleryReset`) replaces the process environment between tests.
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static func make() -> UIViewController {
        let phone = environment["FENTON_GALLERY_PHONE"] == "1"
        var context = UKGalleryChrome.context()
        context.shell = UKShellEnvironment.gallery(phone: phone, cap: phone ? 116 : nil)
        // `FENTON_GALLERY_PHOTOS=1`: Alex has a generated photo, so Profile draws it instead of the initials.
        context.avatars = GalleryAvatarPhotos.avatars(enabled: environment["FENTON_GALLERY_PHOTOS"] == "1", viewerPersonID: "person.demo_alex")
        context.shell?.attentionCount = environment["FENTON_GALLERY_BADGE"].flatMap(Int.init) ?? 0
        context.shell?.isOffline = environment["FENTON_GALLERY_OFFLINE"] == "1"
        if environment["FENTON_GALLERY_RECONNECTING"] == "1" {
            let indicator = ReconnectingIndicator()
            Task { await indicator.follow(isDown: true, delay: .zero, lead: .zero) }
            context.reconnecting = indicator
        }
        let root = UKShellHeaderGalleryPage(context: context, title: environment["FENTON_GALLERY_TITLE"] ?? "Home", isRoot: true)
        let host = UKGalleryChrome.wrap(root, context: context, rootsSection: phone)
        if environment["FENTON_GALLERY_SCHEME"] == "light" { host.overrideUserInterfaceStyle = .light }
        if environment["FENTON_GALLERY_PUSHED"] == "1" {
            // Starts on a pushed page, with Back leading.
            DispatchQueue.main.async {
                root.pushNext(animated: false)
            }
        }
        return host
    }
}

/// The page: a Push button and the last action, or (`FENTON_GALLERY_SCROLL=1`) a scrolling list so the large title collapses.
final class UKShellHeaderGalleryPage: UKPageViewController {
    private let isRoot: Bool
    private let lastAction = UKGalleryLastCallView(title: "Last action")
    private var rows: [UILabel] = []
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    init(context: UKContext, title: String, isRoot: Bool) {
        self.isRoot = isRoot
        super.init(context: context, title: title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var showsHeaderButtons: Bool { true }

    override var headerProfileName: String? {
        let value = Self.environment["FENTON_GALLERY_PROFILE"] ?? "Alex Demo"
        return value == "none" ? nil : value
    }

    override func openQuickLinks() { lastAction.record("quick-links") }
    override func openAccount() { lastAction.record("profile") }

    func pushNext(animated: Bool) {
        let next = UKShellHeaderGalleryPage(context: context, title: Self.environment["FENTON_GALLERY_TITLE"] ?? "Master Bedroom", isRoot: false)
        navigationController?.pushViewController(next, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if Self.environment["FENTON_GALLERY_PLAIN"] == "1" {
            // A solid black page instead of the house backdrop, so a screenshot's glass edges and disc can be measured in pixels.
            view.backgroundColor = .black
        }
        let push = UIButton(type: .system)
        push.setTitle("Push a page", for: .normal)
        push.contentHorizontalAlignment = .leading
        push.accessibilityIdentifier = "shellHeader.push"
        push.addAction(UIAction { [weak self] _ in self?.pushNext(animated: true) }, for: .touchUpInside)
        push.isHidden = !isRoot
        let padding = HassTokens.Spacing.l
        if Self.environment["FENTON_GALLERY_SCROLL"] == "1" {
            let scroll = UIScrollView()
            let stack = UIStackView(arrangedSubviews: [push])
            stack.axis = .vertical
            stack.spacing = HassTokens.Spacing.m
            stack.isLayoutMarginsRelativeArrangement = true
            stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
            stack.translatesAutoresizingMaskIntoConstraints = false
            for row in 0..<40 {
                let label = UILabel()
                rows.append(label)
                label.text = "Row \(row)"
                label.textColor = .label
                label.font = UKShellFont.preferred(.body)
                label.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                stack.addArrangedSubview(label)
            }
            scroll.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            ])
            install(scrollView: scroll)
            // `FENTON_GALLERY_SCROLL_TO=row` jumps there after a moment, for a screenshot of the collapsed title.
            if let row = Self.environment["FENTON_GALLERY_SCROLL_TO"].flatMap(Int.init) {
                Task { [weak scroll, weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard let scroll else { return }
                    guard let self, self.rows.indices.contains(row) else { return }
                    scroll.layoutIfNeeded()
                    scroll.setContentOffset(CGPoint(x: 0, y: self.rows[row].frame.minY - scroll.adjustedContentInset.top), animated: true)
                }
            }
        } else {
            let stack = UIStackView(arrangedSubviews: [push, UIView(), lastAction])
            stack.axis = .vertical
            stack.spacing = HassTokens.Spacing.m
            stack.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: padding),
                stack.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -padding),
                stack.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: padding),
                stack.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -padding),
            ])
        }
    }
}
#endif
