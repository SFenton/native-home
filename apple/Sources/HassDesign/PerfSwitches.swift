import Foundation

/// Launch-time switches that turn one costly layer off for an A/B run (`.agents/testing/apple/performance.md`, "Scroll
/// cost"). The simulator cannot show what a layer costs the GPU, so a phone is launched twice, once with the layer and once
/// without (`FENTON_PERF_DISABLE=headerFade,backdrop`), and the two scroll runs are compared. Everything is on in a normal
/// launch; nothing reads these in the app's own flows.
public enum PerfSwitches {
    /// A layer that can be turned off.
    public enum Layer: String, CaseIterable, Sendable {
        /// The mask that fades content out under the navigation bar (``SwiftUICore/View/headerEdgeFade()``): a full-page
        /// offscreen pass while a page scrolls. Only the pre-iOS 26 fallback draws it now (pages and modals use the system's soft
        /// scroll edge from iOS 26, header-edge-fade R10), so this switch changes nothing on iOS 26.
        case headerFade
        /// Only the mask half of the header fade: the readers (scroll offset, safe area) keep running, so a run without it
        /// shows what the offscreen mask costs on its own. Pre-iOS 26 fallback only.
        case fadeMask
        /// Only the readers half of the header fade: the mask stays, the scroll offset and safe area readers go. Pre-iOS 26 fallback only.
        case fadeReaders
        /// Only the scroll offset reader of the header fade (`onScrollGeometryChange`). Pre-iOS 26 fallback only.
        case fadeScroll
        /// Only the safe area and container geometry readers of the header fade (`onGeometryChange`). Pre-iOS 26 fallback only.
        case fadeGeometry
        /// The blurred house photo behind pages and its scrim (the plain base colour is drawn instead).
        case backdrop
        /// The Liquid Glass behind the floating action bar's buttons (a plain thin material is drawn instead).
        case glassBar
        /// The soft scroll edge effect under the floating action bar (``SwiftUICore/View/floatingActionBar(_:search:)``).
        case scrollEdge
    }

    /// The layers this launch turned off.
    public static let disabled: Set<Layer> = parse(ProcessInfo.processInfo.environment["FENTON_PERF_DISABLE"])

    /// Whether `layer` is turned off for this launch.
    public static func isOff(_ layer: Layer) -> Bool { disabled.contains(layer) }

    /// The layers named in a comma separated list (unknown names are ignored).
    static func parse(_ value: String?) -> Set<Layer> {
        Set((value ?? "").split(separator: ",").compactMap { Layer(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }
}
