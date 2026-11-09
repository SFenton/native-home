#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Entry

/// One page in a column stack: the controller, the host view that slides, and what the owner tagged it with (a ``ShellRoute`` for a
/// page the navigator holds, nil for a page only the columns know). The page has no header here: its title is content (see
/// ``UKColumnTitleHeader``) and Back or Close are bar items of the section's own bar (``UKColumnBarHosting``).
@MainActor
final class UKColumnEntry {
    let controller: UIViewController
    /// What the owner identifies this page by; nil for a local push (``UIViewController/show(_:sender:)``).
    let tag: AnyHashable?
    let host = UIView()
    /// A page that is a navigation controller draws its own bar: no column group for it.
    var drawsOwnChrome: Bool { controller is UINavigationController }
    /// Whether this page goes onto the enclosing navigation stack when the window stops splitting. A form the owner re-presents as a sheet
    /// says no.
    var pushesWhenNarrow = true
    /// Called when the person closes this page (Back, Close, the edge pan), not when the owner removes it.
    var onUserClose: (() -> Void)?

    /// - Parameters:
    ///   - ground: A colour under the page when it paints none of its own.
    ///   - hairline: A 1 pt separator on the page's leading edge.
    init(controller: UIViewController, tag: AnyHashable?, ground: UIColor? = nil, hairline: Bool = false) {
        self.controller = controller
        self.tag = tag
        host.clipsToBounds = true
        host.backgroundColor = ground ?? .clear
        host.isOpaque = false
        controller.loadViewIfNeeded()
        controller.view.frame = host.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(controller.view)
        if hairline {
            let line = UIView()
            line.backgroundColor = UKDesignSurface.separator
            line.isAccessibilityElement = false
            line.frame = CGRect(x: 0, y: 0, width: 1 / UIScreen.main.scale, height: host.bounds.height)
            line.autoresizingMask = [.flexibleHeight, .flexibleRightMargin]
            host.addSubview(line)
        }
    }
}

// MARK: - Columns

/// Whether a page lets Back or Close take it away (``UKColumnPopGuarding``).
enum UKColumnPopDecision: Equatable {
    case allow
    /// A save is in flight: Back and Close are off and the edge pan does not start.
    case block
    /// Edits would be lost: Back and Close ask first (``UKDiscardGuard``).
    case confirmDiscard
}

/// A page in a column that can hold itself open: while it saves (``UKColumnPopDecision/block``) or has edits to lose
/// (``UKColumnPopDecision/confirmDiscard``). The page calls ``UKColumnsViewController/pageStateChanged()`` when its answer changes.
@MainActor
protocol UKColumnPopGuarding: AnyObject {
    var columnPopDecision: UKColumnPopDecision { get }
}

/// Column navigation: the one way a page opens another page beside it, in the UIKit port (owner, 2026-11-01).
///
/// **Miller columns, two visible at a time.** The columns are `[root] + entries`. The window shows the last two: with no entries, the
/// root and the shared empty state (``UKPanePlaceholderViewController``); with one, the root and that page; with more, the page that
/// was on the right slides over to the left column and the new page comes in on the right. Back and Close reverse it. A page never
/// moves between parents: every entry has one host that is slid by frame, so nothing reloads or blinks.
///
/// **Navigation.** A page opens another with `show(_:sender:)` (the standard UIKit call; this controller is its target for any page
/// it hosts) or ``open(_:tag:atDepth:animated:)`` from the root. The rule is one: the stack is cut back to the sender's
/// own column, then the page is appended. A tap in the right column appends (drills); a tap in the left column replaces what is on
/// the right. Back (``popTop(animated:)``) and Close (``closeAll(animated:)``) are bar items and a screen-edge pan.
///
/// **Narrow windows.** Where the window does not split (``SplitPolicy``: iPhone, portrait, the folded Duo) ``isWide`` is false: the
/// root fills the container, no entry is kept, and a page that is shown goes onto the enclosing navigation stack as a push. The owner
/// flips ``setWide(_:)`` (the section's navigation controller for route-backed sections; the page for its own detail pane). Pages that
/// were open when the window stopped splitting are handed to the navigation stack, so a fold or rotation loses nothing.
///
/// **Geometry.** The columns divide as every two-pane screen does (``SplitPolicy/columnWidths(container:hinge:gutter:)``): on the
/// hinge band while the Duo is partly folded, at the free space's midpoint with a 1 pt band when it lies flat or on an iPad. A
/// posture change reflows through the owner's layout pass (``UKReflow`` animates it); this controller writes no layout input from
/// layout.
///
/// **Bars (owner, 2026-11-02).** The container draws no header and hosts no navigation controllers. The section's own bar spans the
/// window above both columns, as on every top-level page. Back (a drilled page) or Close (the first page), with any bar items the
/// open page has of its own, go to the owner page as a column group (``UKColumnBarHosting/setColumnItems(_:)``): a separate trailing
/// group beside the shell's, which the Duo's vertical bar shows apart. A page's title is content at the top of its scroll view.
@MainActor
final class UKColumnsViewController: UIViewController {
    private let rootController: UIViewController?
    private let rootView: UIView
    private let makePlaceholder: () -> UIViewController
    private let shell: UKShellEnvironment?
    private let bag = UKObservationBag()
    private var placeholder: UIViewController?
    private let band = UIView()
    private var hinge: CGRect?
    private var pendingCollapse: [UIViewController] = []
    private var leaving: [UKColumnEntry] = []
    private var animations = 0
    /// Bumped by every commit; a deferred step (the placeholder's fade-out before the first page comes in) runs only if it still matches.
    private var generation = 0
    /// True while the empty state fades out ahead of the first page, which has not been installed yet.
    private var openingPending = false
    private var edgePan: UIScreenEdgePanGestureRecognizer?
    private var pageItemsObservation: [NSKeyValueObservation] = []

