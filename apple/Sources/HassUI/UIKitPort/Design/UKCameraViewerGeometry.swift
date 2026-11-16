#if os(iOS)
import HassDesign
import UIKit

// MARK: - Canonical viewer geometry

/// Shared stacked/split geometry, extracted unchanged from the native viewer.
@MainActor
enum UKCameraViewerGeometry {
    struct Plan {
        let video: CGRect
        let controls: CGRect
        let controlsAxis: UKCameraControlStripView.LayoutAxis
        let height: CGFloat
    }

    static func plan(width: CGFloat, split: Bool, aspect: CGFloat,
                     controlsHeight: (CGFloat, UKCameraControlStripView.LayoutAxis) -> CGFloat) -> Plan {
        let padding = UKPageMetrics.side
        let inner = max(0, width - 2 * padding)
        if split {
            let half = max(0, (inner - padding) / 2)
            let videoHeight = half / aspect
            let height = controlsHeight(half, .vertical)
            return Plan(video: CGRect(x: padding, y: padding, width: half, height: videoHeight),
                        controls: CGRect(x: padding + half + padding, y: padding, width: half, height: height),
                        controlsAxis: .vertical, height: padding + max(videoHeight, height) + padding)
        }
        let column = min(inner, 720)
        let x = padding + (inner - column) / 2
        let videoHeight = column / aspect
        let height = controlsHeight(column, .horizontal)
        let gap = HassTokens.Spacing.xl
        return Plan(video: CGRect(x: x, y: padding, width: column, height: videoHeight),
                    controls: CGRect(x: x, y: padding + videoHeight + gap, width: column, height: height),
                    controlsAxis: .horizontal, height: padding + videoHeight + gap + height + padding)
    }
}
#endif
