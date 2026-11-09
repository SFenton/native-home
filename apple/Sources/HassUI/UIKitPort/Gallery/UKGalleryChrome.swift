#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

/// Page chrome for a feature lane's gallery page: what `ComponentGallery` gives every SwiftUI gallery (`GalleryBackdrop`,
/// `.pageBackdrop()`, `GalleryChrome.swift`). A lane's `UKGallery.<lane>(_:)` builds its page(s) as ``UKPageViewController``s on
/// ``context(store:caller:)`` and returns ``wrap(_:context:)``.
///
/// Switches, the same as the SwiftUI galleries read:
/// - `FENTON_BACKDROP_FIXTURE=1`: the page gets the same wallpaper as the shell, from the fixture photo (`FENTON_BACKDROP_BLUR`,
///   `FENTON_BACKDROP_PHOTO`); without it a gallery draws the plain base.
/// - `FENTON_GALLERY_CLEAN=1`: screenshots leave the debug line out (``UKGalleryLastCallView``).
/// - `FENTON_GALLERY_FLYOUT=1` (the port's own, for the regular-width chrome): the page stands in the flyout layout, with the
///   menu button leading and the flyout openable, as a section root does on iPad.
@MainActor
enum UKGalleryChrome {
    /// The fixture backdrop store when `FENTON_BACKDROP_FIXTURE=1` (or `FENTON_GALLERY_BACKDROP_FIXTURE=1`), built once per gallery
    /// generation: a reused journey app resets the gallery, and the store carries the Background Blur a test moved and the
    /// environment it was read from (`app-reuse.md`). `FENTON_GALLERY_BACKDROP_BLUR` starts it at that percentage.
    private static var backdropStore: HouseBackdropStore? {
        let generation = GalleryReset.shared.appliedRequests
        if let cached, cached.generation == generation { return cached.store }
        let store = HouseBackdropStore.fixture(for: HassServer(baseURL: URL(string: "https://gallery.invalid")!))
        cached = (generation, store)
        return store
    }

    private static var cached: (generation: Int, store: HouseBackdropStore?)?

    /// A context for a gallery page: a fixture store, the fixture wallpaper and a shell environment without a tab bar.
    /// - Parameters:
    ///   - store: The fixture store; an empty one by default.
    ///   - caller: Where service calls go (usually a recorder).
    static func context(store: EntityStore? = nil, caller: (any HassServiceCalling)? = nil) -> UKContext {
        var context = UKContext(store: store ?? EntityStore(), caller: caller)
        context.backdrop = backdropStore
        context.shell = UKShellEnvironment.gallery(phone: flyout)
        return context
    }

    static var flyout: Bool { ProcessInfo.processInfo.environment["FENTON_GALLERY_FLYOUT"] == "1" }

    /// The page in a navigation controller with the shell's transparent bar, on the gallery host that measures the window for the
    /// wallpaper and, with `FENTON_GALLERY_FLYOUT=1`, carries the flyout.
    static func wrap(_ page: UIViewController, context: UKContext, rootsSection: Bool = false) -> UIViewController {
        UKGalleryHostViewController(root: page, context: context, rootsSection: rootsSection)
    }
}

/// Hosts a gallery page: the shell's navigation bar, the wallpaper measured for the window, and optionally the flyout.
final class UKGalleryHostViewController: UIViewController {
    private let navigation: UINavigationController
    private let context: UKContext
    /// The window's one wallpaper, behind the navigation controller (as the shell's is behind the tab controller): pages are transparent.
    private let backdrop: UKBackdropView
    /// Push and pop move as they do in the shell's section stacks.
    private var motion: UKStackMotion?
    private var flyout: UKNavigationFlyoutView?
    private let navigator = ShellNavigator()
    /// Feeds the gallery's own shell environment the fold and the vertical bar, as the root view controller does the shell's: without
    /// it a gallery on the Duo never learns the system moved Quick Links into the rail, so Profile stayed a monogram in the top bar
    /// beside it, and no gallery page saw the hinge (`inVerticalBar`, `windowFold`).
    private var signals: UKDeviceSignals?

    init(root: UIViewController, context: UKContext, rootsSection: Bool) {
        self.context = context
        let wrapped = UKPageHost.wrapped(root, context: context)
        if rootsSection || UKGalleryChrome.flyout { (wrapped as? UKPageViewController)?.isSectionRoot = true }
        navigation = UINavigationController(rootViewController: wrapped)
        backdrop = UKBackdropView(store: context.backdrop, shell: context.shell)
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
        // The phone chrome (`rootsSection`, `FENTON_GALLERY_PHONE=1`) and the flyout both have the large title (header-edge-fade R7 (4)); the
        // pages' `largeTitleDisplayMode` still turns it off where the title is in the header.
        UKNavigationBarStyle.apply(to: navigation.navigationBar, large: rootsSection || UKGalleryChrome.flyout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UKBackdropView.base
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // `FENTON_GALLERY_PLAIN=1` (the shell-header gallery): no wallpaper, so a screenshot's glass edges can be measured in pixels.
        backdrop.isHidden = ProcessInfo.processInfo.environment["FENTON_GALLERY_PLAIN"] == "1"
        view.addSubview(backdrop)
        addChild(navigation)
        navigation.view.backgroundColor = .clear
        let motion = UKStackMotion(navigation: navigation)
        navigation.delegate = motion
        self.motion = motion
        navigation.view.frame = view.bounds
        navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(navigation.view)
        navigation.didMove(toParent: self)
        if UKGalleryChrome.flyout {
            let flyout = UKNavigationFlyoutView(navigator: navigator, shell: context.shell)
            flyout.frame = view.bounds
            flyout.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(flyout)
            self.flyout = flyout
            context.shell?.style = .flyout
            context.shell?.chrome = .resolve(style: .flyout)
        }
        if let store = context.backdrop { Task { await store.refresh() } }
        if let shell = context.shell { signals = UKDeviceSignals(view: view, environment: shell) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        signals?.refresh()
        let canvas = view.bounds.size
        if canvas != context.shell?.canvas {
            context.shell?.canvas = canvas
            context.backdrop?.setWindow(canvas, scale: Double(traitCollection.displayScale))
        }
        let top = view.safeAreaInsets.top.rounded()
        if UKGalleryChrome.flyout, let shell = context.shell {
            let cap = HeaderEdgeFade.edgeCap(statusTop: top, barHeight: UINavigationBar().sizeThatFits(CGSize(width: 1000, height: 1000)).height, barIsRail: false)
            if cap != shell.headerEdgeCap { shell.headerEdgeCap = cap }
        }
    }
}

/// The debug line every gallery shows: the last service call (or action), which XCUITest journeys read through the
/// `gallery.lastCall` identifier to check what a control sent (``GalleryLastCall``).
final class UKGalleryLastCallView: UILabel {
    private let title: String

    /// - Parameter title: `Last call` for service calls, `Last action` for galleries without a service.
    init(title: String = "Last call") {
        self.title = title
        super.init(frame: .zero)
        font = UKShellFont.preferred(.caption1, design: .monospaced)
        adjustsFontForContentSizeCategory = true
        numberOfLines = 3
        // Secondary ink measured 2.2:1 on the iPad sheet's bar.
        textColor = .label
        accessibilityIdentifier = "gallery.lastCall"
        text = "\(title): none"
        isHidden = GalleryEnvironment.isClean
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// What the gallery recorded.
    func record(_ call: String) { text = "\(title): \(call)" }
}
#endif