    /// The pages open beside the root, oldest first.
    private(set) var entries: [UKColumnEntry] = []
    /// Whether the window shows columns side by side. False: the root fills the container and pages are pushed.
    private(set) var isWide = false
    /// Whether the columns' own edge pan can act: wide with a page open to close. The stack's swipe back stands down meanwhile, so one
    /// swipe closes the column or pops the page, never both.
    var takesEdgePan: Bool { isWide && !entries.isEmpty }
    /// The accessibility identifier of the trailing (open) column's host: `split.trailing`, or the page's own name for its detail pane
    /// (the todo page's `todo.pane`, which exists only while a form is open beside the list).
    var trailingIdentifier = "split.trailing"

    /// Whether pages that are open when the window stops splitting are pushed on the enclosing navigation stack. A detail pane that
    /// the owner presents some other way (a sheet) turns it off.
    var pushesCollapsedPages = true
    /// Called after the person pops pages (Back, Close, the edge pan), with how many leading entries carry a tag: the owner trims the
    /// state it keeps (the navigator's path) to that depth.
    var onUserPop: ((_ taggedDepth: Int) -> Void)?
    /// Called when ``isWide`` changes.
    var onWideChange: ((Bool) -> Void)?

    /// - Parameters:
    ///   - rootController: The root column when it is a controller; it becomes a child of this one.
    ///   - placeholder: The empty state in the right column while nothing is open.
    init(rootController: UIViewController, shell: UKShellEnvironment?, placeholder: @escaping () -> UIViewController) {
        self.rootController = rootController
        rootView = rootController.view
        self.shell = shell
        makePlaceholder = placeholder
        super.init(nibName: nil, bundle: nil)
    }

