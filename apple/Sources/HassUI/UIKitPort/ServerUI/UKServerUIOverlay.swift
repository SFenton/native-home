#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Overlay

/// A base with small controls drawn over it at five anchors (`sh.overlay@1`): a map or a tile, with a command, a button, a readout or
/// text on top.
///
/// The overlay is the height of its base. Each control keeps its natural size, at least 44 by 44 pt (HIG, Buttons: "the hit region is
/// at least 44x44 pt"), and sits at its anchor with the author's inset from the edge. `leading` and `trailing` are the logical edges,
/// so they swap in a right-to-left language (HIG, Right to left). Controls are above the base, so they take a touch first;
/// VoiceOver reads the base, then the controls in reading order of their anchors.
@MainActor
final class UKServerUIOverlayView: UIView, UKGridMeasuring {
    private var definition: ServerUIOverlay?
    private var base: UIView?
    private var controls: [(id: String, view: UIView)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityContainerType = .semanticGroup
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Whether the views handed over are not the ones this overlay holds.
    func needsReparent(_ views: [UIView]) -> Bool { ([base].compactMap { $0 } + controls.map(\.view)) != views }

    /// Releases every view, before another owner takes them.
    func clear() {
        ([base].compactMap { $0 } + controls.map(\.view)).forEach { $0.removeFromSuperview() }
        base = nil
        controls = []
    }

    /// Draws `value` with `base` underneath and `controls` on top.
    /// - Parameters:
    ///   - value: The overlay.
    ///   - base: The base's view, or `nil` while the base is hidden.
    ///   - controls: The ids and views of the controls on top, in document order.
    func apply(_ value: ServerUIOverlay, base: UIView?, controls: [(id: String, view: UIView)]) {
        definition = value
        if self.base !== base {
            self.base?.removeFromSuperview()
            self.base = base
            if let base { insertSubview(base, at: 0) }
        }
        let kept = Set(controls.map { ObjectIdentifier($0.view) })
        for old in self.controls where !kept.contains(ObjectIdentifier(old.view)) { old.view.removeFromSuperview() }
        for control in controls where control.view.superview !== self { addSubview(control.view) }
        self.controls = controls
        accessibilityElements = ([base].compactMap { $0 }) + controls.sorted { order(of: $0.id) < order(of: $1.id) }.map(\.view)
        setNeedsLayout()
    }

    /// The reading order of a control's anchor: the top row, the center, then the bottom row, leading edge first.
    private func order(of id: String) -> Int {
        switch definition?.placement(of: id)?.anchor {
        case .topLeading?: 0
        case .topTrailing?: 1
        case .center?: 2
        case .bottomLeading?: 3
        case .bottomTrailing?: 4
        case nil: 5
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        guard let base else { return needed }
        let natural: CGFloat
        if let measuring = base as? UKGridMeasuring { natural = measuring.gridHeight(forWidth: width) }
        else { natural = ceil(base.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height) }
        return max(natural, needed)
    }

    /// The height the controls need so that none leaves the overlay: the top row, the bottom row and the center control never overlap
    /// the edge, each at its 44 pt minimum plus its inset.
    private var needed: CGFloat {
        guard let definition else { return 0 }
        var top: CGFloat = 0, bottom: CGFloat = 0, center: CGFloat = 0
        for (id, _) in controls {
            guard let place = definition.placement(of: id) else { continue }
            let rise = CGFloat(place.inset.points) + ServerUIOverlay.minimumTarget
            switch place.anchor {
            case .topLeading, .topTrailing: top = max(top, rise)
            case .bottomLeading, .bottomTrailing: bottom = max(bottom, rise)
            case .center: center = max(center, ServerUIOverlay.minimumTarget)
            }
        }
        return max(top + bottom, center)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    /// The size a control takes: its own fitted size, never under 44 pt either way and never wider than the base less its insets.
    private func size(of view: UIView, inset: CGFloat) -> CGSize {
        let fitted = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize, withHorizontalFittingPriority: .fittingSizeLevel,
                                                  verticalFittingPriority: .fittingSizeLevel)
        let room = max(ServerUIOverlay.minimumTarget, bounds.width - 2 * inset)
        return CGSize(width: min(room, max(ServerUIOverlay.minimumTarget, ceil(fitted.width))),
                      height: max(ServerUIOverlay.minimumTarget, ceil(fitted.height)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        base?.frame = bounds
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (id, view) in controls {
            guard let place = definition?.placement(of: id) else { continue }
            let inset = CGFloat(place.inset.points)
            let size = size(of: view, inset: inset)
            let left = rightToLeft ? bounds.maxX - inset - size.width : inset
            let right = rightToLeft ? inset : bounds.maxX - inset - size.width
            let top = inset, bottom = bounds.maxY - inset - size.height
            let origin: CGPoint
            switch place.anchor {
            case .topLeading: origin = CGPoint(x: left, y: top)
            case .topTrailing: origin = CGPoint(x: right, y: top)
            case .bottomLeading: origin = CGPoint(x: left, y: bottom)
            case .bottomTrailing: origin = CGPoint(x: right, y: bottom)
            case .center: origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            }
            view.frame = CGRect(origin: origin, size: size)
            bringSubviewToFront(view)
        }
    }
}
#endif
