#if os(iOS)
import Foundation

/// Debug-only layer switches for the UIKit port's render-server A/B (`FENTON_PERF_DISABLE=ukHeaderFade,ukGlass`), the port's
/// counterpart of `PerfSwitches`. Release builds never turn a layer off.
enum UKPerfSwitches {
    enum Layer: String {
        /// The image card's rounded clip.
        case ukCardClip
        /// The image card captions' layer shadows.
        case ukLabelShadow
        /// The 120 Hz scroll rate request.
        case ukScrollRate
        /// Forces the mask fade on iOS 26+ instead of the system soft edge.
        case ukSoftEdge
        /// The gradient mask on a page or sheet's content (``UKHeaderEdgeFade``).
        case ukHeaderFade
        /// The `UIColorEffect` ground on a sheet detent (``UKHassModal``).
        case ukSheetGround
        /// `UIGlassEffect` / blur in ``UKGlass`` (a flat fill is drawn instead).
        case ukGlass
        /// The weather scene decoration (rain, snow, stars, cloud banks).
        case ukDecoration
        /// The finish image layer of a tile face (sheen, rim).
        case ukTileFinish
        /// The chore row cell's background card, hairline, and content (A/B of the list's per-row layers).
        case ukBottomEdgeHidden, ukBottomEdgeHard, ukFabContainer, ukFabInteractive, ukEdgeInteraction, ukRowCard, ukRowHairline, ukRowContent, ukFab, ukHeaderTiles
    }

    #if DEBUG
    static let disabled: Set<Layer> = Set((ProcessInfo.processInfo.environment["FENTON_PERF_DISABLE"] ?? "").split(separator: ",")
        .compactMap { Layer(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    #else
    static let disabled: Set<Layer> = []
    #endif

    static func isOff(_ layer: Layer) -> Bool { disabled.contains(layer) }
}
#endif
