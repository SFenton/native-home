#if os(iOS)
import HassCore
import HassDesign

extension TileInkDefault {
    /// The ink a published document asks for (`sh.tile-ink-default@1`): the primary ink when its manifest lists the capability, else the grey.
    init(_ declared: ServerUITileInkDefault) {
        self = declared == .primary ? .primary : .muted
    }
}
#endif
