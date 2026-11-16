#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Layout helpers

/// One label with room around it, sized at its natural height.
@MainActor
final class UKLabelBox: UIView, UKGridMeasuring {
    let label: UILabel

    init(_ label: UILabel) {
        self.label = label
        super.init(frame: .zero)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}

/// A brightness tile when the light dims, else a power tile (`LightGroupTile`). Both send explicit `turn_on` / `turn_off`
/// (``LightControl``), never `toggle`: Presence Based Lighting's Presence Lock reverts toggles.
@MainActor
final class UKLightGroupTileView: UIView, UKGridMeasuring {
    private let title: String
    private let entityId: String
    private let identifier: String
    private let environment: UKTileEnvironment
    private let send: (LightControl.Command) -> Void
    private let glass: UKGlassTileView
    private let brightness: UKBrightnessTileView

    init(title: String, entityId: String, identifier: String, environment: UKTileEnvironment, send: @escaping (LightControl.Command) -> Void) {
        self.title = title
        self.entityId = entityId
        self.identifier = identifier
        self.environment = environment
        self.send = send
        glass = UKGlassTileView(model: UKGlassTileModel(title: title, symbol: "lightbulb", family: .lights, isActive: false, identifier: identifier),
                                environment: environment)
        brightness = UKBrightnessTileView(title: title, tint: UIColor(HassTokens.RGB.Tint.light), percent: 0)
        super.init(frame: .zero)
        brightness.environment = environment
        brightness.identifier = identifier
        brightness.onPower = { [entityId, send] in send(LightControl.power(entityId, on: $0)) }
        brightness.onBrightness = { [entityId, send] in send(LightControl.brightness(entityId, percent: Double($0))) }
        brightness.isHidden = true
        addSubview(glass)
        addSubview(brightness)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var visibleTile: UIView & UKGridMeasuring { brightness.isHidden ? glass : brightness }
    var hasActiveInteraction: Bool { !brightness.isHidden && brightness.hasActiveInteraction }

    /// Shows the light's state; call it from an observation of the light's box.
    func update(state: EntityState?, isFailed: Bool = false) {
        let unavailable = state?.isUnavailable ?? true
        let dimmable = LightControl.isDimmable(state)
        if dimmable {
            let fill = LightControl.rgb(of: state).map { UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
            brightness.update(fillTint: fill, percent: LightControl.percent(of: state), isUnavailable: unavailable, isFailed: isFailed)
        } else {
            let on = state?.state == "on"
            // An action tile with a `power` disc (`PowerToggleActions.entity`): explicit `turn_on` / `turn_off`, never `toggle`.
            let provider = PowerToggleActions.entity(entityId)
            let specs = provider.actions(for: state)
            var model = UKGlassTileModel(
                title: title, subtitle: isFailed ? "Didn't Respond" : state.map { $0.isUnavailable ? "Unavailable" : (on ? "On" : "Off") }, symbol: specs.first?.symbol ?? "power",
                family: .lights, isActive: on, isUnavailable: unavailable, isError: isFailed,
                behavior: TileBehavior(TileActionCatalog.classification(ofLightOpensDetails: false), primary: PowerToggleActions.actionId),
                actions: specs.items, identifier: identifier)
            model.stateCandidates = provider.stateTextCandidates
            glass.configure(model, environment: environment, action: {}, perform: { [entityId, send] _ in send(LightControl.flip(entityId, shownOn: on)) })
        }
        if brightness.isHidden != !dimmable {
            brightness.isHidden = !dimmable
            glass.isHidden = dimmable
            ukSetNeedsLayoutUpward()
        }
    }

    var gridMinimumWidth: CGFloat { visibleTile.gridMinimumWidth }
    func gridHeight(forWidth width: CGFloat) -> CGFloat { visibleTile.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        brightness.frame = bounds
    }
}

// MARK: - Group detail

#endif
