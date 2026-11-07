#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Guest stays (web `GuestPresenceSecuritySection`, first pass: the stay toggles only; SwiftUI `GuestPresenceSection`). Shown only
/// while a guest toggle is on, matching the web: it takes no room otherwise.
///
/// The toggles go through the optimistic path, made on the first tap: a rejected or offline call rolls the tile back and shows its
/// failed face ("Didn't Respond") for 4 s.
@MainActor
final class UKGuestPresenceSectionView: UIView, UKGridMeasuring {
    private let context: UKContext
    private let caller: (any HassServiceCalling)?
    private let header = UKPageSectionHeaderView("Guests Staying Over")
    private let note = UILabel()
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4))
    private var tiles: [UKGlassTileView] = []
    private let bag = UKObservationBag()
    private var actions: OptimisticActions?

    /// Runs when the section shows or hides, so the view that pads it can take no room either.
    var onVisibilityChange: ((Bool) -> Void)?

    var hinge: CGRect? {
        get { grid.hinge }
        set { grid.hinge = newValue }
    }

    /// - Parameter caller: Where toggles go; nil uses the context's connection. The Security gallery passes its recorder.
    init(context: UKContext, caller: (any HassServiceCalling)?) {
        self.context = context
        self.caller = caller ?? context.connection
        super.init(frame: .zero)
        grid.followsFold = true
        addSubview(header)
        note.numberOfLines = 0
        note.text = "Guest mode skips some away automations. Review security, climate, and auto-clean controls before leaving."
        // Fixed ink: it sits on the dark wallpaper, whatever the scheme.
        note.textColor = UKInk.onDarkSecondary
        addSubview(note)
        tiles = HomeConfig.guestToggles.map {
            UKGlassTileView(model: UKGlassTileModel(title: "", symbol: "power", family: .occupancy, isActive: false,
                                                    behavior: TileBehavior(TileActionCatalog.classification(of: $0), primary: PowerToggleActions.actionId)),
                            environment: UKTileEnvironment(context: context))
        }
        grid.setItems(tiles.map { UKGridItem($0) })
        addSubview(grid)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            note.font = UKFont.preferred(.footnote, traits: traitCollection)
            // Scales with the tiles' text, so accessibility sizes step down to fewer, wider tiles.
            grid.configuration.minCellWidth = UKFont.scaled(110, relativeTo: .subheadline, traits: traitCollection)
            setNeedsLayout()
            superview?.setNeedsLayout()
        }
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func bind() {
        bag.removeAll()
        let store = context.store
        bag.observe { [weak self] in
            guard let self else { return }
            let anyGuests = HomeConfig.guestToggles.contains { store.entity($0.entityId).state?.state == "on" }
            let wasHidden = isHidden
            isHidden = !anyGuests
            if wasHidden != isHidden { onVisibilityChange?(isHidden); superview?.setNeedsLayout() }
            for (toggle, tile) in zip(HomeConfig.guestToggles, tiles) {
                let state = store.entity(toggle.entityId).state
                let shown = actions?.shown(toggle.entityId) ?? state?.state
                let failed = actions?.isFailed(toggle.entityId) ?? false
                let provider = PowerToggleActions.entity(toggle.entityId)
                let specs = provider.actions(for: state?.showing(shown))
                // An action tile, text and disc: the disc carries the state glyph and the body does what it shows, in one tap.
                var model = UKGlassTileModel(
                    title: toggle.title, subtitle: failed ? "Didn't Respond" : shown == "on" ? "Guests staying" : "No guests",
                    symbol: specs.first?.symbol ?? "power", family: .occupancy, isActive: shown == "on",
                    isUnavailable: state?.isUnavailable ?? true, isError: failed,
                    behavior: TileBehavior(TileActionCatalog.classification(of: toggle), primary: PowerToggleActions.actionId),
                    actions: specs.items, identifier: "guest.tile.\(toggle.entityId)")
                model.stateCandidates = provider.stateTextCandidates
                tile.configure(model, environment: UKTileEnvironment(context: context), perform: { [weak self] id in
                    if let spec = specs.first(where: { $0.id == id }) { self?.run(spec) }
                })
            }
        }
    }

    /// Runs a stay toggle's action (an explicit turn on or off, never a toggle) through the optimistic path; nothing without a connection or
    /// caller.
    private func run(_ spec: TileActionSpec) {
        guard let target = caller else { return }
        let created = actions == nil
        let actions = actions ?? OptimisticActions(
            store: context.store, rules: HomeConfig.guestToggleRules, caller: target)
        self.actions = actions
        if created { bind() }
        actions.perform(spec)
    }

    // MARK: Layout

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        header.gridHeight(forWidth: width) + HassTokens.Spacing.s + ceil(note.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height)
            + HassTokens.Spacing.s + grid.gridHeight(forWidth: width)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        var y: CGFloat = 0
        let headerHeight = header.gridHeight(forWidth: width)
        header.frame = CGRect(x: 0, y: y, width: width, height: headerHeight)
        y += headerHeight + HassTokens.Spacing.s
        let noteHeight = ceil(note.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height)
        note.frame = CGRect(x: 0, y: y, width: width, height: noteHeight)
        note.textAlignment = effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        y += noteHeight + HassTokens.Spacing.s
        grid.frame = CGRect(x: 0, y: y, width: width, height: grid.gridHeight(forWidth: width))
    }
}
#endif
