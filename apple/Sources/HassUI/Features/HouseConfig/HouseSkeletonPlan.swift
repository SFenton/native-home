import CoreGraphics

/// The shapes of a house-layout skeleton (`.agents/design/house-config-states.md`, rule 11), as pure geometry so the plan is
/// unit-tested; ``UKConfigSkeletonView`` draws them with ``UKPendingValueBar``'s fill and pulse.
struct HouseSkeletonPlan: Equatable {
    /// Which page the skeleton stands in for.
    enum Kind: Equatable {
        /// Four chip capsules, the weather module, one section bar and four camera-shaped tiles.
        case home
        /// A section bar and four tiles, then a bar and two tiles.
        case page
    }

    /// What a shape stands for; the radius follows the role.
    enum Role: Equatable {
        case chip, module, bar, tile
    }

    /// One placeholder shape in the skeleton's coordinates.
    struct Shape: Equatable {
        let role: Role
        let frame: CGRect
    }

    /// Camera tiles are 1 : 0.78 (width : height), the Home camera tile's shape.
    static let tileAspect: CGFloat = 0.78
    /// The page width from which the tiles take four columns instead of two.
    static let wideWidth: CGFloat = 700
    static let sideMargin: CGFloat = 16
    static let gap: CGFloat = 12
    static let topInset: CGFloat = 8
    static let moduleHeight: CGFloat = 168

    let shapes: [Shape]
    /// The height the shapes use.
    let height: CGFloat

    /// The columns the tiles take in a region of `width`: 2, or 4 from ``wideWidth``.
    static func columns(forWidth width: CGFloat) -> Int { width >= wideWidth ? 4 : 2 }

    /// Lays the shapes out.
    /// - Parameters:
    ///   - kind: The page.
    ///   - width: The skeleton's width.
    ///   - band: The hinge band across the skeleton, as x offsets from its leading edge, while the Duo is partly folded. Home then
    ///     uses fold columns: the chips on top, the module leading, the tiles trailing.
    ///   - chipHeight: A chip capsule's height (scales with text size).
    static func make(_ kind: Kind, width: CGFloat, band: ClosedRange<CGFloat>? = nil, chipHeight: CGFloat = 56) -> HouseSkeletonPlan {
        var shapes: [Shape] = []
        let barHeight: CGFloat = 14
        let barWidth: CGFloat = 120
        var y = topInset

        /// Tiles of one section in `x0 ..< x1`, from `top`; returns the bottom.
        func tiles(_ count: Int, from x0: CGFloat, to x1: CGFloat, top: CGFloat) -> CGFloat {
            let inner = max(x1 - x0 - 2 * sideMargin, 0)
            let columnCount = Self.columns(forWidth: x1 - x0)
            let side = max((inner - CGFloat(columnCount - 1) * gap) / CGFloat(columnCount), 0)
            let height = side * tileAspect
            var bottom = top
            for index in 0..<count {
                let row = index / columnCount, column = index % columnCount
                let frame = CGRect(x: x0 + sideMargin + CGFloat(column) * (side + gap), y: top + CGFloat(row) * (height + gap), width: side, height: height)
                shapes.append(Shape(role: .tile, frame: frame))
                bottom = frame.maxY
            }
            return bottom
        }

        func bar(at x0: CGFloat, top: CGFloat) -> CGFloat {
            shapes.append(Shape(role: .bar, frame: CGRect(x: x0 + sideMargin, y: top, width: barWidth, height: barHeight)))
            return top + barHeight + gap
        }

        switch kind {
        case .home:
            let inner = max(width - 2 * sideMargin, 0)
            let chipWidth = max((inner - 3 * gap) / 4, 0)
            for index in 0..<4 {
                shapes.append(Shape(role: .chip, frame: CGRect(x: sideMargin + CGFloat(index) * (chipWidth + gap), y: y, width: chipWidth, height: chipHeight)))
            }
            y += chipHeight + gap * 2
            if let band, band.lowerBound > 0, band.upperBound < width {
                // Fold columns: the module leads, the tiles trail, level with each other.
                let moduleWidth = max(band.lowerBound - 2 * sideMargin, 0)
                shapes.append(Shape(role: .module, frame: CGRect(x: sideMargin, y: y, width: moduleWidth, height: moduleHeight)))
                let sectionTop = bar(at: band.upperBound, top: y)
                y = max(tiles(4, from: band.upperBound, to: width, top: sectionTop), y + moduleHeight)
            } else {
                shapes.append(Shape(role: .module, frame: CGRect(x: sideMargin, y: y, width: inner, height: moduleHeight)))
                y += moduleHeight + gap * 2
                y = tiles(4, from: 0, to: width, top: bar(at: 0, top: y))
            }
        case .page:
            y = tiles(4, from: 0, to: width, top: bar(at: 0, top: y)) + gap * 2
            y = tiles(2, from: 0, to: width, top: bar(at: 0, top: y))
        }
        return HouseSkeletonPlan(shapes: shapes, height: y + topInset)
    }
}
