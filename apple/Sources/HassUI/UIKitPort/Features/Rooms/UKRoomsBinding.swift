#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

/// A ``UKDynamicGridView`` whose minimum tile width scales with Dynamic Type (`@ScaledMetric(relativeTo:)`) and that avoids the window's
/// hinge on a page.
@MainActor
class UKRoomsGrid: UKDynamicGridView {
    private let base: CGFloat
    private let style: UIFont.TextStyle
    /// Pages follow the Duo's fold (``UKDynamicGridView/followsFold``); a sheet does not.
    var avoidsHinge = true { didSet { followsFold = avoidsHinge } }

    init(minCellWidth: CGFloat, maxColumns: Int, spacing: CGFloat = HassTokens.Spacing.m, equalRowHeights: Bool = false,
         relativeTo style: UIFont.TextStyle = .subheadline, fill: UKGridFill = .share) {
        base = minCellWidth
        self.style = style
        super.init(configuration: UKGridConfiguration(minCellWidth: minCellWidth, maxColumns: maxColumns, spacing: spacing,
                                                      equalRowHeights: equalRowHeights, fill: fill))
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (grid: UKRoomsGrid, _) in grid.rescale() }
        rescale()
        followsFold = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rescale() {
        var configuration = configuration
        let scaled = UKFont.scaled(base, relativeTo: style, traits: traitCollection)
        // A section minimum only grows with text size (duo-widths rule 5): text removes section columns, never adds them.
        configuration.minCellWidth = base >= DynamicGridMetrics.sectionMinWidth ? max(base, scaled) : scaled
        self.configuration = configuration
    }
}

/// An Auto Layout view (a state message) measured at a width inside the hand-laid columns and grids.
@MainActor
final class UKRoomsMeasured: UIView, UKGridMeasuring {
    private let content: UIView

    init(_ content: UIView, identifier: String? = nil) {
        self.content = content
        super.init(frame: .zero)
        addSubview(content)
        // The identifier lives on the message; a semantic group makes it an element XCUITest can find.
        content.accessibilityContainerType = .semanticGroup
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        ceil(content.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                             withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = bounds
    }
}

/// The vacuum's and a remote's transport tapped values, made on the first tap (pattern: optimistic-actions), and a remote's own controller
/// made on its first Power tap. Observable, so a tile bound before the first tap follows the tapped value once it exists.
@MainActor @Observable
final class UKActionsHolder {
    var actions: OptimisticActions?
    var ownController: MediaRemoteController?
}

/// Binding helpers: a tile follows the entities its model closure reads, and the grid measures again when its text changed height.
@MainActor
enum UKRoomsBind {
    /// Shows `model()` on `tile` now and again whenever anything it read changes. The first run never cross-fades.
    static func tile(_ tile: UKGlassTileView, bag: UKObservationBag, environment: UKTileEnvironment,
                     action: (() -> Void)? = nil, perform: ((TileActionItem.ID) -> Void)? = nil, model: @escaping @MainActor () -> UKGlassTileModel) {
        var first = true
        bag.observe { [weak tile] in
            guard let tile else { return }
            let next = model()
            let old = tile.model
            tile.configure(next, environment: environment, animated: !first, action: action, perform: perform)
            if !first, old.subtitle != next.subtitle || old.title != next.title { tile.ukRemeasureContainers() }
            first = false
        }
    }

    /// A read-only tile (`.state`): sensors and entity readings.
    static func readOnly(bag: UKObservationBag, environment: UKTileEnvironment, model: @escaping @MainActor () -> UKGlassTileModel) -> UKGlassTileView {
        let view = UKGlassTileView(model: model(), environment: environment)
        tile(view, bag: bag, environment: environment, model: model)
        return view
    }

    /// `LightGroupTile`: a brightness tile when the light dims, else a power tile. Both send explicit `turn_on` / `turn_off`.
    static func lightTile(title: String, entityId: String, identifier: String, bag: UKObservationBag, environment: UKTileEnvironment,
                          read: @escaping @MainActor () -> EntityState?, send: @escaping (LightControl.Command) -> Void) -> UIView {
        let state = read()
        if LightControl.isDimmable(state) {
            let tile = UKBrightnessTileView(title: title, tint: UIColor(HassTokens.RGB.Tint.light), fillTint: fill(LightControl.rgb(of: state)),
                                            percent: LightControl.percent(of: state), isUnavailable: state?.isUnavailable ?? true)
            tile.environment = environment
            tile.identifier = identifier
            tile.onPower = { send(LightControl.power(entityId, on: $0)) }
            tile.onBrightness = { send(LightControl.brightness(entityId, percent: Double($0))) }
            bag.observe { [weak tile] in
                let state = read()
                tile?.update(fillTint: fill(LightControl.rgb(of: state)), percent: LightControl.percent(of: state),
                             isUnavailable: state?.isUnavailable ?? true)
            }
            return tile
        }
        // An action tile with a `power` disc (owner, 2026-10-27; `PowerToggleActions`): explicit `turn_on` / `turn_off`, never `toggle`.
        let provider = PowerToggleActions.entity(entityId)
        func model() -> UKGlassTileModel {
            let state = read()
            let on = state?.state == "on"
            let specs = provider.actions(for: state)
            var model = UKGlassTileModel(
                title: title, subtitle: state.map { $0.isUnavailable ? "Unavailable" : (on ? "On" : "Off") }, symbol: specs.first?.symbol ?? "power",
                family: .lights, isActive: on, isUnavailable: state?.isUnavailable ?? true,
                behavior: TileBehavior(TileActionCatalog.classification(ofLightOpensDetails: false), primary: PowerToggleActions.actionId),
                actions: specs.items, identifier: identifier)
            model.stateCandidates = provider.stateTextCandidates
            return model
        }
        let tile = UKGlassTileView(model: model(), environment: environment)
        UKRoomsBind.tile(tile, bag: bag, environment: environment, action: {}, perform: { _ in
            let state = read()
            send(LightControl.flip(entityId, shownOn: state?.state == "on"))
        }, model: model)
        return tile
    }

    private static func fill(_ rgb: (red: Double, green: Double, blue: Double)?) -> UIColor? {
        rgb.map { UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
    }
}
#endif
