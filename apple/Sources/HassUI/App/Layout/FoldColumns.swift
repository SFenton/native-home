import CoreGraphics

/// Which part of a page a section sits in while the iPhone Duo is partly folded (`.agents/design/section-sides.md`).
enum FoldSide: String, Sendable, Equatable, CaseIterable {
    /// Above both columns, spanning the page (the status rail) or only the leading region (the notification banner).
    case top
    /// The wider region, before the band.
    case leading
    /// The region after the band.
    case trailing
}

/// Pure geometry for a page whose sections stay on one side of the hinge band while the Duo is partly folded (Option B of
/// `.agents/design/section-sides.md`). ``UKFoldColumns`` measures and places views with it; nothing here reads UIKit.
///
/// The columns exist only where ``resolve(container:isRegularWidth:hinge:)`` answers: a hinge band crosses the window, the window
/// is wider than tall and each side is at least 360 pt (``SplitPolicy``). Everywhere else the answer is nil and a page lays its
/// sections out as one column, exactly as before.
enum FoldColumns {
    /// One section as the layout sees it.
    struct Entry: Equatable {
        /// The part of the page it sits in while split.
        var side: FoldSide
        /// A hidden section takes no room and moves nothing.
        var isHidden = false
        /// A top section that spans only the leading region (the notification banner); false spans the page.
        var topSpansLeadingOnly = false
        /// Ignores the layout's side inset (a rail that runs to the page's edges).
        var fullBleed = false

        /// Whether it takes room (hidden ones take none).
        func isPlaced(split: Bool) -> Bool { !isHidden }
    }

    /// The frames of a page's sections, in the order of its entries, and the page height they need.
    struct Layout: Equatable {
        /// One frame per entry, in the container's coordinates (a hidden entry gets a zero-height frame).
        var frames: [CGRect]
        /// The height of the sections, without the page's own insets.
        var height: CGFloat
        /// The height of the top strip (zero in one column).
        var topHeight: CGFloat
    }

    /// The column widths while a hinge band divides the window, else nil (one column).
    /// - Parameters:
    ///   - container: The space the page is offered, in window coordinates.
    ///   - isRegularWidth: Horizontal size class is regular.
    ///   - hinge: The window's hinge band in window coordinates, if the Duo is partly folded.
    static func resolve(container: CGRect, isRegularWidth: Bool, hinge: CGRect?) -> SplitGeometry? {
        guard hinge != nil,
              let geometry = SplitPolicy.geometry(container: container, isRegularWidth: isRegularWidth, hinge: hinge),
              geometry.isHinge else { return nil }
        return geometry
    }

    /// Frames for `entries` in one column (`geometry` nil) or in the top strip and two columns.
    /// - Parameters:
    ///   - entries: The sections, in flat order.
    ///   - width: The page width.
    ///   - geometry: The column widths from ``resolve(container:isRegularWidth:hinge:)``, nil for one column.
    ///   - spacing: The gap between sections.
    ///   - rightToLeft: Mirrors the columns (the leading column is on the right).
    ///   - sideInset: Space kept clear at both sides of every section (a page whose sections do not pad themselves).
    ///   - flatMaxWidth: The widest the single column runs, centred (a page capped at a readable width); the columns ignore it.
    ///   - height: A section's height at a width (the width less the side insets), asked once per section.
    static func layout(entries: [Entry], width: CGFloat, geometry: SplitGeometry?, spacing: CGFloat, rightToLeft: Bool,
                       sideInset: CGFloat = 0, flatMaxWidth: CGFloat = .greatestFiniteMagnitude,
                       height: (Int, CGFloat) -> CGFloat) -> Layout {
        let pad = 2 * sideInset
        func inset(_ frame: CGRect, _ bleeds: Bool) -> CGRect {
            bleeds ? frame : CGRect(x: frame.minX + sideInset, y: frame.minY, width: max(0, frame.width - pad), height: frame.height)
        }
        func padding(_ index: Int) -> CGFloat { entries[index].fullBleed ? 0 : pad }
        var frames = [CGRect](repeating: .zero, count: entries.count)
        guard let geometry else {
            let inner = min(flatMaxWidth, max(0, width - pad))
            let flatX = sideInset + max(0, (width - pad - inner) / 2)
            var y: CGFloat = 0
            var placed = false
            for (index, entry) in entries.enumerated() where entry.isPlaced(split: false) {
                if placed { y += spacing }
                let h: CGFloat
                if entry.fullBleed {
                    h = height(index, width)
                    frames[index] = CGRect(x: 0, y: y, width: width, height: h)
                } else {
                    h = height(index, inner)
                    frames[index] = CGRect(x: flatX, y: y, width: inner, height: h)
                }
                y += h
                placed = true
            }
            return Layout(frames: frames, height: y, topHeight: 0)
        }
        // The geometry's widths are physical (left, then right); right to left puts the leading side on the right, so its width is the right region's.
        let columns = rightToLeft ? SplitGeometry(leadingWidth: geometry.trailingWidth, bandWidth: geometry.bandWidth,
                                                  trailingWidth: geometry.leadingWidth, isHinge: geometry.isHinge) : geometry
        func x(_ side: FoldSide, _ w: CGFloat) -> CGFloat {
            switch side {
            case .top, .leading: return rightToLeft ? width - w : 0
            case .trailing: return rightToLeft ? 0 : width - w
            }
        }
        var topY: CGFloat = 0
        var placedTop = false
        for (index, entry) in entries.enumerated() where entry.isPlaced(split: true) && entry.side == .top {
            if placedTop { topY += spacing }
            let w = entry.topSpansLeadingOnly ? columns.leadingWidth : width
            let h = height(index, max(0, w - padding(index)))
            frames[index] = inset(CGRect(x: x(.top, w), y: topY, width: w, height: h), entry.fullBleed)
            topY += h
            placedTop = true
        }
        let lowerY = topY + (placedTop ? spacing : 0)
        var bottoms: [FoldSide: CGFloat] = [.leading: 0, .trailing: 0]
        var placed: Set<FoldSide> = []
        for index in entries.indices where entries[index].isPlaced(split: true) && entries[index].side != .top {
            let entry = entries[index]
            let side = entry.side
            let w = side == .leading ? columns.leadingWidth : columns.trailingWidth
            var y = bottoms[side] ?? 0
            if placed.contains(side) { y += spacing }
            let h = height(index, max(0, w - padding(index)))
            frames[index] = inset(CGRect(x: x(side, w), y: lowerY + y, width: w, height: h), entry.fullBleed)
            bottoms[side] = y + h
            placed.insert(side)
        }
        let lower = max(bottoms[.leading] ?? 0, bottoms[.trailing] ?? 0)
        return Layout(frames: frames, height: lowerY + lower, topHeight: topY)
    }

    /// The reading order while split: the top strip, the leading column top to bottom, then the trailing column (section-sides.md rule 10).
    /// - Returns: Entry indices, hidden ones left out.
    static func readingOrder(entries: [Entry]) -> [Int] {
        [FoldSide.top, .leading, .trailing].flatMap { side in
            entries.indices.filter { entries[$0].isPlaced(split: true) && entries[$0].side == side }
        }
    }
}
