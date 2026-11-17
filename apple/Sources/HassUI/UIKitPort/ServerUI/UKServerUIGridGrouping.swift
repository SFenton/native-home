#if os(iOS)
import HassCore
import HassDesign
import HassTelemetry
import UIKit

// MARK: - A grid grouped by state (`sh.grid-state-groups@1`)

/// Arranges one `tile-grid` under a heading for each state group, and moves a tile when its state changes.
///
/// Each child draws one of three faces (``UKGridFace``); ``ServerUIGridGroups`` says which group holds each, drops a group with no tile and keeps
/// the grid's order inside a group. The headings are the existing section heading (`UKPageSectionHeaderView`, the header trait), full-row items
/// of the same grid, so columns are solved once and tiles line up across groups.
///
/// **When a tile moves** (`.agents/design/motion.md` section 6, a recorded exception): a person's tap on the grid slides the tile with
/// `MotionTokens.standardDuration`; a change the house made applies with no animation; a snapshot or reconnect reapply never animates; any change
/// waits while a finger is on the grid or it is dragged or decelerating; Reduce Motion replaces the slide with a 0.2 s fade of the moved tile.
/// The move is one keyed re-arrangement of the same views, never a rebuild, and one `LayoutChange` signpost spans it.
@MainActor
final class UKServerUIGridGrouping: NSObject, UIGestureRecognizerDelegate {
    let groups: ServerUIGridGroups
    private let gridID: String
    private weak var grid: UKDynamicGridView?
    private let surface: TileSurface
    private var headers: [String: UKPageSectionHeaderView] = [:]
    private var arrangement: [ObjectIdentifier] = []
    private var faces: [ObjectIdentifier: UKGridFace] = [:]
    /// The visible children in the grid's order, with the span each asked for; the page sets it before each arrangement.
    private var children: [(view: UIView, span: Int)] = []
    private let press = UILongPressGestureRecognizer()
    private var touching = false
    /// When a person last tapped the grid (not a touch that scrolled).
    private(set) var lastTap: ContinuousClock.Instant?
    private var isPending = false
    private var held = false
    /// Tells a held change the scroll is over (``UKTickerScrollGate``: it watches the offset and the drag and deceleration flags, so it sees the end of a deceleration).
    private var scrollEnd: NSObjectProtocol?
    private var touchStartOffset: CGPoint?
    private var seenReapply = 0
    /// The store's reapply generation now: a change since the last arrangement is a snapshot or reconnect.
    var reapplyGeneration: () -> Int = { 0 }
    /// Re-measures the page after a move. The page sets it.
    var relayout: (_ animated: Bool) -> Void = { _ in }
    /// Arrangements applied by a regroup, for tests and the cost signpost.
    private(set) var regroupCount = 0

    init(_ groups: ServerUIGridGroups, gridID: String, grid: UKDynamicGridView, surface: TileSurface) {
        self.groups = groups
        self.gridID = gridID
        self.grid = grid
        self.surface = surface
        super.init()
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delegate = self
        press.addTarget(self, action: #selector(pressed(_:)))
        grid.addGestureRecognizer(press)
        NotificationCenter.default.addObserver(self, selector: #selector(faceChanged(_:)), name: .ukTileFaceChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let scrollEnd { NotificationCenter.default.removeObserver(scrollEnd) }
    }

    /// Ends the grouping when the document changes it or takes it away.
    func detach() {
        NotificationCenter.default.removeObserver(self)
        grid?.removeGestureRecognizer(press)
        endScrollWatch()
    }

    // MARK: Arranging

    /// The items for `visible`: a heading and the tiles of each group that has any, in the groups' order.
    func items(_ visible: [(view: UIView, span: Int)]) -> [UKGridItem] {
        children = visible
        faces = Dictionary(uniqueKeysWithValues: visible.map { (ObjectIdentifier($0.view), $0.view.ukGridFace) })
        let sections = groups.arrange(visible.indices.map { (key: $0, state: state(faces[ObjectIdentifier(visible[$0].view)] ?? .idle)) })
        var items: [UKGridItem] = []
        for section in sections {
            items.append(UKGridItem(header(section.group), isHeader: true))
            items += section.keys.map { UKGridItem(visible[$0].view, span: visible[$0].span) }
        }
        arrangement = items.map { ObjectIdentifier($0.view) }
        return items
    }

    private func state(_ face: UKGridFace) -> ServerUIGridGroups.State {
        switch face {
        case .active: .active
        case .idle: .idle
        case .unavailable: .unavailable
        }
    }

    private func header(_ group: ServerUIGridGroups.Group) -> UKPageSectionHeaderView {
        if let held = headers[group.id] { return held }
        let header = UKPageSectionHeaderView(group.title, inSheet: surface == .sheet)
        header.surface = surface
        header.accessibilityIdentifier = "\(gridID).group.\(group.id)"
        headers[group.id] = header
        return header
    }

    // MARK: Moving

    @objc private func faceChanged(_ note: Notification) {
        guard let tile = note.object as? UIView, let grid, tile.isDescendant(of: grid), !isPending else { return }
        isPending = true
        // One arrangement for every tile that changed in this turn.
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.settle() } }
    }

