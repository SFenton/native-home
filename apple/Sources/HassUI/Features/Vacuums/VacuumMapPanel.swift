import HassCore
import HassDesign
import Observation
import SwiftUI

/// The map for one sheet: the loader plus the prepared scene, rebuilt only when the map changes.
@MainActor
@Observable
final class VacuumMapState {
    let loader: ValetudoMapLoader
    private(set) var scene: ValetudoMapScene?
    @ObservationIgnored private let vacuum: VacuumConfig
    @ObservationIgnored private var sceneMap: ValetudoMap?
    @ObservationIgnored private var sceneProvenance: ValetudoMapProvenance = .none

    init(vacuum: VacuumConfig, loader: ValetudoMapLoader) {
        self.vacuum = vacuum
        self.loader = loader
        refresh()
    }

    /// Rebuilds the scene if the loader holds a different map.
    func refresh() {
        guard loader.map != sceneMap || loader.provenance != sceneProvenance else { return }
        sceneMap = loader.map
        sceneProvenance = loader.provenance
        scene = loader.map.map { ValetudoMapScene(map: $0, vacuum: vacuum, provenance: loader.provenance) }
    }

    /// A live map is loaded (area drawing needs one).
    var isReady: Bool { scene != nil && loader.provenance == .live }

    /// The area lies inside the focus crop (`selectionAllowed`).
    func allows(_ area: MapGridRect?) -> Bool {
        guard let area, let scene, scene.focus.mode == .focused else { return true }
        return ValetudoMapFocus.rect(area, isWithin: scene.focus.interactionBounds)
    }
}
