#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A room tile for a bedroom device, bound to its controller (`BedSideTile`, `WakeLightTile`). The Rooms page places it in its grid; a stack (the server-UI bedroom control) hosts it in a `UKMeasuredView`.
@MainActor
final class UKBedroomTile: UIView, UKGridMeasuring {
    private let tile: UKGlassTileView
    private let bag = UKObservationBag()
    private lazy var clock = UKEverySecond { [weak self] now in self?.refresh(now: now) }
    private let model: (Date) -> UKGlassTileModel
    private let runs: () -> Bool
    private let action: () -> Void

    private init(environment: UKTileEnvironment, model: @escaping (Date) -> UKGlassTileModel, runs: @escaping () -> Bool, action: @escaping () -> Void) {
        self.model = model
        self.runs = runs
        self.action = action
        tile = UKGlassTileView(model: model(.now), environment: environment, action: action)
        super.init(frame: .zero)
        addSubview(tile)
        bag.observe { [weak self] in
            guard let self else { return }
            self.refresh(now: .now)
            self.clock.setRunning(self.runs())
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refresh(now: Date) { tile.configure(model(now), action: action) }

    /// A bed side's tile (web SleepyPod tile).
    static func bedSide(_ controller: BedSideController, context: UKContext, action: @escaping () -> Void) -> UKBedroomTile {
        UKBedroomTile(environment: UKTileEnvironment(context: context), model: { now in
            let face = BedroomStyle.face(action: controller.action, level: controller.displayedTarget, isAvailable: controller.sideAvailable)
            var model = UKGlassTileModel(title: controller.config.title, subtitle: controller.tileSubtitle(now: now), symbol: "bed.double", family: face.family,
                                         // Fills while the side is on (`ThermostatTileFace.bedSide`).
                                         isActive: face.isActive && !controller.scope.readOnly,
                                         // An unavailable side dims and says "Unavailable" and is not mistaken for "Off".
                                         isUnavailable: !controller.sideAvailable, kind: .navigate, identifier: "room.card.\(controller.config.title)")
            // The lines the tile can show, so the grid gives it the tracks its text needs (content-aware span).
            model.stateCandidates = BedSideController.tileSubtitleCandidates
            return model
        }, runs: { controller.hotFlashHolding }, action: action)
    }

    /// The wake light's tile (web "Wake-Light Alarms" tile).
    static func wakeLight(_ controller: WakeLightController, context: UKContext, action: @escaping () -> Void) -> UKBedroomTile {
        UKBedroomTile(environment: UKTileEnvironment(context: context), model: { _ in
            let snapshot = controller.snapshot
            return UKGlassTileModel(title: controller.config.title, subtitle: WakeLight.subtitle(snapshot), symbol: "sunrise", family: .lights,
                                    // Fills only while a wake is running (ramping, holding or snoozed); an armed alarm stays dark and the
                                    // subtitle names the next one (colour never carries the state alone).
                                    isActive: WakeLight.fillsTile(snapshot), kind: .navigate, identifier: "room.card.\(controller.config.title)")
        }, runs: { false }, action: action)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { tile.gridHeight(forWidth: width) }

    /// The tile's own minimum, so a bed tile takes the tracks it needs as a tile placed directly does.
    var gridMinimumWidth: CGFloat { tile.gridMinimumWidth }

    override func sizeThatFits(_ size: CGSize) -> CGSize { tile.sizeThatFits(size) }

    override func layoutSubviews() {
        super.layoutSubviews()
        tile.frame = bounds
    }
}

#endif