    private func settle() {
        isPending = false
        guard let grid else { return }
        let next = items(children)
        guard next.map({ ObjectIdentifier($0.view) }) != grid.items.map({ ObjectIdentifier($0.view) }) else { return }
        if touching || isScrolling { hold(); return }
        apply(next)
    }

    private var scroll: UIScrollView? { grid?.ukEnclosingScrollView }
    private var isScrolling: Bool { scroll.map { $0.isDragging || $0.isDecelerating } ?? false }

    /// A change that arrives under the finger or a scroll waits and applies the moment both are over, with no new cause.
    private func hold() {
        guard !held else { return }
        held = true
        guard let scroll else { return }
        // The scroll's own end (the finger lifting, the deceleration settling) arrives here; a touch ending is `pressed(_:)`.
        UKTickerScrollGate.install(on: scroll)
        UKTickerScrollGate.nearest(above: grid ?? scroll)?.watch()
        scrollEnd = NotificationCenter.default.addObserver(forName: UKTickerScrollGate.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseIfIdle() }
        }
    }

    private func endScrollWatch() {
        if let scrollEnd { NotificationCenter.default.removeObserver(scrollEnd) }
        scrollEnd = nil
    }

    private func releaseIfIdle() {
        guard held, !touching, !isScrolling else { return }
        held = false
        endScrollWatch()
        settle()
    }

    private func apply(_ next: [UKGridItem]) {
        guard let grid else { return }
        let reapplied = reapplyGeneration() != seenReapply
        seenReapply = reapplyGeneration()
        let person = lastTap.map { ContinuousClock.now - $0 < .seconds(1.5) } ?? false
        let before = Dictionary(uniqueKeysWithValues: grid.items.map { (ObjectIdentifier($0.view), $0.view.frame.origin) })
        let moved = next.filter { !$0.isHeader && before[ObjectIdentifier($0.view)] != nil }.map(\.view)
        regroupCount += 1
        let reduced = UKDesign.reduceMotion
        let animated = person && !reapplied && grid.window != nil
        let interval = Telemetry.begin(Telemetry.Name.layoutChange, page: "GridGroups", animated ? (reduced ? "reduced" : "animated") : "none")
        defer { NextFrame.perform { Telemetry.end(interval) } }
        let change = { [self] in
            grid.regroupItems(next)
            relayout(false)
            grid.layoutIfNeeded()
        }
        if animated, !reduced {
            UIView.animate(withDuration: MotionTokens.standardDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: change)
        } else {
            change()
            if animated {
                // Reduce Motion: no slide; the moved tile fades in on `quick`.
                for view in moved where view.window != nil {
                    view.alpha = 0
                    UIView.animate(withDuration: MotionTokens.quickDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { view.alpha = 1 }
                }
            }
        }
        // The moved tile is the same element, so VoiceOver focus stays on it; the layout change is posted for the rest.
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .layoutChanged, argument: UIAccessibility.focusedElement(using: nil))
        }
    }

    // MARK: Touches

    @objc private func pressed(_ press: UILongPressGestureRecognizer) {
        switch press.state {
        case .began:
            touching = true
            touchStartOffset = scroll?.contentOffset
        case .ended:
            touching = false
            // Only a tap counts as a person's cause: a touch that ended a scroll moved the page.
            if !touchMovedThePage { lastTap = .now }
            touchStartOffset = nil
            releaseIfIdle()
        case .cancelled, .failed:
            touching = false
            releaseIfIdle()
        default: break
        }
    }

    private var touchMovedThePage: Bool {
        guard let scroll, let start = touchStartOffset else { return false }
        return scroll.isDragging || scroll.isDecelerating || abs(scroll.contentOffset.y - start.y) > 3 || abs(scroll.contentOffset.x - start.x) > 3
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif
