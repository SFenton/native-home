#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The media remote sheet (`MediaRemoteSheet`; pattern: `.agents/patterns/media-remote.md`; web `MediaRemoteModalContent.tsx`).
///
/// Direction G (`.agents/design/direction-g.md`, Sheets and Controls: Remote): the sections the remote has (Remote, Apps, Devices,
/// Hue Sync) sit in the bottom glass section bar. Remote shows the 3×3 pad (power in its top-right cell), the volume card and the
/// transport keys; the other sections show only their content. Where a split is allowed (iPad and unfolded iPhone Duo in landscape)
/// and the sheet is wide enough, the pad stays in a leading column and the section scrolls in the trailing one; everywhere else it is
/// one column (HIG: Layout, Sheets).
///
/// ```swift
/// let sheet = UKMediaRemoteSheet.make(controller: remote, imageServer: connection.server, initialTab: .controls, context: context)
/// (sheet as? UKHassModalController)?.present(from: self)
/// ```
@MainActor
enum UKMediaRemoteSheet {
    /// The remote sheet on an existing controller, as `MediaRemoteSheet(...).hassSheet(.page, height: .full)` shows it: a
    /// ``UKHassModalController`` at page width and full height, ready to present.
    /// - Parameters:
    ///   - controller: The remote's controller (the room page owns one for the remote tile).
    ///   - imageServer: Serves app artwork from `/local/images/apps`; nil shows icon fallbacks.
    ///   - initialTab: The tab shown first; falls back to Remote when the remote has no such tab.
    ///   - context: The page's context; the sheet copies it with `surface = .sheet`.
    static func make(controller: MediaRemoteController, imageServer: HassServer?, initialTab: MediaRemoteTab, context: UKContext) -> UIViewController {
        UKHassModalController(root: root(controller: controller, imageServer: imageServer, initialTab: initialTab, context: context),
                              options: options(for: controller.config))
    }

    /// The remote sheet for a config (`MediaRemoteSheet.init(config:store:caller:imageServer:initialTab:)`): builds the controller.
    static func make(config: MediaRemoteConfig, store: EntityStore, caller: any HassServiceCalling, imageServer: HassServer?,
                     initialTab: MediaRemoteTab, context: UKContext) -> UIViewController {
        make(controller: MediaRemoteController(config: config, store: store, caller: caller), imageServer: imageServer,
             initialTab: initialTab, context: context)
    }

    /// The modal's options (`HassModal(config.title, closeStaysInBar: false)` + `.hassSheet(.page, height: .full)`), for a caller
    /// that wraps the sheet's root itself (the gallery's last-call bar).
    static func options(for config: MediaRemoteConfig) -> UKHassModalOptions {
        var options = UKHassModalOptions(title: config.title, fitKey: "MediaRemoteSheet.\(config.id)")
        options.width = .page
        options.height = .full
        return options
    }

    /// The sheet's page: the content, with the section bar pinned along the bottom when the remote has more than one section.
    static func root(controller: MediaRemoteController, imageServer: HassServer?, initialTab: MediaRemoteTab, context: UKContext) -> UIViewController {
        let content = UKMediaRemoteViewController(controller: controller, imageServer: imageServer, initialTab: initialTab,
                                                  context: context.with { $0.surface = .sheet })
        let tabs = controller.config.tabs
        guard tabs.count > 1 else { return content }
        let bar = UKModalTabBar(tabs: tabs, label: "\(controller.config.remoteTitle) sections", title: { $0.title },
                                symbol: { ModalTabSymbols.symbol(for: $0) }, selection: content.remoteTab, identifier: "remote.tabs") { [weak content] tab in
            content?.select(tab)
        }
        content.tabBar = bar
        content.pinBar(bar.inset())
        return content
    }
}

/// The remote's content: one column, or the pad beside the section in two (``MediaRemoteLayout``); the section is the selected tab.
@MainActor
final class UKMediaRemoteViewController: UKPageViewController, UKSheetFitting {
    let controller: MediaRemoteController
    private let imageServer: HassServer?
    private(set) var remoteTab: MediaRemoteTab
    /// The inline keyboard, opened from the pad's keyboard key and shown in the Remote section.
    let keyboard = UKRemoteKeyboardState()
    /// The section bar, when the remote has one: kept in step when the keyboard key switches to Remote.
    weak var tabBar: UKModalTabBar<MediaRemoteTab>?

    var sheetFitScrollView: UIScrollView? { nil }

    private var pinnedBar: UKPagePinnedBar?
    private let layoutContainer = UIView()
    private var leadingColumn: UIView?
    private var section: UIView?
    private var sectionController: UIViewController?
    private var twoColumns = false

    init(controller: MediaRemoteController, imageServer: HassServer?, initialTab: MediaRemoteTab, context: UKContext) {
        self.controller = controller
        self.imageServer = imageServer
        remoteTab = controller.config.tabs.contains(initialTab) ? initialTab : .controls
        super.init(context: context)
    }