    /// - Parameter rootView: The root column when it is a plain view (a page's scroll view or host).
    init(rootView: UIView, shell: UKShellEnvironment?, placeholder: @escaping () -> UIViewController) {
        rootController = nil
        self.rootView = rootView
        self.shell = shell
        makePlaceholder = placeholder
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: View

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let rootController { addChild(rootController) }
        rootView.frame = view.bounds
        view.addSubview(rootView)
        rootController?.didMove(toParent: self)
        band.isUserInteractionEnabled = false
        band.isAccessibilityElement = false
        band.accessibilityElementsHidden = true
        band.isHidden = true
        view.addSubview(band)
        bag.observe { [weak self] in
            guard let self else { return }
            self.hinge = self.shell?.windowHinge
            self.view.setNeedsLayout()
        }
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePanned(_:)))
        pan.edges = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        pan.isEnabled = false
        view.addGestureRecognizer(pan)
        edgePan = pan
    }

    #if DEBUG
    private var debugScrolled = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // `FENTON_DEBUG_COLUMN_SCROLL=<points>`: scrolls the page in the right column that many points once, seven seconds in, so a host
        // script can capture its heading scrolling away and the header fade. A probe, never in a release build.
        // `FENTON_DEBUG_COLUMN_STEPS="9:back,12:close"`: presses Back or Close at those seconds (the rail animation recording).
        if !debugScrolled, let steps = ProcessInfo.processInfo.environment["FENTON_DEBUG_COLUMN_STEPS"] {
            debugScrolled = true
            for step in steps.split(separator: ",") {
                let parts = step.split(separator: ":")
                guard parts.count == 2, let delay = Double(parts[0]) else { continue }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    if parts[1] == "back" { self?.popTop() } else { self?.closeAll() }
                }
            }
            return
        }
        guard !debugScrolled, let value = ProcessInfo.processInfo.environment["FENTON_DEBUG_COLUMN_SCROLL"], let points = Double(value) else { return }
        debugScrolled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let top = self?.entries.last, let scroll = UKScrollToTop.mainScrollView(in: top.controller.view) else { return }
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top + points), animated: true)
        }
    }
    #endif

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard animations == 0 else { return }
        applyResting()
    }

    // MARK: Geometry

    private struct Rects {
        var leading: CGRect
        var trailing: CGRect
        var band: CGRect
        var isHinge = false
    }

    private var rects: Rects {
        let bounds = view.bounds
        guard isWide, bounds.width > 0 else {
            return Rects(leading: bounds, trailing: CGRect(x: bounds.width, y: 0, width: 0, height: bounds.height), band: .zero)
        }
        let geometry = SplitPolicy.columnWidths(container: view.convert(bounds, to: nil), hinge: hinge, gutter: SplitPolicy.midpointBandWidth)
        let leading = CGRect(x: 0, y: 0, width: geometry.leadingWidth, height: bounds.height)
        let band = CGRect(x: geometry.leadingWidth, y: 0, width: geometry.bandWidth, height: bounds.height)
        let trailing = CGRect(x: geometry.leadingWidth + geometry.bandWidth, y: 0, width: geometry.trailingWidth, height: bounds.height)
        return Rects(leading: leading, trailing: trailing, band: band, isHinge: geometry.isHinge)
    }

    /// Where column `index` (0 is the root) rests, given `count` entries.
    private func resting(_ index: Int, of count: Int, in rects: Rects) -> CGRect {
        guard isWide else { return index == 0 ? view.bounds : offRight(rects) }
        let left = max(count - 1, 0), right = count
        if index == left { return rects.leading }
        if index == right { return rects.trailing }
        return index < left ? offLeft(rects) : offRight(rects)
    }

    private func offLeft(_ rects: Rects) -> CGRect { rects.leading.offsetBy(dx: -(rects.leading.width + rects.band.width), dy: 0) }
    private func offRight(_ rects: Rects) -> CGRect { CGRect(x: view.bounds.width, y: 0, width: rects.trailing.width, height: view.bounds.height) }

    private func applyResting() {
        let rects = self.rects
        let count = entries.count
        rootView.frame = resting(0, of: count, in: rects)
        for (offset, entry) in entries.enumerated() { entry.host.frame = resting(offset + 1, of: count, in: rects) }
        if let placeholder, isWide, count == 0 { placeholder.view.frame = rects.trailing }
        let showsBand = isWide && traitCollection.accessibilityContrast == .high && !rects.isHinge
        band.isHidden = !showsBand
        band.frame = rects.band
        band.backgroundColor = showsBand ? .secondaryLabel : .clear
    }

    // MARK: Width

    /// Sets whether columns show side by side. Turning it off hands the open pages to the navigation stack (``pushesCollapsedPages``).
    func setWide(_ wide: Bool) {
        guard wide != isWide else { return }
        loadViewIfNeeded()
        isWide = wide
        if wide {
            ensurePlaceholder()
        } else {
            collapse()
        }
        edgePan?.isEnabled = wide
        refreshState()
        view.setNeedsLayout()
        onWideChange?(wide)
    }

    private func collapse() {
        generation += 1
        openingPending = false
        let locals = entries.filter { $0.tag == nil && $0.pushesWhenNarrow }.map(\.controller)
        for entry in entries { remove(entry) }
        entries = []
        refreshBars()
        removePlaceholder()
        guard pushesCollapsedPages, !locals.isEmpty else { return }
        // After the navigation stack has taken the pages the navigator holds: the owner reconciles in the same turn as this call.
        DispatchQueue.main.async { [weak self] in
            guard let navigation = self?.navigationController else { return }
            for page in locals {
                page.navigationItem.rightBarButtonItems = nil
                navigation.pushViewController(page, animated: false)
            }
        }
    }

    private func ensurePlaceholder() {
        guard placeholder == nil else { return }
        let page = makePlaceholder()
        page.loadViewIfNeeded()
        addChild(page)
        view.insertSubview(page.view, aboveSubview: rootView)
        page.view.frame = rects.trailing
        page.didMove(toParent: self)
        placeholder = page
    }

    private func removePlaceholder() {
        guard let page = placeholder else { return }
        page.willMove(toParent: nil)
        page.view.removeFromSuperview()
        page.removeFromParent()
        placeholder = nil
    }

    // MARK: Navigation

    /// How deep `sender` sits: 0 for the root (or anything that is not a hosted page), `n` for the n-th entry.
    func depth(of sender: Any?) -> Int {
        guard var controller = sender as? UIViewController else { return 0 }
        while true {
            if let index = entries.firstIndex(where: { $0.controller === controller }) { return index + 1 }
            guard let parent = controller.parent else { return 0 }
            controller = parent
        }
    }

    /// The standard UIKit navigation call: a hosted page shows another one. The columns are cut back to the sender's own column and the
    /// page is appended (a drill from the right appends; a tap in the left column replaces what is on the right).
    override func show(_ vc: UIViewController, sender: Any?) {
        open(vc, tag: nil, atDepth: depth(of: sender))
    }

    override func showDetailViewController(_ vc: UIViewController, sender: Any?) {
        show(vc, sender: sender)
    }

    /// Opens `page` after cutting the stack back to `depth` (0 keeps only the root).
    func open(_ page: UIViewController, tag: AnyHashable?, atDepth depth: Int = 0, ground: UIColor? = nil,
              hairline: Bool = false, animated: Bool = true, pushesWhenNarrow: Bool = true, onUserClose: (() -> Void)? = nil) {
        guard isWide else {
            if pushesWhenNarrow { navigationController?.pushViewController(page, animated: animated) }
            return
        }
        let kept = Array(entries.prefix(max(depth, 0)))
        let entry = UKColumnEntry(controller: page, tag: tag, ground: ground, hairline: hairline)
        entry.pushesWhenNarrow = pushesWhenNarrow
        entry.onUserClose = onUserClose
        commit(kept + [entry], animated: animated)
    }

    /// Takes `page` away if it is the open page on the right (a form its owner closed); nothing happens when something else is.
    func remove(_ page: UIViewController, animated: Bool = true) {
        guard entries.last?.controller === page else { return }
        commit(Array(entries.dropLast()), animated: animated)
    }

    /// Opens pages that were on the navigation stack (local pages, with no route) after the tagged entries, unanimated: the window went
    /// from narrow to wide and they keep their place instead of being dropped.
    func adopt(_ pages: [UIViewController]) {
        guard isWide, !pages.isEmpty else { return }
        commit(entries + pages.map { UKColumnEntry(controller: $0, tag: nil) }, animated: false)
    }

    /// A single detail beside the root (an editor, a form), or none: replaces whatever is open. Nothing is kept when the window is narrow.
    func setDetail(_ page: UIViewController?, tag: AnyHashable? = nil, ground: UIColor? = nil, hairline: Bool = false,
                   animated: Bool = true) {
        guard isWide else { return }
        guard let page else {
            if !entries.isEmpty { commit([], animated: animated) }
            return
        }
        commit([UKColumnEntry(controller: page, tag: tag, ground: ground, hairline: hairline)], animated: animated)
    }

    /// Brings the tagged pages in line with `tags` (the navigator's routes): the common prefix stays, the rest is replaced. A page opened
    /// locally above matching tags stays.
    func reconcile(tags: [AnyHashable], make: (AnyHashable) -> UIViewController, animated: Bool) {
        guard isWide else { return }
        let current = entries.prefix { $0.tag != nil }.map { $0.tag! }
        guard current != tags else { return }
        var common = 0
        while common < min(current.count, tags.count), current[common] == tags[common] { common += 1 }
        var next = Array(entries.prefix(common))
        for tag in tags[common...] { next.append(UKColumnEntry(controller: make(tag), tag: tag)) }
        commit(next, animated: animated)
    }

    /// Back: the page on the right goes, the one before it returns to the right. A page that holds itself open (a save in flight, edits
    /// to lose) decides first (``UKColumnPopGuarding``).
    func popTop(animated: Bool = true) {
        guard let top = entries.last else { return }
        guarded(top) { [weak self] in
            guard let self, self.entries.last === top else { return }
            self.commit(Array(self.entries.dropLast()), animated: animated)
            self.reportPop([top])
        }
    }

    /// Close: every page goes and the empty state returns.
    func closeAll(animated: Bool = true) {
        guard let top = entries.last else { return }
        let all = entries
        guarded(top) { [weak self] in
            guard let self, self.entries.last === top else { return }
            self.commit([], animated: animated)
            self.reportPop(all)
        }
    }

    /// Runs `proceed` when the open page allows it now, after the discard confirmation, or never (a save in flight).
    private func guarded(_ entry: UKColumnEntry, _ proceed: @escaping () -> Void) {
        switch (entry.controller as? UKColumnPopGuarding)?.columnPopDecision ?? .allow {
        case .allow: proceed()
        case .block: UKTapFeedback.failure()
        case .confirmDiscard: UKDiscardGuard.confirm(from: entry.controller, source: .none, onDiscard: proceed)
        }
    }

    /// The open page's answer to Back and Close changed (a save began or ended, an edit was made): the bar item follows.
    func pageStateChanged() { refreshBars() }

    private func reportPop(_ removed: [UKColumnEntry]) {
        for entry in removed { entry.onUserClose?() }
        onUserPop?(entries.prefix { $0.tag != nil }.count)
    }

    // MARK: Transition

    private func install(_ entry: UKColumnEntry) {
        addChild(entry.controller)
        view.addSubview(entry.host)
        entry.controller.didMove(toParent: self)
    }

    private func remove(_ entry: UKColumnEntry) {
        entry.controller.willMove(toParent: nil)
        entry.host.removeFromSuperview()
        entry.controller.removeFromParent()
        leaving.removeAll { $0 === entry }
    }

    /// Replaces the entries and moves the columns: a page that is added with none removed slides in from the right (and the pages
    /// before it slide left); pages removed with none added slide out to the right; added with removed (a different row in the left
    /// column, another item) cross-fades in place. Reduce Motion cross-fades all of them in place: no page that stays on screen slides, and the edge pan still works.
    ///
    /// **The empty state's order (owner, 2026-11-01).** Opening the first page: the empty state fades out, and only then does the page
    /// come in. Closing the last page: the page goes out, and only then does the empty state fade in. Replacing or drilling while pages
    /// remain never touches it. The final state always matches `entries.isEmpty`: every commit bumps ``generation``, so a fade that was
    /// overtaken by another tap does nothing when it ends, and a commit that changes nothing still settles the empty state.
    private func commit(_ next: [UKColumnEntry], animated: Bool) {
        let old = entries
        let removed = old.filter { entry in !next.contains { $0 === entry } }
        let added = next.filter { entry in !old.contains { $0 === entry } }
        guard !removed.isEmpty || !added.isEmpty else { settlePlaceholder(); return }
        generation += 1
        openingPending = false
        let gen = generation
        let animate = animated && isWide && view.window != nil
        if animate, old.isEmpty, !next.isEmpty, let placeholder, placeholder.view.alpha > 0.01 {
            openingPending = true
            UKMotion.animate(.quick, reduced: .quick, animations: { placeholder.view.alpha = 0 }) { [weak self] _ in
                guard let self, self.generation == gen else { return }
                self.openingPending = false
                self.transition(to: next, animate: true)
            }
            return
        }
        transition(to: next, animate: animate)
    }

    /// Fades the empty state in when nothing is open and nothing is about to be.
    private func fadeInPlaceholder() {
        guard let placeholder, isWide, entries.isEmpty, !openingPending else { return }
        placeholder.view.isHidden = false
        guard placeholder.view.alpha < 1 else { return }
        UKMotion.animate(.quick, reduced: .quick, animations: { placeholder.view.alpha = 1 })
    }

    /// A commit that changes nothing: if it overtook a pending opening, the empty state comes back.
    private func settlePlaceholder() {
        if openingPending {
            generation += 1
            openingPending = false
        }
        if animations == 0 { fadeInPlaceholder() }
    }

    private func transition(to next: [UKColumnEntry], animate: Bool) {
        let old = entries
        let removed = old.filter { entry in !next.contains { $0 === entry } }
        let added = next.filter { entry in !old.contains { $0 === entry } }
        guard !removed.isEmpty || !added.isEmpty else { return }
        let fades = !removed.isEmpty && !added.isEmpty || UKMotion.reduceMotion
        view.layoutIfNeeded()
        if next.isEmpty || old.isEmpty { ensurePlaceholder() }
        // Closing the last page: the empty state waits (invisible) until the page has gone, then fades in (``fadeInPlaceholder``).
        if next.isEmpty { placeholder?.view.alpha = animate ? 0 : 1 }
        let before = rects
        for entry in added { install(entry) }
        entries = next
        refreshBars()
        let after = rects
        if animate {
            for entry in added {
                entry.host.frame = fades ? resting(next.firstIndex { $0 === entry }! + 1, of: next.count, in: after) : offRight(after)
                entry.host.alpha = fades ? 0 : 1
            }
            for entry in removed { entry.host.frame = resting(old.firstIndex { $0 === entry }! + 1, of: old.count, in: before) }
            // The pages in the window are laid out at their destination first, so their content does not resize mid-slide.
            if let placeholder, next.isEmpty { placeholder.view.frame = after.trailing }
        } else {
            for entry in added { entry.host.alpha = 1 }
        }
        leaving.append(contentsOf: removed)
        let finish = { [weak self] in
            guard let self else { return }
            for entry in removed { self.remove(entry) }
            if !self.entries.isEmpty { self.removePlaceholder() }
            self.refreshState()
            self.fadeInPlaceholder()
            self.view.setNeedsLayout()
        }
        guard animate else {
            for entry in removed { remove(entry) }
            if !entries.isEmpty { removePlaceholder() }
            applyResting()
            refreshState()
            return
        }
        // Reduce Motion (owner, 2026-11-02): a page that stays on screen does not slide. One whose column changes jumps to its new
        // column and cross-fades in place with a snapshot of where it was; only opacity animates.
        var crossFading: [UIView] = []
        if UKMotion.reduceMotion {
            let rects = self.rects
            var survivors = [(view: rootView, frame: resting(0, of: next.count, in: rects))]
            for (offset, entry) in next.enumerated() where !added.contains(where: { $0 === entry }) {
                survivors.append((entry.host, resting(offset + 1, of: next.count, in: rects)))
            }
            for survivor in survivors where survivor.view.frame != survivor.frame {
                if let snapshot = survivor.view.snapshotView(afterScreenUpdates: false) {
                    snapshot.frame = survivor.view.frame
                    snapshot.isUserInteractionEnabled = false
                    snapshot.accessibilityElementsHidden = true
                    view.addSubview(snapshot)
                    crossFading.append(snapshot)
                }
                survivor.view.frame = survivor.frame
                survivor.view.alpha = 0
            }
        }
        animations += 1
        let moves = { [self] in
            if UKMotion.reduceMotion {
                rootView.alpha = 1
                crossFading.forEach { $0.alpha = 0 }
            }
            let rects = self.rects
            self.rootView.frame = self.resting(0, of: next.count, in: rects)
            for (offset, entry) in next.enumerated() {
                entry.host.frame = self.resting(offset + 1, of: next.count, in: rects)
                if fades { entry.host.alpha = 1 }
            }
            for entry in removed {
                if fades { entry.host.alpha = 0 } else { entry.host.frame = self.offRight(rects) }
            }
        }
        UKMotion.animate(fades ? .quick : .standard, reduced: .quick, animations: moves) { [weak self] _ in
            crossFading.forEach { $0.removeFromSuperview() }
            guard let self else { return }
            self.animations -= 1
            if self.animations == 0 { finish() } else { for entry in removed { self.remove(entry) } }
            self.refreshState()
        }
    }

    /// The column group of the section's bar: the open page's own bar items, then Back (a drilled page) or Close (the first page).
    /// Kind `none` (nothing open) hides the item; nil (a narrow window) takes the group away.
    private func refreshBars() {
        pageItemsObservation = []
        guard isWide else {
            columnBarSource?.setColumnBar(nil)
            return
        }
        guard let top = entries.last, !top.drawsOwnChrome else {
            columnBarSource?.setColumnBar(UKColumnBar())
            return
        }
        let item = top.controller.navigationItem
        let changed: (UINavigationItem, NSKeyValueObservedChange<[UIBarButtonItem]?>) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshBars() } }
        }
        pageItemsObservation = [item.observe(\.rightBarButtonItems, changeHandler: changed), item.observe(\.leftBarButtonItems, changeHandler: changed)]
        // The page's own bar items, leading then trailing (Performance's Refresh is a leading one), ride in the column group.
        let own = (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? [])
        let single = entries.count == 1
        let blocked = (top.controller as? UKColumnPopGuarding)?.columnPopDecision == .block
        columnBarSource?.setColumnBar(UKColumnBar(items: own, kind: single ? .close : .back, isEnabled: !blocked, perform: { [weak self] in
            if single { self?.closeAll() } else { self?.popTop() }
        }))
    }

    /// The nearest ancestor that owns a bar to put the column group on.
    private var columnBarSource: UKColumnBarHosting? {
        var controller = parent
        while let current = controller {
            if let host = current as? UKColumnBarHosting { return host }
            controller = current.parent
        }
        return nil
    }

    /// VoiceOver sees only the columns in the window, and the edge pan works only with a page to go back from.
    private func refreshState() {
        refreshBars()
        let count = entries.count
        let left = max(count - 1, 0)
        rootView.accessibilityElementsHidden = isWide && 0 < left
        for (offset, entry) in entries.enumerated() {
            let visible = offset + 1 >= left
            entry.host.accessibilityElementsHidden = !visible
            entry.host.accessibilityIdentifier = offset == count - 1 ? trailingIdentifier : nil
        }
        placeholder?.view.accessibilityElementsHidden = !entries.isEmpty
        placeholder?.view.isHidden = !entries.isEmpty && animations == 0
        edgePan?.isEnabled = takesEdgePan
    }

    // MARK: Interactive back

    private var backAnimator: UIViewPropertyAnimator?

    /// A drag from the screen's leading edge scrubs Back: the right column follows the finger off to the right while the pages before
    /// it return, and lifting past halfway (or with speed) completes it.
    @objc private func edgePanned(_ pan: UIScreenEdgePanGestureRecognizer) {
        handleEdgePan(state: pan.state, translation: pan.translation(in: view).x, velocity: pan.velocity(in: view).x)
    }

    /// The edge pan's behaviour for one state of the gesture (a recognizer's own state cannot be set, so a hosted test drives this).
    func handleEdgePan(state: UIGestureRecognizer.State, translation: CGFloat, velocity: CGFloat) {
        // Under Reduce Motion the swipe still works: the pages follow the finger, a direct manipulation (owner, 2026-11-02).
        guard isWide, !entries.isEmpty else { return }
        // A page that holds itself open (a save, edits to lose) is left with Back or Close, not by a drag.
        if state == .began, let guarded = entries.last?.controller as? UKColumnPopGuarding, guarded.columnPopDecision != .allow { return }
        let width = max(view.bounds.width, 1)
        switch state {
        case .began:
            let old = entries
            let next = Array(entries.dropLast())
            guard let top = old.last else { return }
            if next.isEmpty { ensurePlaceholder(); placeholder?.view.alpha = 0 }
            view.layoutIfNeeded()
            let animator = UIViewPropertyAnimator(duration: MotionTokens.standardDuration, curve: .easeOut) { [self] in
                let after = rects
                rootView.frame = resting(0, of: next.count, in: after)
                for (offset, entry) in next.enumerated() { entry.host.frame = resting(offset + 1, of: next.count, in: after) }
                top.host.frame = offRight(after)
            }
            animations += 1
            animator.pauseAnimation()
            animator.addCompletion { [weak self] position in
                guard let self else { return }
                self.animations -= 1
                if position == .end {
                    self.entries = next
                    self.remove(top)
                    if !self.entries.isEmpty { self.removePlaceholder() }
                    self.reportPop([top])
                }
                self.backAnimator = nil
                self.refreshState()
                self.fadeInPlaceholder()
                self.view.setNeedsLayout()
            }
            backAnimator = animator
        case .changed:
            backAnimator?.fractionComplete = min(max(translation / width, 0), 1)
        case .ended, .cancelled, .failed:
            guard let animator = backAnimator else { return }
            let completes = state == .ended && (animator.fractionComplete > 0.5 || velocity > 600)
            animator.isReversed = !completes
            animator.startAnimation()
        default: break
        }
    }
}
#endif