    /// Pins the section bar along the bottom; call before the view loads.
    func pinBar(_ bar: UIView) { pinnedBar = UKPagePinnedBar(bar: bar) }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        layoutContainer.isAccessibilityElement = false
        layoutContainer.accessibilityContainerType = .semanticGroup
        contentView.addSubview(layoutContainer)
        pinnedBar?.install(in: self)
        rebuild()
        // The line under the title: the media player's app and state.
        bag.observe { [weak self] in
            guard let self else { return }
            let player = controller.store.entity(controller.config.mediaEntityId).state
            UKSheetSubtitle.apply(MediaRemoteSheet.subtitle(player), to: navigationItem)
        }
        // Warms the other tabs' artwork in the background so switching tabs never shows a tile filling in; nothing waits for it.
        let urls = MediaRemoteSheet.artworkURLs(controller.config, server: imageServer)
        Task { await MediaRemoteSheet.prefetch(urls, pipeline: .shared) }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pinnedBar?.layoutChanged()
        // A sheet's own size class is compact on iPad, so the layout decision reads the window.
        let window = view.window
        let windowSize = window?.bounds.size ?? contentView.bounds.size
        let isRegular = (window ?? view).traitCollection.horizontalSizeClass == .regular
        let wantsTwo = MediaRemoteLayout.usesTwoColumns(window: windowSize, isRegularWidth: isRegular, container: contentView.bounds.size)
        if wantsTwo != twoColumns {
            twoColumns = wantsTwo
            rebuild()
        }
        arrange()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.setNeedsLayout()
    }

    // MARK: Sections

    /// Switches to a section (the section bar, or the keyboard key asking for Remote).
    func select(_ newTab: MediaRemoteTab) {
        if let tabBar, tabBar.selection != newTab { tabBar.selection = newTab }
        guard newTab != remoteTab else { return }
        remoteTab = newTab
        guard isViewLoaded else { return }
        UKMotion.dissolve(layoutContainer, token: .contentFade, reduced: .contentFade) { [self] in
            tearDownSection()
            installSection(includesPad: !twoColumns)
            arrange()
        }
    }

    /// The pad's keyboard key: opens or closes the inline keyboard; the field lives in the Remote section.
    private func toggleKeyboard(_ target: String) {
        keyboard.prompt.toggle(target)
        if keyboard.prompt.isOpen { select(.controls) }
    }

    private func rebuild() {
        tearDownSection()
        leadingColumn?.removeFromSuperview()
        leadingColumn = nil
        layoutContainer.accessibilityIdentifier = twoColumns ? "remote.layout.twoColumn" : "remote.layout.singleColumn"
        if twoColumns {
            let pad = UKRemoteDPadView(controller: controller, keyboard: keyboard, limitsToBounds: true) { [weak self] in self?.toggleKeyboard($0) }
            let inset = HassTokens.Spacing.l
            let column = UKColumnView(insets: UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset))
            column.setViews([pad])
            let scroll = UKColumnScrollView(content: column)
            scroll.backgroundColor = .clear
            layoutContainer.addSubview(scroll)
            leadingColumn = scroll
        }
        installSection(includesPad: !twoColumns)
        view.setNeedsLayout()
    }

    private func tearDownSection() {
        if let sectionController {
            sectionController.willMove(toParent: nil)
            sectionController.view.removeFromSuperview()
            sectionController.removeFromParent()
            self.sectionController = nil
        }
        section?.removeFromSuperview()
        section = nil
    }

    /// The selected section. Remote and Apps scroll in one column; Devices and Hue Sync are inset grouped lists, which scroll
    /// themselves.
    private func installSection(includesPad: Bool) {
        switch remoteTab {
        case .controls:
            var padPrompt: ((String) -> Void)?
            if includesPad { padPrompt = { [weak self] target in self?.toggleKeyboard(target) } }
            let controls = UKRemoteControlsView(controller: controller, keyboard: keyboard, padPrompt: padPrompt)
            show(UKRemoteScroll.make(controls))
        case .apps:
            show(UKRemoteScroll.make(UKRemoteAppsView(controller: controller, imageServer: imageServer, context: context)))
        case .devices:
            show(UKRemoteDevicesViewController(controller: controller))
        case .hueSync:
            if let hue = controller.config.lightSync { show(UKRemoteHueSyncViewController(controller: controller, hue: hue)) }
        }
    }

    private func show(_ scroll: UIScrollView) {
        layoutContainer.addSubview(scroll)
        section = scroll
        // The standard page rules (soft top edge, header fade, scroll only when needed) follow the section that scrolls.
        setPageScrollView(scroll)
    }

    private func show(_ child: UIViewController) {
        addChild(child)
        layoutContainer.addSubview(child.view)
        child.didMove(toParent: self)
        sectionController = child
        section = child.view
        // A list section is a page with its own scroller and fade.
        setPageScrollView(nil)
    }

    private func arrange() {
        layoutContainer.frame = contentView.bounds
        let bounds = layoutContainer.bounds
        guard twoColumns, let leadingColumn, let section else {
            section?.frame = bounds
            return
        }
        let half = bounds.width / 2
        let mirror = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        leadingColumn.frame = CGRect(x: mirror ? half : 0, y: 0, width: half, height: bounds.height)
        section.frame = CGRect(x: mirror ? 0 : half, y: 0, width: half, height: bounds.height)
    }

    // MARK: Keyboard

    /// Keeps the focused field above the keyboard: the sheet's scrolling columns get the keyboard's overlap as bottom inset.
    @objc private func keyboardChanged(_ notification: Notification) {
        guard view.window != nil, let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let overlap = max(0, contentView.convert(contentView.bounds, to: nil).maxY - frame.minY)
        let inset = max(0, overlap - view.safeAreaInsets.bottom)
        for case let scroll as UIScrollView in [section, leadingColumn] {
            scroll.contentInset.bottom = inset
            scroll.verticalScrollIndicatorInsets.bottom = inset
            if inset > 0, let field = Self.firstResponder(in: scroll) {
                scroll.scrollRectToVisible(field.convert(field.bounds, to: scroll).insetBy(dx: 0, dy: -HassTokens.Spacing.l), animated: true)
            }
        }
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews { if let found = firstResponder(in: subview) { return found } }
        return nil
    }
}
#endif
